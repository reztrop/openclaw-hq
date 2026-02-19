import SwiftUI
import Combine

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
    private var cancellables = Set<AnyCancellable>()
    private var autoRefreshTask: Task<Void, Never>?

    init(gatewayService: GatewayService, settingsService: SettingsService) {
        self.gatewayService = gatewayService
        self.settingsService = settingsService
        subscribeToEvents()
        subscribeToConnectionState()
        subscribeToProviderSettings()
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
                let rawName = (localName?.isEmpty == false ? (localName ?? gatewayName) : gatewayName)
                let localEmoji = localConfig?.emoji
                let emoji = (localEmoji?.isEmpty == false ? (localEmoji ?? gatewayEmoji) : gatewayEmoji)
                let localModelId = ModelNormalizer.normalize(localConfig?.modelId)
                let modelId = (localModelId?.isEmpty == false ? localModelId : gatewayModelId)
                let canCommunicateWithAgents = localConfig?.canCommunicateWithAgents ?? true
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let isInitialized = FileManager.default.fileExists(atPath: "\(home)/.openclaw/agents/\(id.lowercased())/agent")

                // Preserve existing agent's runtime state if already known
                if let existing = agents.first(where: { $0.id == id }) {
                    var updated = existing
                    updated.name           = rawName.isEmpty ? id : rawName
                    updated.emoji          = emoji
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
                    role: id == defaultId ? "Main Agent" : "Agent",
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
        canCommunicateWithAgents: Bool = true
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

        await refreshAgents()
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
        emoji: String? = nil,
        model: String? = nil,
        identityContent: String? = nil,
        canCommunicateWithAgents: Bool? = nil
    ) async throws {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmedName?.isEmpty == true) ? nil : trimmedName
        let normalizedModel = ModelNormalizer.normalize(model)
        let shouldSendGatewayUpdate = finalName != nil || normalizedModel != nil

        if shouldSendGatewayUpdate {
            _ = try await gatewayService.updateAgent(agentId: agentId, name: finalName, model: normalizedModel)
        }

        if let identity = identityContent {
            _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "IDENTITY.md", content: identity)
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

        // Update local state immediately
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            if let name = finalName { agents[idx].name = name }
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
                agents[idx].status = .busy
                agents[idx].currentActivity = "Working..."
            case "end":
                agents[idx].status = .online
                agents[idx].currentActivity = nil
            case "error":
                agents[idx].status = .online
                agents[idx].currentActivity = nil
            default:
                break
            }
        case "assistant":
            // Text is streaming — agent is active
            if agents[idx].status != .busy {
                agents[idx].status = .busy
            }
        default:
            break
        }
        agents[idx].lastSeen = Date()
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
}

// MARK: - ModelInfo
struct ModelInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var provider: String
    var contextWindow: Int?
    var supportsReasoning: Bool
}
