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
            guard !isExternalDependencySignal(lowered) else { continue }
            if line.count < 12 { continue }
            issues.append(line)
        }

        if issues.isEmpty && containsIssueSignal(lower) && !isIssueNegated(lower) && !isExternalDependencySignal(lower) {
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

    static func isExternalDependencySignal(_ text: String) -> Bool {
        let externalSignals = [
            "blocked by host permission",
            "blocked by host permissions",
            "host-level ui automation permissions required",
            "dependency: host-level",
            "screen recording permission",
            "accessibility permission"
        ]
        return externalSignals.contains { text.contains($0) }
    }
}
