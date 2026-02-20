import Foundation

enum TaskIssueExtractor {
    static func extractIssues(from response: String) -> [String] {
        let contentLines = response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !containsTaskMarkerInstruction($0.lowercased()) }

        let contentOnly = contentLines.joined(separator: "\n")
        let lower = contentOnly.lowercased()
        if lower.contains("no fix required") && !containsIssueSignal(lower) {
            return []
        }

        var issues: [String] = []
        for rawLine in contentLines {
            var line = rawLine

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let dotRange = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                line.removeSubrange(dotRange)
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let lowered = line.lowercased()
            let strippedIssuePrefix = lowered.replacingOccurrences(of: #"^issue:\s*"#, with: "", options: .regularExpression)
            guard !isTaskOutcomeMarker(strippedIssuePrefix) else { continue }
            guard containsIssueSignal(lowered) else { continue }
            guard !isIssueNegated(lowered) else { continue }
            guard !isIssueHeading(lowered) else { continue }
            guard !isIssueResolvedSignal(lowered) else { continue }
            guard !TaskIssueExtractor.isPassingStatusSignal(lowered) else { continue }
            guard !isVerificationStatusSignal(lowered) else { continue }
            guard !isExternalDependencySignal(lowered) else { continue }
            if line.count < 12 { continue }
            issues.append(line)
        }

        if issues.isEmpty && containsIssueSignal(lower) && !isIssueNegated(lower) && !isIssueResolvedSignal(lower) && !TaskIssueExtractor.isPassingStatusSignal(lower) && !isVerificationStatusSignal(lower) && !isExternalDependencySignal(lower) {
            let summary = contentOnly
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                issues.append(String(summary.prefix(240)))
            }
        }

        return Array(NSOrderedSet(array: issues)) as? [String] ?? issues
    }

    static func isTaskOutcomeMarker(_ text: String) -> Bool {
        let marker = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return marker == "[task-complete]" || marker == "[task-blocked]" || marker == "[task-continue]"
    }

    static func containsTaskMarkerInstruction(_ text: String) -> Bool {
        if isTaskOutcomeMarker(text) { return true }
        if text.contains("[task-complete]") || text.contains("[task-blocked]") || text.contains("[task-continue]") {
            return true
        }
        return false
    }

    static func containsIssueSignal(_ text: String) -> Bool {
        let signals = [
            "issue", "bug", "error", "fail", "failing", "regression", "problem",
            "risk", "gap", "missing", "blocked", "constraint", "violation"
        ]
        return signals.contains { text.contains($0) }
    }

    static func isIssueNegated(_ text: String) -> Bool {
        let negations = [
            "no issue", "no issues", "no bug", "no bugs", "no error", "no errors",
            "no regression", "no regressions", "no fix required", "nothing to fix"
        ]
        return negations.contains { text.contains($0) }
    }

    static func isIssueHeading(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let headingPatterns = [
            "issues:", "issue:", "remaining issues:", "known issues:", "open issues:"
        ]
        return headingPatterns.contains(normalized)
    }

    static func isIssueResolvedSignal(_ text: String) -> Bool {
        let resolutionSignals = [
            "resolved", "remediated", "fixed", "addressed", "completed", "closed"
        ]
        let issueAnchors = ["issue", "issues", "regression", "regressions", "bug", "error", "failure", "problem"]
        let hasResolution = resolutionSignals.contains { text.contains($0) }
        let hasIssueAnchor = issueAnchors.contains { text.contains($0) }
        return hasResolution && hasIssueAnchor
    }

    static func isPassingStatusSignal(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.range(of: #"^(pass|passed|ok|success)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if normalized.range(of: #"\((pass|passed|ok|success)\)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if normalized.range(of: #"\b\d+\s+tests?\s+passed\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            if normalized.range(of: #"\b0\s+fail(?:ed|ures?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        let passingSignals = [
            "all checks passed",
            "no regressions found"
        ]
        return passingSignals.contains { normalized.contains($0) }
    }

    static func isVerificationStatusSignal(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedIssuePrefix = normalized.replacingOccurrences(of: #"^issue:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])

        let hasCheckPrefix = normalized.hasPrefix("checked ") || normalized.hasPrefix("check: ")
        let hasConfirmation = normalized.contains("confirmed")
        let confirmsExistingPath = normalized.contains("already exists") || normalized.contains("exists in")
        let confirmsServiceBoundary = normalized.contains("remains in") || normalized.contains("delegation path")

        if hasCheckPrefix && hasConfirmation && (confirmsExistingPath || confirmsServiceBoundary) {
            return true
        }

        let confirmsRegressionEvidenceCommitPresence = strippedIssuePrefix.contains("confirmed")
            && strippedIssuePrefix.contains("regression evidence commit")
            && (strippedIssuePrefix.contains("is present") || strippedIssuePrefix.contains("already present"))

        let hasCommitHash = strippedIssuePrefix.range(of: #"\b[0-9a-f]{7,40}\b"#, options: .regularExpression) != nil
        let isSatisfiedRegressionIssueLine = hasCommitHash
            && strippedIssuePrefix.contains("single-active-task")
            && strippedIssuePrefix.contains("regression tests")
            && (strippedIssuePrefix.contains("✅") || strippedIssuePrefix.contains("pass") || strippedIssuePrefix.contains("passed") || strippedIssuePrefix.contains("complete") || strippedIssuePrefix.contains("completed"))

        return confirmsRegressionEvidenceCommitPresence || isSatisfiedRegressionIssueLine
    }

    static func isExternalDependencySignal(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let externalSignals = [
            "blocked by host permission",
            "blocked by host permissions",
            "host level ui automation permissions",
            "host-level ui automation permissions",
            "dependency: host level",
            "screen recording permission",
            "screen recording not granted",
            "accessibility permission",
            "accessibility not granted",
            "peekaboo permission",
            "peekaboo permissions"
        ]

        if externalSignals.contains(where: { normalized.contains($0) }) {
            return true
        }

        let hasHostPermissionStem = normalized.contains("host permission")
            || normalized.contains("host permissions")
            || normalized.contains("host permiss")

        let hasHostLevelUiAutomationPermission = normalized.contains("host level")
            && normalized.contains("ui automation")
            && normalized.contains("permission")

        let missingHostPermission = hasHostPermissionStem && normalized.contains("missing")
        let hostPermissionBlocker = hasHostPermissionStem && normalized.contains("blocker")
        let blockedByHostPermission = hasHostPermissionStem && normalized.contains("blocked")
        let requiredHostPermission = hasHostPermissionStem && normalized.contains("required")

        return missingHostPermission
            || hostPermissionBlocker
            || blockedByHostPermission
            || requiredHostPermission
            || hasHostLevelUiAutomationPermission
    }
}
