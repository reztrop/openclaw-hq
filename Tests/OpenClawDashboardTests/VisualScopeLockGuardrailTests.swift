import XCTest

final class VisualScopeLockGuardrailTests: XCTestCase {
    func testAppViewModelDoesNotContainTaskOrchestrationRuntime() throws {
        let source = try loadSource("Sources/OpenClawDashboard/ViewModels/AppViewModel.swift")

        let forbiddenSymbols = [
            "startImplementation(for task:",
            "runTaskOrchestrationTick()",
            "routeIssuesToJarvisAndCreateFixTasks",
            "startTaskOrchestrationLoop()",
            "handleTaskExecutionEvent(_ event:"
        ]

        for symbol in forbiddenSymbols {
            XCTAssertFalse(
                source.contains(symbol),
                "AppViewModel reintroduced orchestration symbol: \(symbol)"
            )
        }
    }

    func testProjectsViewModelDoesNotContainExecutionAutomationScaffolding() throws {
        let source = try loadSource("Sources/OpenClawDashboard/ViewModels/ProjectsViewModel.swift")

        let forbiddenSymbols = [
            "createSectionWorkflowTasks(",
            "startVerificationRound(",
            "finalizeProject(projectId:",
            "sendJarvisKickoff(message:",
            "[project-execute]"
        ]

        for symbol in forbiddenSymbols {
            XCTAssertFalse(
                source.contains(symbol),
                "ProjectsViewModel reintroduced non-visual execution logic: \(symbol)"
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
