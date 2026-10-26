import Foundation
import AVFoundation
import FluidAudio
import os

private let logger = Logger(subsystem: "com.volocal.app", category: "stt")

/// Wraps FluidAudio's StreamingEouAsrManager for real-time speech-to-text
/// with native end-of-utterance detection on Apple Neural Engine.
/// Uses SharedAudioEngine for mic input instead of creating its own AVAudioEngine.
@MainActor
final class STTManager: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var partialResult: String = ""
    @Published var error: String?

    /// Called when a complete utterance is detected (EOU)
    var onUtteranceCompleted: ((String) -> Void)?

    /// Called when speech is first detected (partial result arrives)
    var onSpeechDetected: (() -> Void)?

    /// Shared audio engine — injected by VoicePipeline
    weak var sharedAudio: SharedAudioEngine?

    private var asrManager: StreamingEouAsrManager?
    private var hasFiredSpeechDetected = false
    private var isStopping = false

    /// Serial stream for backpressure — prevents unbounded Task spawning per audio buffer
    private var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var processingTask: Task<Void, Never>?

    init() {}

    /// Load the bundled Parakeet EOU models. Does not download.
    func initialize() async {
        guard let bundleDir = ModelRegistry.parakeetModelDirectory, ModelRegistry.parakeetModelsPresent else {
            self.error = "Speech recognition models are missing from the app bundle. Rebuild the app. Volocal does not download them."
            logger.error("Bundled Parakeet EOU models are missing")
            return
        }

        do {
            let manager = StreamingEouAsrManager(chunkSize: .ms320, eouDebounceMs: 300)

            await manager.setPartialCallback { [weak self] text in
                Task { @MainActor in
                    guard let self, !self.isStopping else { return }
                    self.partialResult = text
                    let wordCount = text.split(separator: " ").count
                    if !self.hasFiredSpeechDetected && wordCount >= 2 {
                        self.hasFiredSpeechDetected = true
                        self.onSpeechDetected?()
                    }
                }
            }

            await manager.setEouCallback { [weak self] text in
                Task { @MainActor in
                    guard let self, !self.isStopping else { return }
                    let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !finalText.isEmpty else { return }
                    self.transcript = finalText
                    self.partialResult = ""
                    self.hasFiredSpeechDetected = false
                    self.onUtteranceCompleted?(finalText)
                }
            }

            do {
                logger.info("Loading Parakeet EOU models from \(bundleDir.path)...")
                try await manager.loadModels(modelDir: bundleDir)
            } catch {
                logger.error("Could not load Parakeet from the app bundle: \(error.localizedDescription). Copying the bundled files locally with no network.")
                let localDir = try ModelRegistry.copyParakeetToDocuments(from: bundleDir)
                logger.info("Loading Parakeet EOU models from \(localDir.path)...")
                try await manager.loadModels(modelDir: localDir)
            }
            self.asrManager = manager
            logger.info("Parakeet EOU ready")
        } catch {
            self.error = "STT init failed: \(error.localizedDescription)"
            logger.error("STT init failed: \(error.localizedDescription)")
        }
    }

    func startListening() {
        guard !isListening, asrManager != nil else {
            if asrManager == nil { error = "STT not initialized" }
            return
        }
        guard let sharedAudio else {
            error = "No shared audio engine"
            return
        }

        isStopping = false

        // Set up serial AsyncStream for backpressure
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        self.bufferContinuation = continuation

        let manager = asrManager!
        processingTask = Task {
            for await buffer in stream {
                guard !Task.isCancelled else { break }
                do {
                    _ = try await manager.process(audioBuffer: buffer)
                } catch {
                    await MainActor.run {
                        self.error = "STT error: \(error.localizedDescription)"
                    }
                }
            }
        }

        // Start mic capture with VP AEC (restarts engine with tap installed).
        // Set bridge continuation so tap handler delivers buffers to our stream.
        sharedAudio.bridge.inputContinuation = continuation
        sharedAudio.beginInputCapture()

        isListening = true
        transcript = ""
        partialResult = ""
        hasFiredSpeechDetected = false
        error = nil
        logger.info("STT listening started")
    }

    func stopListening() {
        isStopping = true

        // Stop mic capture and disconnect from stream
        sharedAudio?.endInputCapture()
        bufferContinuation?.finish()
        bufferContinuation = nil
        processingTask?.cancel()
        processingTask = nil

        isListening = false

        Task {
            _ = try? await asrManager?.finish()
            await asrManager?.reset()
        }

        logger.info("STT listening stopped")
    }

    /// Reset ASR state for next utterance without stopping the mic.
    func resetForNextUtterance() {
        hasFiredSpeechDetected = false
        partialResult = ""
        Task {
            await asrManager?.reset()
        }
    }

    /// Simulate a transcript for testing without a real microphone.
    func simulateTranscript(_ text: String) {
        transcript += text + "\n"
        partialResult = ""
        onUtteranceCompleted?(text)
    }
}
