import Cocoa
import SwiftUI

class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 52),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Waveform bars driven by real audio level

struct WaveformView: View {
    let audioLevel: Float
    let barCount = 7

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: barHeight(for: i))
            }
        }
        .frame(height: 28)
        .animation(.interpolatingSpring(stiffness: 300, damping: 12), value: audioLevel)
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Amplify the signal — boost low levels so bars react to quiet speech
        let raw = CGFloat(audioLevel)
        let boosted = pow(raw, 0.4) // sqrt-ish curve makes quiet sounds more visible
        // Each bar has a different multiplier for organic wave shape
        let offsets: [CGFloat] = [0.5, 0.75, 1.0, 0.85, 0.95, 0.7, 0.55]
        let base: CGFloat = 3
        let maxExtra: CGFloat = 25
        return base + maxExtra * boosted * offsets[index]
    }
}

// MARK: - Overlay content

struct OverlayView: View {
    @ObservedObject var pipeline: DictationPipeline

    private var isRecording: Bool { pipeline.state == .recording }

    var body: some View {
        HStack(spacing: 10) {
            // Dot transitions color smoothly
            Circle()
                .fill(isRecording ? Color.red : Color.blue)
                .frame(width: 8, height: 8)

            // Waveform fades out, spinner fades in
            ZStack {
                WaveformView(audioLevel: isRecording ? pipeline.audioLevel : 0)
                    .opacity(isRecording ? 1 : 0)

                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
                    .opacity(isRecording ? 0 : 1)
            }
            .frame(width: 40)
        }
        .animation(.easeInOut(duration: 0.25), value: isRecording)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.black.opacity(0.75))
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                }
                .clipShape(Capsule())
        }
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        }
    }
}

// MARK: - Manager

@MainActor
class OverlayManager {
    private var panel: OverlayPanel?
    private let pipeline: DictationPipeline
    private var isShowing = false
    private var hideGeneration = 0

    init(pipeline: DictationPipeline) {
        self.pipeline = pipeline
    }

    func show() {
        // Cancel any pending hide
        hideGeneration += 1
        isShowing = true

        if panel == nil {
            panel = OverlayPanel()
            let hostingView = NSHostingView(rootView: OverlayView(pipeline: pipeline))
            hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 52)
            panel?.contentView = hostingView
        }

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 120
            let y = screenFrame.maxY - 64
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel?.alphaValue = 0
        panel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        guard isShowing else { return }
        let gen = hideGeneration

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel?.animator().alphaValue = 0
        }, completionHandler: {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.hideGeneration == gen else { return }
                self.isShowing = false
                self.panel?.orderOut(nil)
            }
        })
    }
}
