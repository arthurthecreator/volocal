import Foundation

/// Tracks readiness of the three bundled models.
/// All three are read from the app bundle. Nothing is downloaded at runtime.
@MainActor
final class UnifiedModelManager: ObservableObject {
    @Published var modelStates: [ModelRegistry.ModelType: ModelState] = [:]
    @Published var error: String?

    enum ModelState: Equatable {
        case downloaded
        case error(String)

        var isReady: Bool {
            if case .downloaded = self { return true }
            return false
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
        if ModelRegistry.llmModelPath != nil {
            modelStates[.llm] = .downloaded
        } else {
            modelStates[.llm] = .error(ModelRegistry.missingBundledModelsMessage)
        }

        if ModelRegistry.parakeetModelsPresent {
            modelStates[.stt] = .downloaded
        } else {
            modelStates[.stt] = .error(ModelRegistry.missingBundledModelsMessage)
        }

        if ModelRegistry.pocketTtsModelsPresent {
            modelStates[.tts] = .downloaded
        } else {
            modelStates[.tts] = .error(ModelRegistry.missingBundledModelsMessage)
        }

        if allModelsReady {
            error = nil
        } else {
            error = "A model is missing from this build. Rebuild the app so the bundled models are copied in. Volocal does not download models."
        }
    }

    /// Bundled models are part of the app and cannot be deleted.
    /// This rechecks the bundle and updates readiness.
    func deleteAllModels() {
        checkExistingModels()
    }
}
