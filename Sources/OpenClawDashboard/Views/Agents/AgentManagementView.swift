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
                controlsBar

                if agentsVM.agents.isEmpty && !agentsVM.isRefreshing {
                    emptyState
                } else {
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
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 16) {
                        // Terminal loading screen style
                        Text("// INSTALLING_UPDATE")
                            .font(Theme.headerFont)
                            .foregroundColor(Theme.neonCyan)
                            .shadow(color: Theme.neonCyan.opacity(0.6), radius: 8, x: 0, y: 0)
                            .crtFlicker()

                        ProgressView()
                            .tint(Theme.neonCyan)
                            .scaleEffect(1.1)

                        Text("Applying patch. OpenClaw HQ will relaunch when complete.")
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.darkSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.neonCyan.opacity(0.4), lineWidth: 1)
                            )
                            .shadow(color: Theme.neonCyan.opacity(0.2), radius: 16, x: 0, y: 0)
                    )
                }
            }
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

            Button {
                addMode = .create
                showAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("ADD_UNIT")
                        .font(Theme.terminalFont)
                }
            }
            .buttonStyle(HQButtonStyle(variant: .glow))
            .disabled(!gatewayService.isConnected)
            .help("Create a new agent")

            Button {
                Task { await checkForUpdates() }
            } label: {
                HStack(spacing: 6) {
                    if isCheckingForUpdates || isInstallingUpdate {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.neonCyan)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(isCheckingForUpdates || isInstallingUpdate ? "CHECKING..." : "CHECK_UPDATES")
                        .font(Theme.terminalFont)
                }
            }
            .buttonStyle(HQButtonStyle(variant: .secondary))
            .disabled(isCheckingForUpdates || isInstallingUpdate)
            .help("Check GitHub for newer OpenClaw HQ releases")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.darkBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("// NO_AGENTS_FOUND")
                .font(Theme.headerFont)
                .foregroundColor(Theme.neonCyan.opacity(0.7))
                .padding(.top, 48)

            Text("Connect to your gateway and add your first agent, or scan to discover existing ones.")
                .font(Theme.terminalFont)
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button {
                    addMode = .create
                    showAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("CREATE_AGENT")
                            .font(Theme.terminalFont)
                    }
                }
                .buttonStyle(HQButtonStyle(variant: .glow))

                Button {
                    addMode = .scan
                    showAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("SCAN_AGENTS")
                            .font(Theme.terminalFont)
                    }
                }
                .buttonStyle(HQButtonStyle(variant: .secondary))
            }
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .disabled(!gatewayService.isConnected)
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
