import SwiftUI

struct TasksView: View {
    @EnvironmentObject var tasksVM: TasksViewModel
    @EnvironmentObject var gatewayService: GatewayService

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner()

            // Kanban columns
            HStack(spacing: 16) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    TaskColumn(
                        status: status,
                        tasks: tasksVM.tasksFor(status),
                        onDrop: { droppedTasks in
                            tasksVM.handleDrop(of: droppedTasks, to: status)
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    tasksVM.startNewTask()
                } label: {
                    Label("New Task", systemImage: "plus")
                }
            }
        }
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
    }
}
