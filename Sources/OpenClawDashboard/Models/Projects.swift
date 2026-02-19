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
}

struct ProductSection: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String
    var ownerAgent: String
    var completed: Bool
}

struct ProductBlueprint: Codable {
    var projectName: String
    var overview: String
    var problemsText: String
    var featuresText: String
    var dataModelText: String
    var designText: String
    var sections: [ProductSection]
    var lastUpdated: Date
    var lastTaskPlanAt: Date?
    var activeStage: ProductStage

    static var `default`: ProductBlueprint {
        ProductBlueprint(
            projectName: "New Project",
            overview: "Describe what you want Jarvis and the agent team to build.",
            problemsText: "- Problem 1\n- Problem 2",
            featuresText: "- Core feature 1\n- Core feature 2",
            dataModelText: "- Entity: Agent\n- Entity: Task\n- Entity: Activity\n- Relationships: Agent owns Tasks, Task has Activities",
            designText: "- Primary color system\n- Typography direction\n- Application shell and navigation behavior",
            sections: [
                ProductSection(id: "dashboard", title: "Dashboard", summary: "At-a-glance system overview and key metrics.", ownerAgent: "Jarvis", completed: false),
                ProductSection(id: "agents", title: "Agents", summary: "Agent roster, identity, and collaboration controls.", ownerAgent: "Scope", completed: false),
                ProductSection(id: "activity", title: "Activity", summary: "Chronological feed, search, and filtering.", ownerAgent: "Atlas", completed: false),
                ProductSection(id: "usage", title: "Usage", summary: "Token/cost analytics and trend charts.", ownerAgent: "Matrix", completed: false),
                ProductSection(id: "jobs", title: "Jobs", summary: "Scheduled/recurring operations and execution history.", ownerAgent: "Matrix", completed: false),
                ProductSection(id: "tasks", title: "Tasks", summary: "Kanban workflow with assignments and status.", ownerAgent: "Prism", completed: false),
                ProductSection(id: "skills", title: "Skills", summary: "Capabilities catalog and requirement validation.", ownerAgent: "Atlas", completed: false),
            ],
            lastUpdated: Date(),
            lastTaskPlanAt: nil,
            activeStage: .product
        )
    }
}
