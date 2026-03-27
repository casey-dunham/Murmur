import SwiftUI

struct MenuBarView: View {
    @ObservedObject var pipeline: DictationPipeline
    @State private var showSettings = false
    @State private var copiedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Murmur")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Status pill
            statusPill
                .padding(.horizontal, 12)

            Divider()
                .padding(.top, 12)

            // History
            if pipeline.history.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 24))
                        .foregroundStyle(.quaternary)
                    Text("Hold fn to dictate")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                HStack {
                    Text("Recent")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Spacer()
                    Button("Clear") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            pipeline.clearHistory()
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(pipeline.history) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(pipeline.dictationCount) dictation\(pipeline.dictationCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                Spacer()
                Button("Quit Murmur") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 300, height: 400)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.system(size: 12, weight: .medium))

            Spacer()

            if pipeline.state == .recording {
                WaveformView(audioLevel: pipeline.audioLevel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statusBackground)
        }
    }

    private var statusColor: Color {
        switch pipeline.state {
        case .idle: return .green
        case .recording: return .red
        case .transcribing, .enhancing: return .orange
        case .inserting: return .blue
        case .error: return .red
        }
    }

    private var statusBackground: Color {
        switch pipeline.state {
        case .recording: return .red.opacity(0.1)
        default: return .primary.opacity(0.04)
        }
    }

    private var statusText: String {
        switch pipeline.state {
        case .idle: return "Ready"
        case .recording: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .enhancing: return "Cleaning up..."
        case .inserting: return "Inserting..."
        case .error(let msg): return msg
        }
    }

    // MARK: - History Row

    private func historyRow(_ entry: DictationEntry) -> some View {
        Button {
            pipeline.copyToClipboard(entry.text)
            copiedId = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedId == entry.id { copiedId = nil }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    Text(entry.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
                Spacer(minLength: 4)

                Group {
                    if copiedId == entry.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.quaternary)
                    }
                }
                .font(.system(size: 10))
                .frame(width: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(0.00001)) // hit area
        }
    }
}
