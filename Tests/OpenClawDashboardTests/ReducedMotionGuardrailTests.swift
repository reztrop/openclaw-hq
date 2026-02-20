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
}
