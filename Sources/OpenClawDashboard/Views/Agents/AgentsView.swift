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
        .background(Theme.darkBackground)
        .sheet(item: $agentsVM.selectedAgent) { agent in
            AgentDetailView(agent: agent)
        }
    }

    private var controlsBar: some View {
        HStack {
            Button {
                Task { await agentsVM.refreshAgents() }
            } label: {
                Label("Refresh Agents", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(agentsVM.isRefreshing)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}
