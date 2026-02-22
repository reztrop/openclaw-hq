import SwiftUI
import Charts

struct CostChart: View {
    let data: [ModelUsage]

    var totalTokens: Int {
        data.reduce(0) { $0 + $1.tokens }
    }

    var body: some View {
        ZStack {
            Chart(data) { usage in
                SectorMark(
                    angle: .value("Tokens", usage.tokens),
                    innerRadius: .ratio(0.55),
                    angularInset: 2.0
                )
                .foregroundStyle(by: .value("Model", usage.model.truncated(to: 20)))
                .cornerRadius(4)
            }
            .chartLegend(position: .bottom, alignment: .center, spacing: 8)

            // Center label overlay with total in monospaced
            VStack(spacing: 2) {
                Text(totalTokens.compactTokens)
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.textPrimary)
                Text("TOTAL")
                    .font(Theme.terminalFontSM)
                    .foregroundColor(Theme.textMuted)
                    .tracking(1.2)
            }
            .allowsHitTesting(false)
        }
    }
}
