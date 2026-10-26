import Foundation
import FluidAudio
import os

private let logger = Logger(subsystem: "com.volocal.app", category: "models")

/// Tracks readiness of the three models.
/// The LLM is read from the app bundle. STT and TTS are still downloaded
/// at runtime via FluidAudio; those paths are unchanged.
@MainActor
final class UnifiedModelManager: ObservableObject {
    @Published var modelStates: [ModelRegistry.ModelType: ModelState] = [:]
    @Published var error: String?

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case error(String)

        var isReady: Bool {
            if case .downloaded = self { return true }
            return false
        }

        var progress: Double {
            if case .downloading(let p) = self { return p }
            if case .downloaded = self { return 1.0 }
            return 0
        }
    }

    var allModelsReady: Bool {
        ModelRegistry.ModelType.allCases.allSatisfy { modelStates[$0]?.isReady == true }
    }

    var llmModelPath: String? {
        ModelRegistry.llmModelPath
    }

    init() {
        checkExistingModels()
    }

    private func checkExistingModels() {
        refreshBundledLLM()

        // STT: check if Parakeet EOU models exist
        let sttDir = ModelRegistry.modelsDirectory.appendingPathComponent(Repo.parakeetEou320.folderName)
        let encoderPath = sttDir.appendingPathComponent("streaming_encoder.mlmodelc")
        if FileManager.default.fileExists(atPath: encoderPath.path) {
            modelStates[.stt] = .downloaded
        } else {
            modelStates[.stt] = .notDownloaded
        }

        // TTS: check if PocketTTS models exist in its cache directory
        if Self.pocketTTSModelsExist() {
            modelStates[.tts] = .downloaded
        } else {
            modelStates[.tts] = .notDownloaded
        }
    }

    /// The language model ships inside the app. A missing file is a build
    /// problem, not something the user can download on first launch.
    private func refreshBundledLLM() {
        if ModelRegistry.llmModelPath != nil {
            modelStates[.llm] = .downloaded
        } else {
            modelStates[.llm] = .error("Missing from the app bundle. Rebuild so the GGUF is copied in.")
        }
    }

    /// Check if PocketTTS models are cached.
    /// PocketTTS stores models at ~/Library/Caches/fluidaudio/Models/pocket-tts/
    private static func pocketTTSModelsExist() -> Bool {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let repoDir = cachesDir
            .appendingPathComponent("fluidaudio")
            .appendingPathComponent("Models")
            .appendingPathComponent("pocket-tts")

        // Check for a key model file
        let condStepPath = repoDir.appendingPathComponent("cond_step.mlmodelc")
        return FileManager.default.fileExists(atPath: condStepPath.path)
    }

    // MARK: - Download

    /// Downloads speech models only. The LLM is not fetched at runtime.
    func downloadAllModels() async {
        await withTaskGroup(of: Void.self) { group in
            if modelStates[.stt]?.isReady != true {
                group.addTask { await self.downloadSTT() }
            }
            if modelStates[.tts]?.isReady != true {
                group.addTask { await self.downloadTTS() }
            }
        }
    }

    func retryModel(_ type: ModelRegistry.ModelType) async {
        error = nil

        switch type {
        case .llm:
            refreshBundledLLM()
        case .stt:
            modelStates[.stt] = .notDownloaded
            await downloadSTT()
        case .tts:
            modelStates[.tts] = .notDownloaded
            await downloadTTS()
        }
    }

    // MARK: - STT Download (FluidAudio with progress)

    private func downloadSTT() async {
        modelStates[.stt] = .downloading(progress: 0)

        do {
            try await DownloadUtils.downloadRepo(.parakeetEou320, to: ModelRegistry.modelsDirectory) { [weak self] progress in
                Task { @MainActor in
                    self?.modelStates[.stt] = .downloading(progress: progress.fractionCompleted)
                }
            }
            modelStates[.stt] = .downloaded
            logger.info("STT models downloaded successfully")
        } catch {
            modelStates[.stt] = .error(error.localizedDescription)
            self.error = "STT download failed: \(error.localizedDescription)"
            logger.error("STT download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - TTS Download (FluidAudio PocketTTS with progress)

    private func downloadTTS() async {
        modelStates[.tts] = .downloading(progress: 0)

        do {
            _ = try await PocketTtsResourceDownloader.ensureModels { [weak self] progress in
                Task { @MainActor in
                    self?.modelStates[.tts] = .downloading(progress: progress.fractionCompleted)
                }
            }
            modelStates[.tts] = .downloaded
            logger.info("TTS models downloaded successfully")
        } catch {
            modelStates[.tts] = .error(error.localizedDescription)
            self.error = "TTS download failed: \(error.localizedDescription)"
            logger.error("TTS download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    func deleteAllModels() {
        try? FileManager.default.removeItem(at: ModelRegistry.modelsDirectory)
        try? FileManager.default.createDirectory(at: ModelRegistry.modelsDirectory, withIntermediateDirectories: true)
        // Also clear PocketTTS cache. The bundled LLM is not deleted.
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let ttsCache = cachesDir.appendingPathComponent("fluidaudio")
            try? FileManager.default.removeItem(at: ttsCache)
        }
        checkExistingModels()
    }
}
