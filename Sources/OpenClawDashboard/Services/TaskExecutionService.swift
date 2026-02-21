import Foundation
import Combine

@MainActor
final class TaskExecutionService {
    private enum ExecutionError: Error {
        case timedOut
    }

    private let taskService: TaskService
    private let gatewayService: GatewayService
    private let onTaskCompleted: (TaskItem) -> Void

    private var cancellables = Set<AnyCancellable>()
    private var orchestratorTask: Task<Void, Never>?
    private var activeRuns: Set<UUID> = []
    private var activeAgents: Set<String> = []
    private var nextEligibleAt: [UUID: Date] = [:]
    private var isTickRunning = false
    private var queuedStallBeganAt: Date?

    init(
        taskService: TaskService,
        gatewayService: GatewayService,
        onTaskCompleted: @escaping (TaskItem) -> Void
    ) {
        self.taskService = taskService
        self.gatewayService = gatewayService
        self.onTaskCompleted = onTaskCompleted
        subscribe()
        startLoop()
    }

    deinit {
        orchestratorTask?.cancel()
    }

    func handleTaskMovedToInProgress(_ task: TaskItem) {
        Task { [weak self] in
            await self?.startTaskIfNeeded(taskId: task.id)
        }
    }

    private func subscribe() {
        taskService.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.runTick()
                }
            }
            .store(in: &cancellables)

        taskService.$isExecutionPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                guard let self else { return }
                if !paused {
                    Task { [weak self] in
                        await self?.runTick()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func startLoop() {
        orchestratorTask?.cancel()
        orchestratorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await self.runTick()
            }
        }
    }

    private func runTick() async {
        guard !isTickRunning else { return }
        guard !taskService.isExecutionPaused else { return }
        isTickRunning = true
        defer { isTickRunning = false }

        normalizeBlockedInProgressTasks()
        if !gatewayService.isConnected {
            gatewayService.connect()
        }

        // Ready tasks are considered execution candidates; enqueue automatically.
        let ready = taskService.tasks.filter { !$0.isArchived && $0.status == .scheduled }
        for task in ready {
            taskService.moveTask(task.id, to: .queued)
            taskService.appendTaskEvidence(task.id, text: "Auto-queued at \(Date().shortString)")
        }

        let now = Date()
        var reservedAgents = activeAgents

        // Resume any in-progress tasks that are not actively running.
        let inProgress = taskService.tasksForStatus(.inProgress)
        for task in inProgress {
            guard isEligible(task.id, now: now) else { continue }
            guard let agent = normalizedAgent(task.assignedAgent) else { continue }
            guard !reservedAgents.contains(agent) else { continue }
            reservedAgents.insert(agent)
            Task { [weak self] in
                await self?.startTaskIfNeeded(taskId: task.id)
            }
        }

        // Start queued tasks when agent is free.
        let queued = taskService.tasksForStatus(.queued).sorted(by: queuePrioritySort)
        for task in queued {
            guard isEligible(task.id, now: now) else { continue }
            guard let agent = normalizedAgent(task.assignedAgent) else { continue }
            guard !reservedAgents.contains(agent) else { continue }
            reservedAgents.insert(agent)
            taskService.moveTask(task.id, to: .inProgress)
            taskService.appendTaskEvidence(task.id, text: "Dequeued to In Progress at \(Date().shortString)")
            Task { [weak self] in
                await self?.startTaskIfNeeded(taskId: task.id)
            }
        }

        recoverFromQueuedStall(now: now)
    }

    private func startTaskIfNeeded(taskId: UUID) async {
        guard !taskService.isExecutionPaused else { return }
        guard !activeRuns.contains(taskId) else { return }
        guard let task = taskService.tasks.first(where: { $0.id == taskId }) else { return }
        guard !task.isArchived, task.status == .inProgress else { return }
        guard let agent = normalizedAgent(task.assignedAgent) else { return }
        guard !activeAgents.contains(agent) else { return }

        activeRuns.insert(task.id)
        activeAgents.insert(agent)
        defer {
            activeRuns.remove(task.id)
            activeAgents.remove(agent)
        }

        let sessionKey = task.executionSessionKey?.isEmpty == false
            ? (task.executionSessionKey ?? "")
            : "agent:\(agent):task:\(task.id.uuidString.lowercased())"
        taskService.mutateTask(task.id) { mutable in
            mutable.executionSessionKey = sessionKey
        }
        taskService.appendTaskEvidence(task.id, text: "Kickoff attempt to \(agent) at \(Date().shortString)")

        let projectLine = (task.projectName?.isEmpty == false) ? "Project: \(task.projectName!)" : "Project: Unspecified"
        let details = task.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailLine = (details?.isEmpty == false) ? "Task details: \(details!)" : "Task details: none"
        let taskTextForRelayCheck = "\(task.title)\n\(details ?? "")".lowercased()
        let browserRelayRequired = taskTextForRelayCheck.contains("browser relay")
            || taskTextForRelayCheck.contains("chrome tab")
            || taskTextForRelayCheck.contains("attach tab")
        let relayConstraint = browserRelayRequired
            ? "Browser Relay is explicitly required for this task. If missing, return [task-blocked] with exact setup steps."
            : "Do not ask for Chrome tabs or Browser Relay. Complete using repo/workspace artifacts and report any limits."
        let kickoff = """
        [task-start]
        \(projectLine)
        Task ID: \(task.id.uuidString)
        Task: \(task.title)
        \(detailLine)
        Constraint: \(relayConstraint)

        Continue from existing progress if present.
        You must take concrete execution action in this run.
        Do not wait for manager confirmation if a reasonable next step is available.
        Use [task-blocked] only when an external dependency prevents execution.
        End with exactly one marker line:
        [task-complete] or [task-continue] or [task-blocked]
        """

        do {
            let response = try await sendAgentMessageWithTimeout(
                agentId: agent,
                message: kickoff,
                sessionKey: sessionKey,
                thinkingEnabled: true,
                timeoutSeconds: 180
            )
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                taskService.appendTaskEvidence(task.id, text: "Final response:\n\(text)")
            }
            await notifyJarvisTaskUpdate(task: task, outcomeText: text)

            let outcome = parseOutcome(text)
            switch outcome {
            case .complete:
                taskService.moveTask(task.id, to: .done)
                if let done = taskService.tasks.first(where: { $0.id == task.id }) {
                    onTaskCompleted(done)
                }
            case .continueWork:
                taskService.moveTask(task.id, to: .queued)
                setCooldown(task.id, seconds: 120)
            case .blocked:
                taskService.moveTask(task.id, to: .queued)
                let external = isExternalBlocker(text)
                taskService.appendTaskEvidence(
                    task.id,
                    text: external
                        ? "Blocked outcome detected (external blocker); escalation sent to Jarvis."
                        : "Blocked outcome detected (internal blocker); escalation sent to Jarvis."
                )
                await notifyJarvisBlocked(task: task, response: text)
                setCooldown(task.id, seconds: external ? 60 * 60 : 60)
            }
        } catch {
            let errorText = error.localizedDescription
            taskService.appendTaskEvidence(task.id, text: "Run error: \(errorText)")
            await notifyJarvisTaskRunError(task: task, errorText: errorText)
            taskService.moveTask(task.id, to: .queued)
            let lower = errorText.lowercased()
            if lower.contains("rate limited") || lower.contains("429") || lower.contains("too many requests") || lower.contains("quota") {
                setCooldown(task.id, seconds: 60 * 60)
            } else if lower.contains("timed out") {
                setCooldown(task.id, seconds: 60)
            } else {
                setCooldown(task.id, seconds: 10 * 60)
            }
        }
    }

    private enum Outcome {
        case complete
        case continueWork
        case blocked
    }

    private func parseOutcome(_ text: String) -> Outcome {
        let lower = text.lowercased()
        if lower.contains("[task-complete]") { return .complete }
        if lower.contains("[task-blocked]") { return .blocked }
        if lower.contains("[task-continue]") { return .continueWork }
        return .continueWork
    }

    private func normalizedAgent(_ value: String?) -> String? {
        guard let value else { return nil }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty ? nil : token
    }

    private func queuePrioritySort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
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

    private func isEligible(_ taskId: UUID, now: Date) -> Bool {
        if let date = nextEligibleAt[taskId] {
            return now >= date
        }
        return true
    }

    private func setCooldown(_ taskId: UUID, seconds: TimeInterval) {
        nextEligibleAt[taskId] = Date().addingTimeInterval(seconds)
    }

    /// Dead-man switch: if tasks sit queued with no in-progress work for too long,
    /// force-dispatch one highest-priority task to break silent stalls.
    private func recoverFromQueuedStall(now: Date) {
        let queued = taskService.tasksForStatus(.queued).sorted(by: queuePrioritySort)
        let inProgress = taskService.tasksForStatus(.inProgress)
        guard !queued.isEmpty else {
            queuedStallBeganAt = nil
            return
        }
        guard inProgress.isEmpty, activeRuns.isEmpty else {
            queuedStallBeganAt = nil
            return
        }

        if queuedStallBeganAt == nil {
            queuedStallBeganAt = now
            return
        }

        guard let stalledSince = queuedStallBeganAt,
              now.timeIntervalSince(stalledSince) >= 20 else {
            return
        }

        guard let task = queued.first,
              let agent = normalizedAgent(task.assignedAgent),
              !activeAgents.contains(agent) else {
            return
        }

        nextEligibleAt[task.id] = nil
        taskService.moveTask(task.id, to: .inProgress)
        taskService.appendTaskEvidence(task.id, text: "Forced dispatch after queued stall at \(Date().shortString)")
        Task { [weak self] in
            await self?.startTaskIfNeeded(taskId: task.id)
        }
        queuedStallBeganAt = nil
    }

    private func sendAgentMessageWithTimeout(
        agentId: String,
        message: String,
        sessionKey: String?,
        thinkingEnabled: Bool,
        timeoutSeconds: TimeInterval
    ) async throws -> GatewayService.AgentMessageResponse {
        try await withThrowingTaskGroup(of: GatewayService.AgentMessageResponse.self) { group in
            group.addTask { [gatewayService] in
                try await gatewayService.sendAgentMessage(
                    agentId: agentId,
                    message: message,
                    sessionKey: sessionKey,
                    thinkingEnabled: thinkingEnabled
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw ExecutionError.timedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func normalizeBlockedInProgressTasks() {
        for task in taskService.tasksForStatus(.inProgress) {
            guard lastOutcomeMarker(in: task.lastEvidence) == .blocked else { continue }
            taskService.moveTask(task.id, to: .queued)
            setCooldown(task.id, seconds: 60)
        }
    }

    private func lastOutcomeMarker(in text: String?) -> Outcome? {
        guard let text = text?.lowercased(), !text.isEmpty else { return nil }
        let markers: [(String, Outcome)] = [
            ("[task-complete]", .complete),
            ("[task-continue]", .continueWork),
            ("[task-blocked]", .blocked)
        ]
        var best: (index: String.Index, outcome: Outcome)?
        for (needle, outcome) in markers {
            guard let range = text.range(of: needle, options: .backwards) else { continue }
            if let current = best {
                if range.lowerBound > current.index {
                    best = (range.lowerBound, outcome)
                }
            } else {
                best = (range.lowerBound, outcome)
            }
        }
        return best?.outcome
    }

    private func isExternalBlocker(_ response: String) -> Bool {
        let lower = response.lowercased()
        let needles = [
            "please click", "attach", "need your", "awaiting your",
            "provide token", "provide api key", "missing credential",
            "requires access", "cannot access", "waiting for user", "unreachable system"
        ]
        return needles.contains(where: { lower.contains($0) })
    }

    private func notifyJarvisBlocked(task: TaskItem, response: String) async {
        let project = task.projectName ?? "Unspecified"
        let owner = task.assignedAgent ?? "Unassigned"
        let excerpt = String(response.trimmingCharacters(in: .whitespacesAndNewlines).suffix(900))
        let message = """
        [task-blocked-escalation]
        Task execution returned [task-blocked] and was re-queued.
        Task ID: \(task.id.uuidString)
        Project: \(project)
        Owner: \(owner)
        Title: \(task.title)

        Blocking response excerpt:
        \(excerpt)

        Action required:
        1) Remove blocker or re-scope task.
        2) Provide concrete executable next step.
        3) Avoid placeholder promises without task movement.
        """
        _ = try? await gatewayService.sendAgentMessage(
            agentId: "jarvis",
            message: message,
            sessionKey: nil,
            thinkingEnabled: true
        )
    }

    private func notifyJarvisTaskUpdate(task: TaskItem, outcomeText: String) async {
        let project = task.projectName ?? "Unspecified"
        let owner = task.assignedAgent ?? "Unassigned"
        let status = parseOutcome(outcomeText)
        let marker: String
        switch status {
        case .complete: marker = "[task-complete]"
        case .continueWork: marker = "[task-continue]"
        case .blocked: marker = "[task-blocked]"
        }
        let excerpt = String(outcomeText.trimmingCharacters(in: .whitespacesAndNewlines).suffix(700))
        let message = """
        [task-status-update]
        Project: \(project)
        Task ID: \(task.id.uuidString)
        Owner: \(owner)
        Title: \(task.title)
        Outcome: \(marker)

        Response excerpt:
        \(excerpt)
        """
        _ = try? await gatewayService.sendAgentMessage(
            agentId: "jarvis",
            message: message,
            sessionKey: nil,
            thinkingEnabled: true
        )
    }

    private func notifyJarvisTaskRunError(task: TaskItem, errorText: String) async {
        let project = task.projectName ?? "Unspecified"
        let owner = task.assignedAgent ?? "Unassigned"
        let message = """
        [task-run-error]
        Project: \(project)
        Task ID: \(task.id.uuidString)
        Owner: \(owner)
        Title: \(task.title)
        Error: \(errorText)
        """
        _ = try? await gatewayService.sendAgentMessage(
            agentId: "jarvis",
            message: message,
            sessionKey: nil,
            thinkingEnabled: true
        )
    }
}
