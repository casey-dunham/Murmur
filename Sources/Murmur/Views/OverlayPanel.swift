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

// MARK: - Waveform bars — used for both recording (live audio) and processing (gentle pulse)

struct WaveformView: View {
    let audioLevel: Float
    let isProcessing: Bool
    let barCount = 7

    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: barHeight(for: i))
            }
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.12), value: audioLevel)
        .animation(.easeInOut(duration: 0.8), value: pulsePhase)
        .onChange(of: isProcessing) { _, processing in
            if processing {
                startPulsing()
            } else {
                pulsePhase = 0
            }
        }
        .onAppear {
            if isProcessing { startPulsing() }
        }
    }

    private func startPulsing() {
        // Continuously cycle pulse phase for a gentle breathing animation
        func cycle() {
            guard isProcessing else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                pulsePhase = pulsePhase == 0 ? 1 : 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { cycle() }
        }
        pulsePhase = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { cycle() }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let offsets: [CGFloat] = [0.5, 0.75, 1.0, 0.85, 0.95, 0.7, 0.55]
        let base: CGFloat = 4

        if isProcessing {
            // Gentle pulsing — bars breathe between small and medium height
            let pulseOffsets: [CGFloat] = [0.3, 0.5, 0.7, 0.6, 0.65, 0.45, 0.35]
            let low: CGFloat = 4
            let high: CGFloat = low + 10 * pulseOffsets[index]
            return low + (high - low) * pulsePhase
        }

        // Live audio — bars react to mic level
        let raw = CGFloat(audioLevel)
        let boosted = pow(max(raw, 0), 0.4)
        let maxExtra: CGFloat = 25
        return base + maxExtra * boosted * offsets[index]
    }
}

// MARK: - Overlay content

struct OverlayView: View {
    @ObservedObject var pipeline: DictationPipeline

    private var isRecording: Bool { pipeline.state == .recording }
    private var isProcessing: Bool {
        switch pipeline.state {
        case .transcribing, .enhancing, .inserting: return true
        default: return false
        }
    }

    private var dotColor: Color {
        switch pipeline.state {
        case .recording: return .red
        case .transcribing, .enhancing: return .orange
        case .inserting: return .green
        default: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            // Same waveform bars throughout — live audio when recording, pulse when processing
            WaveformView(
                audioLevel: pipeline.audioLevel,
                isProcessing: isProcessing
            )
            .frame(width: 40)
        }
        .animation(.easeInOut(duration: 0.3), value: dotColor)
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

        if panel == nil {
            panel = OverlayPanel()
            let hostingView = NSHostingView(rootView: OverlayView(pipeline: pipeline))
            hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 52)
            panel?.contentView = hostingView
        }

        // Only animate in if not already visible — avoids blink on state transitions
        guard !isShowing else { return }
        isShowing = true

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
