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

    func testExtractIssuesIgnoresHostPermissionMissingSequence() {
        let response = """
        Issue: host permissions remain missing for the evidence capture.
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

    func testExtractIssuesIgnoresHostLevelUiAutomationDependencyNarrative() {
        let response = """
        Issue: Matrix remediation branch has new commits, but this specific evidence-matrix task remains blocked on host-level UI automation permissions before compact/default/wide tab verification can be executed and evidenced.
        Dependency: requires host UI automation permission grant before evidence run.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresPeekabooNotGrantedPermissionDetails() {
        let response = """
        Issue: Hard blocker remains unchanged: host-level UI automation permissions are still missing (`peekaboo`: Screen Recording Not Granted, Accessibility Not Granted), so compact/default/wide tab evidence capture cannot execute.
        Dependency: host-level UI automation permissions must be granted before matrix capture.
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresScreenRecordingNotGrantedWithCheckmarkPrefix() {
        let response = """
        Issue: ✅ Screen Recording Not Granted
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAccessibilityNotGrantedWithCheckmarkPrefix() {
        let response = """
        Issue: ✅ Accessibility Not Granted
        [task-blocked]
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)
        XCTAssertTrue(issues.isEmpty)
    }
}

