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
    private var lastInterventionFingerprint: String?
    private var lastInterventionAt: Date?
    private let interventionCooldown: TimeInterval = 30 * 60

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

        taskService.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                guard let self else { return }
                Task { [weak self] in
                    await self?.evaluateRecurringIssueIntervention(tasks: tasks)
                }
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

    private func evaluateRecurringIssueIntervention(tasks: [TaskItem]) async {
        guard !taskService.isExecutionPaused else { return }

        let active = tasks.filter { !$0.isArchived && ($0.status == .queued || $0.status == .inProgress) }
        guard !active.isEmpty else { return }

        var issueCounts: [String: Int] = [:]
        var affectedTasks: [TaskItem] = []
        for task in active {
            guard let evidence = task.lastEvidence?.lowercased(), !evidence.isEmpty else { continue }
            let markers = recurringIssueMarkers(in: evidence)
            guard !markers.isEmpty else { continue }
            affectedTasks.append(task)
            for marker in markers {
                issueCounts[marker, default: 0] += 1
            }
        }

        guard !issueCounts.isEmpty else { return }
        let dominant = issueCounts.max(by: { $0.value < $1.value })
        guard let dominantIssue = dominant?.key, let dominantCount = dominant?.value else { return }

        // Trigger only when the same issue repeats across multiple active tasks.
        guard dominantCount >= 3 else { return }

        let fingerprint = "\(dominantIssue)|\(affectedTasks.map { $0.id.uuidString }.sorted().joined(separator: ","))"
        let now = Date()
        if lastInterventionFingerprint == fingerprint,
           let last = lastInterventionAt,
           now.timeIntervalSince(last) < interventionCooldown {
            return
        }

        taskService.setExecutionPaused(true)
        let reportPath = writeInterventionReport(
            dominantIssue: dominantIssue,
            issueCounts: issueCounts,
            affectedTasks: affectedTasks
        )
        await notifyJarvisOfIntervention(reportPath: reportPath, dominantIssue: dominantIssue, affectedTasks: affectedTasks)

        lastInterventionFingerprint = fingerprint
        lastInterventionAt = now
        errorMessage = "Recurring issue detected. Tasks paused and Jarvis intervention report generated."
    }

    private func recurringIssueMarkers(in evidence: String) -> [String] {
        var markers: [String] = []
        let map: [String: String] = [
            "rate limited": "rate_limited",
            "too many requests": "rate_limited",
            "status 429": "rate_limited",
            "quota exceeded": "rate_limited",
            "run error: disconnected": "gateway_disconnected",
            "invalid handshake": "gateway_handshake",
            "[task-blocked]": "task_blocked",
            "cannot proceed without": "missing_scope",
            "missing execution artifact": "missing_scope"
        ]
        for (needle, label) in map where evidence.contains(needle) {
            markers.append(label)
        }
        return Array(Set(markers))
    }

    private func writeInterventionReport(dominantIssue: String, issueCounts: [String: Int], affectedTasks: [TaskItem]) -> String {
        let reportsDir = NSString(string: "~/.openclaw/workspace/reports").expandingTildeInPath
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filePath = "\(reportsDir)/jarvis_intervention_\(timestamp).md"

        let issueLines = issueCounts
            .sorted { $0.value > $1.value }
            .map { "- \($0.key): \($0.value)" }
            .joined(separator: "\n")

        let taskLines = affectedTasks
            .sorted { ($0.lastEvidenceAt ?? $0.updatedAt) > ($1.lastEvidenceAt ?? $1.updatedAt) }
            .map { task in
                let agent = task.assignedAgent ?? "Unassigned"
                let status = task.status.columnTitle
                let last = (task.lastEvidenceAt ?? task.updatedAt).shortString
                return "- [\(status)] \(task.title) (Agent: \(agent), Last: \(last), TaskId: \(task.id.uuidString))"
            }
            .joined(separator: "\n")

        let body = """
        # Jarvis Intervention Report

        Generated: \(Date().shortString)
        Dominant Issue: \(dominantIssue)

        ## Issue Frequency
        \(issueLines)

        ## Affected Active Tasks
        \(taskLines)

        ## Automatic Action Taken
        - Execution paused automatically to prevent token burn loop.
        - Jarvis notified to triage and propose fix tasks.
        - Awaiting user/Jarvis intervention before resume.
        """

        do {
            try FileManager.default.createDirectory(atPath: reportsDir, withIntermediateDirectories: true)
            try body.write(toFile: filePath, atomically: true, encoding: .utf8)
            return filePath
        } catch {
            return "Failed to write report: \(error.localizedDescription)"
        }
    }

    private func notifyJarvisOfIntervention(reportPath: String, dominantIssue: String, affectedTasks: [TaskItem]) async {
        let topTasks = affectedTasks.prefix(6).map {
            "- \($0.title) [\($0.status.columnTitle)] (\($0.assignedAgent ?? "Unassigned"))"
        }.joined(separator: "\n")

        let message = """
        [intervention]
        Recurring issue loop detected and execution has been auto-paused.
        Dominant issue: \(dominantIssue)
        Report: \(reportPath)

        Affected tasks:
        \(topTasks)

        Action required:
        1) Identify root cause.
        2) Create/adjust remediation tasks with owners.
        3) Provide a concise recovery plan for user approval before resume.
        """

        _ = try? await gatewayService.sendAgentMessage(
            agentId: "jarvis",
            message: message,
            sessionKey: nil,
            thinkingEnabled: true
        )
    }
}
