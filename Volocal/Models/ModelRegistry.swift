import Foundation
import FluidAudio

/// Local model locations. The app never downloads weights.
///
/// Each model is resolved from the app Documents directory first (Finder file
/// sharing or `devicectl … --domain-type appDataContainer`), then from the
/// app bundle if the same relative path was embedded at build time.
enum ModelRegistry {
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

        var sizeDescription: String {
            switch self {
            case .llm: return "1.40 GB"
            case .stt: return "~450 MB"
            case .tts: return "~600 MB"
            }
        }

        var detail: String {
            switch self {
            case .llm: return "Qwen3.5-2B Q4_K_M"
            case .stt: return "Parakeet EOU 320"
            case .tts: return "PocketTTS"
            }
        }
    }

    // MARK: - LLM

    /// Exact filename on https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF
    static let llmFilename = "Qwen_Qwen3.5-2B-Q4_K_M.gguf"

    /// LFS size from the Hugging Face tree API (`lfs.size`), 2026-10-26.
    /// The model card table rounds this to 1.40 GB.
    static let llmSizeBytes: Int64 = 1_396_198_496

    static let llmHuggingFaceRepo = "bartowski/Qwen_Qwen3.5-2B-GGUF"

    /// llama.cpp context length (`n_ctx`).
    static let llmContextSize: UInt32 = 8192

    // MARK: - PocketTTS voices the in-app list can select

    /// Must already be on disk. `PocketTtsResourceDownloader.ensureVoice`
    /// would otherwise fetch a missing prompt from Hugging Face.
    static let pocketTTSVoiceNames = [
        "alba", "marius", "javert", "jean",
        "fantine", "cosette", "eponine", "azelma"
    ]

    // MARK: - Documents / bundle roots

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// `Documents/models` — LLM GGUF and the Parakeet tree. Not used for PocketTTS.
    static var modelsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var llmModelPath: String? {
        resolvedLLMFile()?.path
    }

    static func sttModelDirectory() -> URL? {
        let relative = Repo.parakeetEou320.folderName
        let required = ModelNames.ParakeetEOU.requiredModels
        for root in modelsRoots() {
            let dir = url(root, relative)
            let complete = required.allSatisfy { name in
                FileManager.default.fileExists(atPath: url(dir, name).path)
            }
            if complete { return dir }
        }
        return nil
    }

    /// Base directory passed to `PocketTtsManager(directory:)`.
    /// FluidAudio appends `Models/pocket-tts` (`PocketTtsConstants.defaultModelsSubdirectory`
    /// + `Repo.pocketTts.folderName`). The `Models` segment is case-sensitive.
    static func ttsBaseDirectory() -> URL? {
        ttsBaseCandidates().first { ttsRepoIsComplete($0) }
    }

    static func llmMissingMessage() -> String {
        var lines = [
            "Modèle LLM absent. L’app ne télécharge rien.",
            "Fichier attendu : \(llmFilename)",
            "Taille exacte : \(llmSizeBytes) octets (1,40 Go, Q4_K_M).",
            "Source : https://huggingface.co/\(llmHuggingFaceRepo)",
            "Documents : models/\(llmFilename)",
            "(Finder : la racine « Fichiers » de Volocal est Documents.)",
            "Bundle : models/\(llmFilename)"
        ]
        for url in llmCandidates() {
            guard let size = fileSize(url), size != llmSizeBytes else { continue }
            lines.append("Trouvé \(size) octets à \(url.path) — taille attendue \(llmSizeBytes).")
        }
        return lines.joined(separator: "\n")
    }

    static func sttMissingMessage() -> String {
        let files = ModelNames.ParakeetEOU.requiredModels.sorted().joined(separator: "\n• ")
        let relative = "models/\(Repo.parakeetEou320.folderName)/"
        return """
        Modèle STT absent. L’app ne télécharge rien.
        Dossier attendu : \(relative)
        Fichiers :
        • \(files)
        Source : https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml (dossier HF `320ms/`, à placer sous `parakeet-eou-streaming/320ms/`).
        Documents : \(relative)
        Bundle : \(relative)
        """
    }

    static func ttsMissingMessage() -> String {
        let relative = "\(PocketTtsConstants.defaultModelsSubdirectory)/\(Repo.pocketTts.folderName)/"
        let files = ttsRequiredRelativePaths().map { "• \(relative)\($0)" }.joined(separator: "\n")
        return """
        Modèle TTS absent. L’app ne télécharge rien.
        Dossier attendu : \(relative)
        (le M de Models est une majuscule — exigé par FluidAudio.)
        Source : https://huggingface.co/FluidInference/pocket-tts-coreml (racine du repo, pas `v2/`).
        Copier aussi tout `constants_bin/`, y compris `mimi_init_state/`.
        Fichiers vérifiés :
        \(files)
        Documents : \(relative)
        Bundle : \(relative)
        """
    }

    // MARK: - Private resolution

    private static func modelsRoots() -> [URL] {
        var roots = [modelsDirectory]
        if let resource = Bundle.main.resourceURL {
            roots.append(resource.appendingPathComponent("models", isDirectory: true))
        }
        return roots
    }

    private static func llmCandidates() -> [URL] {
        var urls = modelsRoots().map { url($0, llmFilename) }
        if let loose = Bundle.main.url(forResource: "Qwen_Qwen3.5-2B-Q4_K_M", withExtension: "gguf") {
            urls.append(loose)
        }
        return urls
    }

    private static func resolvedLLMFile() -> URL? {
        llmCandidates().first { fileSize($0) == llmSizeBytes }
    }

    private static func ttsBaseCandidates() -> [URL] {
        var bases = [documentsDirectory]
        if let resource = Bundle.main.resourceURL {
            bases.append(resource)
        }
        return bases
    }

    private static func ttsRepoIsComplete(_ base: URL) -> Bool {
        let repo = url(base, "\(PocketTtsConstants.defaultModelsSubdirectory)/\(Repo.pocketTts.folderName)")
        return ttsRequiredRelativePaths().allSatisfy { relative in
            FileManager.default.fileExists(atPath: url(repo, relative).path)
        }
    }

    /// `appendingPathComponent` percent-encodes `/`. Relative paths are applied one component at a time.
    private static func url(_ root: URL, _ relative: String) -> URL {
        relative.split(separator: "/", omittingEmptySubsequences: true).reduce(root) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    /// Paths relative to `Models/pocket-tts/`, matching what FluidAudio loads
    /// without calling Hugging Face.
    private static func ttsRequiredRelativePaths() -> [String] {
        let cores = [
            ModelNames.PocketTTS.condStepFile,
            ModelNames.PocketTTS.flowlmStepFile,
            ModelNames.PocketTTS.flowDecoderFile,
            ModelNames.PocketTTS.mimiDecoderFile,
            ModelNames.PocketTTS.constantsBinDir + "/bos_emb.bin",
            ModelNames.PocketTTS.constantsBinDir + "/text_embed_table.bin",
            ModelNames.PocketTTS.constantsBinDir + "/tokenizer.model",
            ModelNames.PocketTTS.constantsBinDir + "/manifest.json",
            ModelNames.PocketTTS.constantsBinDir + "/mimi_init_state/attn0_cache.bin"
        ]
        let voices = pocketTTSVoiceNames.map {
            ModelNames.PocketTTS.constantsBinDir + "/\($0)_audio_prompt.bin"
        }
        return cores + voices
    }

    private static func fileSize(_ url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.int64Value
    }
}
