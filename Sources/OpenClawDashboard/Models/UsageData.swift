import Foundation

// MARK: - Usage Data
struct UsageData {
    var totalTokens: Int
    var totalCost: Double
    var sessionCount: Int
    var byAgent: [AgentUsage]
    var byModel: [ModelUsage]
    var timeSeries: [UsageDataPoint]
}

// MARK: - Agent Usage
struct AgentUsage: Identifiable {
    var id: String { agentName }
    let agentName: String
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var cost: Double
    var sessionCount: Int
}

// MARK: - Model Usage
struct ModelUsage: Identifiable {
    var id: String { model }
    let model: String
    var tokens: Int
    var cost: Double
    var sessionCount: Int
}

// MARK: - Usage Data Point (Time Series)
struct UsageDataPoint: Identifiable {
    var id: String { date.ISO8601Format() }
    let date: Date
    var tokens: Int
    var cost: Double
}

// MARK: - Date Range
enum DateRange: String, CaseIterable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"

    var label: String {
        switch self {
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        case .ninetyDays: return "90 Days"
        }
    }

    var startDate: Date {
        let days: Int
        switch self {
        case .sevenDays: days = 7
        case .thirtyDays: days = 30
        case .ninetyDays: days = 90
        }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
}
