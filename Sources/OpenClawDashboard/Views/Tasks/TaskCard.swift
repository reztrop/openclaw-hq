import SwiftUI

struct TaskCard: View {
    let task: TaskItem
    let onView: (() -> Void)?
    let showPausedOverlay: Bool
    let showVerifiedOverlay: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    /// Priority monospaced glyph
    private var priorityGlyph: String {
        switch task.priority {
        case .urgent: return "!!"
        case .high:   return "!"
        case .medium: return "-"
        case .low:    return "·"
        }
    }

    var body: some View {
        NeonBorderPanel(
            color: isFocused ? task.priority.color : task.priority.color.opacity(0.55),
            cornerRadius: 10,
            surface: isFocused ? Theme.darkSurface.opacity(0.9) : Theme.darkAccent,
            lineWidth: isFocused ? 1.5 : 1
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Priority bar
                HStack(spacing: 6) {
                    // Priority glyph in monospaced colored text
                    Text(priorityGlyph)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundColor(task.priority.color)
                        .frame(width: 16, alignment: .leading)

                    Text(task.priority.label.uppercased())
                        .font(Theme.terminalFontSM)
                        .foregroundColor(task.priority.color)
                        .tracking(1)

                    Spacer()

                    if let scheduled = task.scheduledFor {
                        Text(scheduled.relativeString)
                            .font(Theme.terminalFontSM)
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

                // Title in monospaced full brightness
                Text(task.title)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)

                // Description preview
                if let desc = task.description, !desc.isEmpty {
                    Text(desc.truncated(to: 80))
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                }

                // Evidence lines prefixed with "// " in muted color
                if let evidence = task.lastEvidence, !evidence.isEmpty {
                    Text("// \(evidence.truncated(to: 96))")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                        .lineLimit(2)
                }

                // Footer: Agent "@name" + time
                HStack(spacing: 6) {
                    if let projectName = task.projectName, !projectName.isEmpty {
                        Text(projectName)
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Color(hex: task.projectColorHex ?? "#9CA3AF"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: task.projectColorHex ?? "#9CA3AF").opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if let agentName = task.assignedAgent {
                        AgentAvatarSmall(agentName: agentName, size: 18)
                        // "@agentname" format in agent brand color
                        Text("@\(agentName.lowercased())")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Theme.agentColor(for: agentName))
                    }
                    Spacer()
                    Text((task.lastEvidenceAt ?? task.updatedAt).relativeString)
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMetadata)
                }
            }
            .padding(12)
        }
        .shadow(color: isFocused ? task.priority.color.opacity(0.3) : .clear, radius: 8, x: 0, y: 0)
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
                        .fill(Color.black.opacity(0.55))
                    VStack(spacing: 8) {
                        if showPausedOverlay {
                            // Neon-bordered terminal stamp
                            NeonBorderPanel(color: Theme.glitchAmber, cornerRadius: 6, surface: Theme.glitchAmber.opacity(0.1), lineWidth: 1.5) {
                                Text("⏸ PAUSED")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .foregroundColor(Theme.glitchAmber)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                            }
                        }
                        if showVerifiedOverlay {
                            NeonBorderPanel(color: Theme.statusOnline, cornerRadius: 6, surface: Theme.statusOnline.opacity(0.1), lineWidth: 1.5) {
                                Text("✓ VERIFIED")
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .foregroundColor(Theme.statusOnline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                            }
                        }
                    }
                }
            }
        }
    }
}
