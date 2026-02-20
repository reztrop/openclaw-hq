import SwiftUI

struct AgentCard: View {
    let agent: Agent
    var onEdit: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 12) {
            // Avatar
            AgentAvatar(
                agentName: agent.name,
                isActive: agent.status.isActive,
                size: 180
            )

            // Info section
            VStack(spacing: 6) {
                // Name + Emoji
                HStack(spacing: 6) {
                    Text(agent.emoji)
                        .font(.title2)
                    Text(agent.name.uppercased())
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                // Role
                Text(agent.role)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)

                // Status
                HStack(spacing: 6) {
                    StatusIndicator(status: agent.status, size: 10)
                    Text(agent.status.label)
                        .font(.caption)
                        .foregroundColor(agent.status.color)
                        .fontWeight(.medium)
                }

                // Model badge (if set)
                if let modelName = agent.modelName ?? agent.model, !modelName.isEmpty {
                    ModelBadge(modelName: modelName)
                }

                if !agent.isInitialized {
                    Text("Not initialized")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Activity or stats
                if let activity = agent.currentActivity {
                    Text(activity)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(1)
                        .padding(.top, 2)
                } else if agent.totalTokens > 0 {
                    Text("\(agent.totalTokens.compactTokens) tokens · \(agent.sessionCount) sessions")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.darkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isHovered ? agent.brandColor.opacity(0.4) : Theme.darkBorder.opacity(0.5),
                            lineWidth: 1
                        )
                )
        )
        .shadow(
            color: isHovered ? agent.brandColor.opacity(0.15) : .clear,
            radius: 16
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay(alignment: .topTrailing) {
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.jarvisBlue)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .padding(8)
                .opacity(0.95)
            }
        }
    }
}
