import SwiftUI

struct TaskDetailSheet: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HQModalChrome {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Task Details")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                detailRow("Title", task.title)
                detailRow("Status", task.status.columnTitle)
                detailRow("Priority", task.priority.label)
                detailRow("Agent", task.assignedAgent ?? "Unassigned")
                detailRow("Project", task.projectName ?? "None")
                detailRow("Created", task.createdAt.shortString)
                detailRow("Updated", task.updatedAt.shortString)
                if let scheduled = task.scheduledFor {
                    detailRow("Scheduled", scheduled.shortString)
                }
                if let completed = task.completedAt {
                    detailRow("Completed", completed.shortString)
                }
                if let evidenceAt = task.lastEvidenceAt {
                    detailRow("Last Activity", evidenceAt.shortString)
                }
                if let sessionKey = task.executionSessionKey, !sessionKey.isEmpty {
                    detailRow("Session Key", sessionKey)
                }

                if let desc = task.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        ScrollView {
                            Text(desc)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                        .padding(10)
                        .background(Theme.darkSurface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.darkBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                if let evidence = task.lastEvidence, !evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Execution Evidence")
                            .font(.caption)
                            .foregroundColor(Theme.neonCyan.opacity(0.95))
                        ScrollView {
                            Text(evidence)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                        .padding(10)
                        .background(Theme.darkSurface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.darkBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                Spacer()
            }
            .padding(16)
            .frame(width: 520, height: 520)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .foregroundColor(.white)
            Spacer()
        }
    }
}
