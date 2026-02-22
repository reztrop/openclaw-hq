import SwiftUI
import AppKit

// MARK: - Add Mode
enum AddAgentMode {
    case create
    case scan
}

// MARK: - AddAgentView
struct AddAgentView: View {
    var initialMode: AddAgentMode = .create
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    @State private var mode: AddAgentMode

    init(initialMode: AddAgentMode = .create) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        HQModalChrome {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("// ADD_UNIT")
                        .font(Theme.headerFont)
                        .foregroundColor(Theme.neonCyan)
                        .shadow(color: Theme.neonCyan.opacity(0.5), radius: 6, x: 0, y: 0)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Text("CLOSE")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Theme.darkSurface)

                // Neon divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.neonCyan.opacity(0.6), Theme.neonCyan.opacity(0.2), Theme.neonCyan.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .shadow(color: Theme.neonCyan.opacity(0.4), radius: 4, x: 0, y: 0)

                // Mode tab strip
                HStack(spacing: 0) {
                    modeTabButton(title: "CREATE_NEW", targetMode: .create)
                    modeTabButton(title: "SCAN_FOR_MISSING", targetMode: .scan)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .background(Theme.darkSurface)

                // Bottom divider under tabs
                Rectangle()
                    .fill(Theme.darkBorder.opacity(0.5))
                    .frame(height: 1)

                // Content
                if mode == .create {
                    CreateAgentForm()
                        .environmentObject(agentsVM)
                        .environmentObject(gatewayService)
                } else {
                    ScanAgentsView()
                        .environmentObject(agentsVM)
                        .environmentObject(gatewayService)
                }
            }
            .frame(minWidth: 820, minHeight: 760)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func modeTabButton(title: String, targetMode: AddAgentMode) -> some View {
        let isActive = mode == targetMode
        Button {
            mode = targetMode
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(Theme.terminalFont)
                    .foregroundColor(isActive ? Theme.neonCyan : Theme.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .shadow(color: isActive ? Theme.neonCyan.opacity(0.6) : .clear, radius: 4, x: 0, y: 0)

                Rectangle()
                    .fill(isActive ? Theme.neonCyan : Color.clear)
                    .frame(height: 2)
                    .shadow(color: isActive ? Theme.neonCyan.opacity(0.8) : .clear, radius: 4, x: 0, y: 0)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: mode)
    }
}

// MARK: - Create Agent Form

// Focus field enum for cyberpunk input styling
private enum FormField: Hashable {
    case name
    case emoji
    case identity
    case soul
}

struct CreateAgentForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    @State private var agentName = ""
    @State private var agentEmoji = "🤖"
    @State private var selectedModelId: String? = nil
    @State private var canCommunicateWithAgents = true
    @State private var bootOnStart = true
    @State private var identityContent = ""
    @State private var soulContent = ""
    @State private var activeImagePath: String? = nil
    @State private var idleImagePath: String? = nil
    @State private var isCreating = false
    @State private var createError: String?
    @State private var modelAutoSuggested = true
    @State private var suppressModelChangeTracking = false
    @FocusState private var isEmojiFieldFocused: Bool
    @FocusState private var focusedField: FormField?
    @State private var isIdentityFocused = false
    @State private var isSoulFocused = false

    private let commonEmojis = ["🤖", "🧠", "🔍", "🧩", "📐", "🗺️", "⚡", "🎯", "🚀", "💡", "🔮", "🌟", "🦊", "🐉", "🦁"]

