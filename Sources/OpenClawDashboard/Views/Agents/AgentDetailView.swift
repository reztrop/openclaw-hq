import SwiftUI

struct AgentDetailView: View {
    let agent: Agent
    @EnvironmentObject var gatewayService: GatewayService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = 0

    var body: some View {
        HQModalChrome {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    // Agent identity
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(agent.emoji)
                                .font(.title2)
                            Text(agent.name.uppercased())
                                .font(Theme.headerFont)
                                .fontWeight(.bold)
                                .foregroundColor(agent.brandColor)
                                .shadow(color: agent.brandColor.opacity(0.6), radius: 6, x: 0, y: 0)
                                .glitchText(color: agent.brandColor)
                        }
                        // Status pill
                        HStack(spacing: 6) {
                            if agent.status.isActive {
                                Text("◉ ONLINE")
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(Theme.statusOnline)
                                    .shadow(color: Theme.statusOnline.opacity(0.6), radius: 4, x: 0, y: 0)
                            } else {
                                Text("◌ OFFLINE")
                                    .font(Theme.terminalFontSM)
                                    .foregroundColor(Theme.statusOffline)
                            }
                        }
                    }

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.darkSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Theme.darkBorder, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Theme.darkSurface)

                // Neon divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [agent.brandColor.opacity(0.6), Theme.neonCyan.opacity(0.3), agent.brandColor.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .shadow(color: agent.brandColor.opacity(0.4), radius: 4, x: 0, y: 0)

                // Tab strip — only shown when Command tab is available
                if agent.status.isActive {
                    HStack(spacing: 0) {
                        tabButton(title: "INFO", tag: 0)
                        tabButton(title: "COMMAND", tag: 1)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .background(Theme.darkSurface)
                } else {
                    HStack {
                        Text("// AGENT_INFO")
                            .font(Theme.subheaderFont)
                            .foregroundColor(Theme.textMuted)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        Spacer()
                    }
                    .background(Theme.darkSurface)
                }

                // Bottom divider under tabs
                Rectangle()
                    .fill(Theme.darkBorder.opacity(0.5))
                    .frame(height: 1)

                // Content
                if selectedSection == 0 {
                    infoSection
                } else {
                    AgentCommandView(agent: agent, gatewayService: gatewayService)
                }
            }
            .frame(width: 680, height: 780)
        }
    }

    // MARK: - Custom Tab Button

    @ViewBuilder
    private func tabButton(title: String, tag: Int) -> some View {
        let isActive = selectedSection == tag
        Button {
            selectedSection = tag
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(Theme.terminalFont)
                    .foregroundColor(isActive ? Theme.neonCyan : Theme.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .shadow(
                        color: isActive ? Theme.neonCyan.opacity(0.6) : .clear,
                        radius: 4, x: 0, y: 0
                    )

                // Neon underline on active
                Rectangle()
                    .fill(isActive ? Theme.neonCyan : Color.clear)
                    .frame(height: 2)
                    .shadow(
                        color: isActive ? Theme.neonCyan.opacity(0.8) : .clear,
                        radius: 4, x: 0, y: 0
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selectedSection)
    }

    // MARK: - Info Section

    private var infoSection: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Large Avatar
                AgentAvatar(
                    agentName: agent.name,
                    isActive: agent.status.isActive,
                    size: 200
                )

                // Role
                Text(agent.role)
                    .font(Theme.subheaderFont)
                    .foregroundColor(Theme.textSecondary)

                // Activity
                if let activity = agent.currentActivity {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(Theme.statusBusy)
                        Text(activity)
                            .font(Theme.terminalFont)
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Theme.darkAccent)
                    .cornerRadius(8)
                }

                // Stats Grid using NeonBorderPanel cells
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 16) {
                    statCard(title: "TOTAL_TOKENS", value: agent.totalTokens.formattedTokens, icon: "number")
                    statCard(title: "SESSIONS", value: "\(agent.sessionCount)", icon: "bubble.left.and.bubble.right")
                    statCard(title: "STATUS", value: agent.status.label.uppercased(), icon: "circle.fill", color: agent.status.color)
                    statCard(title: "LAST_SEEN", value: agent.lastSeen?.relativeString ?? "—", icon: "clock")
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color? = nil) -> some View {
        NeonBorderPanel(color: agent.brandColor, cornerRadius: 12, lineWidth: 1) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color ?? agent.brandColor)
                    .shadow(color: (color ?? agent.brandColor).opacity(0.5), radius: 4, x: 0, y: 0)

                Text(value)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(.white)

                Text(title)
                    .terminalLabel(color: Theme.textMetadata)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }
}
