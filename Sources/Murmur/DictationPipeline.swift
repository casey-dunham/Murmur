import Foundation
import Cocoa
import Combine
@preconcurrency import ApplicationServices

struct DictationEntry: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case enhancing
    case inserting
    case error(String)

    static func == (lhs: DictationState, rhs: DictationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording),
             (.transcribing, .transcribing), (.enhancing, .enhancing),
             (.inserting, .inserting):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

@MainActor
class DictationPipeline: ObservableObject {
    @Published var state: DictationState = .idle
    @Published var lastTranscript: String = ""
    @Published var lastEnhanced: String = ""
    @Published var dictationCount: Int = 0
    @Published var history: [DictationEntry] = []
    @Published var audioLevel: Float = 0.0

    private let maxHistory = 10
    private let speechEngine = SpeechEngine()
    private let textEnhancer = TextEnhancer()
    private let textInserter = TextInserter()

    /// Captured before recording starts so we know where to insert text
    private var targetApp: AXUIElement?
    private var targetElement: AXUIElement?
    private var targetPID: pid_t?

    /// Context captured from the focused text field for AI enhancement
    var contextBefore: String = ""
    var selectedText: String = ""
    var appName: String = ""
    var appBundleID: String = ""

    /// Watchdog timer to auto-recover from stuck states
    private var stateWatchdog: Task<Void, Never>?

