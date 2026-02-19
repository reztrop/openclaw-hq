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
    var projectId: String?
    var projectName: String?
    var projectColorHex: String?
    var isVerificationTask: Bool
    var verificationRound: Int?
    var isVerified: Bool
    var isArchived: Bool

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
        completedAt: Date? = nil,
        projectId: String? = nil,
        projectName: String? = nil,
        projectColorHex: String? = nil,
        isVerificationTask: Bool = false,
        verificationRound: Int? = nil,
        isVerified: Bool = false,
        isArchived: Bool = false
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
        self.projectId = projectId
        self.projectName = projectName
        self.projectColorHex = projectColorHex
        self.isVerificationTask = isVerificationTask
        self.verificationRound = verificationRound
        self.isVerified = isVerified
        self.isArchived = isArchived
    }

    // MARK: - Transferable
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case assignedAgent
        case status
        case priority
        case createdAt
        case updatedAt
        case scheduledFor
        case completedAt
        case projectId
        case projectName
        case projectColorHex
        case isVerificationTask
        case verificationRound
        case isVerified
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        assignedAgent = try c.decodeIfPresent(String.self, forKey: .assignedAgent)
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .scheduled
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        scheduledFor = try c.decodeIfPresent(Date.self, forKey: .scheduledFor)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName)
        projectColorHex = try c.decodeIfPresent(String.self, forKey: .projectColorHex)
        isVerificationTask = try c.decodeIfPresent(Bool.self, forKey: .isVerificationTask) ?? false
        verificationRound = try c.decodeIfPresent(Int.self, forKey: .verificationRound)
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
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
        case .scheduled: return "Ready"
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
