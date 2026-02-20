import XCTest
@testable import OpenClawDashboard

@MainActor
final class AppViewModelInterventionTests: XCTestCase {
    func testRecurringInterventionMessageUpdatesErrorMessage() async {
        let paths = makeTempPaths(testName: #function)
        defer { cleanup(paths.dir) }

        let taskService = TaskService(filePath: paths.tasksFile, stateFilePath: paths.taskStateFile)
        taskService.tasks = [
            TaskItem(title: "A", assignedAgent: "Matrix", status: .inProgress, lastEvidence: "status 429 from provider"),
            TaskItem(title: "B", assignedAgent: "Matrix", status: .inProgress, lastEvidence: "too many requests while sending"),
            TaskItem(title: "C", assignedAgent: "Matrix", status: .queued, lastEvidence: "rate limited by upstream")
        ]

        let gateway = MockGatewayService()
        let interventionService = TaskInterventionService(
            taskService: taskService,
            gatewayService: gateway,
            reportsDirectoryPath: paths.reportsDir,
            stateFilePath: paths.interventionStateFile
        )

        let settingsService = SettingsService()
        var settings = settingsService.settings
        settings.onboardingComplete = true
        settingsService.settings = settings

        let viewModel = AppViewModel(
            settingsService: settingsService,
            gatewayService: gateway,
            taskService: taskService,
            taskInterventionService: interventionService,
            connectGatewayOnInit: false,
            enableNotifications: false
        )

        let expectation = expectation(description: "errorMessage updated")
        Task { @MainActor in
            while viewModel.errorMessage == nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(viewModel.errorMessage, "Recurring issue detected. Tasks paused and Jarvis intervention report generated.")
    }

    private func makeTempPaths(testName: String) -> (dir: String, tasksFile: String, taskStateFile: String, interventionStateFile: String, reportsDir: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawDashboardTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let reports = root.appendingPathComponent("reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)

        return (
            root.path,
            root.appendingPathComponent("tasks-\(testName).json").path,
            root.appendingPathComponent("tasks-state-\(testName).json").path,
            root.appendingPathComponent("intervention-state-\(testName).json").path,
            reports.path
        )
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }
}

@MainActor
private final class MockGatewayService: GatewayService {
    override func sendAgentMessage(agentId: String, message: String, sessionKey: String?, thinkingEnabled: Bool) async throws -> AgentMessageResponse {
        return AgentMessageResponse(text: "ok", sessionKey: sessionKey)
    }
}
