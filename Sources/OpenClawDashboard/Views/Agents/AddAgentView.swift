import SwiftUI

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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Agent")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textMuted)
            }
            .padding(24)
            .background(Theme.darkSurface)

            // Mode picker
            Picker("Mode", selection: $mode) {
                Text("Create New").tag(AddAgentMode.create)
                Text("Scan for Missing").tag(AddAgentMode.scan)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Theme.darkSurface)

            Divider().opacity(0.3)

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
        .background(Theme.darkBackground)
        .frame(minWidth: 820, minHeight: 760)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Create Agent Form
struct CreateAgentForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    @State private var agentName = ""
    @State private var agentEmoji = "🤖"
    @State private var selectedModelId: String? = nil
    @State private var identityContent = ""
    @State private var activeImagePath: String? = nil
    @State private var idleImagePath: String? = nil
    @State private var isCreating = false
    @State private var createError: String?

    private let commonEmojis = ["🤖", "🧠", "🔍", "🧩", "📐", "🗺️", "⚡", "🎯", "🚀", "💡", "🔮", "🌟", "🦊", "🐉", "🦁"]

    private var normalizedId: String {
        agentName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Name + Emoji
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name *").font(.caption).foregroundColor(Theme.textMuted)
                        TextField("e.g. Scout", text: $agentName)
                            .textFieldStyle(.roundedBorder)
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

                // Workspace (read-only preview)
                if !normalizedId.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workspace").font(.caption).foregroundColor(Theme.textMuted)
                        Text("~/.openclaw/workspace/agents/\(normalizedId)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Theme.textMuted)
                            .padding(6)
                            .background(Theme.darkSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                // Model picker
                VStack(alignment: .leading, spacing: 4) {
                    ModelPickerView(agentId: "", selectedModelId: $selectedModelId)
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
                if let err = createError {
                    Label(err, systemImage: "xmark.circle")
                        .foregroundColor(.red)
                        .font(.callout)
                }

                // Create button
                Button(action: { Task { await createAgent() } }) {
                    if isCreating {
                        HStack { ProgressView(); Text("Creating…") }
                    } else {
                        Label("Create Agent", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.jarvisBlue)
                .disabled(agentName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            .padding(24)
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
                identityContent: identityContent.isEmpty ? nil : identityContent
            )
            dismiss()
        } catch {
            createError = error.localizedDescription
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
                ProgressView("Scanning gateway…")
                    .tint(Theme.jarvisBlue)
                    .padding(40)
            } else if let err = scanError {
                VStack(spacing: 8) {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Button("Retry") { Task { await scan() } }.buttonStyle(.bordered)
                }
                .padding(40)
            } else if missingAgents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundColor(.green)
                    Text("All gateway agents are already in your dashboard!")
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Found \(missingAgents.count) agent\(missingAgents.count == 1 ? "" : "s") not yet in your dashboard:")
                            .font(.callout)
                            .foregroundColor(Theme.textSecondary)
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
                                        Text(agent.name).fontWeight(.medium).foregroundColor(.white)
                                        if agent.isDefaultAgent {
                                            Text("MAIN").font(.system(size: 9, weight: .bold))
                                                .foregroundColor(Theme.jarvisBlue)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Theme.jarvisBlue.opacity(0.2)).clipShape(Capsule())
                                        }
                                    }
                                    Text(agent.id).font(.caption).foregroundColor(Theme.textMuted).monospaced()
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Theme.darkSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 8)
                }

                HStack {
                    Button("Select All") { selectedIds = Set(missingAgents.map(\.id)) }
                        .buttonStyle(.plain).foregroundColor(Theme.jarvisBlue)
                    Spacer()
                    Button(action: { importSelected() }) {
                        if isImporting {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Label("Import \(selectedIds.count) Agent\(selectedIds.count == 1 ? "" : "s")", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.jarvisBlue)
                    .disabled(selectedIds.isEmpty || isImporting)
                }
                .padding(24)
            }
        }
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
