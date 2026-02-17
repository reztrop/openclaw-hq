import SwiftUI

struct TaskCard: View {
    let task: TaskItem
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Priority bar
            HStack(spacing: 6) {
                Image(systemName: task.priority.icon)
                    .font(.caption2)
                    .foregroundColor(task.priority.color)
                Text(task.priority.label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(task.priority.color)
                Spacer()

                if let scheduled = task.scheduledFor {
                    Text(scheduled.relativeString)
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
            }

            // Title
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)

            // Description preview
            if let desc = task.description, !desc.isEmpty {
                Text(desc.truncated(to: 80))
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(2)
            }

            // Footer: Agent + time
            HStack(spacing: 6) {
                if let agentName = task.assignedAgent {
                    AgentAvatarSmall(agentName: agentName, size: 20)
                    Text(agentName)
                        .font(.caption)
                        .foregroundColor(Theme.agentColor(for: agentName))
                }
                Spacer()
                Text(task.updatedAt.relativeString)
                    .font(.caption2)
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.darkAccent)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isHovered ? task.priority.color.opacity(0.4) : Theme.darkBorder.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
