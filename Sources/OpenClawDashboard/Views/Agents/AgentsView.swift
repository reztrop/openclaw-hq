import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ConnectionBanner()
                controlsBar

                ZStack {
                    // Dot-grid canvas background
                    Canvas { context, size in
                        let spacing: CGFloat = 24
                        let dotRadius: CGFloat = 1.0
                        let cols = Int(size.width / spacing) + 1
                        let rows = Int(size.height / spacing) + 1
                        for row in 0..<rows {
                            for col in 0..<cols {
                                let x = CGFloat(col) * spacing
                                let y = CGFloat(row) * spacing
                                let rect = CGRect(
                                    x: x - dotRadius,
                                    y: y - dotRadius,
                                    width: dotRadius * 2,
                                    height: dotRadius * 2
                                )
                                context.fill(
                                    Path(ellipseIn: rect),
                                    with: .color(Theme.neonCyan.opacity(0.12))
                                )
                            }
                        }
                    }
                    .allowsHitTesting(false)

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(agentsVM.agents) { agent in
                            AgentCard(agent: agent)
                                .onTapGesture {
                                    agentsVM.selectedAgent = agent
                                }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Theme.darkBackground)
        .sheet(item: $agentsVM.selectedAgent) { agent in
            AgentDetailView(agent: agent)
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 12) {
            // Header label
            Text("[ AGENT_ROSTER ]")
                .font(Theme.headerFont)
                .foregroundColor(Theme.neonCyan)
                .shadow(color: Theme.neonCyan.opacity(0.5), radius: 6, x: 0, y: 0)

            Spacer()

            // Refresh button
            Button {
                Task { await agentsVM.refreshAgents() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                    Text("REFRESH")
                        .font(Theme.terminalFont)
                }
            }
            .buttonStyle(HQButtonStyle(variant: .glow))
            .disabled(agentsVM.isRefreshing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.darkBackground)
    }
}
