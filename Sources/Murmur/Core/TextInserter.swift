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
    func insertText(_ text: String, targetPID: pid_t?, targetApp: AXUIElement?, targetElement: AXUIElement?, isTrusted: Bool = false) {
        log("insertText: pid=\(targetPID ?? -1), trusted=\(isTrusted), hasElement=\(targetElement != nil)")

        // Activate the target app
        activateApp(pid: targetPID)

        // If trusted, try direct AX insertion first (no clipboard disruption)
        if isTrusted, let element = targetElement, insertViaAX(text, element: element) {
            log("AX insert succeeded")
            return
        }

        if isTrusted, let app = targetApp {
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

        // Clipboard + paste via osascript (runs as a separate trusted process)
        log("Using osascript paste")
        pasteViaOsascript(text, targetPID: targetPID)
    }

    private func activateApp(pid: pid_t?) {
        guard let pid = pid,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        log("Activating \(app.localizedName ?? "?") pid=\(pid)")
        app.activate()
        usleep(300_000)
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

    private func pasteViaOsascript(_ text: String, targetPID: pid_t?) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        log("Clipboard set")

        // Use osascript CLI (inherits Terminal's Accessibility trust)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """]

        do {
            try process.run()
            process.waitUntilExit()
            log("osascript exit code: \(process.terminationStatus)")
        } catch {
            log("osascript failed: \(error)")
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
