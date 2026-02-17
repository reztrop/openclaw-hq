import SwiftUI
import Charts

struct CostChart: View {
    let data: [ModelUsage]

    var body: some View {
        Chart(data) { usage in
            SectorMark(
                angle: .value("Tokens", usage.tokens),
                innerRadius: .ratio(0.5),
                angularInset: 2.0
            )
            .foregroundStyle(by: .value("Model", usage.model.truncated(to: 20)))
            .cornerRadius(4)
        }
        .chartLegend(position: .bottom, alignment: .center, spacing: 8)
    }
}
