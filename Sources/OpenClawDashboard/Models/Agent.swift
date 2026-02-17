import SwiftUI

// MARK: - Agent Model
struct Agent: Identifiable, Hashable {
    let id: String
    var name: String
    var emoji: String
    var role: String
    var status: AgentStatus
    var currentActivity: String?
    var lastSeen: Date?
    var totalTokens: Int
    var sessionCount: Int
    var model: String?          // model ID from gateway (e.g. "anthropic/claude-sonnet-4-5")
    var modelName: String?      // human-friendly model name
    var isDefaultAgent: Bool    // true if this is the main/default agent (cannot be deleted)

    var brandColor: Color {
        Theme.agentColor(for: name)
    }

    var avatarActivePath: String? {
        let path = "\(Constants.avatarDirectory)/\(name)_active.png"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    var avatarIdlePath: String? {
        let path = "\(Constants.avatarDirectory)/\(name)_idle.png"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    var currentAvatarPath: String? {
        switch status {
        case .online, .busy:
            return avatarActivePath
        case .idle, .offline:
            return avatarIdlePath
        }
    }

    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
