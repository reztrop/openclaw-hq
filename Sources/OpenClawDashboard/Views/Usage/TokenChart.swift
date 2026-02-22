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
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.gridLineColor)
                AxisValueLabel()
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        // Glow shadow overlay on bars using chart background
        .shadow(color: Theme.neonCyan.opacity(0.12), radius: 8, x: 0, y: 0)
    }
}
