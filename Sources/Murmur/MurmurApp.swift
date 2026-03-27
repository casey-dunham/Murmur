import Cocoa
import SwiftUI
import Combine

@main
struct MurmurApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let hotkeyManager = HotkeyManager()
    private let pipeline = DictationPipeline()
    private var overlayManager: OverlayManager?
    private var stateObserver: AnyCancellable?
    private var clickOutsideMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prompt for permissions on first launch
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        SpeechEngine.requestPermissions()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let contentView = MenuBarView(pipeline: pipeline)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Set up floating overlay
        overlayManager = OverlayManager(pipeline: pipeline)
        stateObserver = pipeline.$state.sink { [weak self] state in
            switch state {
            case .idle:
                self?.overlayManager?.hide()
            case .recording, .transcribing, .enhancing, .inserting:
                self?.overlayManager?.show()
            case .error:
                // Brief show then hide (pipeline auto-resets to idle)
                self?.overlayManager?.show()
            }
        }

        hotkeyManager.onRecordingStart = { [weak self] in
            self?.pipeline.startDictation()
        }
        hotkeyManager.onRecordingStop = { [weak self] in
            self?.pipeline.stopDictation()
        }
        hotkeyManager.startMonitoring()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            // Monitor for clicks outside to close
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
