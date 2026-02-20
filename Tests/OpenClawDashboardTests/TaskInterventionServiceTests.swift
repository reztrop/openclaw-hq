import XCTest
@testable import OpenClawDashboard

@MainActor
final class TaskInterventionServiceTests: XCTestCase {
    func testRecurringIssueTriggersPauseReportAndJarvisEscalation() async {
        let paths = makeTempPaths(testName: #function)
        defer { cleanup(paths.dir) }

        let taskService = TaskService(filePath: paths.tasksFile, stateFilePath: paths.taskStateFile)
        taskService.tasks = []

        taskService.tasks = [
            makeTask(title: "A", evidence: "status 429 from provider"),
            makeTask(title: "B", evidence: "Too many requests while sending"),
            makeTask(title: "C", evidence: "rate limited by upstream")
        ]

        let gateway = MockGatewayService()
        let service = TaskInterventionService(
            taskService: taskService,
            gatewayService: gateway,
            reportsDirectoryPath: paths.reportsDir,
            stateFilePath: paths.interventionStateFile
        )

        let result = await service.evaluateRecurringIssueIntervention(tasks: taskService.tasks)

        XCTAssertEqual(result, "Recurring issue detected. Tasks paused and Jarvis intervention report generated.")
        XCTAssertTrue(taskService.isExecutionPaused)
        XCTAssertEqual(gateway.sentMessages.count, 1)
        XCTAssertTrue(gateway.sentMessages[0].contains("Recurring issue loop detected"))

        let reportFiles = (try? FileManager.default.contentsOfDirectory(atPath: paths.reportsDir)) ?? []
        XCTAssertEqual(reportFiles.count, 1)
        XCTAssertTrue(reportFiles[0].contains("jarvis_intervention_"))
    }

    func testCooldownSuppressesDuplicateIntervention() async {
        let paths = makeTempPaths(testName: #function)
        defer { cleanup(paths.dir) }

        let taskService = TaskService(filePath: paths.tasksFile, stateFilePath: paths.taskStateFile)
        taskService.tasks = [
            makeTask(title: "A", evidence: "status 429 from provider"),
            makeTask(title: "B", evidence: "Too many requests while sending"),
            makeTask(title: "C", evidence: "rate limited by upstream")
        ]

        let gateway = MockGatewayService()
        let fixedNow = Date()
        let service = TaskInterventionService(
            taskService: taskService,
            gatewayService: gateway,
            reportsDirectoryPath: paths.reportsDir,
            stateFilePath: paths.interventionStateFile,
            now: { fixedNow }
        )

        _ = await service.evaluateRecurringIssueIntervention(tasks: taskService.tasks)
        taskService.setExecutionPaused(false)
        let duplicate = await service.evaluateRecurringIssueIntervention(tasks: taskService.tasks)

        XCTAssertNil(duplicate)
        XCTAssertEqual(gateway.sentMessages.count, 1)
    }

    func testCooldownStatePersistsAcrossServiceReinitialization() async {
        let paths = makeTempPaths(testName: #function)
        defer { cleanup(paths.dir) }

        let taskService = TaskService(filePath: paths.tasksFile, stateFilePath: paths.taskStateFile)
        taskService.tasks = [
            makeTask(title: "A", evidence: "status 429 from provider"),
            makeTask(title: "B", evidence: "Too many requests while sending"),
            makeTask(title: "C", evidence: "rate limited by upstream")
        ]

        let firstGateway = MockGatewayService()
        let now = Date()
        let first = TaskInterventionService(
            taskService: taskService,
            gatewayService: firstGateway,
            reportsDirectoryPath: paths.reportsDir,
            stateFilePath: paths.interventionStateFile,
            now: { now }
        )

        _ = await first.evaluateRecurringIssueIntervention(tasks: taskService.tasks)
        XCTAssertEqual(firstGateway.sentMessages.count, 1)

        taskService.setExecutionPaused(false)

        let secondGateway = MockGatewayService()
        let second = TaskInterventionService(
            taskService: taskService,
            gatewayService: secondGateway,
            reportsDirectoryPath: paths.reportsDir,
            stateFilePath: paths.interventionStateFile,
            now: { now.addingTimeInterval(60) }
        )

        let result = await second.evaluateRecurringIssueIntervention(tasks: taskService.tasks)
        XCTAssertNil(result)
        XCTAssertEqual(secondGateway.sentMessages.count, 0)
    }

    func testTaskBlockedMarkersTriggerInterventionAndJarvisMessageIncludesReport() async {
        let paths = makeTempPaths(testName: #function)
        defer { cleanup(paths.dir) }

        let taskService = TaskService(filePath: paths.tasksFile, stateFilePath: paths.taskStateFile)
        taskService.tasks = [
            makeTask(title: "A", evidence: "Issue: [task-blocked] waiting on dependency"),
            makeTask(title: "B", evidence: "[task-blocked] blocked by missing upstream payload"),
            makeTask(title: "C", evidence: "[task-blocked] cannot proceed without schema")
        ]

        let gateway = MockGatewayService()
        let service = TaskInterventionService(
            taskService: taskService,
            gatewayService: gateway,
            reportsDirectoryPath: paths.reportsDir,
            stateFilePath: paths.interventionStateFile
        )

        let result = await service.evaluateRecurringIssueIntervention(tasks: taskService.tasks)

        XCTAssertEqual(result, "Recurring issue detected. Tasks paused and Jarvis intervention report generated.")
        XCTAssertEqual(gateway.sentMessages.count, 1)
        XCTAssertTrue(gateway.sentMessages[0].contains("Dominant issue: task_blocked"))
        XCTAssertTrue(gateway.sentMessages[0].contains("Report: \(paths.reportsDir)/jarvis_intervention_"))
    }

    func testCooldownAppliesToSameIssueEvenWhenTaskIdsChange() async {
        let paths = makeTempPaths(testName: #function)
        defer { cleanup(paths.dir) }

        let taskService = TaskService(filePath: paths.tasksFile, stateFilePath: paths.taskStateFile)
        taskService.tasks = [
            makeTask(title: "A", evidence: "status 429 from provider"),
            makeTask(title: "B", evidence: "Too many requests while sending"),
            makeTask(title: "C", evidence: "rate limited by upstream")
        ]

        let gateway = MockGatewayService()
        var currentNow = Date()
        let service = TaskInterventionService(
            taskService: taskService,
            gatewayService: gateway,
            reportsDirectoryPath: paths.reportsDir,
            stateFilePath: paths.interventionStateFile,
            now: { currentNow }
        )

        _ = await service.evaluateRecurringIssueIntervention(tasks: taskService.tasks)
        XCTAssertEqual(gateway.sentMessages.count, 1)

        taskService.setExecutionPaused(false)
        taskService.tasks = [
            makeTask(title: "D", evidence: "status 429 from provider"),
            makeTask(title: "E", evidence: "Too many requests while sending"),
            makeTask(title: "F", evidence: "rate limited by upstream")
        ]
        currentNow = currentNow.addingTimeInterval(60)

        let result = await service.evaluateRecurringIssueIntervention(tasks: taskService.tasks)
        XCTAssertNil(result)
        XCTAssertEqual(gateway.sentMessages.count, 1)
    }

    private func makeTask(title: String, evidence: String) -> TaskItem {
        TaskItem(title: title, assignedAgent: "Matrix", status: .inProgress, lastEvidence: evidence)
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
    var sentMessages: [String] = []

    override func sendAgentMessage(agentId: String, message: String, sessionKey: String?, thinkingEnabled: Bool) async throws -> AgentMessageResponse {
        sentMessages.append(message)
        return AgentMessageResponse(text: "ok", sessionKey: sessionKey)
    }
}
