import SwiftUI

struct AgentCard: View {
    let agent: Agent
    var onEdit: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var borderPulse = false

    private var brandColor: Color { agent.brandColor }

    var body: some View {
        VStack(spacing: 0) {
            // Top brand stripe
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [brandColor.opacity(0.9), brandColor.opacity(0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)

            VStack(spacing: 12) {
                // Avatar with neon ring
                ZStack {
                    if agent.status.isActive && !reduceMotion {
                        Circle()
                            .stroke(brandColor.opacity(borderPulse ? 0.6 : 0.2), lineWidth: 2)
                            .frame(width: 192, height: 192)
                            .blur(radius: 3)
                    }
                    AgentAvatar(
                        agentName: agent.name,
                        isActive: agent.status.isActive,
                        size: 180
                    )
                }
                .shadow(color: agent.status.isActive ? brandColor.opacity(isHovered ? 0.5 : 0.3) : .clear,
                        radius: isHovered ? 24 : 16)

                // Info section
                VStack(spacing: 6) {
                    // Name + Emoji
                    HStack(spacing: 6) {
                        Text(agent.emoji)
                            .font(.title2)
                        Text(agent.name.uppercased())
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundColor(.white)
                            .glitchText(color: brandColor)
                    }

                    // Role — terminal style
                    Text("// \(agent.role)")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(Theme.textMuted)
                        .tracking(0.5)

                    // Status line
                    HStack(spacing: 5) {
                        Text(agent.status.isActive ? "◉" : "◌")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(agent.status.color)
                        Text(agent.status.label.uppercased())
                            .font(Theme.terminalFontSM)
                            .foregroundColor(agent.status.color)
                            .tracking(1.5)
                    }

                    // Model badge
                    if let modelName = agent.modelName ?? agent.model, !modelName.isEmpty {
                        ModelBadge(modelName: modelName)
                    }

                    if !agent.isInitialized {
                        Text("[UNINITIALIZED]")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.glitchAmber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.glitchAmber.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    // Activity or stats
                    if let activity = agent.currentActivity {
                        Text("> \(activity)")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.terminalGreen)
                            .lineLimit(1)
                            .padding(.top, 2)
                    } else if agent.totalTokens > 0 {
                        Text("\(agent.totalTokens.compactTokens) TKN · \(agent.sessionCount) SES")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted)
                            .tracking(0.5)
                            .padding(.top, 2)
                    }
                }
                .padding(.bottom, 4)
            }
            .padding(16)

            // Bottom brand bar
            Rectangle()
                .fill(Theme.darkBackground.opacity(0.6))
                .frame(height: 24)
                .overlay {
                    Text(Theme.agentRole(for: agent.name).uppercased())
                        .font(Theme.terminalFontSM)
                        .foregroundColor(brandColor.opacity(0.7))
                        .tracking(1.2)
                }
        }
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.darkSurface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isHovered ? brandColor.opacity(0.7) : brandColor.opacity(borderPulse ? 0.4 : 0.2),
                            lineWidth: isHovered ? 1.5 : 1
                        )
                )
        )
        .shadow(color: isHovered ? brandColor.opacity(0.25) : brandColor.opacity(0.08), radius: isHovered ? 20 : 8)
        .overlay(alignment: .topTrailing) {
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(brandColor)
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                borderPulse = true
            }
        }
    }
}
