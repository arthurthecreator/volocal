import Foundation
import AVFoundation
import FluidAudio
import os

private let logger = Logger(subsystem: "com.volocal.app", category: "tts")

/// Wraps FluidAudio's PocketTtsManager for on-device streaming text-to-speech.
/// Uses SharedAudioEngine for audio output instead of creating its own AVAudioEngine.
@MainActor
final class TTSManager: ObservableObject {
    @Published var isSpeaking: Bool = false
    @Published var selectedVoice: String = "alba"
    @Published var error: String?

    private var engine: PocketTtsManager?
    private var speakTask: Task<Void, Never>?
    private var hasTrackedFirstInference = false
    var metrics: SystemMetrics?

    /// Shared audio engine — injected by VoicePipeline
    weak var sharedAudio: SharedAudioEngine?

    static let voiceNames = ModelRegistry.pocketTtsVoices

    init() {}

    /// Load the bundled PocketTTS models, then run a dummy generation to warm up.
    /// Does not download. A missing bundle fails before FluidAudio can reach the network.
    func initialize() async {
        guard let bundleDir = ModelRegistry.pocketTtsBaseDirectory, ModelRegistry.pocketTtsModelsPresent else {
            self.error = "Text-to-speech models are missing from the app bundle. Rebuild the app. Volocal does not download them."
            logger.error("Bundled PocketTTS models are missing")
            return
        }

        do {
            try await loadEngine(directory: bundleDir)
        } catch {
            logger.error("Could not load PocketTTS from the app bundle: \(error.localizedDescription). Copying the bundled files locally with no network.")
            do {
                let localDir = try ModelRegistry.copyPocketTtsToCache(from: bundleDir)
                try await loadEngine(directory: localDir)
            } catch {
                self.error = "TTS init failed: \(error.localizedDescription)"
                return
            }
        }

        do {
            // Warm up: force CoreML to compile models
            logger.info("TTS warmup: running dummy generation...")
            guard let engine else { throw TTSError.engineNotLoaded }
            let stream = try await engine.synthesizeStreaming(text: "Hi", voice: "alba")
            for try await _ in stream {
                break // One frame is enough
            }
            logger.info("TTS warmup done")
        } catch {
            self.error = "TTS init failed: \(error.localizedDescription)"
        }
    }

    private func loadEngine(directory: URL) async throws {
        let manager = PocketTtsManager(directory: directory)
        try await manager.initialize()
        self.engine = manager
    }

    /// Synthesize text via streaming and play frames through shared audio engine.
    func speak(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        speakTask?.cancel()

        isSpeaking = true
        error = nil

        let speakTimeout: TimeInterval = 30
        let task = Task {
            do {
                guard let engine = engine else {
                    throw TTSError.engineNotLoaded
                }
                guard let sharedAudio else {
                    throw TTSError.noSharedAudio
                }

                logger.info("speak start: \"\(text)\"")

                if !hasTrackedFirstInference {
                    metrics?.beginTracking("TTS (PocketTTS)")
                }

                let genStart = CFAbsoluteTimeGetCurrent()
                var chunkCount = 0

                let stream = try await engine.synthesizeStreaming(
                    text: text,
                    voice: selectedVoice,
                    temperature: 0.4
                )

                for try await frame in stream {
                    if !hasTrackedFirstInference {
                        hasTrackedFirstInference = true
                        metrics?.endTracking("TTS (PocketTTS)")
                    }
                    if Task.isCancelled { break }

                    if CFAbsoluteTimeGetCurrent() - genStart > speakTimeout {
                        logger.warning("speak timeout after \(speakTimeout)s, aborting")
                        break
                    }

                    chunkCount += 1
                    logger.debug("chunk \(chunkCount): \(frame.samples.count) samples")
                    sharedAudio.scheduleTTSBuffer(frame.samples)
                }

                logger.info("speak generation done: \(chunkCount) chunks")

                if !Task.isCancelled && chunkCount > 0 {
                    await sharedAudio.waitForPlaybackCompletion()
                }
            } catch {
                if !Task.isCancelled {
                    logger.error("speak failed: \(error.localizedDescription)")
                    self.error = "TTS failed: \(error.localizedDescription)"
                }
            }
            if !Task.isCancelled {
                self.isSpeaking = false
            }
            logger.info("speak end")
        }
        // Set speakTask BEFORE await to avoid race condition (bug #2.10)
        speakTask = task
        await task.value
    }

    /// Stop all audio playback and cancel in-flight generation.
    func stop() {
        speakTask?.cancel()
        speakTask = nil
        sharedAudio?.stopPlayback()
        isSpeaking = false
    }
}

enum TTSError: LocalizedError {
    case engineNotLoaded
    case noSharedAudio

    var errorDescription: String? {
        switch self {
        case .engineNotLoaded:
            return "TTS engine not loaded. Call initialize() first."
        case .noSharedAudio:
            return "No shared audio engine available."
        }
    }
}
