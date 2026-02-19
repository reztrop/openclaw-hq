import Foundation

@MainActor
class ProjectsViewModel: ObservableObject {
    @Published var blueprint: ProductBlueprint = .default
    @Published var statusMessage: String?

    private let filePath: String
    private let taskService: TaskService

    init(taskService: TaskService, filePath: String = Constants.projectsFilePath) {
        self.taskService = taskService
        self.filePath = filePath
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: filePath) else {
            blueprint = .default
            save()
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            blueprint = try decoder.decode(ProductBlueprint.self, from: data)
        } catch {
            blueprint = .default
            statusMessage = "Failed to load saved project plan. Reset to defaults."
        }
    }

    func save() {
        do {
            var copy = blueprint
            copy.lastUpdated = Date()
            blueprint = copy
            let parent = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(copy)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            statusMessage = "Failed to save project plan."
        }
    }

    func setStage(_ stage: ProductStage) {
        blueprint.activeStage = stage
        save()
    }

    func setSectionCompletion(_ id: String, completed: Bool) {
        guard let idx = blueprint.sections.firstIndex(where: { $0.id == id }) else { return }
        blueprint.sections[idx].completed = completed
        save()
    }

    func generateTaskPlan() {
        let project = blueprint.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Unnamed Project"
            : blueprint.projectName.trimmingCharacters(in: .whitespacesAndNewlines)

        let specs: [(String, String, String)] = [
            ("Jarvis", "\(project): orchestrate cross-agent execution plan", "Create phased execution plan and assign responsibilities to specialized agents."),
            ("Scope", "\(project): define requirements and acceptance criteria", "Translate the brief into concrete requirements and measurable acceptance criteria."),
            ("Atlas", "\(project): research dependencies and external constraints", "Identify libraries, APIs, and constraints that affect implementation strategy."),
            ("Matrix", "\(project): implementation architecture and build plan", "Define architecture, milestones, and technical implementation order."),
            ("Prism", "\(project): QA strategy and validation gates", "Define test matrix, release criteria, and regression prevention strategy."),
        ]

        var created = 0
        for spec in specs {
            if taskService.tasks.contains(where: { $0.title == spec.1 }) { continue }
            _ = taskService.createTask(
                title: spec.1,
                description: spec.2,
                assignedAgent: spec.0,
                status: .scheduled,
                priority: .high
            )
            created += 1
        }

        blueprint.lastTaskPlanAt = Date()
        save()
        statusMessage = created == 0
            ? "Task plan already exists for this project."
            : "Created \(created) project task(s) in Tasks."
    }

    func exportMarkdown() -> String {
        let completedCount = blueprint.sections.filter { $0.completed }.count
        let sectionLines = blueprint.sections.map {
            "- [\($0.completed ? "x" : " ")] \($0.title) (\($0.ownerAgent)) — \($0.summary)"
        }.joined(separator: "\n")

        return """
        # \(blueprint.projectName)

        ## Overview
        \(blueprint.overview)

        ## Problems & Solutions
        \(blueprint.problemsText)

        ## Key Features
        \(blueprint.featuresText)

        ## Data Model
        \(blueprint.dataModelText)

        ## Design System
        \(blueprint.designText)

        ## Sections (\(completedCount)/\(blueprint.sections.count) complete)
        \(sectionLines)
        """
    }
}
