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
    private var cancellables = Set<AnyCancellable>()
    private var autoRefreshTask: Task<Void, Never>?

    init(gatewayService: GatewayService) {
        self.gatewayService = gatewayService
        subscribeToEvents()
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
                let rawName = (ident?["name"]  as? String) ?? (raw["name"]  as? String) ?? id
                let emoji   = (ident?["emoji"] as? String) ?? "🤖"

                // Preserve existing agent's runtime state if already known
                if let existing = agents.first(where: { $0.id == id }) {
                    var updated = existing
                    updated.name          = rawName.isEmpty ? id : rawName
                    updated.emoji         = emoji
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

        } catch {
            print("[AgentsVM] Failed to refresh: \(error)")
            // If we have no agents yet, keep empty list
        }
    }

    // MARK: - Status Update

    private func updateFromStatus(_ status: [String: Any]) {
        if let runs = status["runs"] as? [String: Any] {
            let activeIds = Set(
                (runs["active"] as? [[String: Any]] ?? [])
                    .compactMap { $0["agentId"] as? String }
            )
            for i in agents.indices {
                if activeIds.contains(agents[i].id) {
                    agents[i].status = .busy
                }
            }
        }

        if let presence = status["presence"] as? [[String: Any]] {
            for p in presence {
                if let agentId = p["agentId"] as? String,
                   let idx = agents.firstIndex(where: { $0.id == agentId }) {
                    if agents[idx].status == .idle || agents[idx].status == .offline {
                        agents[idx].status = .online
                    }
                    agents[idx].lastSeen = Date()
                }
            }
        }
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

        do {
            let raw = try await gatewayService.fetchModels()
            availableModels = raw.compactMap { dict -> ModelInfo? in
                guard let id = dict["id"] as? String else { return nil }
                return ModelInfo(
                    id: id,
                    name: dict["name"] as? String ?? id,
                    provider: dict["provider"] as? String ?? "Unknown",
                    contextWindow: dict["contextWindow"] as? Int,
                    supportsReasoning: dict["reasoning"] as? Bool ?? false
                )
            }
        } catch {
            print("[AgentsVM] Failed to load models: \(error)")
        }
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
        }

        // Set identity/system prompt if provided
        if let identity = identityContent, !identity.isEmpty {
            _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "IDENTITY.md", content: identity)
        }

        await refreshAgents()
    }

    func updateAgent(agentId: String, name: String? = nil, emoji: String? = nil, model: String? = nil, identityContent: String? = nil) async throws {
        _ = try await gatewayService.updateAgent(agentId: agentId, name: name, model: model, emoji: emoji)

        if let identity = identityContent {
            _ = try? await gatewayService.setAgentFile(agentId: agentId, name: "IDENTITY.md", content: identity)
        }

        // Update local state immediately
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            if let name  = name  { agents[idx].name  = name }
            if let emoji = emoji { agents[idx].emoji = emoji }
            if let model = model {
                agents[idx].model = model
                agents[idx].modelName = availableModels.first(where: { $0.id == model })?.name
            }
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

    // MARK: - Event Subscriptions

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
        let agentId = data["agentId"] as? String ?? "main"
        let status  = data["status"]  as? String

        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            switch status {
            case "running":
                agents[idx].status = .busy
                agents[idx].currentActivity = data["activity"] as? String
                    ?? data["label"]    as? String
                    ?? "Working..."
            case "completed", "ok":
                agents[idx].status = .online
                agents[idx].currentActivity = nil
            case "error":
                agents[idx].status = .online
                agents[idx].currentActivity = nil
            default:
                break
            }
            agents[idx].lastSeen = Date()
        }
    }

    private func handlePresenceEvent(_ data: [String: Any]) {
        if let map = data["agents"] as? [String: String] {
            for (agentId, status) in map {
                if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                    self.agents[idx].status  = AgentStatus(rawValue: status) ?? .offline
                    self.agents[idx].lastSeen = Date()
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
