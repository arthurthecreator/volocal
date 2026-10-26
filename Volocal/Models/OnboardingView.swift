import SwiftUI

/// Shown until every model file is present in Documents or the bundle.
/// Copy is manual (Finder or devicectl). This screen never starts a download.
struct OnboardingView: View {
    @EnvironmentObject var modelManager: UnifiedModelManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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
                    .padding(.top, 24)

                    Text("Aucun téléchargement. Copiez les modèles dans Documents (Finder ou devicectl), ou embarquez-les dans le bundle. Le détail indique le nom de fichier et le dossier.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        ForEach(ModelRegistry.ModelType.allCases) { type in
                            ModelStatusCard(
                                type: type,
                                state: modelManager.modelStates[type] ?? .missing(ModelRegistry.llmMissingMessage())
                            )
                        }
                    }
                    .padding(.horizontal)

                    Button {
                        modelManager.refresh()
                    } label: {
                        Text("Vérifier les fichiers")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(state.isReady ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.body.weight(.medium))
                    Text("\(type.detail) · \(type.sizeDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if state.isReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let message = state.missingMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                Text("Présent")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
