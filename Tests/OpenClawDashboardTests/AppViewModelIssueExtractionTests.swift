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
        - Blocked: Screen Recording permission is not granted for Peekaboo.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertEqual(issues, ["Blocked: Screen Recording permission is not granted for Peekaboo."])
    }
}
