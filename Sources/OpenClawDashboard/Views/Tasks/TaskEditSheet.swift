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

                Divider().background(Theme.darkBorder)

                ScrollView {
                    VStack(spacing: 16) {
                        formSection(title: "Task Basics", subtitle: "Title and description for this task.") {
                            VStack(spacing: 12) {
                                labeledField("Title") {
                                    TextField("Task title", text: $title)
                                        .textFieldStyle(.plain)
                                        .foregroundColor(.white)
                                        .focused($focusedField, equals: .title)
                                        .padding(10)
                                        .background(inputBackground(isFocused: focusedField == .title))
                                        .overlay(inputBorder(isFocused: focusedField == .title))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }

                                labeledField("Description") {
                                    TextEditor(text: $description)
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .scrollContentBackground(.hidden)
                                        .focused($focusedField, equals: .description)
                                        .frame(minHeight: 120)
                                        .padding(8)
                                        .background(inputBackground(isFocused: focusedField == .description))
                                        .overlay(inputBorder(isFocused: focusedField == .description))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }

                        formSection(title: "Assignment", subtitle: "Who should handle this task?") {
                            labeledField("Agent") {
                                Picker("Agent", selection: $assignedAgent) {
                                    Text("Unassigned").tag("")
                                    ForEach(agentOptions.dropFirst(), id: \.self) { agent in
                                        HStack {
                                            Text(Theme.agentEmoji(for: agent))
                                            Text(agent)
                                        }
                                        .tag(agent)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(inputBackground(isFocused: false))
                                .overlay(inputBorder(isFocused: false))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }

                        formSection(title: "Priority", subtitle: "Signal urgency and focus.") {
                            Picker("Priority", selection: $priority) {
                                ForEach(TaskPriority.allCases, id: \.self) { p in
                                    HStack {
                                        Image(systemName: p.icon)
                                            .foregroundColor(p.color)
                                        Text(p.label)
                                    }
                                    .tag(p)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(Theme.jarvisBlue)
                        }

                        formSection(title: "Schedule", subtitle: "Optional time for the task.") {
                            VStack(spacing: 10) {
                                Toggle("Schedule", isOn: $hasSchedule)
                                    .toggleStyle(.switch)
                                    .tint(Theme.jarvisBlue)
                                    .foregroundColor(.white)
                                if hasSchedule {
                                    DatePicker("Date", selection: $scheduledFor, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.field)
                                        .labelsHidden()
                                        .padding(10)
                                        .background(inputBackground(isFocused: false))
                                        .overlay(inputBorder(isFocused: false))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                Divider().background(Theme.darkBorder)

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(HQButtonStyle(variant: .secondary))

                    Spacer()

                    Button(isEditing ? "Save" : "Create") {
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
                    .buttonStyle(HQButtonStyle(variant: .primary))
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
            Text(isEditing ? "Edit Task" : "New Task")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private func formSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.darkSurface.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.darkBorder.opacity(0.7), lineWidth: 1)
                )
        )
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textMuted)
            content()
        }
    }

    private func inputBackground(isFocused: Bool) -> Color {
        isFocused ? Theme.darkBackground.opacity(0.9) : Theme.darkBackground
    }

    private func inputBorder(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(isFocused ? Theme.neonCyan.opacity(0.9) : Theme.darkBorder.opacity(0.8), lineWidth: isFocused ? 1.5 : 1)
            .shadow(color: isFocused ? Theme.neonCyan.opacity(0.25) : .clear, radius: 6, x: 0, y: 0)
    }
}
