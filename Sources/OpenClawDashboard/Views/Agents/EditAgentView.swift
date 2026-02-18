import SwiftUI

struct EditAgentView: View {
    let agent: Agent
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    @State private var agentName: String
    @State private var agentEmoji: String
    @State private var selectedModelId: String?
    @State private var identityContent = ""
    @State private var activeImagePath: String?
    @State private var idleImagePath: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedConfirmation = false

    private let commonEmojis = ["🤖", "🧠", "🔍", "🧩", "📐", "🗺️", "⚡", "🎯", "🚀", "💡", "🔮", "🌟", "🦊", "🐉", "🦁"]

    init(agent: Agent) {
        self.agent = agent
        _agentName = State(initialValue: agent.name)
        _agentEmoji = State(initialValue: agent.emoji)
        _selectedModelId = State(initialValue: agent.model)
        _activeImagePath = State(initialValue: agent.avatarActivePath)
        _idleImagePath = State(initialValue: agent.avatarIdlePath)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Text("Edit \(agent.name)")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { Task { await saveChanges() } }) {
                    if isSaving {
                        ProgressView().scaleEffect(0.7)
                    } else if savedConfirmation {
                        Label("Saved!", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text("Save")
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.jarvisBlue)
                    }
                }
                .disabled(isSaving)
            }
            .padding(20)
            .background(Theme.darkSurface)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Agent ID (read-only)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent ID").font(.caption).foregroundColor(Theme.textMuted)
                        Text(agent.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Theme.textMuted)
                            .padding(6)
                            .background(Theme.darkSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Name + Emoji
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Name").font(.caption).foregroundColor(Theme.textMuted)
                            TextField("Agent name", text: $agentName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(agent.isDefaultAgent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Emoji").font(.caption).foregroundColor(Theme.textMuted)
                            TextField("🤖", text: $agentEmoji)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                    }

                    // Emoji quick pick
                    LazyVGrid(columns: Array(repeating: .init(.fixed(36)), count: 15), spacing: 4) {
                        ForEach(commonEmojis, id: \.self) { e in
                            Button(e) { agentEmoji = e }
                                .font(.title3)
                                .frame(width: 32, height: 32)
                                .background(agentEmoji == e ? Theme.jarvisBlue.opacity(0.3) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .buttonStyle(.plain)
                        }
                    }

                    // Model picker
                    VStack(alignment: .leading, spacing: 4) {
                        ModelPickerView(agentId: agent.id, selectedModelId: $selectedModelId)
                            .environmentObject(agentsVM)
                            .environmentObject(gatewayService)
                    }

                    // Identity / System prompt
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt / Identity (optional)").font(.caption).foregroundColor(Theme.textMuted)
                        TextEditor(text: $identityContent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Theme.darkSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(minHeight: 80, maxHeight: 160)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8).stroke(Theme.darkBorder.opacity(0.4), lineWidth: 1)
                            )
                    }

                    // Avatar pickers
                    HStack(spacing: 16) {
                        inlineAvatarPicker(label: "Active Avatar", path: $activeImagePath, color: .green)
                        inlineAvatarPicker(label: "Idle Avatar", path: $idleImagePath, color: .red)
                        Spacer()
                    }

                    // Error
                    if let err = saveError {
                        Label(err, systemImage: "xmark.circle")
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                }
                .padding(24)
            }
        }
        .background(Theme.darkBackground)
        .frame(minWidth: 820, minHeight: 780)
        .preferredColorScheme(.dark)
    }

    private func saveChanges() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            try await agentsVM.updateAgent(
                agentId: agent.id,
                name: agentName.trimmingCharacters(in: .whitespaces),
                emoji: agentEmoji,
                model: selectedModelId,
                identityContent: identityContent.isEmpty ? nil : identityContent
            )
            withAnimation { savedConfirmation = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                dismiss()
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func inlineAvatarPicker(label: String, path: Binding<String?>, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(Theme.textMuted)
            Button(action: {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.png, .jpeg]
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    path.wrappedValue = url.path
                }
            }) {
                ZStack {
                    if let p = path.wrappedValue, let img = NSImage(contentsOfFile: p) {
                        Image(nsImage: img).resizable().interpolation(.high).antialiased(true).aspectRatio(contentMode: .fill)
                            .frame(width: 78, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .drawingGroup(opaque: false, colorMode: .linear)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.1))
                            .frame(width: 78, height: 78)
                            .overlay(Image(systemName: "plus").foregroundColor(color))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
