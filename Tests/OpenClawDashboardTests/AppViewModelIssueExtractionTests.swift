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
}
