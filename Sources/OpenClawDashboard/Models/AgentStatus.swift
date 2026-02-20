import SwiftUI

enum AgentStatus: String, Codable, CaseIterable {
    case online
    case busy
    case idle
    case offline

    var color: Color {
        switch self {
        case .online: return Theme.statusOnline
        case .busy: return Theme.statusBusy
        case .idle: return Theme.statusIdle
        case .offline: return Theme.statusOffline
        }
    }

    var label: String {
        switch self {
        case .online: return "Online"
        case .busy: return "Busy"
        case .idle: return "Idle"
        case .offline: return "Offline"
        }
    }

    var shouldPulse: Bool {
        self == .busy
    }

    var isActive: Bool {
        self == .busy
    }
}
