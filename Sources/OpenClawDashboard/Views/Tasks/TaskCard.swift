import SwiftUI

struct TaskCard: View {
    let task: TaskItem
    let onView: (() -> Void)?
    let showPausedOverlay: Bool
    let showVerifiedOverlay: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
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
                        .foregroundColor(Theme.textMetadata)
                }
                if let onView {
                    Button {
                        onView()
                    } label: {
                        Image(systemName: "eye")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("View task details")
                }
            }

            // Title
            Text(task.title)
                .font(.system(.subheadline, design: .monospaced))
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

            if let evidence = task.lastEvidence, !evidence.isEmpty {
                Text(evidence.truncated(to: 96))
                    .font(.caption2)
                    .foregroundColor(Theme.neonCyan.opacity(0.9))
                    .lineLimit(2)
            }

            // Footer: Agent + time
            HStack(spacing: 6) {
                if let projectName = task.projectName, !projectName.isEmpty {
                    Text(projectName)
                        .font(.caption2)
                        .foregroundColor(Color(hex: task.projectColorHex ?? "#9CA3AF"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: task.projectColorHex ?? "#9CA3AF").opacity(0.12))
                        .clipShape(Capsule())
                }
                if let agentName = task.assignedAgent {
                    AgentAvatarSmall(agentName: agentName, size: 20)
                    Text(agentName)
                        .font(.caption)
                        .foregroundColor(Theme.agentColor(for: agentName))
                }
                Spacer()
                Text((task.lastEvidenceAt ?? task.updatedAt).relativeString)
                    .font(.caption2)
                    .foregroundColor(Theme.textMetadata)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isFocused ? Theme.darkSurface.opacity(0.9) : Theme.darkAccent)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isFocused ? Theme.jarvisBlue.opacity(0.8) : (isHovered ? task.priority.color.opacity(0.45) : Theme.darkBorder.opacity(0.3)),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                )
        )
        .shadow(color: isFocused ? Theme.jarvisBlue.opacity(0.3) : .clear, radius: 8, x: 0, y: 0)
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.02 : 1.0))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
        .focusable(true)
        .focused($isFocused)
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay {
            if showPausedOverlay || showVerifiedOverlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.42))
                    VStack(spacing: 6) {
                        if showPausedOverlay {
                            Text("PAUSED")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.statusOffline.opacity(0.8))
                                .clipShape(Capsule())
                        }
                        if showVerifiedOverlay {
                            Text("VERIFIED")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.statusOnline.opacity(0.85))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
}
