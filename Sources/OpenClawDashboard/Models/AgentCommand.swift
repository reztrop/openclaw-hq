import Foundation

struct AgentCommand: Identifiable {
    let id = UUID()
    let agentId: String
    let message: String
    let timestamp: Date
    var response: String?
    var status: CommandStatus

    init(agentId: String, message: String) {
        self.agentId = agentId
        self.message = message
        self.timestamp = Date()
        self.response = nil
        self.status = .pending
    }
}

enum CommandStatus: String {
    case pending
    case sent
    case completed
    case failed
}
