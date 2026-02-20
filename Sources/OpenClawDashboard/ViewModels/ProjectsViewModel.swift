import Foundation

@MainActor
class ProjectsViewModel: ObservableObject {
    @Published var projects: [ProjectRecord] = []
    @Published var selectedProjectId: String?
    @Published var statusMessage: String?
    @Published var isApproving = false

    private let filePath: String
    private let gatewayService: GatewayService
    private let taskService: TaskService
    private let workflowService: ProjectWorkflowService
    private var pendingPlanningByConversation: [String: PendingProjectPlanning] = [:]
    private let isExecutionAutomationEnabled = false

    init(gatewayService: GatewayService, taskService: TaskService, filePath: String = Constants.projectsFilePath) {
        self.gatewayService = gatewayService
        self.taskService = taskService
        self.workflowService = ProjectWorkflowService(taskService: taskService, gatewayService: gatewayService)
        self.filePath = filePath
        load()
    }

    var selectedProject: ProjectRecord? {
        guard let id = selectedProjectId else { return nil }
        return projects.first(where: { $0.id == id })
    }

    var hasProjects: Bool { !projects.isEmpty }

    func load() {
        guard FileManager.default.fileExists(atPath: filePath) else {
            projects = []
            selectedProjectId = nil
            pendingPlanningByConversation = [:]
            save()
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let state = try? decoder.decode(ProjectsStateFile.self, from: data) {
                projects = state.projects.sorted(by: { $0.updatedAt > $1.updatedAt })
                selectedProjectId = state.selectedProjectId ?? projects.first?.id
                pendingPlanningByConversation = Dictionary(uniqueKeysWithValues: state.pendingPlanning.map { ($0.conversationId, $0) })
                return
            }

            if let legacy = try? decoder.decode(ProductBlueprint.self, from: data) {
                let fallbackTitle = legacy.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Recovered Project"
                    : legacy.projectName
                let recovered = ProjectRecord(
                    id: UUID().uuidString,
                    title: fallbackTitle,
                    conversationId: nil,
                    createdAt: Date(),
                    updatedAt: Date(),
                    approvedStages: [],
                    furthestStageReached: legacy.activeStage,
                    reviewRound: 0,
                    reviewStatus: .notStarted,
                    blueprint: legacy
                )
                projects = [recovered]
                selectedProjectId = recovered.id
                save()
                statusMessage = "Recovered existing project plan into the new Projects sidebar."
                return
            }

            throw NSError(domain: "OpenClawHQ", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported projects file format"])
        } catch {
            projects = []
            selectedProjectId = nil
            pendingPlanningByConversation = [:]
            statusMessage = "Failed to load projects."
            save()
        }
    }

    func save() {
        do {
            projects.sort { $0.updatedAt > $1.updatedAt }
            let state = ProjectsStateFile(
                selectedProjectId: selectedProjectId,
                projects: projects,
                pendingPlanning: pendingPlanningByConversation.values.sorted(by: { $0.createdAt > $1.createdAt })
            )
            let parent = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            statusMessage = "Failed to save project state."
        }
    }

    func deleteProject(_ id: String) {
        projects.removeAll { $0.id == id }
        if selectedProjectId == id {
            selectedProjectId = projects.first?.id
        }
        save()
    }

    func selectProject(_ id: String) {
        guard projects.contains(where: { $0.id == id }) else { return }
        selectedProjectId = id
        save()
    }

    /// Called when user starts planning via chat + [project].
    func registerProjectPlanningStarted(conversationId: String, userPrompt: String) {
        let kickoff = PendingProjectPlanning(conversationId: conversationId, kickoffPrompt: cleanedKickoffPrompt(userPrompt), createdAt: Date())
        pendingPlanningByConversation[conversationId] = kickoff
        statusMessage = "Project planning started in chat. Project will be created when Jarvis marks scope ready."
        save()
    }

    /// Called when Jarvis returns a readiness marker such as [project-ready].
    func registerProjectScopeReady(conversationId: String, assistantResponse: String) {
        if let existing = projects.first(where: { $0.conversationId == conversationId }) {
            selectedProjectId = existing.id
            pendingPlanningByConversation.removeValue(forKey: conversationId)
            statusMessage = "Linked to existing project from this planning chat."
            save()
            return
        }

        guard let pending = pendingPlanningByConversation[conversationId] else {
            return
        }

        let title = titleFromKickoff(pending.kickoffPrompt)
        let overview = buildOverview(kickoff: pending.kickoffPrompt, assistant: assistantResponse)
        let record = ProjectRecord.makeNew(title: title, conversationId: conversationId, overview: overview)
        projects.insert(record, at: 0)
        selectedProjectId = record.id
        pendingPlanningByConversation.removeValue(forKey: conversationId)
        statusMessage = "Project created from scoped planning conversation."
        save()
    }

    func updateProjectTitle(_ title: String) {
        updateSelected { project in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle = trimmed.isEmpty ? "New Project" : trimmed
            project.title = finalTitle
            project.blueprint.projectName = finalTitle
        }
    }

    func setStage(_ stage: ProductStage) {
        updateSelected { project in
            project.blueprint.activeStage = stage
        }
    }

    func updateOverview(_ text: String) {
        updateSelected { $0.blueprint.overview = text }
    }

    func updateProblems(_ text: String) {
        updateSelected { $0.blueprint.problemsText = text }
    }

    func updateFeatures(_ text: String) {
        updateSelected { $0.blueprint.featuresText = text }
    }

    func updateDataModel(_ text: String) {
        updateSelected { $0.blueprint.dataModelText = text }
    }

    func updateDesign(_ text: String) {
        updateSelected { $0.blueprint.designText = text }
    }

    func updateSectionsDraft(_ text: String) {
        updateSelected { $0.blueprint.sectionsDraftText = text }
    }

    func updateExportNotes(_ text: String) {
        updateSelected { $0.blueprint.exportNotes = text }
    }

    func setSectionCompletion(_ id: String, completed: Bool) {
        updateSelected { project in
            guard let idx = project.blueprint.sections.firstIndex(where: { $0.id == id }) else { return }
            project.blueprint.sections[idx].completed = completed
        }
    }

    func approveCurrentStage() async {
        guard var project = selectedProject else { return }
        guard !isApproving else { return }

        // Ensure latest page content is persisted before orchestration.
        project.updatedAt = Date()
        project.blueprint.lastUpdated = Date()
        saveUpdated(project)

        let stageOrder = ProductStage.allCases
        guard let approvedIndex = stageOrder.firstIndex(of: project.blueprint.activeStage) else { return }
        let approvedStage = project.blueprint.activeStage

        guard approvedStage != .export else {
            if !project.approvedStages.contains(.export) {
                project.approvedStages.append(.export)
            }
            saveUpdated(project)
            statusMessage = "Export finalized."
            return
        }

        let priorFurthestIndex = stageOrder.firstIndex(of: project.furthestStageReached) ?? approvedIndex
        let regenerationEndIndex = max(priorFurthestIndex, approvedIndex + 1)
        let targetStages = Array(stageOrder[(approvedIndex + 1)...regenerationEndIndex])

        isApproving = true
        statusMessage = "Approved \(approvedStage.rawValue). Regenerating downstream stages..."

        var latestSessionKey = project.conversationId
        var regenerated: [ProductStage] = []

        for targetStage in targetStages {
            let prompt = approvalPrompt(
                for: project,
                approvedStage: approvedStage,
                targetStage: targetStage,
                isRegeneration: targetStage != targetStages.first
            )

            do {
                let response = try await gatewayService.sendAgentMessage(
                    agentId: "jarvis",
                    message: prompt,
                    sessionKey: latestSessionKey,
                    thinkingEnabled: true
                )
                if let key = response.sessionKey {
                    latestSessionKey = key
                }
                let draft = normalizedDraft(response.text)
                applyDraft(draft, for: targetStage, to: &project)
                regenerated.append(targetStage)
            } catch {
                statusMessage = "Approval failed while drafting \(targetStage.rawValue): \(error.localizedDescription)"
                isApproving = false
                return
            }
        }

        if !project.approvedStages.contains(approvedStage) {
            project.approvedStages.append(approvedStage)
        }

        // Any stage after the approved one is now a regenerated draft and must be re-approved.
        project.approvedStages.removeAll { stage in
            guard let idx = stageOrder.firstIndex(of: stage) else { return false }
            return idx > approvedIndex
        }

        if let finalStage = regenerated.last {
            project.blueprint.activeStage = finalStage
            project.furthestStageReached = stageOrder[max(priorFurthestIndex, stageOrder.firstIndex(of: finalStage) ?? priorFurthestIndex)]
        } else if let next = approvedStage.next {
            project.blueprint.activeStage = next
            project.furthestStageReached = stageOrder[max(priorFurthestIndex, stageOrder.firstIndex(of: next) ?? priorFurthestIndex)]
        }

        project.updatedAt = Date()
        project.blueprint.lastUpdated = Date()
        project.conversationId = latestSessionKey
        saveUpdated(project)

        let regeneratedNames = regenerated.map { $0.rawValue }.joined(separator: ", ")
        statusMessage = regenerated.isEmpty
            ? "Approved \(approvedStage.rawValue)."
            : "Approved \(approvedStage.rawValue). Regenerated: \(regeneratedNames)."
        isApproving = false
    }

    func exportMarkdown() -> String {
        guard let project = selectedProject else { return "# No Project Selected" }
        let blueprint = project.blueprint
        let completedCount = blueprint.sections.filter { $0.completed }.count
        let sectionLines = blueprint.sections.map {
            "- [\($0.completed ? "x" : " ")] \($0.title) (\($0.ownerAgent)) - \($0.summary)"
        }.joined(separator: "\n")

        return """
        # \(project.title)

        ## Overview
        \(blueprint.overview)

        ## Problems & Solutions
        \(blueprint.problemsText)

        ## Key Features
        \(blueprint.featuresText)

        ## Data Model
        \(blueprint.dataModelText)

        ## Design
        \(blueprint.designText)

        ## Sections Draft
        \(blueprint.sectionsDraftText)

        ## Sections (\(completedCount)/\(blueprint.sections.count) complete)
        \(sectionLines)

        ## Export Notes
        \(blueprint.exportNotes)
        """
    }

    func executeCurrentProjectPlan() async {
        guard isExecutionAutomationEnabled else {
            statusMessage = "Execution automation is disabled in this visual-only build."
            return
        }
        guard var project = selectedProject else { return }
        guard !taskService.isExecutionPaused else {
            statusMessage = "Execution is paused. Resume task activity on the Tasks page first."
            return
        }

        let projectColorHex = colorHex(forProjectId: project.id)
        let projectName = project.title

        let seedTasks: [(String, String, String, TaskPriority)] = [
            ("Finalize execution orchestration", "Jarvis coordinates delivery sequencing and ownership checkpoints for this project. Keep tasks independent to avoid agent thrash.", "Jarvis", .urgent),
            ("Translate approved plan into implementation tasks", "Break the approved project plan into execution-ready work items and acceptance criteria. Ensure work can be done serially per agent.", "Scope", .high),
            ("Research external dependencies and constraints", "Validate APIs, libraries, and integration constraints before implementation. Avoid creating tightly coupled parallel tasks for one agent.", "Atlas", .medium),
            ("Implement core product workflows", "Build the primary flows specified by the approved sections and design plan. Keep each task completable without task switching.", "Matrix", .high),
            ("Define QA gates and validate readiness", "Set validation criteria and verify key paths before release. Bundle related checks into focused single-lane tasks.", "Prism", .high),
        ]

        var created = 0
        for seed in seedTasks {
            let scopedTitle = "\(projectName): \(seed.0)"
            let alreadyExists = taskService.tasks.contains {
                $0.projectId == project.id && $0.title == scopedTitle
            }
            if alreadyExists { continue }

            _ = taskService.createTask(
                title: scopedTitle,
                description: seed.1,
                assignedAgent: seed.2,
                status: .scheduled,
                priority: seed.3,
                scheduledFor: nil,
                projectId: project.id,
                projectName: projectName,
                projectColorHex: projectColorHex,
                isVerificationTask: false,
                verificationRound: nil,
                isVerified: false,
                isArchived: false
            )
            created += 1
        }

        created += workflowService.buildSectionWorkflowTasks(
            for: project,
            projectName: projectName,
            projectColorHex: projectColorHex
        )

        await workflowService.sendExecutionKickoff(
            projectName: projectName,
            sessionKey: project.conversationId
        )

        project.reviewStatus = .notStarted
        project.reviewRound = 0
        project.updatedAt = Date()
        saveUpdated(project)

        statusMessage = created == 0
            ? "Execution already initialized for this project."
            : "Execution started. Created \(created) task(s) in Ready."
    }

    func reconcilePendingPlanningFromChatHistory() async {
        let pending = pendingPlanningByConversation.values
        guard !pending.isEmpty else { return }

        for kickoff in pending {
            guard pendingPlanningByConversation[kickoff.conversationId] != nil else { continue }
            guard projects.contains(where: { $0.conversationId == kickoff.conversationId }) == false else {
                pendingPlanningByConversation.removeValue(forKey: kickoff.conversationId)
                continue
            }

            do {
                let history = try await gatewayService.fetchSessionHistory(sessionKey: kickoff.conversationId, limit: 120)
                guard let scopeReadyMessage = history
                    .reversed()
                    .first(where: { $0.role.lowercased() == "assistant" && indicatesScopeReady($0.text) }) else { continue }
                registerProjectScopeReady(conversationId: kickoff.conversationId, assistantResponse: scopeReadyMessage.text)
            } catch {
                continue
            }
        }
    }

    func handleTaskMovedToDone(_ task: TaskItem) {
        guard isExecutionAutomationEnabled else { return }
        guard let projectId = task.projectId else { return }
        guard var project = projects.first(where: { $0.id == projectId }) else { return }

        if project.reviewStatus == .finalApproved { return }

        if task.isVerificationTask {
            evaluateVerificationCompletion(for: &project, completedTask: task)
            return
        }

        let activeProjectTasks = taskService.tasks.filter {
            $0.projectId == projectId && !$0.isArchived && !$0.isVerificationTask
        }
        guard !activeProjectTasks.isEmpty else { return }

        let allDone = activeProjectTasks.allSatisfy { $0.status == .done }
        if allDone && project.reviewStatus != .inReview && project.reviewStatus != .waitingFinalApproval {
            let outcome = workflowService.beginVerificationRound(
                for: &project,
                projectColorHex: colorHex(forProjectId: project.id),
                reason: "Execution tasks are complete. Perform final verification."
            )
            if case let .maxRoundsReached(maxRounds) = outcome {
                statusMessage = "Reached max verification rounds (\(maxRounds)). Waiting for your final approval."
            }
            saveUpdated(project)
        }
    }

    func handleProjectChatUserMessage(conversationId: String, message: String) {
        guard isExecutionAutomationEnabled else { return }
        guard var project = projects.first(where: { $0.conversationId == conversationId }) else { return }
        let normalized = message.lowercased()

        let requestedChanges = normalized.contains("[changes-requested]") || normalized.contains("changes requested")
        let finalApproval = normalized.contains("[final-approve]") || normalized.contains("final approval")

        if requestedChanges {
            if project.reviewStatus == .finalApproved {
                statusMessage = "Project already finalized. Start a new project or explicitly reopen."
                return
            }
            let outcome = workflowService.beginVerificationRound(
                for: &project,
                projectColorHex: colorHex(forProjectId: project.id),
                reason: "User requested changes. Re-verify all updates."
            )
            switch outcome {
            case .started(let round):
                statusMessage = "Changes requested. Started verification round \(round)."
            case .maxRoundsReached(let maxRounds):
                statusMessage = "Reached max verification rounds (\(maxRounds)). Waiting for your final approval."
            }
            saveUpdated(project)
            return
        }

        if finalApproval {
            guard project.reviewStatus == .waitingFinalApproval else {
                statusMessage = "Final approval received before verification completed."
                return
            }
            workflowService.closeProject(&project)
            saveUpdated(project)
            statusMessage = "Final approval recorded. All tasks for this project were archived."
        }
    }

    private func evaluateVerificationCompletion(for project: inout ProjectRecord, completedTask: TaskItem) {
        let currentRound = completedTask.verificationRound ?? project.reviewRound
        let roundTasks = taskService.tasks.filter {
            $0.projectId == project.id &&
            !$0.isArchived &&
            $0.isVerificationTask &&
            ($0.verificationRound ?? 0) == currentRound
        }
        guard !roundTasks.isEmpty else { return }
        let allVerifiedDone = roundTasks.allSatisfy { $0.status == .done && $0.isVerified }
        guard allVerifiedDone else { return }

        project.reviewStatus = .waitingFinalApproval
        project.updatedAt = Date()
        saveUpdated(project)

        statusMessage = "All agents verified round \(currentRound). Waiting for your final approval in project chat."
    }

    func handleProjectChatAssistantMessage(conversationId: String, message: String) {
        guard pendingPlanningByConversation[conversationId] != nil else { return }
        guard indicatesScopeReady(message) else { return }
        registerProjectScopeReady(conversationId: conversationId, assistantResponse: message)
    }

    private func applyDraft(_ text: String, for stage: ProductStage, to project: inout ProjectRecord) {
        switch stage {
        case .dataModel:
            project.blueprint.dataModelText = text
        case .design:
            project.blueprint.designText = text
        case .sections:
            project.blueprint.sectionsDraftText = text
        case .export:
            project.blueprint.exportNotes = text
        case .product:
            break
        }
    }

    private func approvalPrompt(for project: ProjectRecord, approvedStage: ProductStage, targetStage: ProductStage, isRegeneration: Bool) -> String {
        let b = project.blueprint
        let modeLine = isRegeneration
            ? "Regeneration Mode: true (upstream edits were approved; regenerate this stage accordingly)"
            : "Regeneration Mode: false"

        return """
        [project-approval]
        Project: \(project.title)
        Approved Stage: \(approvedStage.rawValue)
        Target Stage To Draft: \(targetStage.rawValue)
        \(modeLine)

        You are Jarvis coordinating Scope, Atlas, Matrix, and Prism.
        Use the approved inputs below and produce only the requested stage draft.

        Product Overview:
        \(b.overview)

        Problems & Solutions:
        \(b.problemsText)

        Key Features:
        \(b.featuresText)

        Data Model:
        \(b.dataModelText)

        Design:
        \(b.designText)

        Sections Draft:
        \(b.sectionsDraftText)

        Export Notes:
        \(b.exportNotes)

        Rules:
        - Return only content for \(targetStage.rawValue).
        - No wrapper commentary, no markdown fences.
        - Be concrete and implementation-ready.
        - Include agent ownership hints where helpful.
        """
    }

    private func normalizedDraft(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "No draft returned. Ask Jarvis to retry this stage."
        }
        return trimmed
    }

