import SwiftUI
import AppKit

// EDIT_UNIT

struct EditAgentView: View {
    let agent: Agent
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var agentName: String
    @State private var agentTitle: String
    @State private var agentEmoji: String
    @State private var selectedModelId: String?
    @State private var canCommunicateWithAgents: Bool
    @State private var identityContent = ""
    @State private var activeImagePath: String?
    @State private var idleImagePath: String?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedConfirmation = false
    @FocusState private var isEmojiFieldFocused: Bool
    @FocusState private var focusedField: EditField?

    private enum EditField: Hashable {
        case name, title, identity
    }

    private let commonEmojis = ["🤖", "🧠", "🔍", "🧩", "📐", "🗺️", "⚡", "🎯", "🚀", "💡", "🔮", "🌟", "🦊", "🐉", "🦁"]

    init(agent: Agent) {
        self.agent = agent
        _agentName = State(initialValue: agent.name)
        _agentTitle = State(initialValue: agent.role)
        _agentEmoji = State(initialValue: agent.emoji)
        _selectedModelId = State(initialValue: agent.model)
        _canCommunicateWithAgents = State(initialValue: agent.canCommunicateWithAgents)
        _activeImagePath = State(initialValue: agent.avatarActivePath)
        _idleImagePath = State(initialValue: agent.avatarIdlePath)
    }

