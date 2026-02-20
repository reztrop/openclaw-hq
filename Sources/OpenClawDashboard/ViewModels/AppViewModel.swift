import SwiftUI
import Combine

enum AppTab: String, CaseIterable {
    case agents = "Agents"
    case chat = "Chat"
    case projects = "Projects"
    case tasks = "Tasks"
    case skills = "Skills"
    case usage = "Usage"
    case activity = "Activity"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .agents:   return "cpu"
        case .chat:     return "bubble.left.and.bubble.right"
        case .projects: return "square.stack.3d.up"
        case .tasks:    return "checklist"
        case .skills:   return "wand.and.stars"
        case .usage:    return "chart.bar"
        case .activity: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
class AppViewModel: ObservableObject {
    @Published var selectedTab: AppTab = .agents
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var showOnboarding: Bool = false
    @Published var isMainSidebarCollapsed: Bool = false
    @Published var isCompactWindow: Bool = false

    let settingsService = SettingsService()
    let gatewayService = GatewayService()
    let taskService = TaskService()
    lazy var agentsViewModel = AgentsViewModel(gatewayService: gatewayService, settingsService: settingsService, taskService: taskService)
    lazy var chatViewModel = ChatViewModel(gatewayService: gatewayService, settingsService: settingsService)
    lazy var projectsViewModel = ProjectsViewModel(gatewayService: gatewayService, taskService: taskService)
    lazy var tasksViewModel = TasksViewModel(taskService: taskService)
    lazy var skillsViewModel = SkillsViewModel()
    lazy var usageViewModel = UsageViewModel(gatewayService: gatewayService)
    lazy var gatewayStatusViewModel = GatewayStatusViewModel(gatewayService: gatewayService)
    lazy var activityLogViewModel = ActivityLogViewModel(gatewayService: gatewayService)
    private var notificationService: NotificationService?

    private var cancellables = Set<AnyCancellable>()

    init() {
        chatViewModel.onProjectPlanningStarted = { [weak self] sessionKey, userPrompt in
            guard let self else { return }
            self.projectsViewModel.registerProjectPlanningStarted(conversationId: sessionKey, userPrompt: userPrompt)
        }
        chatViewModel.onProjectScopeReady = { [weak self] sessionKey, assistantResponse in
            guard let self else { return }
            self.projectsViewModel.registerProjectScopeReady(conversationId: sessionKey, assistantResponse: assistantResponse)
        }
        chatViewModel.onProjectChatAssistantMessage = { [weak self] sessionKey, message in
            guard let self else { return }
            self.projectsViewModel.handleProjectChatAssistantMessage(conversationId: sessionKey, message: message)
        }
        chatViewModel.onProjectChatUserMessage = { [weak self] sessionKey, message in
            guard let self else { return }
            self.projectsViewModel.handleProjectChatUserMessage(conversationId: sessionKey, message: message)
        }
        tasksViewModel.onTaskMovedToDone = { [weak self] task in
            guard let self else { return }
            self.projectsViewModel.handleTaskMovedToDone(task)
        }
        tasksViewModel.onTaskMovedToInProgress = { [weak self] task in
            guard let self else { return }
            Task { [weak self] in
                await self?.startImplementation(for: task)
            }
        }

        // Set up notifications
        notificationService = NotificationService(settingsService: settingsService, gatewayService: gatewayService)
        notificationService?.requestPermission()

        // Monitor gateway connection
        gatewayService.$connectionState
            .receive(on: DispatchQueue.main)
            .map { $0.isConnected }
            .removeDuplicates()
            .sink { [weak self] connected in
                if connected {
                    self?.isLoading = false
                    Task { [weak self] in
                        await self?.initialFetch()
                    }
                }
            }
            .store(in: &cancellables)

        gatewayService.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error
            }
            .store(in: &cancellables)

        // Check if onboarding is needed
        if !settingsService.settings.onboardingComplete {
            showOnboarding = true
            isLoading = false
        } else {
            // Normal startup: connect gateway using saved settings
            let s = settingsService.settings
            gatewayService.connect(host: s.gatewayHost, port: s.gatewayPort, token: s.authToken)

            // Stop loading after timeout even if not connected
            Task {
                try? await Task.sleep(for: .seconds(3))
                if isLoading {
                    isLoading = false
                }
            }
        }
    }

    /// Called when the onboarding wizard completes successfully
    func onboardingCompleted() {
        showOnboarding = false
        isLoading = true

        // Connect to gateway with freshly saved settings
        let s = settingsService.settings
        gatewayService.connect(host: s.gatewayHost, port: s.gatewayPort, token: s.authToken)

        // Timeout fallback
        Task {
            try? await Task.sleep(for: .seconds(5))
            if isLoading {
                isLoading = false
            }
        }
    }

    private func initialFetch() async {
        await agentsViewModel.refreshAgents()
        await skillsViewModel.refreshSkills()
        await projectsViewModel.reconcilePendingPlanningFromChatHistory()
    }

    private func startImplementation(for task: TaskItem) async {
        guard !taskService.isExecutionPaused else { return }
        guard task.status == .inProgress else { return }
        guard let agent = task.assignedAgent?.trimmingCharacters(in: .whitespacesAndNewlines), !agent.isEmpty else { return }

        let projectLine: String = {
            if let projectName = task.projectName, !projectName.isEmpty {
                return "Project: \(projectName)"
            }
            return "Project: Unspecified"
        }()

        let description = task.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailLine = (description?.isEmpty == false) ? "Task details: \(description!)" : "Task details: none"

        let kickoff = """
        [task-start]
        \(projectLine)
        Task ID: \(task.id.uuidString)
        Task: \(task.title)
        \(detailLine)

        Begin implementation immediately.
        Before doing new work, first check whether this task already has partial progress and continue from that state.
        Keep updates concise and execution-focused.
        """

        _ = try? await gatewayService.sendAgentMessage(
            agentId: agent.lowercased(),
            message: kickoff,
            sessionKey: nil,
            thinkingEnabled: true
        )
    }
}
