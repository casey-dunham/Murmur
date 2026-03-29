import Cocoa
import Carbon

extension NSSound {
    static let tink = NSSound(named: "Tink")
    static let pop = NSSound(named: "Pop")
}

private func hkLog(_ msg: String) {
    let line = "[\(Date())] HOTKEY: \(msg)\n"
    let path = "/tmp/murmur_debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

class HotkeyManager {
    var onRecordingStart: (() -> Void)?
    var onRecordingStop: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Fn state
    private var isFnHeld = false

    // Double-tap detection: based on time between DOWN events
    private var lastFnDownTime: Date?
    private var isToggleRecording = false
    private var ignoreNextFnUp = false

    // Deferred stop — allows double-tap detection window
    private var deferredStop: DispatchWorkItem?

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

        hkLog("monitors started")
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
        guard event.timestamp != lastEventTimestamp else { return }
        lastEventTimestamp = event.timestamp

        if event.type == .flagsChanged && event.keyCode == 63 {
            let fnPressed = event.modifierFlags.contains(.function)
            let otherMods: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if !event.modifierFlags.intersection(otherMods).isEmpty { return }

            if fnPressed {
                handleFnDown()
            } else {
                handleFnUp()
            }
        } else if event.type == .keyDown && isToggleRecording {
            hkLog("key pressed during toggle (keyCode=\(event.keyCode)), stopping")
            finishToggle()
        }
    }

    // MARK: - Fn DOWN

    private func handleFnDown() {
        guard !isFnHeld else { return }
        isFnHeld = true

        let now = Date()
        let sinceLastDown = lastFnDownTime.map { now.timeIntervalSince($0) }
        lastFnDownTime = now

        hkLog("Fn DOWN, sinceLastDown=\(sinceLastDown.map { String(format: "%.3f", $0) } ?? "nil"), toggle=\(isToggleRecording)")

        // If already in toggle mode, fn press means stop
        if isToggleRecording {
            hkLog("  -> fn pressed in toggle mode, will stop on release")
            // Don't stop until release so we don't fire a stray character
            return
        }

        // Check for double-tap: two fn DOWNs within 0.8s
        if let gap = sinceLastDown, gap < 0.8 {
            hkLog("  -> DOUBLE TAP detected (gap=\(String(format: "%.3f", gap))s)")
            deferredStop?.cancel()
            deferredStop = nil
            isToggleRecording = true
            ignoreNextFnUp = true

            // Make sure recording is active
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStart?()
            }
            return
        }

        // Single press — start recording
        deferredStop?.cancel()
        deferredStop = nil

        DispatchQueue.main.async { [weak self] in
            NSSound.tink?.play()
            self?.onRecordingStart?()
        }
    }

    // MARK: - Fn UP

    private func handleFnUp() {
        guard isFnHeld else { return }
        isFnHeld = false

        hkLog("Fn UP, ignoreNext=\(ignoreNextFnUp), toggle=\(isToggleRecording)")

        // If this UP is from the double-tap press, ignore it
        if ignoreNextFnUp {
            hkLog("  -> ignoring (double-tap release)")
            ignoreNextFnUp = false
            return
        }

        // If in toggle mode, fn release stops recording
        if isToggleRecording {
            hkLog("  -> stopping toggle")
            finishToggle()
            return
        }

        // Normal release — defer the stop to allow double-tap detection
        hkLog("  -> deferring stop (0.6s)")
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isToggleRecording else { return }
            hkLog("  -> deferred stop fired")
            DispatchQueue.main.async {
                NSSound.pop?.play()
                self.onRecordingStop?()
            }
        }
        deferredStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - Stop toggle recording

    private func finishToggle() {
        hkLog("finishToggle")
        isToggleRecording = false
        ignoreNextFnUp = false
        lastFnDownTime = nil
        deferredStop?.cancel()
        deferredStop = nil
        DispatchQueue.main.async { [weak self] in
            NSSound.pop?.play()
            self?.onRecordingStop?()
        }
    }
}
