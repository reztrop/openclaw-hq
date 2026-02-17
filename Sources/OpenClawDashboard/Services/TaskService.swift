import Foundation

// MARK: - Task Service
@MainActor
class TaskService: ObservableObject {
    @Published var tasks: [TaskItem] = []

    private let filePath: String

    init(filePath: String = Constants.tasksFilePath) {
        self.filePath = filePath
        loadTasks()
    }

    // MARK: - Persistence

    func loadTasks() {
        guard FileManager.default.fileExists(atPath: filePath) else {
            tasks = Self.sampleTasks
            saveTasks()
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            tasks = try decoder.decode([TaskItem].self, from: data)
        } catch {
            print("[TaskService] Failed to load tasks: \(error)")
            tasks = Self.sampleTasks
        }
    }

    func saveTasks() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tasks)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            print("[TaskService] Failed to save tasks: \(error)")
        }
    }

    // MARK: - CRUD

    func createTask(
        title: String,
        description: String? = nil,
        assignedAgent: String? = nil,
        status: TaskStatus = .scheduled,
        priority: TaskPriority = .medium,
        scheduledFor: Date? = nil
    ) -> TaskItem {
        let task = TaskItem(
            title: title,
            description: description,
            assignedAgent: assignedAgent,
            status: status,
            priority: priority,
            scheduledFor: scheduledFor
        )
        tasks.append(task)
        saveTasks()
        return task
    }

    func updateTask(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            var updated = task
            updated.updatedAt = Date()
            tasks[index] = updated
            saveTasks()
        }
    }

    func deleteTask(_ taskId: UUID) {
        tasks.removeAll { $0.id == taskId }
        saveTasks()
    }

    func moveTask(_ taskId: UUID, to status: TaskStatus) {
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].status = status
            tasks[index].updatedAt = Date()
            if status == .done {
                tasks[index].completedAt = Date()
            }
            saveTasks()
        }
    }

    func tasksForStatus(_ status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status }
    }

    // MARK: - Sample Data

    static let sampleTasks: [TaskItem] = [
        TaskItem(title: "Initialize Scope agent", description: "Set up planning agent with acceptance criteria templates", assignedAgent: "Jarvis", status: .scheduled, priority: .high),
        TaskItem(title: "Initialize Atlas agent", description: "Configure research agent with knowledge base access", assignedAgent: "Jarvis", status: .scheduled, priority: .high),
        TaskItem(title: "Refactor auth middleware", description: "Clean up token validation and add rate limiting", assignedAgent: "Matrix", status: .queued, priority: .medium),
        TaskItem(title: "Security audit: API endpoints", description: "Review all public endpoints for auth bypass vulnerabilities", assignedAgent: "Prism", status: .inProgress, priority: .urgent),
        TaskItem(title: "Update README docs", description: "Reflect new agent architecture in documentation", assignedAgent: "Atlas", status: .queued, priority: .low),
        TaskItem(title: "Fix Slack message threading", description: "Thread replies not appearing in correct channel", assignedAgent: "Matrix", status: .done, priority: .medium, completedAt: Date().addingTimeInterval(-3600)),
    ]
}
