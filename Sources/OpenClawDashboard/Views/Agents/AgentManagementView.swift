import SwiftUI

struct AgentManagementView: View {
    @EnvironmentObject var agentsVM: AgentsViewModel
    @EnvironmentObject var gatewayService: GatewayService

    @State private var showAddSheet = false
    @State private var addMode: AddAgentMode = .create
    @State private var agentToEdit: Agent?
    @State private var agentToDelete: Agent?
    @State private var showDeleteConfirm = false
    @State private var isCheckingForUpdates = false
    @State private var isInstallingUpdate = false
    @State private var availableUpdate: AppUpdateService.ReleaseInfo?
    @State private var showUpdateAvailableAlert = false
    @State private var showStatusAlert = false
    @State private var statusAlertTitle = ""
    @State private var statusAlertMessage = ""

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
                            AgentCard(agent: agent) {
                                agentToEdit = agent
                            }
                            .onTapGesture {
                                agentsVM.selectedAgent = agent
                            }
                            .contextMenu {
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
                // Add button
                Button {
                    addMode = .create
                    showAddSheet = true
                } label: {
                    Label("Add Agent", systemImage: "plus.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .disabled(!gatewayService.isConnected)
                .help("Create a new agent")

                Button {
                    Task { await checkForUpdates() }
                } label: {
                    if isCheckingForUpdates || isInstallingUpdate {
                        Label("Checking...", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Check for Updates", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(isCheckingForUpdates || isInstallingUpdate)
                .help("Check GitHub for newer OpenClaw HQ releases")
            }
        }
        .alert("Update Available", isPresented: $showUpdateAvailableAlert) {
            Button("Skip", role: .cancel) {}
            Button("Update") {
                guard let release = availableUpdate else { return }
                Task { await installUpdate(release) }
            }
        } message: {
            if let release = availableUpdate {
                Text("Version \(release.version) is available. Do you want to update OpenClaw HQ now?")
            } else {
                Text("A new version is available.")
            }
        }
        .alert(statusAlertTitle, isPresented: $showStatusAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusAlertMessage)
        }
        .overlay {
            if isInstallingUpdate {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("Installing update...")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("OpenClaw HQ will relaunch when complete.")
                            .foregroundColor(Theme.textMuted)
                            .font(.caption)
                    }
                    .padding(24)
                    .background(Theme.darkSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.darkBorder.opacity(0.5), lineWidth: 1)
                    )
                }
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

    private func checkForUpdates() async {
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let result = try await AppUpdateService.shared.checkForUpdates(currentVersion: currentVersion)

            switch result {
            case .updateAvailable(let release):
                availableUpdate = release
                showUpdateAvailableAlert = true
            case .upToDate(let current, let latest):
                statusAlertTitle = "Up to Date"
                statusAlertMessage = "Installed version \(current) already matches the latest GitHub release (\(latest))."
                showStatusAlert = true
            }
        } catch {
            statusAlertTitle = "Update Check Failed"
            statusAlertMessage = error.localizedDescription
            showStatusAlert = true
        }
    }

    private func installUpdate(_ release: AppUpdateService.ReleaseInfo) async {
        isInstallingUpdate = true
        defer { isInstallingUpdate = false }

        do {
            try await AppUpdateService.shared.installUpdate(release)
        } catch {
            statusAlertTitle = "Update Failed"
            statusAlertMessage = error.localizedDescription
            showStatusAlert = true
        }
    }
}
