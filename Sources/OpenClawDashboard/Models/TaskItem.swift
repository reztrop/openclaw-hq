import SwiftUI

// MARK: - Task Model
struct TaskItem: Identifiable, Codable, Hashable, Transferable {
    let id: UUID
    var title: String
    var description: String?
    var assignedAgent: String?
    var status: TaskStatus
    var priority: TaskPriority
    var createdAt: Date
    var updatedAt: Date
    var scheduledFor: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        assignedAgent: String? = nil,
        status: TaskStatus = .scheduled,
        priority: TaskPriority = .medium,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        scheduledFor: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.assignedAgent = assignedAgent
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduledFor = scheduledFor
        self.completedAt = completedAt
    }

    // MARK: - Transferable
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Task Status
enum TaskStatus: String, Codable, CaseIterable {
    case scheduled
    case queued
    case inProgress
    case done

    var columnTitle: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .queued: return "Queue"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }

    var icon: String {
        switch self {
        case .scheduled: return "calendar"
        case .queued: return "tray.full"
        case .inProgress: return "bolt.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .scheduled: return Theme.columnScheduled
        case .queued: return Theme.columnQueued
        case .inProgress: return Theme.columnInProgress
        case .done: return Theme.columnDone
        }
    }
}

// MARK: - Task Priority
enum TaskPriority: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case urgent

    var label: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        case .urgent: return Theme.priorityUrgent
        }
    }

    var icon: String {
        switch self {
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
}
