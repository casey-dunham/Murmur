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
        pipelineLog("captured target: pid=\(targetPID ?? -1), hasApp=\(targetApp != nil), hasElement=\(targetElement != nil)")

        state = .recording
        lastTranscript = ""
        lastEnhanced = ""

        do {
            try speechEngine.startRecording()
        } catch {
            state = .error("Recording failed: \(error.localizedDescription)")
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

            let enhanced: String
            if apiKey.isEmpty {
                enhanced = transcript
            } else {
                enhanced = try await textEnhancer.enhance(transcript: transcript, apiKey: apiKey)
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
