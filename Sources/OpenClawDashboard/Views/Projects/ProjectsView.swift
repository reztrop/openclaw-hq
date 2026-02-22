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
                    Rectangle()
                        .fill(Theme.darkBorder.opacity(0.5))
                        .frame(width: 1)
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
                        HStack(spacing: 6) {
                            Text("$")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                            Text(status)
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.textMuted)
                        }
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
                Text("// PROJECT_DOSSIER")
                    .terminalLabel()
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
            // "[ PROJECT_DOSSIER ]" header
            HStack(spacing: 4) {
                Text("[")
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan.opacity(0.6))
                Text("PROJECT_DOSSIER")
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan)
                    .glitchText()
                Text("]")
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan.opacity(0.6))
            }
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
                title: "PROJECT_NAME",
                text: Binding(
                    get: { project.title },
                    set: { projectsVM.updateProjectTitle($0) }
                ),
                onCommit: { }
            )
            Text("Edit any page before approval. Approving a page auto-saves and dispatches Jarvis + team to regenerate downstream pages up to your current progress.")
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
        }
    }

    private func projectRow(_ project: ProjectRecord) -> some View {
        let isSelected = projectsVM.selectedProjectId == project.id
        let isHovered = hoveredProjectId == project.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                // "> PROJECT_NAME" format
                HStack(spacing: 4) {
                    if isSelected {
                        Text(">")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(Theme.neonCyan)
                    }
                    Text(project.title.uppercased())
                        .font(.system(.caption, design: .monospaced).weight(isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? Theme.neonCyan : Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                HQBadge(text: project.blueprint.activeStage.rawValue, tone: .neutral)
            }
            Text(project.blueprint.overview)
                .font(Theme.terminalFontSM)
                .foregroundColor(isSelected ? Theme.textSecondary : Theme.textMuted)
                .lineLimit(2)
            Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.terminalFontSM)
                .foregroundColor(isSelected ? Theme.textMetadata : Theme.textMuted)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Theme.neonCyan.opacity(0.07) : Theme.darkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected
                                ? Theme.neonCyan.opacity(0.7)
                                : (isHovered ? Theme.darkBorder : Theme.darkBorder.opacity(0.5)),
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            hoveredProjectId = hovering ? project.id : (hoveredProjectId == project.id ? nil : hoveredProjectId)
        }
    }

    private func stageBar(_ project: ProjectRecord) -> some View {
        HStack(spacing: 8) {
            ForEach(ProductStage.allCases) { stage in
                let isActive = project.blueprint.activeStage == stage
                let isApproved = project.approvedStages.contains(stage)

                Button {
                    projectsVM.setStage(stage)
                } label: {
                    HStack(spacing: 6) {
                        if isApproved {
                            Text("[✓]")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundColor(Theme.statusOnline)
                        } else {
                            Text("[\(stage.rawValue.prefix(1))]")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(isActive ? Theme.neonCyan : Theme.textMuted)
                        }
                        Text(stage.rawValue.uppercased())
                            .font(Theme.terminalFontSM)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundColor(
                        isApproved ? Theme.statusOnline :
                        (isActive ? Theme.neonCyan : Theme.textSecondary)
                    )
                    .background(
                        isActive
                            ? Theme.neonCyan.opacity(0.1)
                            : (isApproved ? Theme.statusOnline.opacity(0.07) : Theme.darkSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isActive ? Theme.neonCyan.opacity(0.7) :
                                (isApproved ? Theme.statusOnline.opacity(0.4) : Theme.darkBorder.opacity(0.6)),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            stageCardTitle("PRODUCT", "Define scope and outcomes before team drafting starts.")
            LabeledTextEditor(
                title: "PROJECT_OVERVIEW",
                text: Binding(get: { project.blueprint.overview }, set: { projectsVM.updateOverview($0) }),
                minHeight: 110,
                onCommit: { }
            )
            HStack(spacing: 12) {
                LabeledTextEditor(
                    title: "PROBLEMS_AND_SOLUTIONS",
                    text: Binding(get: { project.blueprint.problemsText }, set: { projectsVM.updateProblems($0) }),
                    minHeight: 170,
                    onCommit: { }
                )
                LabeledTextEditor(
                    title: "KEY_FEATURES",
                    text: Binding(get: { project.blueprint.featuresText }, set: { projectsVM.updateFeatures($0) }),
                    minHeight: 170,
                    onCommit: { }
                )
            }
            HStack(spacing: 10) {
                Button("SAVE") { projectsVM.save() }
                    .buttonStyle(HQButtonStyle(variant: .secondary))
                Button(project.blueprint.activeStage.approveLabel.uppercased()) {
                    Task { await projectsVM.approveCurrentStage() }
                }
                .buttonStyle(HQButtonStyle(variant: .glow))
                .disabled(projectsVM.isApproving)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neonCyan.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionsStage(_ project: ProjectRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stageCardTitle("SECTIONS", "Team-generated section draft plus completion tracking.")
            LabeledTextEditor(
                title: "SECTIONS_DRAFT",
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
                    .tint(Theme.neonCyan)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(section.title.uppercased())
                                .font(Theme.terminalFont)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Text("@\(section.ownerAgent.lowercased())")
                                .font(Theme.terminalFontSM)
                                .foregroundColor(Theme.agentColor(for: section.ownerAgent))
                        }
                        Text(section.summary)
                            .foregroundColor(Theme.textSecondary)
                            .font(.subheadline)
                    }
                }
                .padding(12)
                .background(Theme.darkBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.darkBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 10) {
                Button("SAVE") { projectsVM.save() }
                    .buttonStyle(HQButtonStyle(variant: .secondary))
                Button(project.blueprint.activeStage.approveLabel.uppercased()) {
                    Task { await projectsVM.approveCurrentStage() }
                }
                .buttonStyle(HQButtonStyle(variant: .glow))
                .disabled(projectsVM.isApproving)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neonCyan.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func exportStage(_ project: ProjectRecord) -> some View {
        let markdown = projectsVM.exportMarkdown()
        return VStack(alignment: .leading, spacing: 14) {
            stageCardTitle("EXPORT", "Final package and rollout notes.")
            LabeledTextEditor(
                title: "EXPORT_NOTES",
                text: Binding(get: { project.blueprint.exportNotes }, set: { projectsVM.updateExportNotes($0) }),
                minHeight: 140,
                onCommit: { }
            )
            Text(markdown)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.terminalGreen)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.darkBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.neonCyan.opacity(0.2), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 10) {
                Button("SAVE") { projectsVM.save() }
                    .buttonStyle(HQButtonStyle(variant: .secondary))
                Button("SAVE_AS") {
                    saveExportAs(projectName: project.title, markdown: markdown)
                }
                .buttonStyle(HQButtonStyle(variant: .secondary))
                Button("EXECUTE") {
                    Task { await projectsVM.executeCurrentProjectPlan() }
                }
                .buttonStyle(HQButtonStyle(variant: .glow))
                .disabled(projectsVM.isApproving)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neonCyan.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            stageCardTitle(title.uppercased(), subtitle)
            LabeledTextEditor(title: title.uppercased(), text: value, minHeight: 280, onCommit: { })
            HStack(spacing: 10) {
                Button("SAVE") { saveAction() }
                    .buttonStyle(HQButtonStyle(variant: .secondary))
                Button(approveLabel.uppercased()) { approveAction() }
                    .buttonStyle(HQButtonStyle(variant: .glow))
                    .disabled(isApproving)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.neonCyan.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stageCardTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("// \(title)")
                .terminalLabel()
            Text(subtitle)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
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
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .tracking(1.2)
            TextField("", text: $text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .foregroundColor(Theme.textPrimary)
                .focused($isFocused)
                .cyberpunkInput(isFocused: isFocused)
        }
    }
}

private struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat
    var onCommit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.terminalFontSM)
                .foregroundColor(Theme.textMuted)
                .tracking(1.2)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(8)
                .frame(minHeight: minHeight)
                .background(Theme.darkBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isFocused ? Theme.neonCyan.opacity(0.7) : Theme.darkBorder.opacity(0.6),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                        .shadow(color: isFocused ? Theme.neonCyan.opacity(0.2) : .clear, radius: 6)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .tint(Theme.neonCyan)
                .onChange(of: text) { _, _ in onCommit() }
        }
    }
}
