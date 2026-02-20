import Foundation

// MARK: - Task Service
@MainActor
class TaskService: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var isExecutionPaused: Bool = false

    private let filePath: String
    private let stateFilePath: String
    private var lastTasksFileModificationDate: Date?
    private var lastStateFileModificationDate: Date?
    private var filePollTask: Task<Void, Never>?

    private struct TaskRuntimeState: Codable {
        var isExecutionPaused: Bool
    }

    init(filePath: String = Constants.tasksFilePath, stateFilePath: String = Constants.tasksStateFilePath) {
        self.filePath = filePath
        self.stateFilePath = stateFilePath
        loadTasks()
        loadRuntimeState()
        refreshKnownFileModificationDates()
        startFilePolling()
    }

    deinit {
        filePollTask?.cancel()
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
            lastTasksFileModificationDate = fileModificationDate(at: filePath)
        } catch {
            print("[TaskService] Failed to save tasks: \(error)")
        }
    }

    private func loadRuntimeState() {
        guard FileManager.default.fileExists(atPath: stateFilePath) else {
            isExecutionPaused = false
            saveRuntimeState()
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
            let decoder = JSONDecoder()
            let state = try decoder.decode(TaskRuntimeState.self, from: data)
            isExecutionPaused = state.isExecutionPaused
        } catch {
            isExecutionPaused = false
        }
    }

    private func saveRuntimeState() {
        do {
            let state = TaskRuntimeState(isExecutionPaused: isExecutionPaused)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: URL(fileURLWithPath: stateFilePath), options: .atomic)
            lastStateFileModificationDate = fileModificationDate(at: stateFilePath)
        } catch {
            print("[TaskService] Failed to save runtime state: \(error)")
        }
    }

    private func startFilePolling() {
        filePollTask?.cancel()
        filePollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.reloadFromDiskIfNeeded()
            }
        }
    }

    private func reloadFromDiskIfNeeded() {
        let currentTasksMod = fileModificationDate(at: filePath)
        let currentStateMod = fileModificationDate(at: stateFilePath)

        if currentTasksMod != lastTasksFileModificationDate {
            loadTasks()
            lastTasksFileModificationDate = currentTasksMod
        }

        if currentStateMod != lastStateFileModificationDate {
            loadRuntimeState()
            lastStateFileModificationDate = currentStateMod
        }
    }

    private func refreshKnownFileModificationDates() {
        lastTasksFileModificationDate = fileModificationDate(at: filePath)
        lastStateFileModificationDate = fileModificationDate(at: stateFilePath)
    }

    private func fileModificationDate(at path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    func setExecutionPaused(_ paused: Bool) {
        isExecutionPaused = paused
        saveRuntimeState()
    }

    func toggleExecutionPaused() {
        setExecutionPaused(!isExecutionPaused)
    }

    // MARK: - CRUD

    func createTask(
        title: String,
        description: String? = nil,
        assignedAgent: String? = nil,
        status: TaskStatus = .scheduled,
        priority: TaskPriority = .medium,
        scheduledFor: Date? = nil,
        projectId: String? = nil,
        projectName: String? = nil,
        projectColorHex: String? = nil,
        isVerificationTask: Bool = false,
        verificationRound: Int? = nil,
        isVerified: Bool = false,
        isArchived: Bool = false
    ) -> TaskItem {
        let task = TaskItem(
            title: title,
            description: description,
            assignedAgent: assignedAgent,
            status: status,
            priority: priority,
            scheduledFor: scheduledFor,
            projectId: projectId,
            projectName: projectName,
            projectColorHex: projectColorHex,
            isVerificationTask: isVerificationTask,
            verificationRound: verificationRound,
            isVerified: isVerified,
            isArchived: isArchived
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
                if tasks[index].isVerificationTask {
                    tasks[index].isVerified = true
                }
            } else {
                tasks[index].completedAt = nil
                if tasks[index].isVerificationTask {
                    tasks[index].isVerified = false
                }
            }
            saveTasks()
        }
    }

    func archiveTasks(for projectId: String) {
        var mutated = false
        for idx in tasks.indices {
            if tasks[idx].projectId == projectId, !tasks[idx].isArchived {
                tasks[idx].isArchived = true
                tasks[idx].updatedAt = Date()
                mutated = true
            }
        }
        if mutated {
            saveTasks()
        }
    }

    func tasksForStatus(_ status: TaskStatus) -> [TaskItem] {
        tasks
            .filter { $0.status == status && !$0.isArchived }
            .sorted {
                if status == .done {
                    let lhsVerified = $0.isVerificationTask && $0.isVerified
                    let rhsVerified = $1.isVerificationTask && $1.isVerified
                    if lhsVerified != rhsVerified { return lhsVerified && !rhsVerified }
                }
                let lhsPriority = Self.priorityRank($0.priority)
                let rhsPriority = Self.priorityRank($1.priority)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.createdAt > $1.createdAt
            }
    }

    private static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
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
