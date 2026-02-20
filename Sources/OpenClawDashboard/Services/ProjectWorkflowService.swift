import Foundation

@MainActor
final class ProjectWorkflowService {
    enum VerificationRoundOutcome {
        case started(round: Int)
        case maxRoundsReached(maxRounds: Int)
    }

    private let taskService: TaskService
    private let gatewayService: GatewayService

    init(taskService: TaskService, gatewayService: GatewayService) {
        self.taskService = taskService
        self.gatewayService = gatewayService
    }

    func buildSectionWorkflowTasks(for project: ProjectRecord, projectName: String, projectColorHex: String) -> Int {
        let sourceSections = project.blueprint.sections.filter { $0.completed }
        let sections = sourceSections.isEmpty ? project.blueprint.sections : sourceSections
        guard !sections.isEmpty else { return 0 }

        let designContext = conciseContext(project.blueprint.designText)
        let draftContext = conciseContext(project.blueprint.sectionsDraftText)

        var created = 0
        for section in sections {
            let scopedTitle = "\(projectName): Build \(section.title) core workflow"
            let alreadyExists = taskService.tasks.contains {
                $0.projectId == project.id && $0.title == scopedTitle
            }
            if alreadyExists { continue }

            let description = """
            Deliver the primary user workflow for \(section.title).

            Section goal:
            \(section.summary)

            Design plan context:
            \(designContext)

            Approved sections context:
            \(draftContext)

            Constraints:
            - Keep the task independently completable.
            - Avoid task switching across unrelated sections.
            - Hand off to Jarvis when implementation is review-ready.
            """

            _ = taskService.createTask(
                title: scopedTitle,
                description: description,
                assignedAgent: normalizedAgent(section.ownerAgent),
                status: .scheduled,
                priority: section.completed ? .high : .medium,
                scheduledFor: nil,
                projectId: project.id,
                projectName: projectName,
                projectColorHex: projectColorHex,
                isVerificationTask: false,
                verificationRound: nil,
                isVerified: false,
                isArchived: false
            )
            created += 1
        }

        return created
    }

    func sendExecutionKickoff(projectName: String, sessionKey: String?) async {
        let kickoffMessage = """
        [project-execute]
        Project: \(projectName)
        Start execution now. Create and coordinate concrete task updates through the team.
        Prioritize urgent and high-priority work first.
        Constraint: each agent can only have one task in progress at a time.
        Constraint: create independent tasks that reduce switching and cross-task blocking.
        """
        await sendJarvisKickoff(message: kickoffMessage, sessionKey: sessionKey)
    }

    func beginVerificationRound(for project: inout ProjectRecord, projectColorHex: String, reason: String) -> VerificationRoundOutcome {
        let maxRounds = 3
        if project.reviewRound >= maxRounds {
            project.reviewStatus = .waitingFinalApproval
            project.updatedAt = Date()
            return .maxRoundsReached(maxRounds: maxRounds)
        }

        let nextRound = project.reviewRound + 1
        let agents = ["Jarvis", "Scope", "Atlas", "Matrix", "Prism"]

        for agent in agents {
            let title = "\(project.title): Final Verification (\(agent)) - Round \(nextRound)"
            let exists = taskService.tasks.contains {
                $0.projectId == project.id &&
                $0.title == title &&
                !$0.isArchived
            }
            if exists { continue }

            _ = taskService.createTask(
                title: title,
                description: """
                \(reason)
                Review all recent changes for completeness and regressions. If fixes are needed, route them through Jarvis.
                """,
                assignedAgent: agent,
                status: .scheduled,
                priority: .urgent,
                scheduledFor: nil,
                projectId: project.id,
                projectName: project.title,
                projectColorHex: projectColorHex,
                isVerificationTask: true,
                verificationRound: nextRound,
                isVerified: false,
                isArchived: false
            )
        }

        project.reviewRound = nextRound
        project.reviewStatus = .inReview
        project.updatedAt = Date()

        let kickoff = """
        [project-verification]
        Project: \(project.title)
        Verification Round: \(nextRound)
        Reason: \(reason)
        All agents must verify latest state and report to Jarvis.
        """
        let sessionKey = project.conversationId
        Task { [weak self] in
            guard let self else { return }
            await self.sendJarvisKickoff(message: kickoff, sessionKey: sessionKey)
        }

        return .started(round: nextRound)
    }

    func closeProject(_ project: inout ProjectRecord) {
        project.reviewStatus = .finalApproved
        project.updatedAt = Date()
        taskService.archiveTasks(for: project.id)
    }

    private func sendJarvisKickoff(message: String, sessionKey: String?) async {
        _ = try? await gatewayService.sendAgentMessage(
            agentId: "jarvis",
            message: message,
            sessionKey: sessionKey,
            thinkingEnabled: true
        )
    }

    private func conciseContext(_ text: String, fallback: String = "No additional context captured yet.") -> String {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return fallback }
        let maxLength = 420
        if cleaned.count <= maxLength { return cleaned }
        let prefix = cleaned.prefix(maxLength)
        return "\(prefix)…"
    }

    private func normalizedAgent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Matrix" }
        return trimmed
    }
}
