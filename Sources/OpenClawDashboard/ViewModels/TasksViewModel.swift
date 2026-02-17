import SwiftUI

@MainActor
class TasksViewModel: ObservableObject {
    @Published var isEditing = false
    @Published var editingTask: TaskItem?
    @Published var showingNewTask = false

    private let taskService: TaskService

    init(taskService: TaskService) {
        self.taskService = taskService
    }

    var tasks: [TaskItem] {
        taskService.tasks
    }

    func tasksFor(_ status: TaskStatus) -> [TaskItem] {
        taskService.tasksForStatus(status)
    }

    func countFor(_ status: TaskStatus) -> Int {
        tasksFor(status).count
    }

    // MARK: - CRUD

    func createTask(
        title: String,
        description: String?,
        assignedAgent: String?,
        priority: TaskPriority,
        scheduledFor: Date?
    ) {
        _ = taskService.createTask(
            title: title,
            description: description,
            assignedAgent: assignedAgent,
            status: .scheduled,
            priority: priority,
            scheduledFor: scheduledFor
        )
        objectWillChange.send()
    }

    func updateTask(_ task: TaskItem) {
        taskService.updateTask(task)
        objectWillChange.send()
    }

    func deleteTask(_ taskId: UUID) {
        taskService.deleteTask(taskId)
        objectWillChange.send()
    }

    func moveTask(_ taskId: UUID, to status: TaskStatus) {
        taskService.moveTask(taskId, to: status)
        objectWillChange.send()
    }

    func handleDrop(of tasks: [TaskItem], to status: TaskStatus) -> Bool {
        for task in tasks {
            moveTask(task.id, to: status)
        }
        return !tasks.isEmpty
    }

    // MARK: - Edit Sheet

    func startEditing(_ task: TaskItem) {
        editingTask = task
        isEditing = true
    }

    func startNewTask() {
        editingTask = nil
        showingNewTask = true
    }
}
