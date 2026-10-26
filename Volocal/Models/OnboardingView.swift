import SwiftUI

/// Shown only when a bundled model file is missing. There is no download.
struct OnboardingView: View {
    @EnvironmentObject var modelManager: UnifiedModelManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    Text("Volocal")
                        .font(.largeTitle.bold())

                    Text("On-device voice AI")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(ModelRegistry.ModelType.allCases) { type in
                        ModelStatusCard(
                            type: type,
                            state: modelManager.modelStates[type] ?? .error(ModelRegistry.missingBundledModelsMessage)
                        )
                    }
                }
                .padding(.horizontal)

                Text("The language, speech recognition, and text-to-speech models are included in the app. A missing file is a build problem. Volocal does not download models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let error = modelManager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("")
        }
    }
}

// MARK: - Model Status Card

struct ModelStatusCard: View {
    let type: ModelRegistry.ModelType
    let state: UnifiedModelManager.ModelState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(state.isReady ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(type.displayName)
                        .font(.body.weight(.medium))
                    Spacer()
                    statusLabel
                }

                Text(type.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if state.isReady {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch state {
        case .downloaded:
            Text("Included")
                .font(.caption)
                .foregroundStyle(.green)
        case .error(let msg):
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }
}
