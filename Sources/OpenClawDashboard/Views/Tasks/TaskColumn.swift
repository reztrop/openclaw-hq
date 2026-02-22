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
            // Column header with box-drawing chars: "┌─[ STATUS: N ]─"
            HStack(spacing: 0) {
                Text("┌─[")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(status.color.opacity(0.6))
                Text(" \(status.columnTitle.uppercased()): \(tasks.count) ")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(status.color)
                Text("]─")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(status.color.opacity(0.6))
                Rectangle()
                    .fill(status.color.opacity(0.3))
                    .frame(height: 1)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                status.color.opacity(0.08)
                    .overlay(
                        Rectangle()
                            .fill(status.color.opacity(0.2))
                            .frame(height: 1),
                        alignment: .bottom
                    )
            )

            // Cards area with faint status tint + scanline overlay
            ScanlinePanel(opacity: 0.03) {
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
            .background(status.color.opacity(0.03))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            HQPanel(
                cornerRadius: 12,
                surface: Theme.darkSurface.opacity(0.5),
                border: isTargeted ? status.color.opacity(0.85) : status.color.opacity(0.25),
                lineWidth: isTargeted ? 2 : 1
            ) { Color.clear }
        )
        .shadow(
            color: isTargeted ? status.color.opacity(0.25) : .clear,
            radius: isTargeted ? 12 : 0
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
        EmptyStateView(
            icon: status.icon,
            title: "No \(status.columnTitle.lowercased()) tasks",
            subtitle: nil,
            alignment: .center,
            textAlignment: .center,
            maxWidth: .infinity,
            iconSize: 20,
            iconColor: status.color.opacity(0.75),
            contentPadding: 16,
            showPanel: true
        )
    }
}
