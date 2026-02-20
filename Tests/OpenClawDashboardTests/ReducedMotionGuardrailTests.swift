import XCTest

final class ReducedMotionGuardrailTests: XCTestCase {
    func testTaskColumnDropTargetAnimationRespectsReduceMotion() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpenClawDashboardTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root

        let taskColumnPath = repoRoot
            .appendingPathComponent("Sources/OpenClawDashboard/Views/Tasks/TaskColumn.swift")
            .path

        let source = try String(contentsOfFile: taskColumnPath, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if reduceMotion {") &&
            source.contains("withAnimation(.easeOut(duration: 0.2))"),
            "TaskColumn drop target animation must be gated by accessibilityReduceMotion."
        )
    }

    func testSettingsSaveConfirmationRespectsReduceMotion() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let settingsPath = repoRoot
            .appendingPathComponent("Sources/OpenClawDashboard/Views/Settings/SettingsView.swift")
            .path

        let source = try String(contentsOfFile: settingsPath, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Motion.perform(reduceMotion) { savedConfirmation = true }") &&
            source.contains("Motion.perform(reduceMotion) { savedConfirmation = false }"),
            "SettingsView save confirmation should respect Reduce Motion."
        )
    }

    func testAgentCommandScrollRespectsReduceMotion() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let commandViewPath = repoRoot
            .appendingPathComponent("Sources/OpenClawDashboard/Views/Agents/AgentCommandView.swift")
            .path

        let source = try String(contentsOfFile: commandViewPath, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Motion.perform(reduceMotion)") &&
            source.contains("scrollProxy.scrollTo(\"waiting\", anchor: .bottom)"),
            "AgentCommandView scroll animation should respect Reduce Motion."
        )
    }
}
