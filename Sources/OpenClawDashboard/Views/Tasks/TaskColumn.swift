import SwiftUI

struct TaskColumn: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let isExecutionPaused: Bool
    let onDrop: ([TaskItem]) -> Bool
    let onMove: (UUID, TaskStatus) -> Void
    let onView: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Column header
            HStack {
                Image(systemName: status.icon)
                    .foregroundColor(status.color)
                    .font(.subheadline)
                Text(status.columnTitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                HQBadge(text: "\(tasks.count)", tone: .neutral)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .background(status.color.opacity(0.3))

            // Cards area
            ScrollView {
                LazyVStack(spacing: 10) {
                    if tasks.isEmpty {
                        TaskColumnEmptyState(status: status)
                    } else {
                        ForEach(tasks) { task in
                            TaskCard(
                                task: task,
                                onView: { onView(task) },
                                showPausedOverlay: isExecutionPaused && status == .inProgress,
                                showVerifiedOverlay: status == .done && task.isVerificationTask && task.isVerified
                            )
                                .draggable(task)
                                .contextMenu {
                                    Button("Edit") { onEdit(task) }
                                    Divider()
                                    ForEach(TaskStatus.allCases, id: \.self) { targetStatus in
                                        if targetStatus != status {
                                            Button("Move to \(targetStatus.columnTitle)") {
                                                onMove(task.id, targetStatus)
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) { onDelete(task.id) }
                                }
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            HQPanel(
                cornerRadius: 12,
                surface: Theme.darkSurface.opacity(0.5),
                border: isTargeted ? status.color.opacity(0.6) : Theme.darkBorder.opacity(0.3),
                lineWidth: isTargeted ? 2 : 1
            ) { Color.clear }
        )
        .dropDestination(for: TaskItem.self) { items, _ in
            onDrop(items)
        } isTargeted: { targeted in
            if reduceMotion {
                isTargeted = targeted
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isTargeted = targeted
                }
            }
        }
    }


}

private struct TaskColumnEmptyState: View {
    let status: TaskStatus

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: status.icon)
                .font(.system(size: 22))
                .foregroundColor(status.color.opacity(0.7))
            Text("No \(status.columnTitle.lowercased()) tasks")
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.darkSurface.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.darkBorder.opacity(0.4), lineWidth: 1)
                )
        )
    }
}
