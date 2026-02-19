import Foundation

enum ProductStage: String, CaseIterable, Codable, Identifiable {
    case product = "Product"
    case dataModel = "Data Model"
    case design = "Design"
    case sections = "Sections"
    case export = "Export"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .product: return "doc.text"
        case .dataModel: return "circle.grid.2x2"
        case .design: return "square.on.square"
        case .sections: return "list.bullet.rectangle"
        case .export: return "shippingbox"
        }
    }

    var next: ProductStage? {
        switch self {
        case .product: return .dataModel
        case .dataModel: return .design
        case .design: return .sections
        case .sections: return .export
        case .export: return nil
        }
    }

    var approveLabel: String {
        switch self {
        case .product: return "Approve Product"
        case .dataModel: return "Approve Data Model"
        case .design: return "Approve Design"
        case .sections: return "Approve Sections"
        case .export: return "Finalize Export"
        }
    }
}

struct ProductSection: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String
    var ownerAgent: String
    var completed: Bool
}

struct ProductBlueprint: Codable, Hashable {
    var projectName: String
    var overview: String
    var problemsText: String
    var featuresText: String
    var dataModelText: String
    var designText: String
    var sectionsDraftText: String
    var sections: [ProductSection]
    var exportNotes: String
    var lastUpdated: Date
    var activeStage: ProductStage

    static var defaultSections: [ProductSection] {
        [
            ProductSection(id: "dashboard", title: "Dashboard", summary: "At-a-glance system overview and key metrics.", ownerAgent: "Jarvis", completed: false),
            ProductSection(id: "agents", title: "Agents", summary: "Agent roster, identity, and collaboration controls.", ownerAgent: "Scope", completed: false),
            ProductSection(id: "activity", title: "Activity", summary: "Chronological feed, search, and filtering.", ownerAgent: "Atlas", completed: false),
            ProductSection(id: "usage", title: "Usage", summary: "Token/cost analytics and trend charts.", ownerAgent: "Matrix", completed: false),
            ProductSection(id: "jobs", title: "Jobs", summary: "Scheduled and recurring operations.", ownerAgent: "Matrix", completed: false),
            ProductSection(id: "tasks", title: "Tasks", summary: "Kanban workflow with assignments and status.", ownerAgent: "Prism", completed: false),
            ProductSection(id: "skills", title: "Skills", summary: "Capabilities catalog and requirement validation.", ownerAgent: "Atlas", completed: false),
        ]
    }

    static var `default`: ProductBlueprint {
        ProductBlueprint(
            projectName: "New Project",
            overview: "Describe what you want Jarvis and the team to build.",
            problemsText: "- Problem 1\n- Problem 2",
            featuresText: "- Core feature 1\n- Core feature 2",
            dataModelText: "",
            designText: "",
            sectionsDraftText: "",
            sections: defaultSections,
            exportNotes: "",
            lastUpdated: Date(),
            activeStage: .product
        )
    }

    enum CodingKeys: String, CodingKey {
        case projectName
        case overview
        case problemsText
        case featuresText
        case dataModelText
        case designText
        case sectionsDraftText
        case sections
        case exportNotes
        case lastUpdated
        case activeStage
    }

    init(
        projectName: String,
        overview: String,
        problemsText: String,
        featuresText: String,
        dataModelText: String,
        designText: String,
        sectionsDraftText: String,
        sections: [ProductSection],
        exportNotes: String,
        lastUpdated: Date,
        activeStage: ProductStage
    ) {
        self.projectName = projectName
        self.overview = overview
        self.problemsText = problemsText
        self.featuresText = featuresText
        self.dataModelText = dataModelText
        self.designText = designText
        self.sectionsDraftText = sectionsDraftText
        self.sections = sections
        self.exportNotes = exportNotes
        self.lastUpdated = lastUpdated
        self.activeStage = activeStage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProductBlueprint.default
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName) ?? d.projectName
        overview = try c.decodeIfPresent(String.self, forKey: .overview) ?? d.overview
        problemsText = try c.decodeIfPresent(String.self, forKey: .problemsText) ?? d.problemsText
        featuresText = try c.decodeIfPresent(String.self, forKey: .featuresText) ?? d.featuresText
        dataModelText = try c.decodeIfPresent(String.self, forKey: .dataModelText) ?? d.dataModelText
        designText = try c.decodeIfPresent(String.self, forKey: .designText) ?? d.designText
        sectionsDraftText = try c.decodeIfPresent(String.self, forKey: .sectionsDraftText) ?? ""
        sections = try c.decodeIfPresent([ProductSection].self, forKey: .sections) ?? d.sections
        exportNotes = try c.decodeIfPresent(String.self, forKey: .exportNotes) ?? ""
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
        activeStage = try c.decodeIfPresent(ProductStage.self, forKey: .activeStage) ?? .product
    }
}

struct ProjectRecord: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var conversationId: String?
    var createdAt: Date
    var updatedAt: Date
    var approvedStages: [ProductStage]
    var furthestStageReached: ProductStage
    var blueprint: ProductBlueprint

    static func makeNew(title: String, conversationId: String? = nil, overview: String? = nil) -> ProjectRecord {
        var blueprint = ProductBlueprint.default
        blueprint.projectName = title
        if let overview, !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blueprint.overview = overview
        }
        return ProjectRecord(
            id: UUID().uuidString,
            title: title,
            conversationId: conversationId,
            createdAt: Date(),
            updatedAt: Date(),
            approvedStages: [],
            furthestStageReached: .product,
            blueprint: blueprint
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case conversationId
        case createdAt
        case updatedAt
        case approvedStages
        case furthestStageReached
        case blueprint
    }

    init(
        id: String,
        title: String,
        conversationId: String?,
        createdAt: Date,
        updatedAt: Date,
        approvedStages: [ProductStage],
        furthestStageReached: ProductStage,
        blueprint: ProductBlueprint
    ) {
        self.id = id
        self.title = title
        self.conversationId = conversationId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.approvedStages = approvedStages
        self.furthestStageReached = furthestStageReached
        self.blueprint = blueprint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        conversationId = try c.decodeIfPresent(String.self, forKey: .conversationId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        approvedStages = try c.decodeIfPresent([ProductStage].self, forKey: .approvedStages) ?? []
        blueprint = try c.decode(ProductBlueprint.self, forKey: .blueprint)
        furthestStageReached = try c.decodeIfPresent(ProductStage.self, forKey: .furthestStageReached) ?? blueprint.activeStage
    }
}

struct PendingProjectPlanning: Codable, Hashable {
    var conversationId: String
    var kickoffPrompt: String
    var createdAt: Date
}

struct ProjectsStateFile: Codable {
    var selectedProjectId: String?
    var projects: [ProjectRecord]
    var pendingPlanning: [PendingProjectPlanning]
}
