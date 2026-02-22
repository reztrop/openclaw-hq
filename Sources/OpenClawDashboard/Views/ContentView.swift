import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var gatewayStatusVM: GatewayStatusViewModel
    @State private var showHealthPopover = false

    var body: some View {
        ZStack {
            CyberpunkBackdrop()

            if appViewModel.showOnboarding {
                OnboardingView()
                    .environmentObject(appViewModel)
            } else if appViewModel.isLoading {
                LoadingView()
            } else {
                VStack(spacing: 0) {
                    titleBar
                    mainLayout
                }
            }
        }
    }

    // MARK: - Global Title Bar

    private var titleBar: some View {
        HStack(spacing: 0) {
            // Left: app identity
            HStack(spacing: 6) {
                Text("OPENCLAW")
                    .font(.system(.subheadline, design: .monospaced, weight: .black))
                    .foregroundColor(Theme.neonCyan)
                Text("//")
                    .font(.system(.subheadline, design: .monospaced, weight: .light))
                    .foregroundColor(Theme.neonCyan.opacity(0.5))
                Text("HQ")
                    .font(.system(.subheadline, design: .monospaced, weight: .black))
                    .foregroundColor(Theme.neonMagenta)
            }
            .glitchText(color: Theme.neonMagenta)
            .padding(.leading, 16)

            Spacer()

            // Center: current tab
            Text("[ \(appViewModel.selectedTab.rawValue.uppercased()) ]")
                .font(Theme.terminalFont)
                .foregroundColor(Theme.textMetadata)
                .tracking(2)

            Spacer()

            // Right: live clock
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(currentTimeString)
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 32)
        .background(
            ZStack {
                Theme.darkBackground.opacity(0.95)
                Rectangle()
                    .fill(Theme.neonCyan.opacity(0.06))
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.neonCyan.opacity(0.3))
                .frame(height: 1)
        }
    }

    private var currentTimeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm // yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - Main Layout

    private var mainLayout: some View {
        GeometryReader { geo in
            HSplitView {
                if !appViewModel.isMainSidebarCollapsed {
                    sidebarColumn
                        .frame(minWidth: 180, idealWidth: 210, maxWidth: 280)
                }

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .crtFlicker()
            }
            .onAppear { updateWindowLayoutFlags(for: geo.size.width) }
            .onChange(of: geo.size.width) { _, newWidth in
                updateWindowLayoutFlags(for: newWidth)
            }
            .onChange(of: appViewModel.selectedTab) { _, tab in
                if tab != .chat { appViewModel.isMainSidebarCollapsed = false }
            }
        }
    }

    // MARK: - Sidebar Column

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            sidebarHeader

            // Neon divider
            Rectangle()
                .fill(Theme.neonCyan.opacity(0.25))
                .frame(height: 1)

            // Tab list
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        terminalTabRow(tab)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            connectionStatus
        }
        .background(
            ZStack {
                Theme.darkSurface.opacity(0.85)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.08)
            }
        )
        .overlay(alignment: .trailing) {
            // Right-edge neon separator
            Rectangle()
                .fill(Theme.neonCyan.opacity(0.3))
                .frame(width: 1)
        }
    }

    // MARK: - Terminal Tab Row

    private func terminalTabRow(_ tab: AppTab) -> some View {
        let isActive = appViewModel.selectedTab == tab

        return Button {
            appViewModel.selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                // Left active stripe
                Rectangle()
                    .fill(isActive ? Theme.neonCyan : Color.clear)
                    .frame(width: 3)
                    .animation(.easeOut(duration: 0.15), value: isActive)

                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isActive ? Theme.neonCyan : Theme.textMuted)
                    .frame(width: 16)

                Text(isActive ? "▶ \(tab.rawValue.uppercased())" : tab.rawValue.uppercased())
                    .font(Theme.terminalFontSM)
                    .foregroundColor(isActive ? Theme.neonCyan : Theme.textMuted)
                    .tracking(0.8)

                Spacer()
            }
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Theme.neonCyan.opacity(0.08) : Color.clear)
            )
            .shadow(color: isActive ? Theme.neonCyan.opacity(0.2) : .clear, radius: 6, x: 0, y: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sidebar Header

    private var sidebarHeader: some View {
        VStack(spacing: 3) {
            Text("┌─ AGENT OS ─┐")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.neonCyan.opacity(0.6))

            Text("OPENCLAW HQ")
                .font(.system(.subheadline, design: .monospaced, weight: .black))
                .foregroundColor(Theme.neonCyan)
                .glitchText(color: Theme.neonMagenta)

            Text("└─────────────┘")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.neonCyan.opacity(0.6))

            Text("// v1.0 · LOFI CYBERNET")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.darkBackground.opacity(0.8))
    }

    // MARK: - Connection Status Footer

    private var connectionStatus: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.darkBorder.opacity(0.5))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                // SYS status line
                HStack(spacing: 6) {
                    StatusIndicator(status: appViewModel.gatewayService.isConnected ? .online : .offline)
                        .frame(width: 8, height: 8)
                    Text(appViewModel.gatewayService.isConnected ? "SYS: ONLINE" : "SYS: OFFLINE")
                        .font(Theme.terminalFontSM)
                        .foregroundColor(appViewModel.gatewayService.isConnected ? Theme.statusOnline : Theme.statusOffline)
                        .tracking(1)
                    Spacer()
                    SettingsLink {
                        Image(systemName: "gear")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                // Gateway address
                Text("GW: 127.0.0.1:18789")
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted.opacity(0.6))

                // Health stats if connected
                if appViewModel.gatewayService.isConnected, let health = gatewayStatusVM.health {
                    HStack(spacing: 10) {
                        Text("RUNS:\(health.activeRuns)")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(health.activeRuns > 0 ? Theme.statusBusy : Theme.textMuted.opacity(0.6))
                        Text("UP:\(health.uptimeString)")
                            .font(Theme.terminalFontSM)
                            .foregroundColor(Theme.textMuted.opacity(0.6))
                    }
                    .onTapGesture { showHealthPopover.toggle() }
                    .popover(isPresented: $showHealthPopover) {
                        healthPopoverContent(health)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func healthPopoverContent(_ health: GatewayHealth) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("// GATEWAY_STATUS")
                .font(Theme.subheaderFont)
                .foregroundColor(Theme.neonCyan)

            Rectangle()
                .fill(Theme.neonCyan.opacity(0.2))
                .frame(height: 1)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("STATUS").terminalLabel()
                    Text(health.isHealthy ? "HEALTHY" : "DEGRADED")
                        .font(Theme.terminalFont)
                        .foregroundColor(health.isHealthy ? Theme.statusOnline : Theme.statusOffline)
                }
                GridRow {
                    Text("UPTIME").terminalLabel()
                    Text(health.uptimeString)
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.textPrimary)
                }
                GridRow {
                    Text("ACTIVE_RUNS").terminalLabel()
                    Text("\(health.activeRuns)")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.textPrimary)
                }
                GridRow {
                    Text("DEVICES").terminalLabel()
                    Text("\(health.connectedDevices)")
                        .font(Theme.terminalFont)
                        .foregroundColor(Theme.textPrimary)
                }
                if let model = health.model {
                    GridRow {
                        Text("MODEL").terminalLabel()
                        Text(model)
                            .font(Theme.terminalFont)
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(Theme.darkSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.neonCyan.opacity(0.3), lineWidth: 1)
        )
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
        case .projects:
            ProjectsView()
                .environmentObject(appViewModel.projectsViewModel)
        case .tasks:
            TasksView()
        case .skills:
            SkillsView()
                .environmentObject(appViewModel.skillsViewModel)
        case .usage:
            UsageView()
        case .activity:
            ActivityLogView()
        case .settings:
            SettingsView()
                .environmentObject(appViewModel.settingsService)
                .environmentObject(appViewModel.gatewayService)
        }
    }

    private func updateWindowLayoutFlags(for width: CGFloat) {
        let state = ContentLayoutPolicy.state(
            for: width,
            selectedTab: appViewModel.selectedTab,
            currentSidebarCollapsed: appViewModel.isMainSidebarCollapsed
        )
        if appViewModel.isCompactWindow != state.isCompactWindow {
            appViewModel.isCompactWindow = state.isCompactWindow
        }
        if appViewModel.isMainSidebarCollapsed != state.isMainSidebarCollapsed {
            appViewModel.isMainSidebarCollapsed = state.isMainSidebarCollapsed
        }
    }
}

