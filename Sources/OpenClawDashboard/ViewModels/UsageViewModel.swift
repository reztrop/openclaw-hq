import SwiftUI
import Combine

@MainActor
class UsageViewModel: ObservableObject {
    @Published var usageData: UsageData?
    @Published var sessions: [Session] = []
    @Published var dateRange: DateRange = .sevenDays
    @Published var isLoading = false

    private let gatewayService: GatewayService

    init(gatewayService: GatewayService) {
        self.gatewayService = gatewayService
    }

    // MARK: - Fetch

    func fetchUsageData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch sessions
            let sessionDicts = try await gatewayService.fetchSessionsList()
            sessions = sessionDicts.compactMap { Session.from(dict: $0) }

            // Build usage data from sessions
            var byAgent: [String: AgentUsage] = [:]
            var byModel: [String: ModelUsage] = [:]
            var totalTokens = 0
            var totalCost = 0.0

            for session in sessions {
                totalTokens += session.totalTokens
                let model = session.model ?? "unknown"
                let sessionCost = CostRates.cost(
                    for: model,
                    inputTokens: session.inputTokens,
                    outputTokens: session.outputTokens
                )
                totalCost += sessionCost

                let agentName = resolveAgentName(session.agentId)
                if var existing = byAgent[agentName] {
                    existing.inputTokens += session.inputTokens
                    existing.outputTokens += session.outputTokens
                    existing.totalTokens += session.totalTokens
                    existing.cost += sessionCost
                    existing.sessionCount += 1
                    byAgent[agentName] = existing
                } else {
                    byAgent[agentName] = AgentUsage(
                        agentName: agentName,
                        inputTokens: session.inputTokens,
                        outputTokens: session.outputTokens,
                        totalTokens: session.totalTokens,
                        cost: sessionCost,
                        sessionCount: 1
                    )
                }

                if var existing = byModel[model] {
                    existing.tokens += session.totalTokens
                    existing.cost += sessionCost
                    existing.sessionCount += 1
                    byModel[model] = existing
                } else {
                    byModel[model] = ModelUsage(
                        model: model,
                        tokens: session.totalTokens,
                        cost: sessionCost,
                        sessionCount: 1
                    )
                }
            }

            // Build time series from sessions
            let timeSeries = buildTimeSeries(from: sessions)

            usageData = UsageData(
                totalTokens: totalTokens,
                totalCost: totalCost,
                sessionCount: sessions.count,
                byAgent: Array(byAgent.values).sorted { $0.totalTokens > $1.totalTokens },
                byModel: Array(byModel.values).sorted { $0.tokens > $1.tokens },
                timeSeries: timeSeries
            )
        } catch {
            print("[UsageVM] Failed to fetch usage: \(error)")
        }
    }

    private func resolveAgentName(_ agentId: String?) -> String {
        guard let id = agentId else { return "Jarvis" }
        if id == "main" { return "Jarvis" }
        return id.capitalized
    }

    private func buildTimeSeries(from sessions: [Session]) -> [UsageDataPoint] {
        let calendar = Calendar.current
        var dailyTokens: [String: Int] = [:]
        var dailyCost: [String: Double] = [:]

        for session in sessions {
            guard let date = session.updatedAt else { continue }
            let dayKey = date.dayString
            dailyTokens[dayKey, default: 0] += session.totalTokens
            dailyCost[dayKey, default: 0] += CostRates.cost(
                for: session.model ?? "unknown",
                inputTokens: session.inputTokens,
                outputTokens: session.outputTokens
            )
        }

        // Generate entries for the date range
        var points: [UsageDataPoint] = []
        var currentDate = dateRange.startDate
        let endDate = Date()

        while currentDate <= endDate {
            let dayKey = currentDate.dayString
            points.append(UsageDataPoint(
                date: currentDate,
                tokens: dailyTokens[dayKey] ?? 0,
                cost: dailyCost[dayKey] ?? 0
            ))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
        }

        return points
    }
}
