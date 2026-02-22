import SwiftUI

struct TaskEditSheet: View {
    let task: TaskItem?
    let onSave: (String, String?, String?, TaskPriority, Date?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var assignedAgent: String = ""
    @State private var priority: TaskPriority = .medium
    @State private var hasSchedule: Bool = false
    @State private var scheduledFor: Date = Date()

    @FocusState private var focusedField: Field?

    private let agentOptions = ["", "Jarvis", "Matrix", "Prism", "Scope", "Atlas"]

    var isEditing: Bool { task != nil }

    private enum Field {
        case title
        case description
    }

    var body: some View {
        HQModalChrome {
            VStack(spacing: 0) {
                header

                Rectangle()
                    .fill(Theme.neonCyan.opacity(0.2))
                    .frame(height: 1)

                ScrollView {
                    VStack(spacing: 16) {
                        terminalFormSection(title: "TASK_BASICS", subtitle: "title and description for this task") {
                            VStack(spacing: 12) {
                                labeledField("TITLE") {
                                    TextField("TASK_TITLE", text: $title)
                                        .textFieldStyle(.plain)
                                        .foregroundColor(Theme.textPrimary)
                                        .focused($focusedField, equals: .title)
                                        .cyberpunkInput(isFocused: focusedField == .title)
                                }

                                labeledField("DESCRIPTION") {
                                    ZStack(alignment: .topLeading) {
                                        TextEditor(text: $description)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(Theme.textPrimary)
                                            .scrollContentBackground(.hidden)
                                            .focused($focusedField, equals: .description)
                                            .frame(minHeight: 120)
                                            .padding(8)
                                            .background(Theme.darkBackground)
                                    }
                                    .background(Theme.darkBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                focusedField == .description ? Theme.neonCyan.opacity(0.8) : Theme.darkBorder.opacity(0.5),
                                                lineWidth: focusedField == .description ? 1.5 : 1
                                            )
                                            .shadow(color: focusedField == .description ? Theme.neonCyan.opacity(0.2) : .clear, radius: 6)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }

                        terminalFormSection(title: "ASSIGNMENT", subtitle: "who should handle this task") {
                            labeledField("AGENT") {
                                Picker("Agent", selection: $assignedAgent) {
                                    Text("—UNASSIGNED—").tag("")
                                    ForEach(agentOptions.dropFirst(), id: \.self) { agent in
                                        HStack {
                                            Text(Theme.agentEmoji(for: agent))
                                            Text("@\(agent.lowercased())")
                                        }
                                        .tag(agent)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Theme.darkBackground)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.darkBorder.opacity(0.8), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        terminalFormSection(title: "PRIORITY", subtitle: "signal urgency and focus") {
                            Picker("Priority", selection: $priority) {
                                ForEach(TaskPriority.allCases, id: \.self) { p in
                                    HStack {
                                        Image(systemName: p.icon)
                                            .foregroundColor(p.color)
                                        Text(p.label.uppercased())
                                    }
                                    .tag(p)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(Theme.neonCyan)
                        }

                        terminalFormSection(title: "SCHEDULE", subtitle: "optional time for the task") {
                            VStack(spacing: 10) {
                                Toggle("ENABLE_SCHEDULE", isOn: $hasSchedule)
                                    .toggleStyle(.switch)
                                    .tint(Theme.neonCyan)
                                    .font(Theme.terminalFont)
                                    .foregroundColor(Theme.textSecondary)
                                if hasSchedule {
                                    DatePicker("Date", selection: $scheduledFor, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.field)
                                        .labelsHidden()
                                        .padding(8)
                                        .background(Theme.darkBackground)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.darkBorder.opacity(0.8), lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                Rectangle()
                    .fill(Theme.darkBorder.opacity(0.5))
                    .frame(height: 1)

                HStack {
                    Button("CANCEL") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(HQButtonStyle(variant: .secondary))

                    Spacer()

                    Button(isEditing ? "WRITE_CHANGES" : "CREATE_TASK") {
                        onSave(
                            title,
                            description.isEmpty ? nil : description,
                            assignedAgent.isEmpty ? nil : assignedAgent,
                            priority,
                            hasSchedule ? scheduledFor : nil
                        )
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
                    .buttonStyle(HQButtonStyle(variant: .glow))
                }
                .padding(16)
            }
            .frame(width: 520, height: 560)
        }
        .onAppear {
            if let task = task {
                title = task.title
                description = task.description ?? ""
                assignedAgent = task.assignedAgent ?? ""
                priority = task.priority
                if let scheduled = task.scheduledFor {
                    hasSchedule = true
                    scheduledFor = scheduled
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "// EDIT_TASK" : "// NEW_TASK")
                .terminalLabel()
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.darkSurface)
    }

    private func terminalFormSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("// \(title)")
                    .terminalLabel()
                Text(subtitle)
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
            }

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.darkSurface.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.darkBorder.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .tracking(1.2)
            content()
        }
    }
}
