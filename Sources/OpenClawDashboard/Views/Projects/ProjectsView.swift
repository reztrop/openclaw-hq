import SwiftUI
import AppKit

struct ProjectsView: View {
    @EnvironmentObject var projectsVM: ProjectsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stageBar
                stageContent
                if let status = projectsVM.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 2)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Theme.darkBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Plan and drive end-to-end execution across Jarvis, Scope, Atlas, Matrix, and Prism.")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var stageBar: some View {
        HStack(spacing: 10) {
            ForEach(ProductStage.allCases) { stage in
                Button {
                    projectsVM.setStage(stage)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: stage.icon)
                        Text(stage.rawValue)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(projectsVM.blueprint.activeStage == stage ? .black : Theme.textSecondary)
                    .background(projectsVM.blueprint.activeStage == stage ? Theme.jarvisBlue : Theme.darkSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.darkBorder, lineWidth: projectsVM.blueprint.activeStage == stage ? 0 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch projectsVM.blueprint.activeStage {
        case .product:
            productStage
        case .dataModel:
            textStage(title: "Data Model", subtitle: "Define core entities and relationships.", text: binding(\.dataModelText))
        case .design:
            textStage(title: "Design", subtitle: "Capture visual/system rules and shell behavior.", text: binding(\.designText))
        case .sections:
            sectionsStage
        case .export:
            exportStage
        }
    }

    private var productStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            stageCardTitle("Product Definition", "Define project vision and delivery scope.")
            LabeledTextField(title: "Project Name", text: binding(\.projectName), onCommit: projectsVM.save)
            LabeledTextEditor(title: "Project Overview", text: binding(\.overview), minHeight: 100, onCommit: projectsVM.save)
            HStack(spacing: 12) {
                LabeledTextEditor(title: "Problems & Solutions", text: binding(\.problemsText), minHeight: 150, onCommit: projectsVM.save)
                LabeledTextEditor(title: "Key Features", text: binding(\.featuresText), minHeight: 150, onCommit: projectsVM.save)
            }
            HStack(spacing: 10) {
                Button("Save Plan") { projectsVM.save() }
                    .buttonStyle(.bordered)
                Button("Generate Tasks") { projectsVM.generateTaskPlan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func textStage(title: String, subtitle: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stageCardTitle(title, subtitle)
            LabeledTextEditor(title: title, text: text, minHeight: 260, onCommit: projectsVM.save)
            Button("Save \(title)") { projectsVM.save() }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var sectionsStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            stageCardTitle("Sections", "Assign ownership and track completion.")
            ForEach(projectsVM.blueprint.sections) { section in
                HStack(alignment: .top, spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { section.completed },
                        set: { projectsVM.setSectionCompletion(section.id, completed: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(section.title)
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Text(section.ownerAgent)
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.darkBackground)
                                .clipShape(Capsule())
                        }
                        Text(section.summary)
                            .foregroundColor(Theme.textSecondary)
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .background(Theme.darkBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button("Generate Tasks from Sections") { projectsVM.generateTaskPlan() }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var exportStage: some View {
        let markdown = projectsVM.exportMarkdown()
        return VStack(alignment: .leading, spacing: 14) {
            stageCardTitle("Export", "Copy project blueprint for sharing or downstream execution.")
            Text(markdown)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.darkBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                Button("Copy Markdown") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(markdown, forType: .string)
                    projectsVM.statusMessage = "Export copied to clipboard."
                }
                .buttonStyle(.borderedProminent)
                Button("Save") { projectsVM.save() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stageCardTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(.white)
            Text(subtitle)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ProductBlueprint, String>) -> Binding<String> {
        Binding(
            get: { projectsVM.blueprint[keyPath: keyPath] },
            set: {
                projectsVM.blueprint[keyPath: keyPath] = $0
            }
        )
    }
}

private struct LabeledTextField: View {
    let title: String
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundColor(Theme.textMuted)
                .font(.caption)
            TextField("", text: $text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Theme.darkBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.darkBorder, lineWidth: 1))
                .foregroundColor(.white)
        }
    }
}

private struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundColor(Theme.textMuted)
                .font(.caption)
            TextEditor(text: $text)
                .font(.body)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: minHeight)
                .background(Theme.darkBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.darkBorder, lineWidth: 1))
                .onChange(of: text) { _, _ in onCommit() }
        }
    }
}