    private var normalizedId: String {
        agentName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: // IDENTITY Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("// IDENTITY")
                        .terminalLabel(color: Theme.neonCyan)

                    // Name + Emoji row
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NAME *")
                                .terminalLabel()
                            TextField("e.g. Scout", text: $agentName)
                                .focused($focusedField, equals: .name)
                                .cyberpunkInput(isFocused: focusedField == .name)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMOJI")
                                .terminalLabel()
                            TextField("🤖", text: $agentEmoji)
                                .focused($isEmojiFieldFocused)
                                .cyberpunkInput(isFocused: isEmojiFieldFocused)
                                .frame(width: 70)
                        }
                    }

                    // Emoji quick pick
                    LazyVGrid(columns: Array(repeating: .init(.fixed(36)), count: 15), spacing: 4) {
                        ForEach(commonEmojis, id: \.self) { e in
                            Button(e) { agentEmoji = e }
                                .font(.title3)
                                .frame(width: 32, height: 32)
                                .background(agentEmoji == e ? Theme.neonCyan.opacity(0.2) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(agentEmoji == e ? Theme.neonCyan.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
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
                                .foregroundColor(Theme.textMuted)
                                .frame(width: 32, height: 32)
                        }
                        .background(Theme.darkSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .buttonStyle(.plain)
                        .help("Open full emoji picker")
                    }

                    // Workspace (read-only preview)
                    if !normalizedId.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WORKSPACE")
                                .terminalLabel()
                            Text("~/.openclaw/workspace/agents/\(normalizedId)")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                                .padding(8)
                                .background(Theme.darkSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Theme.darkBorder.opacity(0.5), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                // MARK: Model picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("// MODEL")
                        .terminalLabel(color: Theme.neonCyan)

                    ModelPickerView(agentId: "", selectedModelId: $selectedModelId)
                        .environmentObject(agentsVM)
                        .environmentObject(gatewayService)

                    if !agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("RECOMMENDED: \(agentsVM.recommendedDefaultModelId(agentName: agentName, identityHint: identityContent))")
                            .terminalLabel()
                    }
                }

                // MARK: // CONFIG Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("// CONFIG")
                        .terminalLabel(color: Theme.neonCyan)

                    Toggle(isOn: $canCommunicateWithAgents) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow Agent-to-Agent Collaboration")
                                .foregroundColor(.white)
                                .font(.system(.body, design: .monospaced))
                            Text("When enabled, this agent may coordinate with other agents via Jarvis.")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $bootOnStart) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Boot on Start")
                                .foregroundColor(.white)
                                .font(.system(.body, design: .monospaced))
                            Text("When enabled, Jarvis immediately boots and verifies this agent after creation so it can start working right away.")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                        }
                    }
                    .toggleStyle(.switch)

                    // Workspace files hint
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(Theme.neonCyan)
                        Text("Creating an agent writes IDENTITY.md, USER.md, SOUL.md, BOOTSTRAP.md, AGENTS.md, TOOLS.md, MEMORY.md, and HEARTBEAT.md to the workspace automatically.")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Theme.neonCyan.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.neonCyan.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // MARK: // PERSONALITY Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("// PERSONALITY")
                        .terminalLabel(color: Theme.neonCyan)

                    // Identity / Role
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ROLE & IDENTITY")
                                .terminalLabel()
                            Text("What this agent is and does — written to IDENTITY.md")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted.opacity(0.7))
                        }
                        TextEditor(text: $identityContent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Theme.darkBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(minHeight: 80, maxHeight: 140)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        isIdentityFocused ? Theme.neonCyan.opacity(0.7) : Theme.darkBorder.opacity(0.4),
                                        lineWidth: isIdentityFocused ? 2 : 1
                                    )
                            )
                            .shadow(color: isIdentityFocused ? Theme.neonCyan.opacity(0.2) : .clear, radius: 6, x: 0, y: 0)
                            .onTapGesture { isIdentityFocused = true }
                    }

                    // Soul / Personality
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PERSONALITY & BEHAVIOR")
                                .terminalLabel()
                            Text("Core values, operating style, how it should behave — written to SOUL.md")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted.opacity(0.7))
                        }
                        TextEditor(text: $soulContent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Theme.darkBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(minHeight: 80, maxHeight: 140)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        isSoulFocused ? Theme.neonCyan.opacity(0.7) : Theme.darkBorder.opacity(0.4),
                                        lineWidth: isSoulFocused ? 2 : 1
                                    )
                            )
                            .shadow(color: isSoulFocused ? Theme.neonCyan.opacity(0.2) : .clear, radius: 6, x: 0, y: 0)
                            .onTapGesture { isSoulFocused = true }
                    }
                }

                // MARK: Avatar pickers
                VStack(alignment: .leading, spacing: 8) {
                    Text("// AVATARS")
                        .terminalLabel(color: Theme.neonCyan)

                    HStack(spacing: 16) {
                        inlineAvatarPicker(label: "ACTIVE", path: $activeImagePath, color: Theme.statusOnline)
                        inlineAvatarPicker(label: "IDLE", path: $idleImagePath, color: Theme.statusOffline)
                        Spacer()
                    }
                }

                // Error display
                if let err = createError {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(Theme.statusOffline)
                        Text(err)
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.statusOffline)
                    }
                    .padding(10)
                    .background(Theme.statusOffline.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.statusOffline.opacity(0.3), lineWidth: 1)
                    )
                }

                // Create button
                Button(action: { Task { await createAgent() } }) {
                    if isCreating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(Theme.neonCyan)
                                .controlSize(.small)
                            Text("CREATING...")
                                .font(Theme.terminalFont)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("CREATE_AGENT")
                                .font(Theme.terminalFont)
                        }
                    }
                }
                .buttonStyle(HQButtonStyle(variant: .glow))
                .disabled(agentName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .controlSize(.large)
            }
            .padding(24)
        }
        .background(Theme.darkBackground)
        .onAppear {
            Task {
                await agentsVM.loadModels()
                applyRecommendedModel(force: true)
            }
        }
        .onChange(of: agentName) { _, _ in
            applyRecommendedModel()
        }
        .onChange(of: identityContent) { _, _ in
            applyRecommendedModel()
        }
        .onChange(of: selectedModelId) { _, _ in
            guard !suppressModelChangeTracking else { return }
            modelAutoSuggested = false
        }
        .onTapGesture {
            // Dismiss text editor focus states when tapping outside
            isIdentityFocused = false
            isSoulFocused = false
        }
    }

    private func createAgent() async {
        isCreating = true
        createError = nil
        defer { isCreating = false }

        do {
            try await agentsVM.createAgent(
                name: agentName.trimmingCharacters(in: .whitespaces),
                emoji: agentEmoji,
                model: selectedModelId,
                identityContent: identityContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : identityContent,
                soulContent: soulContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : soulContent,
                canCommunicateWithAgents: canCommunicateWithAgents,
                bootOnStart: bootOnStart,
                activeAvatarPath: activeImagePath,
                idleAvatarPath: idleImagePath
            )
            dismiss()
        } catch {
            createError = error.localizedDescription
        }
    }

    private func applyRecommendedModel(force: Bool = false) {
        guard force || modelAutoSuggested else { return }
        let recommended = agentsVM.recommendedDefaultModelId(agentName: agentName, identityHint: identityContent)
        guard selectedModelId?.caseInsensitiveCompare(recommended) != .orderedSame else { return }
        suppressModelChangeTracking = true
        selectedModelId = recommended
        DispatchQueue.main.async {
            suppressModelChangeTracking = false
        }
    }

    private func inlineAvatarPicker(label: String, path: Binding<String?>, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .terminalLabel()
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
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 78, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .drawingGroup(opaque: false, colorMode: .linear)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.08))
                            .frame(width: 78, height: 78)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(color.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: "plus")
                                    .foregroundColor(color.opacity(0.7))
                            )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Scan Agents View
