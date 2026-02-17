import SwiftUI

struct ActivityEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let agentId: String
    let agentName: String
    let eventType: ActivityEventType
    let message: String
    let details: String?
}

enum ActivityEventType: String, CaseIterable {
    case statusChange = "Status"
    case taskComplete = "Task"
    case error = "Error"
    case command = "Command"
    case session = "Session"
    case health = "Health"

    var icon: String {
        switch self {
        case .statusChange: return "arrow.triangle.2.circlepath"
        case .taskComplete: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .command: return "terminal"
        case .session: return "bubble.left.and.bubble.right"
        case .health: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .statusChange: return Theme.jarvisBlue
        case .taskComplete: return Theme.statusOnline
        case .error: return Theme.statusOffline
        case .command: return Theme.scopePurple
        case .session: return Theme.prismCyan
        case .health: return Theme.atlasAmber
        }
    }
}
