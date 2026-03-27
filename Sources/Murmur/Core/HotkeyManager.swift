import Cocoa
import Carbon

extension NSSound {
    static let tink = NSSound(named: "Tink")
    static let pop = NSSound(named: "Pop")
}

class HotkeyManager {
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Fn hold state
    private var isFnHeld = false
    private var fnPressTime: Date?

    // Double-tap Fn toggle state
    private var lastFnReleaseTime: Date?
    private var isToggleRecording = false

    // Deduplicate events from both monitors
    private var lastEventTimestamp: TimeInterval = 0

    func startMonitoring() {
        stopMonitoring()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        // Deduplicate — both monitors fire for events when app is focused
        guard event.timestamp != lastEventTimestamp else { return }
        lastEventTimestamp = event.timestamp

        if event.type == .flagsChanged {
            handleFnKey(event)
        } else if event.type == .keyDown && isToggleRecording {
            // Any non-Fn key press stops toggle recording
            if event.keyCode != 63 {
                stopToggleRecording()
            }
        }
    }

    private func handleFnKey(_ event: NSEvent) {
        // Only respond to the physical Fn/Globe key (keyCode 63)
        guard event.keyCode == 63 else { return }

        let fnPressed = event.modifierFlags.contains(.function)

        // Ignore if other modifiers are also held
        let otherMods: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let hasOtherMods = !event.modifierFlags.intersection(otherMods).isEmpty
        if hasOtherMods { return }

        if fnPressed && !isFnHeld {
            // Fn pressed down
            isFnHeld = true
            fnPressTime = Date()

            if isToggleRecording { return }

            DispatchQueue.main.async { [weak self] in
                NSSound.tink?.play()
                self?.onRecordingStart?()
            }

        } else if !fnPressed && isFnHeld {
            // Fn released
            isFnHeld = false
            let heldDuration = Date().timeIntervalSince(fnPressTime ?? Date())

            if isToggleRecording {
                return
            }

            if heldDuration < 0.25 {
                // Short tap — check for double tap
                if let lastRelease = lastFnReleaseTime,
                   Date().timeIntervalSince(lastRelease) < 0.4 {
                    // Double tap — switch to toggle mode (recording already started)
                    lastFnReleaseTime = nil
                    isToggleRecording = true
                    return
                }

                // Single short tap — cancel
                lastFnReleaseTime = Date()
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStop?()
                }
            } else {
                // Long hold released — stop recording
                lastFnReleaseTime = nil
                DispatchQueue.main.async { [weak self] in
                    NSSound.pop?.play()
                    self?.onRecordingStop?()
                }
            }
        }
    }

    private func stopToggleRecording() {
        isToggleRecording = false
        lastFnReleaseTime = nil
        DispatchQueue.main.async { [weak self] in
            NSSound.pop?.play()
            self?.onRecordingStop?()
        }
    }
}