struct ScanAgentsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    @State private var gatewayAgents: [Agent] = []
    @State private var selectedIds: Set<String> = []
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var isImporting = false

    private var missingAgents: [Agent] {
        gatewayAgents.filter { ga in
            !agentsVM.agents.contains(where: { $0.id == ga.id })
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.neonCyan)
                    Text("SCANNING_GATEWAY...")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(40)
            } else if let err = scanError {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(Theme.glitchAmber)
                        Text(err)
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.glitchAmber)
                    }
                    Button {
                        Task { await scan() }
                    } label: {
                        Text("RETRY")
                            .font(Theme.terminalFont)
                    }
                    .buttonStyle(HQButtonStyle(variant: .secondary))
                }
                .padding(40)
            } else if missingAgents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Theme.statusOnline)
                        .shadow(color: Theme.statusOnline.opacity(0.5), radius: 6, x: 0, y: 0)
                    Text("ALL_AGENTS_SYNCED")
                        .font(Theme.headerFont)
                        .foregroundColor(Theme.statusOnline)
                    Text("All gateway agents are already in your dashboard.")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOUND \(missingAgents.count) AGENT\(missingAgents.count == 1 ? "" : "S") NOT IN DASHBOARD:")
                            .terminalLabel(color: Theme.neonCyan)
                            .padding(.horizontal, 24)

                        ForEach(missingAgents) { agent in
                            HStack(spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { selectedIds.contains(agent.id) },
                                    set: { checked in
                                        if checked { selectedIds.insert(agent.id) }
                                        else { selectedIds.remove(agent.id) }
                                    }
                                ))
                                .labelsHidden()

                                Text(agent.emoji).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(agent.name)
                                            .font(.system(.body, design: .monospaced, weight: .semibold))
                                            .foregroundColor(.white)
                                        if agent.isDefaultAgent {
                                            Text("MAIN")
                                                .font(Theme.terminalFontSM)
                                                .foregroundColor(Theme.neonCyan)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Theme.neonCyan.opacity(0.15))
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Theme.neonCyan.opacity(0.4), lineWidth: 1)
                                                )
                                        }
                                    }
                                    Text(agent.id)
                                        .font(Theme.terminalFontSM)
                                        .foregroundColor(Theme.textMuted)
                                        .monospaced()
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Theme.darkSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Theme.darkBorder.opacity(0.5), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 8)
                }

                HStack {
                    Button {
                        selectedIds = Set(missingAgents.map(\.id))
                    } label: {
                        Text("SELECT_ALL")
                            .font(Theme.terminalFont)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.neonCyan)

                    Spacer()

                    Button(action: { importSelected() }) {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.neonCyan)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 11, weight: .bold))
                                Text("IMPORT_\(selectedIds.count)_AGENT\(selectedIds.count == 1 ? "" : "S")")
                                    .font(Theme.terminalFont)
                            }
                        }
                    }
                    .buttonStyle(HQButtonStyle(variant: .glow))
                    .disabled(selectedIds.isEmpty || isImporting)
                }
                .padding(24)
            }
        }
        .background(Theme.darkBackground)
        .task { await scan() }
    }

    private func scan() async {
        isScanning = true
        scanError = nil
        defer { isScanning = false }

        do {
            let (defaultId, _, rawAgents) = try await gatewayService.fetchAgentsListFull()
            gatewayAgents = rawAgents.map { raw in
                let id    = raw["id"]    as? String ?? UUID().uuidString
                let ident = raw["identity"] as? [String: Any]
                let name  = (ident?["name"]  as? String) ?? (raw["name"]  as? String) ?? id
                let emoji = (ident?["emoji"] as? String) ?? "🤖"
                return Agent(
                    id: id, name: name.isEmpty ? id : name, emoji: emoji,
                    role: id == defaultId ? "Main Agent" : "Agent",
                    status: .offline, totalTokens: 0, sessionCount: 0,
                    isDefaultAgent: id == defaultId
                )
            }
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func importSelected() {
        isImporting = true
        let toImport = missingAgents.filter { selectedIds.contains($0.id) }
        agentsVM.importAgents(toImport)
        dismiss()
    }
}
