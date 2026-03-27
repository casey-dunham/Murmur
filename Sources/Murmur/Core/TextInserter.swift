import Cocoa
import ApplicationServices

private func log(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    let path = "/tmp/murmur_debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

class TextInserter: @unchecked Sendable {

    private let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "net.kovidgoyal.kitty",
    ]

    func insertText(_ text: String, targetPID: pid_t?, targetApp: AXUIElement?, targetElement: AXUIElement?, isTrusted: Bool = false) {
        log("insertText: pid=\(targetPID ?? -1), trusted=\(isTrusted), hasElement=\(targetElement != nil)")

        // Activate the target app
        activateApp(pid: targetPID)

        let isTerminal = isTerminalApp(pid: targetPID)
        log("isTerminal=\(isTerminal)")

        // For non-terminal apps with AX trust, try direct insertion (cleanest)
        if isTrusted && !isTerminal {
            if let element = targetElement, insertViaAX(text, element: element) {
                log("AX insert succeeded")
                return
            }
            if let app = targetApp {
                var focusedEl: AnyObject?
                if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedEl) == .success,
                   focusedEl != nil {
                    let element = focusedEl! as! AXUIElement
                    if insertViaAX(text, element: element) {
                        log("AX insert (re-queried) succeeded")
                        return
                    }
                }
            }
        }

        // Clipboard + paste (works everywhere)
        log("Using clipboard paste")
        pasteViaClipboard(text, targetPID: targetPID, isTrusted: isTrusted)
    }

    private func isTerminalApp(pid: pid_t?) -> Bool {
        guard let pid = pid,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier else { return false }
        return terminalBundleIDs.contains(bundleID)
    }

    private func activateApp(pid: pid_t?) {
        guard let pid = pid,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        log("Activating \(app.localizedName ?? "?") pid=\(pid)")
        app.activate()
        usleep(300_000) // 300ms
    }

    private func insertViaAX(_ text: String, element: AXUIElement) -> Bool {
        var selectedRange: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            log("AX setSelectedText: \(result.rawValue)")
            return result == .success
        }
        return false
    }

    private func pasteViaClipboard(_ text: String, targetPID: pid_t?, isTrusted: Bool) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        log("Clipboard set")

        if isTrusted, let pid = targetPID {
            // If we have AX trust, use CGEvent (fastest)
            let source = CGEventSource(stateID: .combinedSessionState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
                log("FAIL: Could not create CGEvents")
                return
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
            log("Cmd+V via CGEvent to pid \(pid)")
        } else {
            // No AX trust — use osascript which has its own permissions
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", """
                tell application "System Events"
                    keystroke "v" using command down
                end tell
            """]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                log("osascript paste exit=\(process.terminationStatus)")
            } catch {
                log("osascript failed: \(error)")
            }
        }

        // Restore clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}
