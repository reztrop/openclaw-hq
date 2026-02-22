import SwiftUI

struct TasksView: View {
    @EnvironmentObject var tasksVM: TasksViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTaskForView: TaskItem?

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()
            controlsBar

            if tasksVM.isExecutionPaused {
                HStack(spacing: 8) {
                    Text("⏸")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.glitchAmber)
                    Text("EXECUTION_SUSPENDED — IN-PROGRESS WORK HALTED")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.glitchAmber)
                        .tracking(1)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Theme.glitchAmber.opacity(0.08))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.glitchAmber.opacity(0.25)).frame(height: 1)
                }
            }

            if tasksVM.isLoading {
                loadingState
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            } else if let error = tasksVM.loadError {
                errorState(error)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            } else if activeTasks.isEmpty {
                emptyState
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            } else {
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

    private var activeTasks: [TaskItem] {
        tasksVM.tasks.filter { !$0.isArchived }
    }

    private var loadingState: some View {
        HQStateView(
            icon: "arrow.triangle.2.circlepath",
            title: "Loading tasks…",
            subtitle: "Syncing local task board state.",
            tone: .accent,
            iconSize: 28,
            maxWidth: 420,
            contentPadding: 28,
            showsProgress: true,
            progressTint: Theme.neonCyan
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorState(_ message: String) -> some View {
        HQStateView(
            icon: "exclamationmark.triangle.fill",
            title: "Tasks failed to load",
            subtitle: message,
            tone: .danger,
            iconSize: 34,
            maxWidth: 460,
            contentPadding: 24,
            showPanel: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "tray",
            title: "No tasks yet",
            subtitle: "Create your first task to start tracking execution.",
            actionLabel: "New Task",
            action: { tasksVM.startNewTask() }
        )
        .background(Theme.darkBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var controlsBar: some View {
        HStack(spacing: 10) {
            // "[ OPS_BOARD ]" header
            HStack(spacing: 6) {
                Text("[")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan.opacity(0.6))
                Text("OPS_BOARD")
                    .font(Theme.headerFont)
                    .foregroundColor(Theme.neonCyan)
                    .glitchText()
                Text("]")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan.opacity(0.6))
            }

            Spacer()

            HQButton(variant: .glow) {
                tasksVM.startNewTask()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("NEW_TASK")
                        .font(Theme.terminalFont)
                }
            }

            HQButton(variant: tasksVM.isExecutionPaused ? .primary : .danger) {
                tasksVM.toggleExecutionPaused()
            } label: {
                HStack(spacing: 6) {
                    Text(tasksVM.isExecutionPaused ? "▶" : "⏸")
                    Text(tasksVM.isExecutionPaused ? "RESUME" : "SUSPEND")
                        .font(Theme.terminalFont)
                }
            }
            .help(tasksVM.isExecutionPaused ? "Resume all task activity" : "Pause all task activity")
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
                print("[Tasks] Displaced in-progress task to Queue: \(displaced.title)")
            }
            _ = outcome.startedTask
        }
        return handledAny
    }

    private func handleTaskMove(_ taskId: UUID, to status: TaskStatus) {
        let outcome = tasksVM.moveTaskWithExecutionRules(taskId, to: status)
        if let displaced = outcome.displacedTask {
            print("[Tasks] Displaced in-progress task to Queue: \(displaced.title)")
        }
        _ = outcome.startedTask
    }
}
