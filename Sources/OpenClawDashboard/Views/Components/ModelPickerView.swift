import SwiftUI

// MARK: - ModelPickerView
/// Displays all available models from the gateway, grouped by provider.
/// On selection, immediately calls agents.update and shows a brief "Saved" confirmation.
struct ModelPickerView: View {
    let agentId: String
    @Binding var selectedModelId: String?
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    @State private var isSaving = false
    @State private var savedConfirmation = false
    @State private var saveError: String?

    private var groupedModels: [(provider: String, models: [ModelInfo])] {
        let grouped = Dictionary(grouping: agentsVM.availableModels, by: \.provider)
        return grouped.map { (provider: $0.key, models: $0.value.sorted(by: { $0.name < $1.name })) }
            .sorted { $0.provider < $1.provider }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Model")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                Spacer()
                if isSaving {
                    ProgressView().scaleEffect(0.6)
                } else if savedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                if let err = saveError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            if agentsVM.isLoadingModels {
                ProgressView("Loading models…")
                    .tint(Theme.jarvisBlue)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            } else if agentsVM.availableModels.isEmpty {
                Button("Load Models") {
                    Task { await agentsVM.loadModels() }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            } else {
                Picker("", selection: Binding(
                    get: { selectedModelId ?? "" },
                    set: { newId in
                        guard newId != selectedModelId else { return }
                        selectedModelId = newId
                        if !agentId.isEmpty {
                            Task { await saveModel(newId) }
                        }
                    }
                )) {
                    Text("No model selected").tag("")

                    ForEach(groupedModels, id: \.provider) { group in
                        Section(group.provider) {
                            ForEach(group.models) { model in
                                HStack {
                                    Text(model.name)
                                    if model.supportsReasoning {
                                        Image(systemName: "brain")
                                            .foregroundColor(.purple)
                                    }
                                    if let ctx = model.contextWindow {
                                        Text("\(ctx / 1000)K ctx")
                                            .foregroundColor(Theme.textMuted)
                                    }
                                }
                                .tag(model.id)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
        .task { await agentsVM.loadModels() }
    }

    private func saveModel(_ modelId: String) async {
        guard !agentId.isEmpty, !modelId.isEmpty else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            try await agentsVM.updateAgent(agentId: agentId, model: modelId)
            withAnimation { savedConfirmation = true }
            // Dismiss "Saved" after 2 seconds
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { savedConfirmation = false }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - ModelBadge
/// A small pill shown on AgentCard to display the current model.
struct ModelBadge: View {
    let modelName: String

    // Shorten display (e.g. "anthropic/claude-sonnet-4-5" → "claude-sonnet-4-5")
    private var displayName: String {
        if modelName.contains("/") {
            return String(modelName.split(separator: "/").last ?? Substring(modelName))
        }
        return modelName
    }

    var body: some View {
        Text(displayName)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(Theme.jarvisBlue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.jarvisBlue.opacity(0.15))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}