    init() {
        speechEngine.onAudioLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.audioLevel = level
            }
        }
    }

    private func pipelineLog(_ msg: String) {
        let line = "[\(Date())] PIPELINE: \(msg)\n"
        let path = "/tmp/murmur_debug.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    func startDictation() {
        pipelineLog("startDictation called, current state=\(state)")
        guard state == .idle else { pipelineLog("NOT idle, skipping"); return }

        captureTarget()
        captureContext()
        pipelineLog("captured target: pid=\(targetPID ?? -1), hasApp=\(targetApp != nil), hasElement=\(targetElement != nil)")
        pipelineLog("context: app=\(appName) (\(appBundleID)), selectedText=\(selectedText.prefix(40)), contextBefore=\(contextBefore.prefix(40))")

        state = .recording
        lastTranscript = ""
        lastEnhanced = ""
        startWatchdog()

        do {
            try speechEngine.startRecording()
        } catch {
            state = .error("Recording failed: \(error.localizedDescription)")
        }
    }

    private func startWatchdog() {
        stateWatchdog?.cancel()
        stateWatchdog = Task { [weak self] in
            do {
                // If stuck in any non-idle state for 30 seconds, force reset
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                // Cancelled — previous watchdog killed by a new dictation session, bail out
                return
            }
            guard let self = self else { return }
            if self.state != .idle {
                self.pipelineLog("WATCHDOG: stuck in \(self.state), forcing reset to idle")
                self.state = .error("Operation timed out")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled { self.state = .idle }
            }
        }
    }

    func stopDictation() {
        pipelineLog("stopDictation called, state=\(state)")
        guard state == .recording else { pipelineLog("NOT recording, skipping"); return }
        speechEngine.stopRecording()
        audioLevel = 0.0
        state = .transcribing
        pipelineLog("transcribing...")

        Task {
            await processDictation()
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clearHistory() {
        history.removeAll()
    }

    private func captureTarget() {
        // Capture via system-wide AX element (gets true focused element)
        let systemWide = AXUIElementCreateSystemWide()

        // Get focused app
        var focusedApp: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
           focusedApp != nil {
            targetApp = (focusedApp! as! AXUIElement)

            // Get PID from the AX app
            var pid: pid_t = 0
            AXUIElementGetPid(targetApp!, &pid)
            targetPID = pid
        } else if let frontApp = NSWorkspace.shared.frontmostApplication {
            // Fallback to NSWorkspace
            targetPID = frontApp.processIdentifier
            targetApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        } else {
            targetPID = nil
            targetApp = nil
            targetElement = nil
            return
        }

        // Get focused UI element (the text field)
        var focusedEl: AnyObject?
        if let app = targetApp,
           AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedEl) == .success,
           focusedEl != nil {
            targetElement = (focusedEl! as! AXUIElement)
        } else {
            targetElement = nil
        }
    }

    private static let emailBundleIDs: Set<String> = [
        "com.apple.mail",
        "com.google.Gmail",
        "com.microsoft.Outlook",
        "com.readdle.smartemail",
        "com.superhuman.electron",
    ]

    private static let chatBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.facebook.archon",    // Messenger
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
        "com.apple.MobileSMS",
        "us.zoom.xos",
    ]

    private static let codeBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "dev.zed.Zed",
        "com.jetbrains.intellij",
    ]

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "net.kovidgoyal.kitty",
    ]

    /// Detect what kind of app the user is dictating into
    func detectAppType() -> String {
        let bid = appBundleID
        if Self.emailBundleIDs.contains(bid) { return "email" }
        if Self.chatBundleIDs.contains(bid) { return "chat" }
        if Self.codeBundleIDs.contains(bid) { return "code" }
        if Self.terminalBundleIDs.contains(bid) { return "terminal" }
        // Heuristic: browsers with common webmail/chat URLs could be detected too
        if bid.contains("browser") || bid.contains("Safari") || bid.contains("Chrome") {
            return "browser"
        }
        return "document"
    }

    /// Read existing text and selection from the focused element
    private func captureContext() {
        contextBefore = ""
        selectedText = ""
        appName = ""
        appBundleID = ""

        // Get app info
        if let pid = targetPID,
           let app = NSRunningApplication(processIdentifier: pid) {
            appName = app.localizedName ?? ""
            appBundleID = app.bundleIdentifier ?? ""
        }

        guard let element = targetElement else { return }

        // Read selected text (if any — indicates "edit/command" mode)
        var selValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selValue) == .success,
           let sel = selValue as? String, !sel.isEmpty {
            selectedText = String(sel.prefix(500))
        }

        // Read surrounding text for context (up to last 300 chars)
        var textValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
           let fullText = textValue as? String {
            // Get cursor position to grab text before it
            var rangeValue: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
               rangeValue != nil {
                let range = rangeValue! as! AXValue
                var cfRange = CFRange(location: 0, length: 0)
                if AXValueGetValue(range, .cfRange, &cfRange) {
                    let cursorPos = cfRange.location
                    let start = max(0, cursorPos - 300)
                    let startIdx = fullText.index(fullText.startIndex, offsetBy: min(start, fullText.count))
                    let endIdx = fullText.index(fullText.startIndex, offsetBy: min(cursorPos, fullText.count))
                    if startIdx < endIdx {
                        contextBefore = String(fullText[startIdx..<endIdx])
                    }
                }
            } else {
                // No cursor info — use last 300 chars
                contextBefore = String(fullText.suffix(300))
            }
        }
    }

    private func processDictation() async {
        do {
            pipelineLog("processDictation: transcribing...")
            let transcript = try await speechEngine.transcribe()
            pipelineLog("transcript: \(transcript.prefix(50))")
            lastTranscript = transcript

            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                pipelineLog("empty transcript, returning idle")
                state = .idle
                return
            }

            state = .enhancing
            pipelineLog("enhancing...")
            let apiKey = UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? ""

            let appType = detectAppType()
            let enhanced: String
            if apiKey.isEmpty {
                enhanced = transcript
            } else {
                enhanced = try await textEnhancer.enhance(
                    transcript: transcript,
                    apiKey: apiKey,
                    contextBefore: contextBefore,
                    selectedText: selectedText,
                    appName: appName,
                    appType: appType
                )
            }
            lastEnhanced = enhanced

            pipelineLog("enhanced: \(enhanced.prefix(50))")
            // Insert text at the captured target
            state = .inserting
            pipelineLog("inserting text...")
            let inserter = textInserter
            let pid = targetPID
            let app = targetApp
            let element = targetElement
            let isTrusted = AXIsProcessTrusted()
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    inserter.insertText(enhanced, targetPID: pid, targetApp: app, targetElement: element, isTrusted: isTrusted)
                    continuation.resume()
                }
            }

            dictationCount += 1
            history.insert(DictationEntry(text: enhanced, timestamp: Date()), at: 0)
            if history.count > maxHistory {
                history = Array(history.prefix(maxHistory))
            }
            state = .idle
        } catch {
            state = .error(error.localizedDescription)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            state = .idle
        }
    }
}
