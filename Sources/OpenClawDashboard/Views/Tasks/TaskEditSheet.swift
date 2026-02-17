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

    private let agentOptions = ["", "Jarvis", "Matrix", "Prism", "Scope", "Atlas"]

    var isEditing: Bool { task != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            .padding()

            Divider().background(Theme.darkBorder)

            // Form
            Form {
                Section {
                    TextField("Task title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(height: 80)
                        .font(.body)
                }

                Section("Assignment") {
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
                }

                Section("Priority") {
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
                }

                Section {
                    Toggle("Schedule", isOn: $hasSchedule)
                    if hasSchedule {
                        DatePicker("Date", selection: $scheduledFor, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .formStyle(.grouped)

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
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
                .buttonStyle(.borderedProminent)
                .tint(Theme.jarvisBlue)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
        .background(Theme.darkBackground)
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
}
