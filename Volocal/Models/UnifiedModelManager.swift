import Foundation
import os

private let logger = Logger(subsystem: "com.volocal.app", category: "models")

/// Tracks whether the three local models are on disk.
/// There is no download path: missing weights stay missing until a file copy.
@MainActor
final class UnifiedModelManager: ObservableObject {
    @Published var modelStates: [ModelRegistry.ModelType: ModelState] = [:]
    @Published var error: String?

    enum ModelState: Equatable {
        case missing(String)
        case ready

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }

        var missingMessage: String? {
            if case .missing(let message) = self { return message }
            return nil
        }
    }

    var allModelsReady: Bool {
        ModelRegistry.ModelType.allCases.allSatisfy { modelStates[$0]?.isReady == true }
    }

    var llmModelPath: String? {
        ModelRegistry.llmModelPath
    }

    init() {
        refresh()
    }

    func refresh() {
        var missing: [String] = []

        if ModelRegistry.llmModelPath != nil {
            modelStates[.llm] = .ready
        } else {
            let message = ModelRegistry.llmMissingMessage()
            modelStates[.llm] = .missing(message)
            missing.append(message)
        }

        if ModelRegistry.sttModelDirectory() != nil {
            modelStates[.stt] = .ready
        } else {
            let message = ModelRegistry.sttMissingMessage()
            modelStates[.stt] = .missing(message)
            missing.append(message)
        }

        if ModelRegistry.ttsBaseDirectory() != nil {
            modelStates[.tts] = .ready
        } else {
            let message = ModelRegistry.ttsMissingMessage()
            modelStates[.tts] = .missing(message)
            missing.append(message)
        }

        error = missing.isEmpty ? nil : missing.joined(separator: "\n\n")
        if missing.isEmpty {
            logger.info("All local models are present")
        } else {
            logger.error("Missing local models (\(missing.count, privacy: .public))")
        }
    }
}
