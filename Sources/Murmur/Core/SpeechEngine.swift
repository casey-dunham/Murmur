import Foundation
import AVFoundation
import Speech

class SpeechEngine {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var isRecording = false

    /// Published audio level (0.0–1.0) for waveform visualization
    var onAudioLevel: ((Float) -> Void)?

    /// Call once at app startup from main thread
    static func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    func startRecording() throws {
        let engine = AVAudioEngine()
        audioEngine = engine

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("murmur_\(UUID().uuidString).wav")
        tempFileURL = fileURL

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: recordingFormat.sampleRate,
                AVNumberOfChannelsKey: recordingFormat.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ]
        )

        isRecording = true

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, self.isRecording else { return }
            try? self.audioFile?.write(from: buffer)

            // Calculate RMS audio level
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrtf(sum / Float(frameLength))
            // Normalize to 0–1 range — boost heavily so quiet speech is visible
            let normalized = min(rms * 5.0, 1.0)
            self.onAudioLevel?(normalized)
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() {
        // Stop writing first to prevent data race with audio tap
        isRecording = false

        guard let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        audioFile = nil
    }

    func transcribe() async throws -> String {
        guard let fileURL = tempFileURL else {
            throw MurmurError.noRecording
        }
        defer { cleanup() }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw MurmurError.speechRecognizerUnavailable
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw MurmurError.speechNotAuthorized
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        var hasResumed = false
        var recognitionTask: SFSpeechRecognitionTask?

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                    guard !hasResumed else { return }

                    if let error = error {
                        hasResumed = true
                        continuation.resume(throwing: error)
                        return
                    }
                    if let result = result, result.isFinal {
                        hasResumed = true
                        continuation.resume(returning: result.bestTranscription.formattedString)
                        return
                    }
                    if result == nil && error == nil {
                        hasResumed = true
                        continuation.resume(returning: "")
                    }
                }
            }
        } onCancel: {
            recognitionTask?.cancel()
        }
    }

    func cleanup() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }
}

enum MurmurError: LocalizedError {
    case noRecording
    case speechRecognizerUnavailable
    case speechNotAuthorized
    case enhancementFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRecording:
            return "No recording found"
        case .speechRecognizerUnavailable:
            return "Speech recognizer is not available"
        case .speechNotAuthorized:
            return "Speech recognition not authorized"
        case .enhancementFailed(let reason):
            return "Text enhancement failed: \(reason)"
        }
    }
}
