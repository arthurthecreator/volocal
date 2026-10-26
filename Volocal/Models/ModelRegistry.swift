import Foundation

/// Central registry of all models used by Volocal.
/// The language model, Parakeet EOU, and PocketTTS are bundled in the app.
/// Nothing is downloaded at runtime.
enum ModelRegistry {
    /// All model types used in the app
    enum ModelType: String, CaseIterable, Identifiable {
        case llm
        case stt
        case tts

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .llm: return "Language Model"
            case .stt: return "Speech Recognition"
            case .tts: return "Text-to-Speech"
            }
        }

        var icon: String {
            switch self {
            case .llm: return "brain"
            case .stt: return "mic.fill"
            case .tts: return "speaker.wave.3.fill"
            }
        }

        var detail: String {
            switch self {
            case .llm: return "Qwen3.5-2B Instruct Q4_K_M"
            case .stt: return "Parakeet EOU 320"
            case .tts: return "PocketTTS"
            }
        }
    }

    static let missingBundledModelsMessage =
        "Missing from the app bundle. Rebuild so the models are copied in. Volocal does not download models."

    // MARK: - LLM
    //
    // Filename must match scripts/llm-gguf.lock. The build phase downloads
    // that file into Volocal/Resources/LLM and Xcode copies the folder into
    // the app bundle. There is no runtime Hugging Face download.

    static let llmFilename = "Qwen_Qwen3.5-2B-Q4_K_M.gguf"

    /// Subdirectory inside the app bundle (folder reference Resources/LLM).
    static let llmBundleSubdirectory = "LLM"

    // MARK: - Speech models
    //
    // These two strings are checked by scripts/fetch_audio_models.sh.
    // They are paths inside the app bundle. The build copies the folder
    // reference Volocal/Resources/Audio, so the same relative paths exist
    // under Volocal/Resources/ on disk.

    static let parakeetBundleRelativePath = "Audio/STT/parakeet-eou-streaming/320ms"
    static let pocketTtsBundleRelativePath = "Audio/TTS"

    /// Voices whose prompt files must be in the bundle. PocketTTS downloads
    /// a voice on demand when its file is missing; every name TTSManager
    /// can select is listed here so that path never runs.
    static let pocketTtsVoices = [
        "alba", "marius", "javert", "jean",
        "fantine", "cosette", "eponine", "azelma"
    ]

    // MARK: - Paths

    /// Path to the bundled GGUF, or nil if the build did not copy it in.
    static var llmModelPath: String? {
        let name = (llmFilename as NSString).deletingPathExtension
        let ext = (llmFilename as NSString).pathExtension
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: ext,
            subdirectory: llmBundleSubdirectory
        ) else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size > 1024 else { return nil }
        return url.path
    }

    /// Bundled Parakeet directory passed to `StreamingEouAsrManager.loadModels`.
    static var parakeetModelDirectory: URL? {
        bundleDirectory(parakeetBundleRelativePath)
    }

    /// Bundled PocketTTS base directory. `PocketTtsManager` appends
    /// `Models/pocket-tts` to this URL.
    static var pocketTtsBaseDirectory: URL? {
        bundleDirectory(pocketTtsBundleRelativePath)
    }

    static var parakeetModelsPresent: Bool {
        guard let directory = parakeetModelDirectory else { return false }
        let required = [
            "streaming_encoder.mlmodelc/weights/weight.bin",
            "decoder.mlmodelc/weights/weight.bin",
            "joint_decision.mlmodelc/weights/weight.bin",
            "vocab.json",
        ]
        return required.allSatisfy { nonEmptyFile(directory.appendingPathComponent($0)) }
    }

    static var pocketTtsModelsPresent: Bool {
        guard let base = pocketTtsBaseDirectory else { return false }
        let repo = base.appendingPathComponent("Models/pocket-tts", isDirectory: true)
        var required = [
            "cond_step.mlmodelc/weights/weight.bin",
            "flowlm_step.mlmodelc/weights/weight.bin",
            "flow_decoder.mlmodelc/weights/weight.bin",
            "mimi_decoder_v2.mlmodelc/weights/weight.bin",
            "constants_bin/tokenizer.model",
            "constants_bin/bos_emb.bin",
            "constants_bin/text_embed_table.bin",
            "constants_bin/manifest.json",
        ]
        required.append(contentsOf: pocketTtsVoices.map { "constants_bin/\($0)_audio_prompt.bin" })
        return required.allSatisfy { nonEmptyFile(repo.appendingPathComponent($0)) }
    }

    /// Copy the bundled Parakeet tree to Documents/models, which is the
    /// directory this app previously passed to FluidAudio. No network.
    static func copyParakeetToDocuments(from source: URL) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destination = docs
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("parakeet-eou-streaming", isDirectory: true)
            .appendingPathComponent("320ms", isDirectory: true)
        try replaceCopy(from: source, to: destination)
        return destination
    }

    /// Copy the bundled PocketTTS repo to Library/Caches/fluidaudio/Models,
    /// which is where PocketTtsManager looks when given that cache directory.
    /// Returns the cache directory to pass as `directory`. No network.
    static func copyPocketTtsToCache(from bundleBase: URL) throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let base = caches.appendingPathComponent("fluidaudio", isDirectory: true)
        let source = bundleBase.appendingPathComponent("Models/pocket-tts", isDirectory: true)
        let destination = base
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("pocket-tts", isDirectory: true)
        try replaceCopy(from: source, to: destination)
        return base
    }

    // MARK: - Private

    private static func bundleDirectory(_ relativePath: String) -> URL? {
        let root = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }

    private static func nonEmptyFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attrs[.size] as? NSNumber else {
            return false
        }
        return number.uint64Value > 0
    }

    private static func replaceCopy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.copyItem(at: source, to: destination)
    }
}
