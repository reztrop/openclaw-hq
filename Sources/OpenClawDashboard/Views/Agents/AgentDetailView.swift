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
                HStack {
                    // Agent identity
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(agent.emoji)
                            Text(agent.name)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        HStack(spacing: 4) {
                            StatusIndicator(status: agent.status, size: 8)
                            Text(agent.status.label)
                                .font(.caption)
                                .foregroundColor(agent.status.color)
                        }
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                // Tab picker (only shown when Command tab is available)
                if agent.status.isActive {
                    Picker("", selection: $selectedSection) {
                        Text("Info").tag(0)
                        Text("Command").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                } else {
                    Text("Agent Info")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                }

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
                    .font(.title3)
                    .foregroundColor(Theme.textSecondary)

                // Activity
                if let activity = agent.currentActivity {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(Theme.statusBusy)
                        Text(activity)
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Theme.darkAccent)
                    .cornerRadius(8)
                }

                // Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 16) {
                    statCard(title: "Total Tokens", value: agent.totalTokens.formattedTokens, icon: "number")
                    statCard(title: "Sessions", value: "\(agent.sessionCount)", icon: "bubble.left.and.bubble.right")
                    statCard(title: "Status", value: agent.status.label, icon: "circle.fill", color: agent.status.color)
                    statCard(title: "Last Seen", value: agent.lastSeen?.relativeString ?? "—", icon: "clock")
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color ?? agent.brandColor)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.darkSurface)
        .cornerRadius(12)
    }
}
