import Foundation

/// Central registry of all models used by Volocal.
/// The language model is bundled in the app. Speech models are still
/// downloaded at runtime (see UnifiedModelManager); this file does not
/// change how those are obtained.
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

        /// Shown only while a model still needs a download. The LLM has no
        /// runtime download, so this string is not a download size for it.
        var sizeDescription: String {
            switch self {
            case .llm: return "Included"
            case .stt: return "~450 MB"
            case .tts: return "~600 MB"
            }
        }

        var detail: String {
            switch self {
            case .llm: return "Qwen3.5-2B Q4_K_S"
            case .stt: return "Parakeet EOU 320"
            case .tts: return "PocketTTS"
            }
        }
    }

    // MARK: - LLM
    //
    // Filename must match scripts/llm-gguf.lock. The build phase downloads
    // that file into Volocal/Resources/LLM and Xcode copies the folder into
    // the app bundle. There is no runtime Hugging Face download.

    static let llmFilename = "Qwen_Qwen3.5-2B-Q4_K_S.gguf"

    /// Subdirectory inside the app bundle (folder reference Resources/LLM).
    static let llmBundleSubdirectory = "LLM"

    // MARK: - Paths

    /// Documents directory used by the FluidAudio STT download. Not used for the LLM.
    static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

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
}
