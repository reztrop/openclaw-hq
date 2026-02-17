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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await agentsVM.refreshAgents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(agentsVM.isRefreshing)
            }
        }
    }
}
