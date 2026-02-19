import SwiftUI

struct TasksView: View {
    @EnvironmentObject var tasksVM: TasksViewModel
    @EnvironmentObject var gatewayService: GatewayService
    @State private var selectedTaskForView: TaskItem?

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()
            controlsBar

            if tasksVM.isExecutionPaused {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                    Text("Task execution is paused. In-progress tasks are halted.")
                        .font(.subheadline)
                }
                .foregroundColor(Theme.statusOffline)
                .padding(.vertical, 8)
            }

            // Kanban columns
            HStack(spacing: 16) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    TaskColumn(
                        status: status,
                        tasks: tasksVM.tasksFor(status),
                        isExecutionPaused: tasksVM.isExecutionPaused,
                        onDrop: { droppedTasks in
                            handleDroppedTasks(droppedTasks, to: status)
                        },
                        onMove: { taskId, targetStatus in
                            handleTaskMove(taskId, to: targetStatus)
                        },
                        onView: { task in
                            selectedTaskForView = task
                        },
                        onEdit: { task in
                            tasksVM.startEditing(task)
                        },
                        onDelete: { taskId in
                            tasksVM.deleteTask(taskId)
                        }
                    )
                }
            }
            .padding(20)
        }
        .background(Theme.darkBackground)
        .sheet(isPresented: $tasksVM.showingNewTask) {
            TaskEditSheet(task: nil) { title, desc, agent, priority, scheduled in
                tasksVM.createTask(
                    title: title,
                    description: desc,
                    assignedAgent: agent,
                    priority: priority,
                    scheduledFor: scheduled
                )
            }
        }
        .sheet(isPresented: $tasksVM.isEditing) {
            if let task = tasksVM.editingTask {
                TaskEditSheet(task: task) { title, desc, agent, priority, scheduled in
                    var updated = task
                    updated.title = title
                    updated.description = desc
                    updated.assignedAgent = agent
                    updated.priority = priority
                    updated.scheduledFor = scheduled
                    tasksVM.updateTask(updated)
                }
            }
        }
        .sheet(item: $selectedTaskForView) { task in
            TaskDetailSheet(task: task)
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 10) {
            Button {
                tasksVM.startNewTask()
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Button {
                tasksVM.toggleExecutionPaused()
            } label: {
                Label(tasksVM.isExecutionPaused ? "Resume" : "Pause",
                      systemImage: tasksVM.isExecutionPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            .help(tasksVM.isExecutionPaused ? "Resume all task activity" : "Pause all task activity")

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func handleDroppedTasks(_ droppedTasks: [TaskItem], to status: TaskStatus) -> Bool {
        var handledAny = false
        for task in droppedTasks {
            let outcome = tasksVM.moveTaskWithExecutionRules(task.id, to: status)
            handledAny = true

            if let displaced = outcome.displacedTask {
                // Surface queue displacement for visibility.
                print("[Tasks] Displaced in-progress task to Queue: \(displaced.title)")
            }

            if let started = outcome.startedTask {
                Task { await beginImplementation(for: started) }
            }
        }
        return handledAny
    }

    private func handleTaskMove(_ taskId: UUID, to status: TaskStatus) {
        let outcome = tasksVM.moveTaskWithExecutionRules(taskId, to: status)
        if let displaced = outcome.displacedTask {
            print("[Tasks] Displaced in-progress task to Queue: \(displaced.title)")
        }
        if let started = outcome.startedTask {
            Task { await beginImplementation(for: started) }
        }
    }

    private func beginImplementation(for task: TaskItem) async {
        guard !tasksVM.isExecutionPaused else { return }
        guard task.status == .inProgress else { return }
        guard let agent = task.assignedAgent?.trimmingCharacters(in: .whitespacesAndNewlines), !agent.isEmpty else { return }

        let projectLine: String = {
            if let projectName = task.projectName, !projectName.isEmpty {
                return "Project: \(projectName)"
            }
            return "Project: Unspecified"
        }()

        let description = task.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailLine = (description?.isEmpty == false) ? "Task details: \(description!)" : "Task details: none"

        let kickoff = """
        [task-start]
        \(projectLine)
        Task ID: \(task.id.uuidString)
        Task: \(task.title)
        \(detailLine)

        Begin implementation immediately.
        Before doing new work, first check whether this task already has partial progress and continue from that state.
        Keep updates concise and execution-focused.
        """

        _ = try? await gatewayService.sendAgentMessage(
            agentId: agent.lowercased(),
            message: kickoff,
            sessionKey: nil,
            thinkingEnabled: true
        )
    }
}
