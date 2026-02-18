import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var gatewayStatusVM: GatewayStatusViewModel
    @State private var showHealthPopover = false

    var body: some View {
        ZStack {
            Theme.darkBackground.ignoresSafeArea()

            if appViewModel.showOnboarding {
                // First-run onboarding wizard shown as a full window overlay
                OnboardingView()
                    .environmentObject(appViewModel)
            } else if appViewModel.isLoading {
                LoadingView()
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailView
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App title header
            sidebarHeader

            Divider().background(Theme.darkBorder)

            // Tab navigation list — takes all remaining vertical space
            List(AppTab.allCases, id: \.self, selection: $appViewModel.selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .font(.headline)
                    .foregroundColor(appViewModel.selectedTab == tab ? .white : Theme.textSecondary)
                    .padding(.vertical, 6)
            }
            .listStyle(.sidebar)

            // API Connections toggle panel — passed settingsService directly
            // to avoid environment object resolution issues inside NavigationSplitView
            ProviderSettingsView(settingsService: appViewModel.settingsService)

            // Connection status + settings gear
            connectionStatus
        }
        .frame(minWidth: 180)
    }

    private var sidebarHeader: some View {
        VStack(spacing: 4) {
            Text(Constants.appName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("Agent Dashboard")
                .font(.caption)
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.darkBackground)
    }

    private var connectionStatus: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(appViewModel.gatewayService.isConnected ? Theme.statusOnline : Theme.statusOffline)
                    .frame(width: 8, height: 8)
                Text(appViewModel.gatewayService.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                Spacer()
                SettingsLink {
                    Image(systemName: "gear")
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }

            if appViewModel.gatewayService.isConnected, let health = gatewayStatusVM.health {
                HStack(spacing: 12) {
                    Label("\(health.activeRuns)", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(health.activeRuns > 0 ? Theme.statusBusy : Theme.textMuted)
                    Label(health.uptimeString, systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                }
                .onTapGesture { showHealthPopover.toggle() }
                .popover(isPresented: $showHealthPopover) {
                    healthPopoverContent(health)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func healthPopoverContent(_ health: GatewayHealth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gateway Status")
                .font(.headline)
                .foregroundColor(.white)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Status").foregroundColor(Theme.textMuted).font(.caption)
                    Text(health.isHealthy ? "Healthy" : "Degraded")
                        .foregroundColor(health.isHealthy ? Theme.statusOnline : Theme.statusOffline)
                        .font(.caption)
                }
                GridRow {
                    Text("Uptime").foregroundColor(Theme.textMuted).font(.caption)
                    Text(health.uptimeString).foregroundColor(.white).font(.caption)
                }
                GridRow {
                    Text("Active Runs").foregroundColor(Theme.textMuted).font(.caption)
                    Text("\(health.activeRuns)").foregroundColor(.white).font(.caption)
                }
                GridRow {
                    Text("Devices").foregroundColor(Theme.textMuted).font(.caption)
                    Text("\(health.connectedDevices)").foregroundColor(.white).font(.caption)
                }
                if let model = health.model {
                    GridRow {
                        Text("Model").foregroundColor(Theme.textMuted).font(.caption)
                        Text(model).foregroundColor(.white).font(.caption)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 250)
        .background(Theme.darkSurface)
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch appViewModel.selectedTab {
        case .agents:
            AgentManagementView()
                .environmentObject(appViewModel.agentsViewModel)
                .environmentObject(appViewModel.gatewayService)
        case .chat:
            ChatView(chatViewModel: appViewModel.chatViewModel)
                .environmentObject(appViewModel)
                .environmentObject(appViewModel.agentsViewModel)
        case .tasks:
            TasksView()
        case .usage:
            UsageView()
        case .activity:
            ActivityLogView()
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @EnvironmentObject var settingsService: SettingsService

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.jarvisBlue)
            Text("Connecting to OpenClaw Gateway...")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Text(settingsService.settings.gatewayURL)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .monospaced()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.darkBackground)
    }
}
