import Foundation
import Combine

@MainActor
class ActivityLogViewModel: ObservableObject {
    @Published var events: [ActivityEvent] = []
    @Published var filter: ActivityEventType?
    @Published var searchText: String = ""

    private let maxEvents = 500
    private let gatewayService: GatewayService
    private var cancellables = Set<AnyCancellable>()

    init(gatewayService: GatewayService) {
        self.gatewayService = gatewayService

        gatewayService.agentEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleAgentEvent(data) }
            .store(in: &cancellables)

        gatewayService.presenceEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handlePresenceEvent(data) }
            .store(in: &cancellables)

        gatewayService.tickEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleTickEvent(data) }
            .store(in: &cancellables)

        gatewayService.healthEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleHealthEvent(data) }
            .store(in: &cancellables)
    }

    var filteredEvents: [ActivityEvent] {
        var result = events
        if let filter = filter {
            result = result.filter { $0.eventType == filter }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.message.lowercased().contains(query) ||
                $0.agentName.lowercased().contains(query) ||
                ($0.details?.lowercased().contains(query) ?? false)
            }
        }
        return result
    }

    func clearEvents() {
        events.removeAll()
    }

    // MARK: - Event Handlers

    private func handleAgentEvent(_ data: [String: Any]) {
        let agentId = data["agentId"] as? String ?? "main"
        let agentName = resolveAgentName(agentId)
        let status = data["status"] as? String ?? data["type"] as? String ?? "update"
        let activity = data["activity"] as? String

        let eventType: ActivityEventType = (status == "error") ? .error : .statusChange
        let message: String
        switch status {
        case "running": message = "\(agentName) started a task"
        case "completed", "ok": message = "\(agentName) completed a task"
        case "error": message = "\(agentName) encountered an error"
        default: message = "\(agentName): \(status)"
        }

        addEvent(ActivityEvent(
            timestamp: Date(),
            agentId: agentId,
            agentName: agentName,
            eventType: eventType,
            message: message,
            details: activity
        ))
    }

    private func handlePresenceEvent(_ data: [String: Any]) {
        let agentId = data["agentId"] as? String ?? "main"
        let agentName = resolveAgentName(agentId)
        let action = data["action"] as? String ?? "update"

        let message: String
        switch action {
        case "join", "online": message = "\(agentName) came online"
        case "leave", "offline": message = "\(agentName) went offline"
        default: message = "\(agentName) presence: \(action)"
        }

        addEvent(ActivityEvent(
            timestamp: Date(),
            agentId: agentId,
            agentName: agentName,
            eventType: .statusChange,
            message: message,
            details: nil
        ))
    }

    private func handleTickEvent(_ data: [String: Any]) {
        let runs = data["activeRuns"] as? Int
            ?? (data["runs"] as? [[String: Any]])?.count
            ?? 0

        if runs > 0 {
            addEvent(ActivityEvent(
                timestamp: Date(),
                agentId: "system",
                agentName: "Gateway",
                eventType: .session,
                message: "\(runs) active run\(runs == 1 ? "" : "s")",
                details: nil
            ))
        }
    }

    private func handleHealthEvent(_ data: [String: Any]) {
        let healthy = data["healthy"] as? Bool ?? true
        addEvent(ActivityEvent(
            timestamp: Date(),
            agentId: "system",
            agentName: "Gateway",
            eventType: .health,
            message: healthy ? "Health check passed" : "Health check failed",
            details: nil
        ))
    }

    private func addEvent(_ event: ActivityEvent) {
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events.removeLast(events.count - maxEvents)
        }
    }

    private func resolveAgentName(_ agentId: String) -> String {
        if agentId == "main" { return "Jarvis" }
        return agentId.capitalized
    }
}
