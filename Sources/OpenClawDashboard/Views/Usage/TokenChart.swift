import SwiftUI
import Charts

struct TokenChart: View {
    let data: [AgentUsage]

    var body: some View {
        Chart(data) { usage in
            BarMark(
                x: .value("Agent", usage.agentName),
                y: .value("Tokens", usage.totalTokens)
            )
            .foregroundStyle(Theme.agentColor(for: usage.agentName))
            .cornerRadius(6)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.darkBorder.opacity(0.5))
                AxisValueLabel()
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }
}
