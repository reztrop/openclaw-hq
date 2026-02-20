import XCTest
@testable import OpenClawDashboard

final class TaskIssueExtractorTests: XCTestCase {
    func testTaskOutcomeMarkerRequiresExactBracketMarker() {
        XCTAssertFalse(TaskIssueExtractor.isTaskOutcomeMarker("status: complete"))
        XCTAssertFalse(TaskIssueExtractor.isTaskOutcomeMarker("status: blocked"))
        XCTAssertFalse(TaskIssueExtractor.isTaskOutcomeMarker("status: continue"))
        XCTAssertFalse(TaskIssueExtractor.isTaskOutcomeMarker("done"))
        XCTAssertFalse(TaskIssueExtractor.isTaskOutcomeMarker("completed"))

        XCTAssertTrue(TaskIssueExtractor.isTaskOutcomeMarker("[task-complete]"))
        XCTAssertTrue(TaskIssueExtractor.isTaskOutcomeMarker("[task-blocked]"))
        XCTAssertTrue(TaskIssueExtractor.isTaskOutcomeMarker("[task-continue]"))
    }

    func testTaskMarkerInstructionDetectionDoesNotUseFuzzyFallbacks() {
        XCTAssertFalse(TaskIssueExtractor.containsTaskMarkerInstruction("status: complete"))
        XCTAssertFalse(TaskIssueExtractor.containsTaskMarkerInstruction("status: blocked"))
        XCTAssertFalse(TaskIssueExtractor.containsTaskMarkerInstruction("status: continue"))
        XCTAssertFalse(TaskIssueExtractor.containsTaskMarkerInstruction("done"))
        XCTAssertFalse(TaskIssueExtractor.containsTaskMarkerInstruction("completed"))

        XCTAssertTrue(TaskIssueExtractor.containsTaskMarkerInstruction("end with [task-complete]"))
    }

    func testExtractIssuesIgnoresRemediatedBaselineRegressions() {
        let response = """
        Update complete.
        Remaining issues were baseline regressions identified and now remediated.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresExpectedNoExtractedIssuesLine() {
        let response = """
        Expected: no extracted issues.
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

    func testExtractIssuesIgnoresPassingRegressionCheckStatus() {
        let response = """
        PASS: task-1300 regression checks complete
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresPassingRegressionCheckStatusWithDashDelimiter() {
        let response = """
        PASS - task-1300 regression checks complete with keyboard trap issue in model picker
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresPassingRegressionPreventionValidationStatus() {
        let response = """
        task-1300 regression-prevention validation passed successfully
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAddedRegressionChecksLine() {
        let response = """
        Added regression checks for the Tasks tab.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAddedRegressionHardeningCheckLine() {
        let response = """
        Issue: Added regression-hardening check to validator:
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAddedRegressionTestAboveLine() {
        let response = """
        Issue: Added regression test above
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAddedTargetedRegressionTestsLine() {
        let response = """
        Issue: Added targeted regression tests in:
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresIssuePrefixedAddedRegressionChecksLine() {
        let response = """
        Issue: Added regression checks for the Tasks tab.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAddedModeRegressionCoverageLine() {
        let response = """
        Issue: Added `--mode local|live|both` so drift/regressions are caught against runtime bundles.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAddedRegressionCoverageFalsePositiveLine() {
        let response = """
        Issue: Added regression coverage for this exact class of false-positive:
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAddedStrongerRegressionCoverageValidatorLine() {
        let response = """
        Issue: Added stronger regression coverage in the validator:
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresRemediatedOutcomeParserRiskLine() {
        let response = """
        Issue: 2) Outcome parser false-complete risk — PASS (remediated)
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesKeepsFailingRegressionStatus() {
        let response = """
        FAIL: task-1300 regression checks complete with keyboard trap issue in model picker
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first, "FAIL: task-1300 regression checks complete with keyboard trap issue in model picker")
    }

    func testExtractIssuesKeepsFailingRegressionPreventionValidationStatus() {
        let response = """
        task-1300 regression-prevention validation failed on task marker parsing
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first, "task-1300 regression-prevention validation failed on task marker parsing")
    }

    func testExtractIssuesIgnoresPassingRegressionEvidenceStatus() {
        let response = """
        EV-1300-001 (PASS): task-1300 regression checks complete
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesKeepsFailingRegressionEvidenceStatus() {
        let response = """
        EV-1300-002 (FAIL): task-1300 regression checks complete with keyboard trap issue in model picker
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first, "EV-1300-002 (FAIL): task-1300 regression checks complete with keyboard trap issue in model picker")
    }

    func testExtractIssuesIgnoresCheckedAndConfirmedDelegationStatus() {
        let response = """
        Checked for prior partial progress first (`git status` clean) and confirmed the recurring-issue delegation path already exists in AppViewModel and service orchestration remains in TaskInterventionService.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresConfirmedSingleActiveTaskRegressionEvidenceCommitPresence() {
        let response = """
        Issue: Confirmed single-active-task regression evidence commit is present:
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresConfirmedFixPresenceLine() {
        let response = """
        Issue: Confirmed issue `4084772` (Task 1300) fix is present in `TaskIssueExtractor`.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresExistingFixPresenceLine() {
        let response = """
        Issue: Existing fix present in `Sources/OpenClawDashboard/Utils/TaskIssueExtractor.swift`.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresDeltaCommitAlreadyPresentLine() {
        let response = """
        Issue: Delta commit already present: `c428407` — “Ignore hyphenated host-permission blocker issues”
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresSatisfiedSingleActiveTaskRegressionIssueLine() {
        let response = """
        Issue: `574e168` single-active-task regression tests ✅
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresAlreadyFixedAndValidatedIssueLine() {
        let response = """
        Issue: Resumed from prior partial progress: this issue has already been fixed in the repo and validated.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesIgnoresRemediatedPriorProgressFindingLine() {
        let response = """
        Checked existing progress first: this issue was already remediated in prior commits (`161355f`, parser marker hardening), so I continued from that state by adding a targeted regression guard for this exact finding text.
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertTrue(issues.isEmpty)
    }

    func testExtractIssuesKeepsResolvedIssueClassificationBugLine() {
        let response = """
        Issue: Resolved issue classification bug
        """

        let issues = TaskIssueExtractor.extractIssues(from: response)

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first, "Issue: Resolved issue classification bug")
    }
}
