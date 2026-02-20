import Foundation

@MainActor
final class TaskInterventionService {
    private let taskService: TaskService
    private let gatewayService: GatewayService

    private var lastInterventionFingerprint: String?
    private var lastInterventionAt: Date?
    private let interventionCooldown: TimeInterval = 30 * 60

    init(taskService: TaskService, gatewayService: GatewayService) {
        self.taskService = taskService
        self.gatewayService = gatewayService
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

        let fingerprint = "\(dominantIssue)|\(affectedTasks.map { $0.id.uuidString }.sorted().joined(separator: ","))"
        let now = Date()
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
