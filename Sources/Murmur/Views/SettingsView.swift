import SwiftUI
import AVFoundation

struct SettingsView: View {
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""
    @Environment(\.dismiss) private var dismiss

    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            // API Key
            GroupBox("Claude API Key") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Used for transcript cleanup. Without it, raw transcription is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }

            // Hotkey
            GroupBox("Hotkey") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        KeyCap("fn")
                        Text("Hold to dictate, release to insert")
                            .font(.caption)
                    }
                    HStack(spacing: 6) {
                        KeyCap("fn")
                        KeyCap("fn")
                        Text("Double-tap to toggle (any key stops)")
                            .font(.caption)
                    }
                }
                .padding(4)
            }

            // Permissions
            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 8) {
                    permissionRow("Microphone", granted: microphoneGranted)
                    permissionRow("Accessibility", granted: accessibilityGranted)

                    if !accessibilityGranted {
                        Button("Open Accessibility Settings") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            )
                        }
                        .font(.caption)
                    }
                }
                .padding(4)
            }

            Spacer()

            HStack {
                Button("Refresh Permissions") {
                    checkPermissions()
                }
                .font(.caption)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360, height: 420)
        .onAppear {
            checkPermissions()
        }
    }

    private func permissionRow(_ name: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(name)
                .font(.subheadline)
        }
    }

    private func checkPermissions() {
        // Check accessibility — use AXIsProcessTrusted() directly
        accessibilityGranted = AXIsProcessTrusted()

        // Check microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.microphoneGranted = granted
                }
            }
        default:
            microphoneGranted = false
        }
    }
}

struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.primary.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
            }
    }
}