struct WindowLayoutState: Equatable {
    let isCompactWindow: Bool
    let isMainSidebarCollapsed: Bool
}

enum ContentLayoutPolicy {
    static let compactThreshold: CGFloat = 1300

    static func state(for width: CGFloat, selectedTab: AppTab, currentSidebarCollapsed: Bool) -> WindowLayoutState {
        let isCompactWindow = width < compactThreshold
        let keepSidebarCollapsed = isCompactWindow && selectedTab == .chat
        return WindowLayoutState(
            isCompactWindow: isCompactWindow,
            isMainSidebarCollapsed: keepSidebarCollapsed ? currentSidebarCollapsed : false
        )
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @EnvironmentObject var settingsService: SettingsService

    var body: some View {
        VStack(spacing: 20) {
            // Pulsing terminal cursor
            Text("█")
                .font(.system(size: 48, design: .monospaced))
                .foregroundColor(Theme.neonCyan)

            VStack(spacing: 8) {
                Text("INITIALIZING OPENCLAW HQ...")
                    .font(Theme.subheaderFont)
                    .foregroundColor(Theme.neonCyan)

                Text("ESTABLISHING NEURAL LINK")
                    .font(Theme.terminalFont)
                    .foregroundColor(Theme.textMuted)

                Text(settingsService.settings.gatewayURL)
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMetadata)
            }

            ProgressView()
                .scaleEffect(0.8)
                .tint(Theme.neonCyan)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.darkBackground)
    }
}
