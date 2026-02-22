import SwiftUI

struct TaskDetailSheet: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HQModalChrome {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Text("// TASK_DETAIL")
                        .terminalLabel()
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                sectionDivider("METADATA")

                detailRow("TITLE", task.title)
                detailRow("STATUS", task.status.columnTitle.uppercased())
                detailRow("PRIORITY", task.priority.label.uppercased())
                detailRow("AGENT", task.assignedAgent.map { "@\($0.lowercased())" } ?? "—UNASSIGNED—")
                detailRow("PROJECT", task.projectName ?? "—NONE—")
                detailRow("CREATED", task.createdAt.shortString)
                detailRow("UPDATED", task.updatedAt.shortString)

                if let scheduled = task.scheduledFor {
                    detailRow("SCHEDULED", scheduled.shortString)
                }
                if let completed = task.completedAt {
                    detailRow("COMPLETED", completed.shortString)
                }
                if let evidenceAt = task.lastEvidenceAt {
                    detailRow("LAST_ACTIVITY", evidenceAt.shortString)
                }
                if let sessionKey = task.executionSessionKey, !sessionKey.isEmpty {
                    detailRow("SESSION_KEY", sessionKey)
                }

                if let desc = task.description, !desc.isEmpty {
                    sectionDivider("DESCRIPTION")
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView {
                            Text(desc)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                        .padding(10)
                        .background(Theme.darkSurface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.darkBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                if let evidence = task.lastEvidence, !evidence.isEmpty {
                    sectionDivider("EXECUTION_EVIDENCE")
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView {
                            Text(evidence)
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.neonCyan.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                        .padding(10)
                        .background(Theme.darkSurface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.neonCyan.opacity(0.25), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                Spacer()
            }
            .padding(16)
            .frame(width: 520, height: 520)
        }
    }

    private func sectionDivider(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text("──")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Theme.darkBorder)
            Text(label)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .tracking(1.2)
            Rectangle()
                .fill(Theme.darkBorder.opacity(0.5))
                .frame(height: 1)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .terminalLabel(color: Theme.textMuted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
            Spacer()
        }
    }
}
