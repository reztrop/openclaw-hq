import SwiftUI
import Combine
import AppKit
import Foundation

@MainActor
class AgentsViewModel: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var selectedAgent: Agent?
    @Published var isRefreshing = false
    @Published var defaultAgentId: String?
    @Published var availableModels: [ModelInfo] = []
    @Published var isLoadingModels = false

    let gatewayService: GatewayService
    let settingsService: SettingsService
    let taskService: TaskService
    private var cancellables = Set<AnyCancellable>()
    private var autoRefreshTask: Task<Void, Never>?
    private var runtimeBusyAgents: Set<String> = []

    init(gatewayService: GatewayService, settingsService: SettingsService, taskService: TaskService) {
        self.gatewayService = gatewayService
        self.settingsService = settingsService
        self.taskService = taskService
        subscribeToEvents()
        subscribeToConnectionState()
        subscribeToProviderSettings()
        subscribeToTaskState()
        startAutoRefresh()
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    private func startAutoRefresh() {
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if self?.gatewayService.isConnected == true {
                    await self?.refreshAgents()
                }
            }
        }
    }

    // MARK: - Fetch Agents

    func refreshAgents() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // Get full agent list from gateway (with identity fields)
            let (defaultId, _, rawAgents) = try await gatewayService.fetchAgentsListFull()
            defaultAgentId = defaultId

            // Build Agent structs from gateway data
            let updatedAgents: [Agent] = rawAgents.map { raw -> Agent in
                let id    = raw["id"]    as? String ?? UUID().uuidString
                let ident = raw["identity"] as? [String: Any]
                let gatewayName = (ident?["name"]  as? String) ?? (raw["name"]  as? String) ?? id
                let gatewayEmoji = (ident?["emoji"] as? String) ?? "🤖"
                let gatewayModelId = ModelNormalizer.normalize((ident?["model"] as? String) ?? (raw["model"] as? String))
                let localConfig = settingsService.settings.localAgents.first(where: { $0.id == id })
                let localName = localConfig?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let localTitle = localConfig?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawName = (localName?.isEmpty == false ? (localName ?? gatewayName) : gatewayName)
                let localEmoji = localConfig?.emoji
                let emoji = (localEmoji?.isEmpty == false ? (localEmoji ?? gatewayEmoji) : gatewayEmoji)
                let localModelId = ModelNormalizer.normalize(localConfig?.modelId)
                let modelId = (localModelId?.isEmpty == false ? localModelId : gatewayModelId)
                let canCommunicateWithAgents = localConfig?.canCommunicateWithAgents ?? true
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let isInitialized = FileManager.default.fileExists(atPath: "\(home)/.openclaw/agents/\(id.lowercased())/agent")
                let roleTitle = resolveRoleTitle(
                    agentId: id,
                    agentName: rawName.isEmpty ? id : rawName,
                    isDefaultAgent: id == defaultId,
                    localTitle: localTitle
                )

                // Preserve existing agent's runtime state if already known
                if let existing = agents.first(where: { $0.id == id }) {
                    var updated = existing
                    updated.name           = rawName.isEmpty ? id : rawName
                    updated.emoji          = emoji
                    updated.role           = roleTitle
                    updated.model          = modelId
                    updated.modelName      = modelId
                    updated.isDefaultAgent = id == defaultId
                    updated.canCommunicateWithAgents = canCommunicateWithAgents
                    updated.isInitialized  = isInitialized
                    return updated
                }

                return Agent(
                    id: id,
                    name: rawName.isEmpty ? id : rawName,
                    emoji: emoji,
                    role: roleTitle,
                    status: gatewayService.isConnected ? .idle : .offline,
                    totalTokens: 0,
                    sessionCount: 0,
                    model: modelId,
                    modelName: modelId,
                    isDefaultAgent: id == defaultId,
                    canCommunicateWithAgents: canCommunicateWithAgents,
                    isInitialized: isInitialized
                )
            }

            agents = updatedAgents
            applyTaskDrivenStatuses()

            // Overlay with status from health/presence
            if let status = try? await gatewayService.fetchStatus() {
                updateFromStatus(status)
            }

            // Token counts from sessions
            let sessions = (try? await gatewayService.fetchSessionsList()) ?? []
            updateTokenCounts(from: sessions)

            await migrateSparkModelsIfNeeded()

        } catch {
            print("[AgentsVM] Failed to refresh: \(error)")
            // If we have no agents yet, keep empty list
        }
    }

    // MARK: - Status Update

    private func updateFromStatus(_ status: [String: Any]) {
        // The `status` RPC returns session/heartbeat data — it does not carry
        // per-agent live run state. Agent status (.busy/.online) is driven entirely
        // by `agent` lifecycle events received in handleAgentEvent().
        // Agents start as .idle when connected; events update them from there.
        _ = status
    }

    private func updateTokenCounts(from sessions: [[String: Any]]) {
        var tokensByAgent: [String: Int] = [:]
        var sessionsByAgent: [String: Int] = [:]

        for session in sessions {
            let agentId = session["agentId"] as? String ?? "main"
            let tokens  = session["totalTokens"] as? Int ?? 0
            tokensByAgent[agentId, default: 0]    += tokens
            sessionsByAgent[agentId, default: 0]  += 1
        }

        for i in agents.indices {
            agents[i].totalTokens  = tokensByAgent[agents[i].id]  ?? 0
            agents[i].sessionCount = sessionsByAgent[agents[i].id] ?? 0
        }
    }

    // MARK: - Models

    func loadModels() async {
        guard availableModels.isEmpty else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        await applyModelFilter()
    }

    /// Rebuilds `availableModels` from the gateway catalog filtered by the
    /// user's enabled-providers setting. Called on load and whenever the
    /// settings change so the picker always reflects current selections.
    private func applyModelFilter() async {
        // Determine which providers to show.
        // enabledProviders == nil means "never configured" — fall back to auth.json keys.
        let enabledSet: Set<String>
        if let list = settingsService.settings.enabledProviders, !list.isEmpty {
            enabledSet = Set(list)
        } else {
            enabledSet = loadAuthenticatedProviders()
        }

        do {
            let raw = try await gatewayService.fetchModels()

            let allModels = raw.compactMap { dict -> ModelInfo? in
                guard let id = dict["id"] as? String else { return nil }
                return ModelInfo(
                    id: id,
                    name: dict["name"] as? String ?? id,
                    provider: dict["provider"] as? String ?? "Unknown",
                    contextWindow: dict["contextWindow"] as? Int,
                    supportsReasoning: dict["reasoning"] as? Bool ?? false
                )
            }

            // Filter by user-selected providers, then strip the synthetic spark entry.
            let filtered = enabledSet.isEmpty
                ? allModels
                : allModels.filter { enabledSet.contains($0.provider) }
            availableModels = filtered.filter { !$0.id.lowercased().contains("spark") }
        } catch {
            print("[AgentsVM] Failed to load models: \(error)")
        }
    }

    /// Fallback: reads ~/.openclaw/agents/main/agent/auth.json and returns the
    /// set of authenticated provider IDs (the top-level keys).
    private func loadAuthenticatedProviders() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let authPath = "\(home)/.openclaw/agents/main/agent/auth.json"
        guard let data = FileManager.default.contents(atPath: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return Set(json.keys)
    }

    // MARK: - Agent CRUD

    func createAgent(
        name: String,
        emoji: String,
        model: String?,
        identityContent: String?,
        soulContent: String? = nil,
        canCommunicateWithAgents: Bool = true,
        bootOnStart: Bool = true,
        activeAvatarPath: String? = nil,
        idleAvatarPath: String? = nil
    ) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let normalizedId = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let workspace = "\(home)/.openclaw/workspace/agents/\(normalizedId)"

        guard let result = try await gatewayService.createAgent(name: name, workspace: workspace, emoji: emoji),
              let agentId = result["agentId"] as? String else {
            throw NSError(domain: "OpenClawHQ", code: 1, userInfo: [NSLocalizedDescriptionKey: "Agent creation failed"])
        }

        // Set model if provided
        if let model = model, !model.isEmpty {
            let normalizedModel = ModelNormalizer.normalize(model)
            _ = try? await gatewayService.updateAgent(agentId: agentId, model: normalizedModel)
            saveLocalAgentOverride(agentId: agentId) { config in
                config.modelId = normalizedModel
            }
        }

        saveLocalAgentOverride(agentId: agentId) { config in
            config.emoji = emoji
            config.canCommunicateWithAgents = canCommunicateWithAgents
        }

        // Write full workspace file set so the agent comes online fully initialized
        await writeAgentWorkspaceFiles(
            agentId: agentId,
            name: name,
            emoji: emoji,
            identityContent: identityContent,
            soulContent: soulContent,
            canCommunicateWithAgents: canCommunicateWithAgents
        )
        ensureWorkspaceFilesExist(
            workspacePath: workspace,
            name: name,
            emoji: emoji,
            identityContent: identityContent,
            soulContent: soulContent
        )

        // Persist selected avatars (if any) into the dashboard avatar directory.
        try copySelectedAvatars(
            displayName: name,
            activeAvatarPath: activeAvatarPath,
            idleAvatarPath: idleAvatarPath
        )
        AvatarService.shared.clearCache()

        await refreshAgents()

        if bootOnStart {
            Task { [weak self] in
                await self?.bootAgentOnStart(
                    agentId: agentId,
                    agentName: name,
                    emoji: emoji,
                    identityContent: identityContent,
                    soulContent: soulContent,
                    bootRequested: true
                )
            }
        }
    }

    private func bootAgentOnStart(
        agentId: String,
        agentName: String,
        emoji: String,
        identityContent: String?,
        soulContent: String?,
        bootRequested: Bool
    ) async {
        let coordinatorId = preferredCoordinatorAgentId()
        let identityText = identityContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let soulText = soulContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bootRequest = """
        A new agent was just created and needs formal onboarding handling.
        Agent ID: \(agentId)
        Agent Name: \(agentName)
        Emoji: \(emoji)
        Boot on Start selected: \(bootRequested ? "YES" : "NO")

        Handling requirements (must complete in order):
        1) Confirm the agent exists and all expected files are present:
           IDENTITY.md, SOUL.md, USER.md, TOOLS.md, AGENTS.md, BOOTSTRAP.md, MEMORY.md, HEARTBEAT.md, TITLE.md
        2) Use the natural language provided below to ensure IDENTITY.md and SOUL.md are implemented accordingly.
        3) Assign this new hire a concise job title and write it to TITLE.md (single line).
        4) Verify each file is set and usable.
        5) If Boot on Start is YES, initialize the new agent and confirm it can accept work now.
        6) Return a concise verification summary with pass/fail per file and readiness status.

        IDENTITY INPUT:
        \(identityText.isEmpty ? "(none supplied)" : identityText)

        SOUL INPUT:
        \(soulText.isEmpty ? "(none supplied)" : soulText)
        """

        do {
            _ = try await gatewayService.sendAgentCommand(coordinatorId, message: bootRequest)
        } catch {
            print("[AgentsVM] Coordinator boot request failed (\(coordinatorId)): \(error)")
        }

        guard bootRequested else { return }

        // Always directly warm up the new agent so initialization is guaranteed even
        // if Jarvis does not immediately delegate.
        let directWarmup = """
        Startup check: read your workspace files, complete bootstrap behavior, then reply in one line with READY if you are initialized and able to accept tasks immediately.
        """
        var warmedUp = false
        for attempt in 1...3 where !warmedUp {
            do {
                _ = try await gatewayService.sendAgentCommand(agentId, message: directWarmup)
                warmedUp = true
            } catch {
                print("[AgentsVM] Direct boot warmup failed (\(agentId)) attempt \(attempt): \(error)")
                try? await Task.sleep(for: .milliseconds(700))
            }
        }

        if !warmedUp {
            do {
                try await warmupAgentViaCLI(agentId: agentId, message: directWarmup)
            } catch {
                print("[AgentsVM] CLI boot warmup failed (\(agentId)): \(error)")
            }
        }
    }

    private func preferredCoordinatorAgentId() -> String {
        if let jarvis = agents.first(where: { $0.name.lowercased() == "jarvis" || $0.id.lowercased() == "jarvis" }) {
            return jarvis.id
        }
        if let defaultAgentId, !defaultAgentId.isEmpty {
            return defaultAgentId
        }
        return "main"
    }

    /// Writes the full set of workspace files (IDENTITY, USER, SOUL, BOOTSTRAP, AGENTS, TOOLS,
    /// MEMORY, HEARTBEAT) for a newly created agent. Called during createAgent so the agent is fully
    /// initialized rather than starting with an empty workspace.
    private func writeAgentWorkspaceFiles(
        agentId: String,
        name: String,
        emoji: String,
        identityContent: String?,
        soulContent: String?,
        canCommunicateWithAgents: Bool
    ) async {
        let hasIdentity = identityContent.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let hasSoul     = soulContent.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let roleText    = hasIdentity ? identityContent! : "Update this with a description of this agent's role and responsibilities."
        let soulText    = hasSoul ? soulContent! : "**Do the job well.** Quality over speed. Correctness over convenience.\n\n**Be honest about what you don't know.** Uncertainty labeled as uncertainty is useful. Uncertainty presented as fact is dangerous.\n\n**Stay in your lane.** Do not take actions outside your defined role without explicit instruction."
        let inferredTitle = inferThemedTitle(
            agentName: name,
            identityText: identityContent,
            soulText: soulContent,
            isDefaultAgent: false
        )

        // IDENTITY.md
        let identityFile = """
        # IDENTITY.md - Who Am I?

        - **Name:**
          \(name)
        - **Emoji:**
          \(emoji)

        ---

        ## Role

        \(roleText)

        ## Chain of Command

        Reports to Jarvis. Does not address Andrew directly.
        All communication routes through Jarvis.
        """
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "IDENTITY.md", content: identityFile)

        // USER.md
        let userFile = """
        # USER.md - About Your Human

        - **Name:**
          Andrew
        - **What to call them:**
          Does not address Andrew directly. All communication routes through Jarvis.
        - **Timezone:**
          America/New_York
        - **Pronouns:**
          he/him

        ## Andrew's Style (For Context)

        - Values precision and grounded decisions over speed and guesswork
        - Security and quality are non-negotiable; expects risks surfaced proactively
        - Prefers structured, clear output — not walls of prose, not vague summaries
        - Does not want to feel interrogated; Jarvis handles that interface

        ## What Andrew Needs From \(name) Specifically

        \(name) operates through Jarvis. Andrew's experience is Jarvis bringing well-researched,
        well-executed results. \(name)'s contribution is invisible unless Jarvis chooses to surface it.

        ---

        *\(name) serves Andrew through Jarvis. That indirection is by design — respect it.*
        """
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "USER.md", content: userFile)

        // SOUL.md
        let soulFile = """
        # SOUL.md - Who You Are

        ## Core Truths

        \(soulText)

        ## Output Format

        When delivering results, structure output clearly:

        1. **Summary** — what was done and why
        2. **Key findings or outputs** — the actual work product
        3. **Issues or blockers** — anything that needs attention
        4. **Next steps** — what comes next, if applicable

        ## Continuity

        Each session, you wake up fresh. These files are your memory. Read them. Update them.
        They are how you persist.

        ---

        *This file is yours to evolve. Update it as your role becomes clearer.*
        """
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "SOUL.md", content: soulFile)

        // BOOTSTRAP.md
        let bootstrapFile = """
        # BOOTSTRAP.md - Hello, World

        *You just came online. You already know who you are — read IDENTITY.md.*

        Your name is \(name). Read your workspace files to understand your role and operating
        principles. Then signal readiness to Jarvis.

        ## First Session

        1. Read `IDENTITY.md` — confirm who you are and your role
        2. Read `USER.md` — understand Andrew and how you relate to him (through Jarvis)
        3. Read `SOUL.md` — internalize your operating principles
        4. Signal readiness to Jarvis — not to Andrew

        Something like:
        > "\(name) online. Ready."

        ## When You're Settled

        Delete this file. You don't need a bootstrap script once you know your role.

        ---

        *Clarity is the destination. Start moving toward it.*
        """
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "BOOTSTRAP.md", content: bootstrapFile)

        // AGENTS.md
        let agentsFile = """
        # AGENTS.md - Workspace Rules

        ## Memory Files

        - `IDENTITY.md` — who this agent is and their role
        - `USER.md` — about Andrew and this agent's relationship to him
        - `SOUL.md` — core values and operating principles
        - `TOOLS.md` — agent-specific tools, notes, and known constraints
        - `MEMORY.md` — durable working memory and handoff notes
        - `HEARTBEAT.md` — lightweight per-session log

        ## Rules

        - Read workspace files at the start of each session
        - Update `TOOLS.md` as knowledge and constraints accumulate
        - Update `MEMORY.md` with durable findings and handoff context
        - Update `HEARTBEAT.md` with a brief note each session
        - Route all communication through Jarvis — never address Andrew directly
        - Do not approve work as complete — that authority belongs elsewhere in the chain

        ## Safety

        - Never expose credentials, tokens, or sensitive data
        - Never take destructive action without explicit instruction
        - When uncertain, ask Jarvis — not Andrew
        """
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "AGENTS.md", content: agentsFile)

        let communicationSection = canCommunicateWithAgents
            ? """
            ## Inter-Agent Communication

            - Enabled: this agent may coordinate with other agents through Jarvis.
            - Use OpenClaw CLI when needed:
              - `openclaw agent --agent jarvis --channel last -m "<update>"`
              - `openclaw agent --agent atlas --channel last -m "<research request>"`
              - `openclaw agent --agent matrix --channel last -m "<build request>"`
              - `openclaw agent --agent prism --channel last -m "<qa request>"`
              - `openclaw agent --agent scope --channel last -m "<planning request>"`
            """
            : """
            ## Inter-Agent Communication

            - Disabled: this agent should not initiate communication with other agents.
            - Route outputs only to Jarvis; do not delegate to peers.
            """

        // TOOLS.md
        let toolsFile = """
        # TOOLS.md - \(name) Local Notes

        This file is for specifics unique to \(name)'s setup. Update it as knowledge accumulates.

        ## Resources

        *(Add preferred sources, trusted references, and known-good resources here.)*

        - **OpenClaw gateway:** ws://127.0.0.1:18789 (local, token auth)

        ## Known Constraints

        *(Maintain a living list of discovered constraints and limits here.)*

        \(communicationSection)

        ## Environment

        - **Platform:** macOS (Andrew's primary machine)
        - **Timezone:** America/New_York
        - **Hub:** Reports to Jarvis

        ---

        *Keep this current — it feeds every downstream decision.*
        """
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "TOOLS.md", content: toolsFile)

        // TITLE.md
        let titleFile = "\(inferredTitle)\n"
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "TITLE.md", content: titleFile)

        // MEMORY.md
        let memoryFile = """
        # MEMORY.md

        ## Durable Notes

        - Keep long-lived context here: decisions, conventions, handoff notes, and known constraints.
        - Do not store secrets or credentials.

        ## Current Focus

        - (Update with current mission focus and next actions.)
        """
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "MEMORY.md", content: memoryFile)

        // HEARTBEAT.md
        let heartbeatFile = "# HEARTBEAT.md\n\n*(Session log — update each session with date and brief summary of work done.)*\n"
        _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "HEARTBEAT.md", content: heartbeatFile)
    }

    func updateAgent(
        agentId: String,
        name: String? = nil,
        title: String? = nil,
        emoji: String? = nil,
        model: String? = nil,
        identityContent: String? = nil,
        canCommunicateWithAgents: Bool? = nil,
        activeAvatarPath: String? = nil,
        idleAvatarPath: String? = nil
    ) async throws {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmedName?.isEmpty == true) ? nil : trimmedName
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = (trimmedTitle?.isEmpty == true) ? nil : trimmedTitle
        let normalizedModel = ModelNormalizer.normalize(model)
        let shouldSendGatewayUpdate = finalName != nil || normalizedModel != nil

        if shouldSendGatewayUpdate {
            _ = try await gatewayService.updateAgent(agentId: agentId, name: finalName, model: normalizedModel)
        }

        if let identity = identityContent {
            _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "IDENTITY.md", content: identity)
        }
        if let finalTitle {
            _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "TITLE.md", content: "\(finalTitle)\n")
            saveLocalAgentOverride(agentId: agentId) { config in
                config.title = finalTitle
            }
        }

        if let emoji = emoji {
            saveLocalAgentOverride(agentId: agentId) { config in
                config.emoji = emoji
            }
        }

        if let model = normalizedModel, !model.isEmpty {
            saveLocalAgentOverride(agentId: agentId) { config in
                config.modelId = model
            }
        }

        if let canCommunicateWithAgents {
            saveLocalAgentOverride(agentId: agentId) { config in
                config.canCommunicateWithAgents = canCommunicateWithAgents
            }
        }

        // Persist avatar updates into the dashboard avatar directory.
        let effectiveName: String = {
            if let finalName, !finalName.isEmpty { return finalName }
            return agents.first(where: { $0.id == agentId })?.name ?? agentId
        }()
        try copySelectedAvatars(
            displayName: effectiveName,
            activeAvatarPath: activeAvatarPath,
            idleAvatarPath: idleAvatarPath
        )
        AvatarService.shared.clearCache()

        await refreshAgents()

        // Update local state immediately
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            if let name = finalName { agents[idx].name = name }
            if let finalTitle { agents[idx].role = finalTitle }
            if let emoji = emoji { agents[idx].emoji = emoji }
            if let model = normalizedModel {
                agents[idx].model = model
                agents[idx].modelName = availableModels.first(where: { $0.id == model })?.name
            }
            if let canCommunicateWithAgents {
                agents[idx].canCommunicateWithAgents = canCommunicateWithAgents
            }
        }
    }

    private func copySelectedAvatars(
        displayName: String,
        activeAvatarPath: String?,
        idleAvatarPath: String?
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: Constants.avatarDirectory, withIntermediateDirectories: true, attributes: nil)

        let targetName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetName.isEmpty else { return }

        func copyAvatar(from sourcePath: String, to destinationPath: String) throws {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let destinationURL = URL(fileURLWithPath: destinationPath)

            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if scoped { sourceURL.stopAccessingSecurityScopedResource() }
            }

            guard let image = NSImage(contentsOf: sourceURL),
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(
                    domain: "OpenClawHQ",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Selected avatar is not a valid image file."]
                )
            }

            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try pngData.write(to: destinationURL)
        }

        if let activeAvatarPath, !activeAvatarPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let activeDest = "\(Constants.avatarDirectory)/\(targetName)_active.png"
            try copyAvatar(from: activeAvatarPath, to: activeDest)
        }
        if let idleAvatarPath, !idleAvatarPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let idleDest = "\(Constants.avatarDirectory)/\(targetName)_idle.png"
            try copyAvatar(from: idleAvatarPath, to: idleDest)
        }
    }

    private func ensureWorkspaceFilesExist(
        workspacePath: String,
        name: String,
        emoji: String,
        identityContent: String?,
        soulContent: String?
    ) {
        let fm = FileManager.default
        let expected = [
            "IDENTITY.md", "SOUL.md", "USER.md", "TOOLS.md",
            "AGENTS.md", "BOOTSTRAP.md", "MEMORY.md", "HEARTBEAT.md", "TITLE.md"
        ]

        let fallbackIdentity = """
        # IDENTITY.md - Who Am I?

        - **Name:** \(name)
        - **Emoji:** \(emoji)

        ## Role
        \(identityContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (identityContent ?? "") : "Update this with a description of this agent's role and responsibilities.")
        """
        let fallbackSoul = """
        # SOUL.md - Who You Are

        \(soulContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (soulContent ?? "") : "Do the job well. Be explicit about uncertainty. Stay within role boundaries.")
        """
        let fallbackByFile: [String: String] = [
            "IDENTITY.md": fallbackIdentity,
            "SOUL.md": fallbackSoul,
            "USER.md": "# USER.md\n",
            "TOOLS.md": "# TOOLS.md\n",
            "AGENTS.md": "# AGENTS.md\n",
            "BOOTSTRAP.md": "# BOOTSTRAP.md\n",
            "MEMORY.md": "# MEMORY.md\n",
            "HEARTBEAT.md": "# HEARTBEAT.md\n",
            "TITLE.md": "\(inferThemedTitle(agentName: name, identityText: identityContent, soulText: soulContent, isDefaultAgent: false))\n"
        ]

        for file in expected {
            let path = "\(workspacePath)/\(file)"
            let missing = !fm.fileExists(atPath: path)
            let empty = (try? String(contentsOfFile: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?? true
            if (missing || empty), let fallback = fallbackByFile[file] {
                try? fallback.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    private func warmupAgentViaCLI(agentId: String, message: String) async throws {
        let candidates = ["/opt/homebrew/bin/openclaw", "/usr/local/bin/openclaw", "/usr/bin/openclaw"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "OpenClawHQ", code: 10, userInfo: [NSLocalizedDescriptionKey: "openclaw CLI not found"])
        }

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["agent", "--agent", agentId, "--channel", "last", "-m", message, "--json"]

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
            process.environment = env

            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(domain: "OpenClawHQ", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "CLI warmup failed"])
            }
        }.value
    }

    private func resolveRoleTitle(agentId: String, agentName: String, isDefaultAgent: Bool, localTitle: String?) -> String {
        if let localTitle, !localTitle.isEmpty,
           localTitle.lowercased() != "specialist agent" && localTitle.lowercased() != "the specialist" {
            return localTitle
        }
        if let workspaceTitle = readTitleFromWorkspace(agentId: agentId), !workspaceTitle.isEmpty,
           workspaceTitle.lowercased() != "specialist agent" && workspaceTitle.lowercased() != "the specialist" {
            return workspaceTitle
        }
        let identityText = readWorkspaceFile(agentId: agentId, fileName: "IDENTITY.md")
        let soulText = readWorkspaceFile(agentId: agentId, fileName: "SOUL.md")
        return inferThemedTitle(
            agentName: agentName,
            identityText: identityText,
            soulText: soulText,
            isDefaultAgent: isDefaultAgent
        )
    }

    private func readTitleFromWorkspace(agentId: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.openclaw/workspace/agents/\(agentId.lowercased())/TITLE.md"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        return raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func readWorkspaceFile(agentId: String, fileName: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.openclaw/workspace/agents/\(agentId.lowercased())/\(fileName)"
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    private func defaultTitleForAgent(name: String) -> String {
        switch name.lowercased() {
        case "jarvis": return "The Conductor"
        case "atlas": return "The Scholar"
        case "matrix": return "The Tinkerer"
        case "prism": return "The Skeptic"
        case "scope": return "The Architect"
        default: return "The Specialist"
        }
    }

    private func inferThemedTitle(
        agentName: String,
        identityText: String?,
        soulText: String?,
        isDefaultAgent: Bool
    ) -> String {
        if isDefaultAgent { return "The Conductor" }

        let canonical = Theme.agentRole(for: agentName)
        if canonical != "Agent" { return canonical }

        let text = "\(identityText ?? "") \(soulText ?? "")".lowercased()
        if text.contains("security") || text.contains("cyber") || text.contains("network") || text.contains("firewall") || text.contains("incident") || text.contains("vulnerability") {
            return "The Sentinel"
        }
        if text.contains("design") || text.contains("ui") || text.contains("ux") || text.contains("visual") || text.contains("brand") || text.contains("creative") {
            return "The Visionary"
        }
        if text.contains("quality") || text.contains("test") || text.contains("qa") || text.contains("audit") || text.contains("verification") {
            return "The Examiner"
        }
        if text.contains("plan") || text.contains("roadmap") || text.contains("product") || text.contains("scope") || text.contains("program") {
            return "The Strategist"
        }
        if text.contains("research") || text.contains("analysis") || text.contains("data") || text.contains("insight") || text.contains("investigate") {
            return "The Analyst"
        }
        if text.contains("build") || text.contains("engineer") || text.contains("code") || text.contains("implementation") || text.contains("architecture") || text.contains("api") {
            return "The Builder"
        }
        if text.contains("operations") || text.contains("automation") || text.contains("workflow") || text.contains("execution") {
            return "The Operator"
        }
        if text.contains("documentation") || text.contains("writer") || text.contains("content") || text.contains("communication") {
            return "The Scribe"
        }
        return defaultTitleForAgent(name: agentName)
    }

    private func saveLocalAgentOverride(agentId: String, update: (inout LocalAgentConfig) -> Void) {
        settingsService.update { settings in
            var localAgents = settings.localAgents
            var config = localAgents.first(where: { $0.id == agentId }) ?? LocalAgentConfig(id: agentId)
            update(&config)
            if let idx = localAgents.firstIndex(where: { $0.id == agentId }) {
                localAgents[idx] = config
            } else {
                localAgents.append(config)
            }
            settings.localAgents = localAgents
        }
    }

    func deleteAgent(agentId: String) async throws {
        guard agentId != defaultAgentId else {
            throw NSError(domain: "OpenClawHQ", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot delete the main agent"])
        }
        _ = try await gatewayService.deleteAgent(agentId: agentId, deleteFiles: true)
        withAnimation {
            agents.removeAll { $0.id == agentId }
        }
    }

    func importAgents(_ agentsToImport: [Agent]) {
        for agent in agentsToImport {
            if !agents.contains(where: { $0.id == agent.id }) {
                agents.append(agent)
            }
        }
    }

    private func migrateSparkModelsIfNeeded() async {
        let sparkAgents = agents.filter { ($0.model ?? "").lowercased().contains("spark") }
        guard !sparkAgents.isEmpty else { return }

        for agent in sparkAgents {
            let replacement = recommendedModel(for: agent)
            do {
                _ = try await gatewayService.updateAgent(agentId: agent.id, model: replacement)
                if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
                    agents[idx].model = replacement
                    agents[idx].modelName = replacement
                }
            } catch {
                print("[AgentsVM] model migration failed for \(agent.id): \(error)")
            }
        }
    }

    private func recommendedModel(for agent: Agent) -> String {
        let key = "\(agent.id) \(agent.name)".lowercased()
        if key.contains("jarvis") { return "openai/gpt-5.3-codex" }
        if key.contains("scope") { return "openai/gpt-5.1-codex-max" }
        if key.contains("prism") || key.contains("atlas") { return "openai/gpt-5.2" }
        if key.contains("matrix") { return "openai/gpt-5.2-codex" }
        return "openai/gpt-5.2-codex"
    }

    // MARK: - Event Subscriptions

    /// Reset availableModels whenever the connection drops so that the next
    /// loadModels() call always re-reads auth.json and re-filters against
    /// the current set of authenticated providers.
    private func subscribeToConnectionState() {
        gatewayService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .disconnected = state {
                    self?.availableModels = []
                }
            }
            .store(in: &cancellables)
    }

    /// Re-filter the model list immediately whenever the user toggles a provider
    /// in the sidebar settings panel.
    private func subscribeToProviderSettings() {
        settingsService.$settings
            .map(\.enabledProviders)
            .removeDuplicates { $0 == $1 }
            .dropFirst()   // skip initial value; loadModels() handles first load
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.gatewayService.isConnected else { return }
                self.availableModels = []   // clear so applyModelFilter re-runs
                Task { await self.applyModelFilter() }
            }
            .store(in: &cancellables)
    }

    private func subscribeToEvents() {
        gatewayService.agentEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleAgentEvent(data) }
            .store(in: &cancellables)

        gatewayService.presenceEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handlePresenceEvent(data) }
            .store(in: &cancellables)
    }

    private func handleAgentEvent(_ data: [String: Any]) {
        // Agent events have: { runId, stream, seq, data: { phase?, text? }, sessionKey }
        // agentId is encoded in the sessionKey as "agent:{agentId}:{rest}"
        guard let sessionKey = data["sessionKey"] as? String else { return }
        let agentId = agentIdFromSessionKey(sessionKey)

        guard let idx = agents.firstIndex(where: { $0.id == agentId }) else { return }

        let stream = data["stream"] as? String ?? ""
        let eventData = data["data"] as? [String: Any]
        let phase = eventData?["phase"] as? String

        switch stream {
        case "lifecycle":
            switch phase {
            case "start":
                runtimeBusyAgents.insert(agentId)
                agents[idx].currentActivity = "Working..."
            case "end":
                runtimeBusyAgents.remove(agentId)
                agents[idx].currentActivity = nil
            case "error":
                runtimeBusyAgents.remove(agentId)
                agents[idx].currentActivity = nil
            default:
                break
            }
        case "assistant":
            // Text is streaming — agent is active
            runtimeBusyAgents.insert(agentId)
        default:
            break
        }
        agents[idx].lastSeen = Date()
        applyTaskDrivenStatuses()
    }

    /// Extracts agentId from a session key like "agent:{agentId}:{rest}"
    private func agentIdFromSessionKey(_ sessionKey: String) -> String {
        let lower = sessionKey.lowercased()
        guard lower.hasPrefix("agent:") else { return "main" }
        let after = lower.dropFirst("agent:".count)
        let agentId = after.components(separatedBy: ":").first ?? "main"
        return agentId.isEmpty ? "main" : agentId
    }

    private func handlePresenceEvent(_ data: [String: Any]) {
        // Presence events carry system presence (host, gateway, clients) not agent status.
        // Agent status is driven entirely by `agent` lifecycle events.
        // No-op: presence events don't contain per-agent status info.
        _ = data
    }

    private func subscribeToTaskState() {
        taskService.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyTaskDrivenStatuses()
            }
            .store(in: &cancellables)

        taskService.$isExecutionPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyTaskDrivenStatuses()
            }
            .store(in: &cancellables)
    }

    private func applyTaskDrivenStatuses() {
        for i in agents.indices {
            if !gatewayService.isConnected {
                agents[i].status = .offline
                continue
            }

            let id = agents[i].id.lowercased()
            let hasRuntimeBusy = runtimeBusyAgents.contains(id)

            if hasRuntimeBusy {
                agents[i].status = .busy
                if agents[i].currentActivity == nil || agents[i].currentActivity?.isEmpty == true {
                    agents[i].currentActivity = "Working..."
                }
            } else {
                agents[i].status = .online
                if agents[i].currentActivity == "Working..." {
                    agents[i].currentActivity = nil
                }
            }
        }
    }
}

// MARK: - ModelInfo
struct ModelInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var provider: String
    var contextWindow: Int?
    var supportsReasoning: Bool
}
