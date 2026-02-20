import XCTest

final class VisualScopeLockGuardrailTests: XCTestCase {
    func testAppViewModelDoesNotContainTaskOrchestrationRuntime() throws {
        let source = try loadSource("Sources/OpenClawDashboard/ViewModels/AppViewModel.swift")

        assertSource(
            source,
            doesNotContain: [
                "startImplementation(for task:",
                "runTaskOrchestrationTick()",
                "routeIssuesToJarvisAndCreateFixTasks",
                "startTaskOrchestrationLoop()",
                "handleTaskExecutionEvent(_ event:",
                "private struct InterventionState",
                "private var lastInterventionFingerprint",
                "private var lastInterventionAt",
                "recurringIssueMarkers(in evidence:",
                "writeInterventionReport(dominantIssue:",
                "notifyJarvisOfIntervention(reportPath:",
                "loadInterventionState()",
                "saveInterventionState()",
                "interventionCooldown",
                "private func evaluateRecurringIssueIntervention(tasks:"
            ],
            context: "AppViewModel"
        )
    }

    func testProjectsViewModelDoesNotContainExecutionAutomationScaffolding() throws {
        let source = try loadSource("Sources/OpenClawDashboard/ViewModels/ProjectsViewModel.swift")

        assertSource(
            source,
            doesNotContain: [
                "createSectionWorkflowTasks(",
                "startVerificationRound(",
                "finalizeProject(projectId:",
                "sendJarvisKickoff(message:",
                "[project-execute]"
            ],
            context: "ProjectsViewModel"
        )
    }

    func testRecurringIssueInterventionLivesInServiceLayer() throws {
        let appSource = try loadSource("Sources/OpenClawDashboard/ViewModels/AppViewModel.swift")
        assertSource(
            appSource,
            contains: [
                "taskInterventionService.evaluateRecurringIssueIntervention(tasks: tasks)"
            ],
            context: "AppViewModel"
        )

        assertSource(
            appSource,
            doesNotContain: [
                "setExecutionPaused(true)",
                "sendAgentMessage(agentId:",
                "dominantIssue"
            ],
            context: "AppViewModel"
        )

        let serviceSource = try loadSource("Sources/OpenClawDashboard/Services/TaskInterventionService.swift")
        assertSource(
            serviceSource,
            contains: [
                "final class TaskInterventionService",
                "notifyJarvisOfIntervention(reportPath:",
                "recurringIssueMarkers(in evidence:",
                "interventionCooldown"
            ],
            context: "TaskInterventionService"
        )
    }

    private func assertSource(
        _ source: String,
        contains requiredSymbols: [String],
        context: String
    ) {
        for symbol in requiredSymbols {
            XCTAssertTrue(
                source.contains(symbol),
                "\(context) missing expected guardrail symbol: \(symbol)"
            )
        }
    }

    private func assertSource(
        _ source: String,
        doesNotContain forbiddenSymbols: [String],
        context: String
    ) {
        for symbol in forbiddenSymbols {
            XCTAssertFalse(
                source.contains(symbol),
                "\(context) reintroduced forbidden symbol: \(symbol)"
            )
        }
    }

    private func loadSource(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let path = repoRoot.appendingPathComponent(relativePath).path
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
