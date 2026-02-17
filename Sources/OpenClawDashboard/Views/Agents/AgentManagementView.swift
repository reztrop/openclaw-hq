import SwiftUI

struct AgentManagementView: View {
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    @State private var showAddSheet = false
    @State private var addMode: AddAgentMode = .create
    @State private var agentToEdit: Agent?
    @State private var agentToDelete: Agent?
    @State private var showDeleteConfirm = false

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ConnectionBanner()

                if agentsVM.agents.isEmpty && !agentsVM.isRefreshing {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(agentsVM.agents) { agent in
                            AgentCard(agent: agent)
                                .onTapGesture {
                                    agentsVM.selectedAgent = agent
                                }
                                .contextMenu {
                                    Button {
                                        agentToEdit = agent
                                    } label: {
                                        Label("Edit Agent", systemImage: "pencil")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        agentToDelete = agent
                                        showDeleteConfirm = true
                                    } label: {
                                        Label(
                                            agent.isDefaultAgent ? "Cannot Delete Main Agent" : "Delete Agent",
                                            systemImage: "trash"
                                        )
                                    }
                                    .disabled(agent.isDefaultAgent)
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
                .environmentObject(agentsVM)
                .environmentObject(gatewayService)
        }
        .sheet(isPresented: $showAddSheet) {
            AddAgentView(initialMode: addMode)
                .environmentObject(agentsVM)
                .environmentObject(gatewayService)
        }
        .sheet(item: $agentToEdit) { agent in
            EditAgentView(agent: agent)
                .environmentObject(agentsVM)
                .environmentObject(gatewayService)
        }
        .sheet(isPresented: $showDeleteConfirm) {
            if let agent = agentToDelete {
                DeleteAgentConfirmView(agent: agent) {
                    Task {
                        try? await agentsVM.deleteAgent(agentId: agent.id)
                    }
                }
                .environmentObject(agentsVM)
                .environmentObject(gatewayService)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Scan button
                Button {
                    addMode = .scan
                    showAddSheet = true
                } label: {
                    Label("Scan for Missing", systemImage: "arrow.clockwise.circle")
                }
                .disabled(!gatewayService.isConnected)
                .help("Scan gateway for agents not shown in dashboard")

                // Add button
                Button {
                    addMode = .create
                    showAddSheet = true
                } label: {
                    Label("Add Agent", systemImage: "plus.circle.fill")
                }
                .disabled(!gatewayService.isConnected)
                .help("Create a new agent")

                // Refresh button
                Button {
                    Task { await agentsVM.refreshAgents() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(agentsVM.isRefreshing)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)

            Text("No Agents Found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Connect to your gateway and click + to add your first agent, or scan to discover existing ones.")
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: 360)

            HStack(spacing: 12) {
                Button {
                    addMode = .scan
                    showAddSheet = true
                } label: {
                    Label("Scan for Agents", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!gatewayService.isConnected)

                Button {
                    addMode = .create
                    showAddSheet = true
                } label: {
                    Label("Create Agent", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.jarvisBlue)
                .disabled(!gatewayService.isConnected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }
}
