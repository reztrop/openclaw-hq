import XCTest
@testable import OpenClawDashboard

final class AppViewModelIssueExtractionTests: XCTestCase {
    func testExtractIssuesIgnoresStandaloneTaskBlockedMarker() {
        let response = """
        Completed local checks.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresIssuePrefixedMarkerPlaceholder() {
        let response = """
        Auto-generated from findings.
        Issue: [task-blocked]
        [task-continue]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesKeepsRealBlockerText() {
        let response = """
        - Blocked: API auth token is invalid for gateway calls.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertEqual(issues, ["Blocked: API auth token is invalid for gateway calls."])
    }

    func testExtractIssuesIgnoresHostPermissionDependencyBlockers() {
        let response = """
        Issue: Compact/default/wide matrix evidence: still blocked by host permissions.
        Dependency: host-level UI automation permissions required before compact/default/wide evidence can run.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresHostPermissionMissingSignals() {
        let response = """
        Issue: Compact/default/wide matrix evidence cannot be executed because host permissions are still missing.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresHyphenatedHostPermissionBlockers() {
        let response = """
        Issue: host-permission blockers are preventing the matrix validation run.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresTruncatedHostPermissionBlockersInTaskTitles() {
        let response = """
        Task: Fix: Compact/default/wide matrix evidence is still blocked by host permissi...
        [task-start]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresPeekabooPermissionBlockers() {
        let response = """
        Task: Fix: `peekaboo permissions` ❌ still blocked:
        Issue: `peekaboo permissions` ❌ still blocked.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresPassingTestResultSummary() {
        let response = """
        Task: Fix: Result: **5 tests passed, 0 failures**
        Issue: Result: **5 tests passed, 0 failures**
        [task-start]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }
}