    var body: some View {
        HQModalChrome {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    Button("CANCEL") { dismiss() }
                        .buttonStyle(HQButtonStyle(variant: .secondary))

                    Spacer()

                    VStack(spacing: 2) {
                        Text("// EDIT_UNIT")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted)
                            .tracking(1.5)
                        Text(agent.name.uppercased())
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundColor(Theme.neonCyan)
                            .glitchText()
                    }

                    Spacer()

                    Button(action: { Task { await saveChanges() } }) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7)
                        } else if savedConfirmation {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("SAVED")
                            }
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.statusOnline)
                        } else {
                            Text("WRITE_UNIT")
                        }
                    }
                    .buttonStyle(HQButtonStyle(variant: .glow))
                    .disabled(isSaving)
                }
                .padding(20)
                .background(Theme.darkSurface)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.neonCyan.opacity(0.25))
                        .frame(height: 1)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // Agent ID (read-only)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("// UNIT_ID")
                                .terminalLabel()
                            NeonBorderPanel(color: Theme.darkBorder, cornerRadius: 6, surface: Theme.darkBackground, lineWidth: 1) {
                                HStack(spacing: 8) {
                                    Text("$")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(Theme.textMuted)
                                    Text(agent.id)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(Theme.textMetadata)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                            }
                        }

                        // IDENTITY section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("// IDENTITY")
                                .terminalLabel()

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NAME")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(Theme.textMuted)
                                        .tracking(1.2)
                                    TextField("UNIT_NAME", text: $agentName)
                                        .textFieldStyle(.plain)
                                        .foregroundColor(Theme.textPrimary)
                                        .focused($focusedField, equals: .name)
                                        .cyberpunkInput(isFocused: focusedField == .name)
                                        .disabled(agent.isDefaultAgent)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("EMOJI")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(Theme.textMuted)
                                        .tracking(1.2)
                                    TextField("🤖", text: $agentEmoji)
                                        .textFieldStyle(.plain)
                                        .foregroundColor(Theme.textPrimary)
                                        .focused($isEmojiFieldFocused)
                                        .cyberpunkInput(isFocused: isEmojiFieldFocused)
                                        .frame(width: 60)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("TITLE")
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(Theme.textMuted)
                                    .tracking(1.2)
                                TextField("e.g. THE_ARCHITECT", text: $agentTitle)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(Theme.textPrimary)
                                    .focused($focusedField, equals: .title)
                                    .cyberpunkInput(isFocused: focusedField == .title)
                            }

                            // Emoji quick pick
                            LazyVGrid(columns: Array(repeating: .init(.fixed(36)), count: 15), spacing: 4) {
                                ForEach(commonEmojis, id: \.self) { e in
                                    Button(e) { agentEmoji = e }
                                        .font(.title3)
                                        .frame(width: 32, height: 32)
                                        .background(agentEmoji == e ? Theme.neonCyan.opacity(0.2) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(agentEmoji == e ? Theme.neonCyan.opacity(0.7) : Color.clear, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .buttonStyle(.plain)
                                }
                                Button {
                                    isEmojiFieldFocused = true
                                    DispatchQueue.main.async {
                                        NSApp.orderFrontCharacterPalette(nil)
                                    }
                                } label: {
                                    Image(systemName: "face.smiling")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 32, height: 32)
                                        .foregroundColor(Theme.textMuted)
                                }
                                .background(Theme.darkSurface)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.darkBorder, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .buttonStyle(.plain)
                                .help("Open full emoji picker")
                            }
                        }

                        // MODEL section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("// MODEL")
                                .terminalLabel()

                            ModelPickerView(agentId: agent.id, selectedModelId: $selectedModelId)
                                .environmentObject(agentsVM)
                                .environmentObject(gatewayService)

                            HStack(spacing: 8) {
                                let recommended = agentsVM.recommendedDefaultModelId(agentName: agentName, identityHint: identityContent)
                                Text("REC:\(recommended)")
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(Theme.textMuted)
                                Spacer()
                                Button("USE_RECOMMENDED") {
                                    selectedModelId = recommended
                                }
                                .buttonStyle(HQButtonStyle(variant: .secondary))
                            }
                        }

                        // PERSONALITY section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("// PERSONALITY")
                                .terminalLabel()

                            Toggle(isOn: $canCommunicateWithAgents) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ALLOW_AGENT_COLLABORATION")
                                        .font(Theme.terminalFont)
                                        .foregroundColor(Theme.textPrimary)
                                    Text("When enabled, this unit may coordinate with other agents via Jarvis.")
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(Theme.textMuted)
                                }
                            }
                            .toggleStyle(.switch)
                            .tint(Theme.neonCyan)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("SYSTEM_PROMPT / IDENTITY (optional)")
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(Theme.textMuted)
                                    .tracking(1.2)
                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $identityContent)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(Theme.terminalGreen)
                                        .scrollContentBackground(.hidden)
                                        .background(Theme.darkBackground)
                                        .focused($focusedField, equals: .identity)
                                        .frame(minHeight: 80, maxHeight: 160)
                                }
                                .background(Theme.darkBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            focusedField == .identity ? Theme.neonCyan.opacity(0.8) : Theme.darkBorder.opacity(0.5),
                                            lineWidth: focusedField == .identity ? 1.5 : 1
                                        )
                                        .shadow(color: focusedField == .identity ? Theme.neonCyan.opacity(0.25) : .clear, radius: 6)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        // AVATARS section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("// AVATARS")
                                .terminalLabel()

                            HStack(spacing: 16) {
                                inlineAvatarPicker(label: "ACTIVE_STATE", path: $activeImagePath, color: Theme.statusOnline)
                                inlineAvatarPicker(label: "IDLE_STATE", path: $idleImagePath, color: Theme.statusOffline)
                                Spacer()
                            }
                        }

                        // Error display
                        if let err = saveError {
                            HStack(spacing: 8) {
                                Text("ERR:")
                                    .font(Theme.terminalFont)
                                    .foregroundColor(Theme.statusOffline)
                                Text(err)
                                    .font(Theme.terminalFont)
                                    .foregroundColor(Theme.statusOffline)
                            }
                            .padding(10)
                            .background(Theme.statusOffline.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.statusOffline.opacity(0.4), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(24)
                }
            }
            .frame(minWidth: 860, minHeight: 820)
        }
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
                title: agentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                emoji: agentEmoji,
                model: selectedModelId,
                identityContent: identityContent.isEmpty ? nil : identityContent,
                canCommunicateWithAgents: canCommunicateWithAgents,
                activeAvatarPath: activeImagePath,
                idleAvatarPath: idleImagePath
            )
            Motion.perform(reduceMotion) { savedConfirmation = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                dismiss()
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func inlineAvatarPicker(label: String, path: Binding<String?>, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .tracking(1.2)
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
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .drawingGroup(opaque: false, colorMode: .linear)
                    } else {
                        NeonBorderPanel(color: color, cornerRadius: 8, surface: color.opacity(0.05), lineWidth: 1) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .foregroundColor(color)
                                    .font(.title3)
                                Text("SELECT")
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(color.opacity(0.7))
                            }
                            .frame(width: 78, height: 78)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
