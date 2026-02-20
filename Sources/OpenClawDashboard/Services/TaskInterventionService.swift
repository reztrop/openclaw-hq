import Foundation

@MainActor
final class TaskInterventionService {
    private struct InterventionState: Codable {
        var lastInterventionFingerprint: String?
        var lastInterventionAt: Date?
    }

    private let taskService: TaskService
    private let gatewayService: GatewayService
    private let reportsDirectoryPath: String
    private let stateFilePath: String
    private let now: () -> Date

    private var lastInterventionFingerprint: String?
    private var lastInterventionAt: Date?
    private let interventionCooldown: TimeInterval = 30 * 60

    init(
        taskService: TaskService,
        gatewayService: GatewayService,
        reportsDirectoryPath: String = Constants.taskInterventionReportsDirectory,
        stateFilePath: String = Constants.taskInterventionStateFilePath,
        now: @escaping () -> Date = Date.init
    ) {
        self.taskService = taskService
        self.gatewayService = gatewayService
        self.reportsDirectoryPath = reportsDirectoryPath
        self.stateFilePath = stateFilePath
        self.now = now
        loadInterventionState()
    }

    func evaluateRecurringIssueIntervention(tasks: [TaskItem]) async -> String? {
        guard !taskService.isExecutionPaused else { return nil }

        let active = tasks.filter { !$0.isArchived && ($0.status == .queued || $0.status == .inProgress) }
        guard !active.isEmpty else { return nil }

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

        guard !issueCounts.isEmpty else { return nil }
        let dominant = issueCounts.max(by: { $0.value < $1.value })
        guard let dominantIssue = dominant?.key, let dominantCount = dominant?.value else { return nil }

        // Trigger only when the same issue repeats across multiple active tasks.
        guard dominantCount >= 3 else { return nil }

        // Cooldown should apply to the recurring issue itself, not the specific task IDs.
        // Task IDs churn as retries regenerate tasks, but repeated interventions for the
        // same dominant issue within the cooldown window should still be suppressed.
        let fingerprint = dominantIssue
        let now = now()
        if lastInterventionFingerprint == fingerprint,
           let last = lastInterventionAt,
           now.timeIntervalSince(last) < interventionCooldown {
            return nil
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
        saveInterventionState()
        return "Recurring issue detected. Tasks paused and Jarvis intervention report generated."
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
        let reportsDir = reportsDirectoryPath
        let timestamp = ISO8601DateFormatter().string(from: now()).replacingOccurrences(of: ":", with: "-")
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

    private func loadInterventionState() {
        guard FileManager.default.fileExists(atPath: stateFilePath) else { return }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
            let decoder = JSONDecoder()
            let state = try decoder.decode(InterventionState.self, from: data)
            lastInterventionFingerprint = state.lastInterventionFingerprint
            lastInterventionAt = state.lastInterventionAt
        } catch {
            lastInterventionFingerprint = nil
            lastInterventionAt = nil
        }
    }

    private func saveInterventionState() {
        do {
            let state = InterventionState(
                lastInterventionFingerprint: lastInterventionFingerprint,
                lastInterventionAt: lastInterventionAt
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            let stateDir = URL(fileURLWithPath: stateFilePath).deletingLastPathComponent().path
            try FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: stateFilePath), options: .atomic)
        } catch {
            print("[TaskInterventionService] Failed to save cooldown state: \(error)")
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
