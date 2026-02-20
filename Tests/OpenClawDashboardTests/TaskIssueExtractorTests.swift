import XCTest
@testable import OpenClawDashboard

final class TaskIssueExtractorTests: XCTestCase {
    func testExtractIssuesIgnoresRemediatedBaselineRegressions() {
        let response = """
        Update complete.
        Remaining issues were baseline regressions identified and now remediated.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesKeepsUnresolvedIssueLines() {
        let response = """
        Remaining issues:
        - Regression in Tasks tab keyboard focus still failing.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first, "Regression in Tasks tab keyboard focus still failing.")
    }
}
