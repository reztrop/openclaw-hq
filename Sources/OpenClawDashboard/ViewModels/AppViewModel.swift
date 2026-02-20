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
    private var activeTaskRuns: Set<UUID> = []
    private var activeAgentRuns: Set<String> = []
    private var taskNextEligibleAt: [UUID: Date] = [:]
    private var verificationEscalationAt: [UUID: Date] = [:]
    private var routedIssueSignatures: Set<String> = []
    private var orchestrationLoopTask: Task<Void, Never>?
    private var isRunningOrchestrationTick = false

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

        gatewayService.agentEventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleTaskExecutionEvent(event)
            }
            .store(in: &cancellables)

        taskService.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.runTaskOrchestrationTick()
                }
            }
            .store(in: &cancellables)

        taskService.$isExecutionPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.runTaskOrchestrationTick()
                }
            }
            .store(in: &cancellables)

        startTaskOrchestrationLoop()

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
        guard isTaskAutomationEnabled else { return }
        guard !taskService.isExecutionPaused else { return }
        guard let current = taskService.tasks.first(where: { $0.id == task.id }) else { return }
        guard current.status == .inProgress, !current.isArchived else { return }
        guard let agent = current.assignedAgent?.trimmingCharacters(in: .whitespacesAndNewlines), !agent.isEmpty else { return }
        let agentToken = agent.lowercased()
        guard !activeTaskRuns.contains(current.id) else { return }
        guard !activeAgentRuns.contains(agentToken) else { return }
        activeTaskRuns.insert(current.id)
        activeAgentRuns.insert(agentToken)

        let sessionKey = current.executionSessionKey?.isEmpty == false
            ? (current.executionSessionKey ?? "")
            : "agent:\(agentToken):task:\(current.id.uuidString.lowercased())"
        taskService.mutateTask(current.id) { mutable in
            mutable.executionSessionKey = sessionKey
        }
        taskService.appendTaskEvidence(current.id, text: "Kickoff sent to \(agent) at \(Date().shortString)")

        let projectLine: String = {
            if let projectName = current.projectName, !projectName.isEmpty {
                return "Project: \(projectName)"
            }
            return "Project: Unspecified"
        }()

        let description = current.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailLine = (description?.isEmpty == false) ? "Task details: \(description!)" : "Task details: none"

        let kickoff = buildKickoffPrompt(for: current, projectLine: projectLine, detailLine: detailLine)

        defer {
            activeTaskRuns.remove(current.id)
            activeAgentRuns.remove(agentToken)
        }

        do {
            let response = try await gatewayService.sendAgentMessage(
                agentId: agentToken,
                message: kickoff,
                sessionKey: sessionKey,
                thinkingEnabled: true
            )
            let finalText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalText.isEmpty {
                taskService.appendTaskEvidence(current.id, text: "Final response:\n\(finalText)")
            } else {
                taskService.appendTaskEvidence(current.id, text: "Run completed with no assistant text.")
            }

            let detectedIssues = extractIssues(from: finalText)
            if !detectedIssues.isEmpty {
                await routeIssuesToJarvisAndCreateFixTasks(sourceTask: current, issues: detectedIssues)
                taskService.appendTaskEvidence(current.id, text: "Routed \(detectedIssues.count) issue(s) to Jarvis and created fix tasks.")
            }

            var outcome = taskOutcome(for: current, from: finalText)
            if !detectedIssues.isEmpty && outcome == .complete {
                outcome = .continueWork
            }
            switch outcome {
            case .complete:
                taskService.moveTask(current.id, to: .done)
                if let doneTask = taskService.tasks.first(where: { $0.id == current.id }) {
                    projectsViewModel.handleTaskMovedToDone(doneTask)
                }
            case .blocked:
                if current.isVerificationTask {
                    await requestJarvisUnblockForVerification(task: current, blockedResponse: finalText)
                    taskService.appendTaskEvidence(current.id, text: "Verification escalation sent to Jarvis.")
                }
                taskService.moveTask(current.id, to: .queued)
                setRetryCooldown(taskId: current.id, seconds: 45)
            case .continueWork:
                taskService.moveTask(current.id, to: .queued)
                setRetryCooldown(taskId: current.id, seconds: 10)
            }
        } catch {
            taskService.appendTaskEvidence(current.id, text: "Run error: \(error.localizedDescription)")
            taskService.moveTask(current.id, to: .queued)
            setRetryCooldown(taskId: current.id, seconds: 20)
        }

        await runTaskOrchestrationTick()
    }

    private func buildKickoffPrompt(for task: TaskItem, projectLine: String, detailLine: String) -> String {
        let markerRules = """
        End with exactly one marker line:
        [task-complete] if done,
        [task-continue] if more work remains,
        [task-blocked] if blocked waiting on a hard dependency.
        """

        if task.isVerificationTask {
            let recentEvidence = String((task.lastEvidence ?? "").suffix(1200))
            let evidenceBlock = recentEvidence.isEmpty ? "Execution evidence on task card: none yet." : "Execution evidence on task card:\n\(recentEvidence)"

            return """
            [task-start]
            \(projectLine)
            Task ID: \(task.id.uuidString)
            Task: \(task.title)
            \(detailLine)

            This is a FINAL VERIFICATION task.
            Review all available artifacts in this workspace plus the task evidence below.
            If Jarvis artifact scope is missing, continue with best-effort verification and include a \"Scope Gaps\" section in your response.
            Do not use [task-blocked] solely because Jarvis scope is missing.
            Use [task-blocked] only for hard external blockers (credentials/tool outage/missing system dependency).

            \(evidenceBlock)

            \(markerRules)
            """
        }

        return """
        [task-start]
        \(projectLine)
        Task ID: \(task.id.uuidString)
        Task: \(task.title)
        \(detailLine)

        Begin implementation immediately.
        Before doing new work, first check whether this task already has partial progress and continue from that state.
        Keep updates concise and execution-focused. Work autonomously to completion.
        \(markerRules)
        """
    }

    private enum TaskOutcome {
        case complete
        case continueWork
        case blocked
    }

    private func taskOutcome(for task: TaskItem, from response: String) -> TaskOutcome {
        let markers = Set(
            response
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { $0 == "[task-complete]" || $0 == "[task-blocked]" || $0 == "[task-continue]" }
        )

        if markers.contains("[task-blocked]") {
            return .blocked
        }
        if markers.contains("[task-complete]") {
            return .complete
        }
        if markers.contains("[task-continue]") {
            return .continueWork
        }

        let lower = response.lowercased()
        if task.isVerificationTask && hasVerificationScopeGap(lower) {
            return .blocked
        }

        return .continueWork
    }

    private func hasVerificationScopeGap(_ lower: String) -> Bool {
        let patterns = [
            "scope gaps",
            "out of scope for current evidence",
            "no implementation/execution artifact",
            "no pr/branch/commit range/files",
            "cannot proceed without jarvis-provided execution artifact scope",
            "missing execution artifact"
        ]
        return patterns.contains { lower.contains($0) }
    }

    private func extractIssues(from response: String) -> [String] {
        let lower = response.lowercased()
        if lower.contains("no fix required") && !containsIssueSignal(lower) {
            return []
        }

        var issues: [String] = []
        for rawLine in response.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let dotRange = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                line.removeSubrange(dotRange)
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let lowered = line.lowercased()
            guard containsIssueSignal(lowered) else { continue }
            guard !isIssueNegated(lowered) else { continue }
            if line.count < 12 { continue }
            issues.append(line)
        }

        if issues.isEmpty && containsIssueSignal(lower) && !isIssueNegated(lower) {
            // Fallback: use compact summary when issues are implied but not bulleted.
            let summary = response
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                issues.append(String(summary.prefix(240)))
            }
        }

        return Array(NSOrderedSet(array: issues)) as? [String] ?? issues
    }

    private func containsIssueSignal(_ text: String) -> Bool {
        let signals = [
            "issue", "bug", "error", "fail", "failing", "regression", "problem",
            "risk", "gap", "missing", "blocked", "constraint", "violation"
        ]
        return signals.contains { text.contains($0) }
    }

    private func isIssueNegated(_ text: String) -> Bool {
        let negations = [
            "no issue", "no issues", "no bug", "no bugs", "no error", "no errors",
            "no regression", "no regressions", "no fix required", "nothing to fix"
        ]
        return negations.contains { text.contains($0) }
    }

    private func routeIssuesToJarvisAndCreateFixTasks(sourceTask: TaskItem, issues: [String]) async {
        let projectName = sourceTask.projectName?.isEmpty == false ? (sourceTask.projectName ?? "Unspecified") : "Unspecified"
        let projectColor = sourceTask.projectColorHex
        let projectId = sourceTask.projectId

        var createdTasks: [TaskItem] = []
        for issue in issues {
            let signature = issueSignature(projectId: projectId, issue: issue)
            if routedIssueSignatures.contains(signature) { continue }
            if hasExistingTaskForIssue(projectId: projectId, issue: issue) {
                routedIssueSignatures.insert(signature)
                continue
            }

            let assignee = preferredAgent(for: issue)
            let title = "Fix: \(normalizedIssueTitle(issue))"
            let description = """
            Auto-generated from task \(sourceTask.id.uuidString) findings.
            Issue: \(issue)

            Required:
            1. Implement or resolve the issue.
            2. Add/adjust validation for regression prevention.
            3. Report completion with concrete evidence.
            """
            let created = taskService.createTask(
                title: title,
                description: description,
                assignedAgent: assignee,
                status: .scheduled,
                priority: .high,
                scheduledFor: nil,
                projectId: projectId,
                projectName: projectName,
                projectColorHex: projectColor,
                isVerificationTask: false,
                verificationRound: nil,
                isVerified: false,
                isArchived: false
            )
            createdTasks.append(created)
            routedIssueSignatures.insert(signature)
        }

        if createdTasks.isEmpty { return }
        let taskSummary = createdTasks.map { "- \($0.title) -> \($0.assignedAgent ?? "Unassigned")" }.joined(separator: "\n")
        let issueSummary = issues.map { "- \($0)" }.joined(separator: "\n")

        let jarvisMessage = """
        [issue-routing]
        Project: \(projectName)
        Source Task ID: \(sourceTask.id.uuidString)
        Issues detected:
        \(issueSummary)

        The dashboard auto-created remediation tasks:
        \(taskSummary)

        Coordinate execution immediately, enforce dependency order, and keep one active in-progress task per agent.
        """
        _ = try? await gatewayService.sendAgentMessage(
            agentId: "jarvis",
            message: jarvisMessage,
            sessionKey: nil,
            thinkingEnabled: true
        )
    }

    private func issueSignature(projectId: String?, issue: String) -> String {
        let project = projectId ?? "global"
        let normalized = issue
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(project)|\(normalized)"
    }

    private func hasExistingTaskForIssue(projectId: String?, issue: String) -> Bool {
        let needle = normalizedIssueTitle(issue).lowercased()
        return taskService.tasks.contains { task in
            guard !task.isArchived else { return false }
            if task.projectId != projectId { return false }
            return task.title.lowercased().contains(needle)
        }
    }

    private func normalizedIssueTitle(_ issue: String) -> String {
        let compact = issue
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= 70 { return compact }
        return String(compact.prefix(70)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func preferredAgent(for issue: String) -> String {
        let text = issue.lowercased()
        if text.contains("auth") || text.contains("security") || text.contains("origin") || text.contains("token") || text.contains("ws") {
            return "Prism"
        }
        if text.contains("dependency") || text.contains("api contract") || text.contains("integration") || text.contains("research") {
            return "Atlas"
        }
        if text.contains("scope") || text.contains("requirements") || text.contains("orchestr") || text.contains("planning") {
            return "Scope"
        }
        if text.contains("qa") || text.contains("verification") || text.contains("regression") || text.contains("accessibility") {
            return "Prism"
        }
        return "Matrix"
    }

    private func startTaskOrchestrationLoop() {
        orchestrationLoopTask?.cancel()
        orchestrationLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self.runTaskOrchestrationTick()
            }
        }
    }

    private func runTaskOrchestrationTick() async {
        guard !isRunningOrchestrationTick else { return }
        guard gatewayService.isConnected else { return }
        guard !taskService.isExecutionPaused else { return }
        isRunningOrchestrationTick = true
        defer { isRunningOrchestrationTick = false }

        // Promote newly created Ready tasks into the execution queue.
        let readyTasks = taskService.tasks.filter { !$0.isArchived && $0.status == .scheduled }
        for task in readyTasks {
            taskService.moveTask(task.id, to: .queued)
            taskService.appendTaskEvidence(task.id, text: "Queued by orchestrator at \(Date().shortString)")
        }

        let now = Date()
        let sortedTasks = taskService.tasks
            .filter { !$0.isArchived }
            .sorted(by: taskPriorityComparator)

        var reservedAgents = activeAgentRuns

        // Resume orphaned in-progress tasks first.
        let stalledInProgress = sortedTasks.filter {
            $0.status == .inProgress && !activeTaskRuns.contains($0.id)
        }
        for task in stalledInProgress {
            guard isEligibleToRun(task.id, now: now) else { continue }
            guard let agent = normalizedAgent(task.assignedAgent) else { continue }
            guard !reservedAgents.contains(agent) else { continue }
            reservedAgents.insert(agent)
            Task { [weak self] in
                await self?.startImplementation(for: task)
            }
        }

        // Start queued tasks for free agents (one task per agent at a time).
        let queuedTasks = sortedTasks.filter { $0.status == .queued }
        for task in queuedTasks {
            guard isEligibleToRun(task.id, now: now) else { continue }
            if task.isVerificationTask, hasOutstandingRemediationWork(for: task) {
                continue
            }
            guard let agent = normalizedAgent(task.assignedAgent) else { continue }
            guard !reservedAgents.contains(agent) else { continue }
            reservedAgents.insert(agent)
            taskService.moveTask(task.id, to: .inProgress)
            taskService.appendTaskEvidence(task.id, text: "Dequeued to In Progress at \(Date().shortString)")
            Task { [weak self] in
                await self?.startImplementation(for: task)
            }
        }
    }

    private func taskPriorityComparator(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        let lRank = priorityRank(lhs.priority)
        let rRank = priorityRank(rhs.priority)
        if lRank != rRank { return lRank < rRank }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.createdAt < rhs.createdAt
    }

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }

    private func normalizedAgent(_ value: String?) -> String? {
        guard let value else { return nil }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty ? nil : token
    }

    private func isEligibleToRun(_ taskId: UUID, now: Date) -> Bool {
        if let next = taskNextEligibleAt[taskId] {
            return now >= next
        }
        return true
    }

    private func setRetryCooldown(taskId: UUID, seconds: TimeInterval) {
        taskNextEligibleAt[taskId] = Date().addingTimeInterval(seconds)
    }

    private func hasOutstandingRemediationWork(for verificationTask: TaskItem) -> Bool {
        taskService.tasks.contains { task in
            guard !task.isArchived else { return false }
            guard task.projectId == verificationTask.projectId else { return false }
            guard !task.isVerificationTask else { return false }
            return task.status != .done
        }
    }

    private func requestJarvisUnblockForVerification(task: TaskItem, blockedResponse: String) async {
        if let last = verificationEscalationAt[task.id], Date().timeIntervalSince(last) < 180 {
            return
        }
        verificationEscalationAt[task.id] = Date()
        let projectName = task.projectName?.isEmpty == false ? (task.projectName ?? "Unspecified") : "Unspecified"
        let message = """
        [verification-unblock]
        Project: \(projectName)
        Verification Task ID: \(task.id.uuidString)
        Verification Task: \(task.title)
        Assigned Reviewer: \(task.assignedAgent ?? "Unknown")

        The reviewer reported a blocked verification run.
        Provide concrete artifact scope immediately (commits/files/outputs), update the team context, and continue execution.

        Blocked response:
        \(blockedResponse)
        """
        _ = try? await gatewayService.sendAgentMessage(
            agentId: "jarvis",
            message: message,
            sessionKey: nil,
            thinkingEnabled: true
        )
    }

    deinit {
        orchestrationLoopTask?.cancel()
    }

    private func handleTaskExecutionEvent(_ event: [String: Any]) {
        guard let sessionKey = event["sessionKey"] as? String, !sessionKey.isEmpty else { return }
        guard let task = taskService.tasks.first(where: {
            ($0.status == .inProgress || $0.status == .queued) && !$0.isArchived && $0.executionSessionKey == sessionKey
        }) else { return }

        let stream = event["stream"] as? String ?? ""
        let payload = event["data"] as? [String: Any]

        if stream == "assistant", let chunk = payload?["text"] as? String, !chunk.isEmpty {
            taskService.appendTaskEvidence(task.id, text: chunk)
            return
        }

        if stream == "lifecycle", let phase = payload?["phase"] as? String {
            if phase == "start" {
                taskService.appendTaskEvidence(task.id, text: "Run started at \(Date().shortString)")
            } else if phase == "end" {
                taskService.appendTaskEvidence(task.id, text: "Run ended at \(Date().shortString)")
            } else if phase == "error" {
                taskService.appendTaskEvidence(task.id, text: "Run reported error at \(Date().shortString)")
            }
        }
    }
}
