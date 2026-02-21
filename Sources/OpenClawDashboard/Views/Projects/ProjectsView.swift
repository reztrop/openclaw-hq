import SwiftUI
import AppKit

struct ProjectsView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var projectsVM: ProjectsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSidebarCollapsed = false
    @State private var hoveredProjectId: String?

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if !isSidebarCollapsed {
                    Divider().background(Theme.darkBorder)
                    sidebar
                        .frame(width: 320)
                        .background(
                            ZStack {
                                Theme.darkSurface.opacity(0.7)
                                Rectangle()
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.12)
                            }
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .onAppear {
                if geo.size.width < 1180 {
                    isSidebarCollapsed = true
                }
                enforceSidebarRules()
            }
            .onChange(of: geo.size.width) { _, newWidth in
                if newWidth < 980 {
                    isSidebarCollapsed = true
                }
                enforceSidebarRules()
            }
            .onChange(of: isSidebarCollapsed) { _, _ in
                enforceSidebarRules()
            }
            .onChange(of: appViewModel.isMainSidebarCollapsed) { _, _ in
                enforceSidebarRules()
            }
            .onChange(of: appViewModel.isCompactWindow) { _, _ in
                enforceSidebarRules()
            }
        }
        .background(Theme.darkBackground)
    }

    @ViewBuilder
    private var detail: some View {
        if let project = projectsVM.selectedProject {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailHeader(project)
                    stageBar(project)
                    stageContent(project)
                    if let status = projectsVM.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 12) {
                topBar
                Spacer()
                EmptyStateView(
                    icon: "tray.2",
                    title: "No projects yet",
                    subtitle: "Use Chat → Start Project Planning, then work with Jarvis. A project appears here once Jarvis confirms scope is ready.",
                    maxWidth: 680,
                    iconSize: 36,
                    showPanel: true
                )
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Projects")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }

            if projectsVM.projects.isEmpty {
                EmptyStateView(
                    icon: "tray.2",
                    title: "No projects yet",
                    subtitle: "Projects are created automatically when Jarvis confirms planning scope is ready.",
                    alignment: .leading,
                    textAlignment: .leading,
                    maxWidth: .infinity,
                    iconSize: 20,
                    contentPadding: 12,
                    showPanel: true
                )
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(projectsVM.projects) { project in
                        HStack(spacing: 6) {
                            Button {
                                projectsVM.selectProject(project.id)
                            } label: {
                                projectRow(project)
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button(role: .destructive) {
                                    projectsVM.deleteProject(project.id)
                                } label: {
                                    Label("Delete Project", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundColor(Theme.textMuted)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    private func topBarTitle(_ project: ProjectRecord?) -> String {
        project?.title ?? "Projects"
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(topBarTitle(projectsVM.selectedProject))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            Button {
                if reduceMotion {
                    isSidebarCollapsed.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarCollapsed.toggle()
                    }
                }
            } label: {
                Label(isSidebarCollapsed ? "Show Projects" : "Hide Projects",
                      systemImage: isSidebarCollapsed ? "sidebar.right" : "sidebar.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(HQButtonStyle(variant: .secondary))
            .help(isSidebarCollapsed ? "Show Projects" : "Hide Projects")
        }
    }

    private func detailHeader(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            topBar
            LabeledTextField(
                title: "Project Name",
                text: Binding(
                    get: { project.title },
                    set: { projectsVM.updateProjectTitle($0) }
                ),
                onCommit: { }
            )
            Text("Edit any page before approval. Approving a page auto-saves and dispatches Jarvis + team to regenerate downstream pages up to your current progress.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func projectRow(_ project: ProjectRecord) -> some View {
        let isSelected = projectsVM.selectedProjectId == project.id
        let isHovered = hoveredProjectId == project.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(project.title)
                    .font(.headline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                HQBadge(text: project.blueprint.activeStage.rawValue, tone: .neutral)
            }
            Text(project.blueprint.overview)
                .font(.caption)
                .foregroundColor(isSelected ? Theme.textSecondary : Theme.textMuted)
                .lineLimit(2)
            Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(isSelected ? Theme.textMetadata : Theme.textMuted)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Theme.darkAccent : Theme.darkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                                ? Theme.neonCyan.opacity(0.9)
                                : (isHovered ? Theme.darkBorder : Theme.darkBorder.opacity(0.6)),
                            lineWidth: isSelected ? 1.2 : 1
                        )
                )
                .shadow(color: isSelected ? Theme.neonCyan.opacity(0.12) : .clear, radius: 10)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.neonCyan)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            hoveredProjectId = hovering ? project.id : (hoveredProjectId == project.id ? nil : hoveredProjectId)
        }
    }

    private func stageBar(_ project: ProjectRecord) -> some View {
        HStack(spacing: 10) {
            ForEach(ProductStage.allCases) { stage in
                Button {
                    projectsVM.setStage(stage)
                } label: {
                    HStack(spacing: 8) {
                        if project.approvedStages.contains(stage) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.statusOnline)
                        } else {
                            Image(systemName: stage.icon)
                        }
                        Text(stage.rawValue)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(project.blueprint.activeStage == stage ? .black : Theme.textSecondary)
                    .background(project.blueprint.activeStage == stage ? Theme.jarvisBlue : Theme.darkSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.darkBorder, lineWidth: project.blueprint.activeStage == stage ? 0 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func stageContent(_ project: ProjectRecord) -> some View {
        switch project.blueprint.activeStage {
        case .product:
            productStage(project)
        case .dataModel:
            singleTextStage(
                title: "Data Model",
                subtitle: "Team draft generated after Product approval. Edit, save, then approve.",
                value: Binding(
                    get: { project.blueprint.dataModelText },
                    set: { projectsVM.updateDataModel($0) }
                ),
                saveAction: { projectsVM.save() },
                approveAction: { Task { await projectsVM.approveCurrentStage() } },
                approveLabel: project.blueprint.activeStage.approveLabel,
                isApproving: projectsVM.isApproving
            )
        case .design:
            singleTextStage(
                title: "Design",
                subtitle: "System and UI draft generated after Data Model approval.",
                value: Binding(
                    get: { project.blueprint.designText },
                    set: { projectsVM.updateDesign($0) }
                ),
                saveAction: { projectsVM.save() },
                approveAction: { Task { await projectsVM.approveCurrentStage() } },
                approveLabel: project.blueprint.activeStage.approveLabel,
                isApproving: projectsVM.isApproving
            )
        case .sections:
            sectionsStage(project)
        case .export:
            exportStage(project)
        }
    }

    private func productStage(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stageCardTitle("Product", "Define scope and outcomes before team drafting starts.")
            LabeledTextEditor(
                title: "Project Overview",
                text: Binding(get: { project.blueprint.overview }, set: { projectsVM.updateOverview($0) }),
                minHeight: 110,
                onCommit: { }
            )
            HStack(spacing: 12) {
                LabeledTextEditor(
                    title: "Problems & Solutions",
                    text: Binding(get: { project.blueprint.problemsText }, set: { projectsVM.updateProblems($0) }),
                    minHeight: 170,
                    onCommit: { }
                )
                LabeledTextEditor(
                    title: "Key Features",
                    text: Binding(get: { project.blueprint.featuresText }, set: { projectsVM.updateFeatures($0) }),
                    minHeight: 170,
                    onCommit: { }
                )
            }
            HStack(spacing: 10) {
                Button("Save") { projectsVM.save() }
                    .buttonStyle(.bordered)
                Button(project.blueprint.activeStage.approveLabel) {
                    Task { await projectsVM.approveCurrentStage() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectsVM.isApproving)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sectionsStage(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stageCardTitle("Sections", "Team-generated section draft plus completion tracking.")
            LabeledTextEditor(
                title: "Sections Draft",
                text: Binding(get: { project.blueprint.sectionsDraftText }, set: { projectsVM.updateSectionsDraft($0) }),
                minHeight: 180,
                onCommit: { }
            )

            ForEach(project.blueprint.sections) { section in
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

            HStack(spacing: 10) {
                Button("Save") { projectsVM.save() }
                    .buttonStyle(.bordered)
                Button(project.blueprint.activeStage.approveLabel) {
                    Task { await projectsVM.approveCurrentStage() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectsVM.isApproving)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func exportStage(_ project: ProjectRecord) -> some View {
        let markdown = projectsVM.exportMarkdown()
        return VStack(alignment: .leading, spacing: 14) {
            stageCardTitle("Export", "Final package and rollout notes.")
            LabeledTextEditor(
                title: "Export Notes",
                text: Binding(get: { project.blueprint.exportNotes }, set: { projectsVM.updateExportNotes($0) }),
                minHeight: 140,
                onCommit: { }
            )
            Text(markdown)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.darkBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                Button("Save") { projectsVM.save() }
                    .buttonStyle(.bordered)
                Button("Save As") {
                    saveExportAs(projectName: project.title, markdown: markdown)
                }
                .buttonStyle(.borderedProminent)
                Button("Execute") {
                    Task { await projectsVM.executeCurrentProjectPlan() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectsVM.isApproving)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func singleTextStage(
        title: String,
        subtitle: String,
        value: Binding<String>,
        saveAction: @escaping () -> Void,
        approveAction: @escaping () -> Void,
        approveLabel: String,
        isApproving: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stageCardTitle(title, subtitle)
            LabeledTextEditor(title: title, text: value, minHeight: 280, onCommit: { })
            HStack(spacing: 10) {
                Button("Save") { saveAction() }
                    .buttonStyle(.bordered)
                Button(approveLabel) { approveAction() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApproving)
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

    private func enforceSidebarRules() {
        guard appViewModel.isCompactWindow else { return }

        if !isSidebarCollapsed {
            if !appViewModel.isMainSidebarCollapsed {
                appViewModel.isMainSidebarCollapsed = true
            }
        } else if appViewModel.isMainSidebarCollapsed {
            appViewModel.isMainSidebarCollapsed = false
        }
    }

    private func saveExportAs(projectName: String, markdown: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(projectName.replacingOccurrences(of: " ", with: "_"))-plan.md"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                projectsVM.statusMessage = "Saved project plan to \(url.path)."
            } catch {
                projectsVM.statusMessage = "Failed to save file: \(error.localizedDescription)"
            }
        }
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