    private func cleanedKickoffPrompt(_ raw: String) -> String {
        raw.replacingOccurrences(of: "[project]", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func indicatesScopeReady(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.contains("[project-ready]") { return true }

        let normalized = lower.replacingOccurrences(of: "[^a-z0-9\\s-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let negativePhrases = [
            "not ready",
            "isn't ready",
            "is not complete",
            "not complete",
            "still planning",
            "still scoping"
        ]
        if negativePhrases.contains(where: { normalized.contains($0) }) {
            return false
        }

        let directPhrases = [
            "project is scoped",
            "scope is ready",
            "scoping is complete",
            "scope complete",
            "project scope is complete",
            "project scope is ready",
            "ready to create the project",
            "new project created",
            "project has been created",
            "created a new project",
            "created the project"
        ]
        if directPhrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        let hasScopeOrProject = normalized.contains("project") || normalized.contains("scope") || normalized.contains("scoping")
        let hasReadySignal = normalized.contains("ready") || normalized.contains("complete") || normalized.contains("completed") || normalized.contains("created")
        return hasScopeOrProject && hasReadySignal
    }

    private func buildOverview(kickoff: String, assistant: String) -> String {
        let cleanKickoff = cleanedKickoffPrompt(kickoff)
        let cleanAssistant = assistant
            .replacingOccurrences(of: "[project-ready]", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanAssistant.isEmpty { return cleanKickoff }
        if cleanKickoff.isEmpty { return cleanAssistant }
        return "\(cleanKickoff)\n\nScoped Summary:\n\(cleanAssistant)"
    }

    private func titleFromKickoff(_ raw: String) -> String {
        let cleaned = cleanedKickoffPrompt(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if cleaned.isEmpty { return "New Project" }
        if cleaned.count <= 54 { return cleaned }
        return String(cleaned.prefix(54)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func colorHex(forProjectId projectId: String) -> String {
        let palette = ["#3B82F6", "#22C55E", "#F59E0B", "#06B6D4", "#A855F7", "#EF4444", "#F97316", "#14B8A6"]
        let hash = abs(projectId.hashValue)
        return palette[hash % palette.count]
    }

    private func saveUpdated(_ project: ProjectRecord) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        save()
    }

    private func updateSelected(_ mutate: (inout ProjectRecord) -> Void) {
        guard let id = selectedProjectId,
              let idx = projects.firstIndex(where: { $0.id == id }) else { return }

        var copy = projects[idx]
        mutate(&copy)
        copy.updatedAt = Date()
        copy.blueprint.lastUpdated = Date()
        projects[idx] = copy
        save()
    }
}
