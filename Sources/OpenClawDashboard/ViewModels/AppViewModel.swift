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

    let settingsService: SettingsService
    let gatewayService: GatewayService
    let taskService: TaskService
    lazy var agentsViewModel = AgentsViewModel(gatewayService: gatewayService, settingsService: settingsService, taskService: taskService)
    lazy var chatViewModel = ChatViewModel(gatewayService: gatewayService, settingsService: settingsService)
    lazy var projectsViewModel = ProjectsViewModel(gatewayService: gatewayService, taskService: taskService)
    lazy var tasksViewModel = TasksViewModel(taskService: taskService)
    lazy var skillsViewModel = SkillsViewModel()
    lazy var usageViewModel = UsageViewModel(gatewayService: gatewayService)
    lazy var gatewayStatusViewModel = GatewayStatusViewModel(gatewayService: gatewayService)
    lazy var activityLogViewModel = ActivityLogViewModel(gatewayService: gatewayService)
    private var notificationService: NotificationService?
    private let taskInterventionService: TaskInterventionService
    private let taskCompactionService: TaskCompactionService
    private var taskExecutionService: TaskExecutionService?
    private let isTaskAutomationEnabled = false

    private var cancellables = Set<AnyCancellable>()

    convenience init() {
        self.init(
            settingsService: SettingsService(),
            gatewayService: GatewayService(),
            taskService: TaskService()
        )
    }

    init(
        settingsService: SettingsService,
        gatewayService: GatewayService,
        taskService: TaskService,
        taskInterventionService: TaskInterventionService? = nil,
        taskCompactionService: TaskCompactionService? = nil,
        taskExecutionService: TaskExecutionService? = nil,
        notificationService: NotificationService? = nil,
        connectGatewayOnInit: Bool = true,
        enableNotifications: Bool = true
    ) {
        self.settingsService = settingsService
        self.gatewayService = gatewayService
        self.taskService = taskService
        self.taskInterventionService = taskInterventionService
            ?? TaskInterventionService(taskService: taskService, gatewayService: gatewayService)
        self.taskCompactionService = taskCompactionService
            ?? TaskCompactionService(taskService: taskService, gatewayService: gatewayService)
        self.notificationService = notificationService
        self.taskExecutionService = taskExecutionService

        if isTaskAutomationEnabled, self.taskExecutionService == nil {
            let onTaskCompleted: (TaskItem) -> Void = { [weak self] task in
                guard let self else { return }
                self.projectsViewModel.handleTaskMovedToDone(task)
            }
            self.taskExecutionService = TaskExecutionService(
                taskService: taskService,
                gatewayService: gatewayService,
                onTaskCompleted: onTaskCompleted
            )
        }

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
        if isTaskAutomationEnabled {
            tasksViewModel.onTaskMovedToDone = { [weak self] task in
                guard let self else { return }
                self.projectsViewModel.handleTaskMovedToDone(task)
            }
            tasksViewModel.onTaskMovedToInProgress = { [weak self] task in
                guard let self else { return }
                self.taskExecutionService?.handleTaskMovedToInProgress(task)
            }
        }

        // Set up notifications
        if enableNotifications {
            if self.notificationService == nil {
                self.notificationService = NotificationService(settingsService: settingsService, gatewayService: gatewayService)
            }
            self.notificationService?.requestPermission()
        }

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

        taskService.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    if let interventionMessage = await self.taskInterventionService.evaluateRecurringIssueIntervention(tasks: tasks) {
                        self.errorMessage = interventionMessage
                        return
                    }
                    if let compactionMessage = await self.taskCompactionService.evaluateScopeCompaction(tasks: tasks) {
                        self.errorMessage = compactionMessage
                    }
                }
            }
            .store(in: &cancellables)

        // Check if onboarding is needed
        if !settingsService.settings.onboardingComplete {
            showOnboarding = true
            isLoading = false
        } else if connectGatewayOnInit {
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
        } else {
            isLoading = false
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

    // recurring-issue intervention delegated directly in task sink
}
