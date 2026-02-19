import SwiftUI

@main
struct OpenClawDashboardApp: App {
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup(Constants.appName) {
            ContentView()
                .environmentObject(appViewModel)
                .environmentObject(appViewModel.settingsService)
                .environmentObject(appViewModel.gatewayService)
                .environmentObject(appViewModel.taskService)
                .environmentObject(appViewModel.agentsViewModel)
                .environmentObject(appViewModel.projectsViewModel)
                .environmentObject(appViewModel.tasksViewModel)
                .environmentObject(appViewModel.usageViewModel)
                .environmentObject(appViewModel.gatewayStatusViewModel)
                .environmentObject(appViewModel.activityLogViewModel)
                .frame(
                    minWidth: 1000, idealWidth: Constants.windowWidth,
                    minHeight: 600, idealHeight: Constants.windowHeight
                )
                .background(Theme.darkBackground)
                .preferredColorScheme(.dark)
                .onAppear {
                    AvatarService.shared.preloadAllAvatars()
                }
        }
        .defaultSize(width: Constants.windowWidth, height: Constants.windowHeight)
        .commands {
            // View menu — tab switching
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Agents") { appViewModel.selectedTab = .agents }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Chat") { appViewModel.selectedTab = .chat }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Projects") { appViewModel.selectedTab = .projects }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Tasks") { appViewModel.selectedTab = .tasks }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Usage") { appViewModel.selectedTab = .usage }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Activity") { appViewModel.selectedTab = .activity }
                    .keyboardShortcut("6", modifiers: .command)
            }

            // File menu — new task
            CommandGroup(after: .newItem) {
                Button("New Task") {
                    appViewModel.selectedTab = .tasks
                    appViewModel.tasksViewModel.startNewTask()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // Refresh
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task {
                        switch appViewModel.selectedTab {
                        case .agents:
                            await appViewModel.agentsViewModel.refreshAgents()
                        case .chat:
                            await appViewModel.agentsViewModel.refreshAgents()
                            await appViewModel.chatViewModel.refresh(agentIds: appViewModel.agentsViewModel.agents.map { $0.id })
                        case .usage:
                            await appViewModel.usageViewModel.fetchUsageData()
                        case .activity, .tasks, .settings, .projects:
                            break
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appViewModel.settingsService)
                .environmentObject(appViewModel.gatewayService)
                .preferredColorScheme(.dark)
        }
    }
}
