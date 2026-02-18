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
                let gatewayModelId = (ident?["model"] as? String) ?? (raw["model"] as? String)
                let localConfig = settingsService.settings.localAgents.first(where: { $0.id == id })
                let localName = localConfig?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawName = (localName?.isEmpty == false ? (localName ?? gatewayName) : gatewayName)
                let localEmoji = localConfig?.emoji
                let emoji = (localEmoji?.isEmpty == false ? (localEmoji ?? gatewayEmoji) : gatewayEmoji)
                let modelId = (localConfig?.modelId?.isEmpty == false ? localConfig?.modelId : gatewayModelId)

                // Preserve existing agent's runtime state if already known
                if let existing = agents.first(where: { $0.id == id }) {
                    var updated = existing
                    updated.name           = rawName.isEmpty ? id : rawName
                    updated.emoji          = emoji
                    updated.model          = modelId
                    updated.modelName      = modelId
                    updated.isDefaultAgent = id == defaultId
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
                    isDefaultAgent: id == defaultId
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

    func createAgent(name: String, emoji: String, model: String?, identityContent: String?) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let normalizedId = name.lowercased().replacingOccurrences(of: " ", with: "-")
        let workspace = "\(home)/.openclaw/workspace/agents/\(normalizedId)"

        guard let result = try await gatewayService.createAgent(name: name, workspace: workspace, emoji: emoji),
              let agentId = result["agentId"] as? String else {
            throw NSError(domain: "OpenClawHQ", code: 1, userInfo: [NSLocalizedDescriptionKey: "Agent creation failed"])
        }

        // Set model if provided
        if let model = model, !model.isEmpty {
            _ = try? await gatewayService.updateAgent(agentId: agentId, model: model)
            saveLocalAgentOverride(agentId: agentId) { config in
                config.modelId = model
            }
        }

        // Set identity/system prompt if provided
        if let identity = identityContent, !identity.isEmpty {
            _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "IDENTITY.md", content: identity)
        }

        await refreshAgents()
    }

    func updateAgent(agentId: String, name: String? = nil, emoji: String? = nil, model: String? = nil, identityContent: String? = nil) async throws {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmedName?.isEmpty == true) ? nil : trimmedName
        let shouldSendGatewayUpdate = finalName != nil || model != nil

        if shouldSendGatewayUpdate {
            _ = try await gatewayService.updateAgent(agentId: agentId, name: finalName, model: model)
        }

        if let identity = identityContent {
            _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "IDENTITY.md", content: identity)
        }

        if let emoji = emoji {
            saveLocalAgentOverride(agentId: agentId) { config in
                config.emoji = emoji
            }
        }

        if let model = model, !model.isEmpty {
            saveLocalAgentOverride(agentId: agentId) { config in
                config.modelId = model
            }
        }

        // Update local state immediately
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            if let name = finalName { agents[idx].name = name }
            if let emoji = emoji { agents[idx].emoji = emoji }
            if let model = model {
                agents[idx].model = model
                agents[idx].modelName = availableModels.first(where: { $0.id == model })?.name
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
