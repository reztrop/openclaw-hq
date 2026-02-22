import SwiftUI
import Charts

struct UsageView: View {
    @EnvironmentObject var usageVM: UsageViewModel
    @EnvironmentObject var gatewayService: GatewayService

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ConnectionBanner()
                controlsBar

                VStack(spacing: 24) {
                    summaryCards

                    HStack(spacing: 20) {
                        tokensByAgentChart
                        costByModelChart
                    }
                    .frame(height: 300)

                    timeSeriesChart
                        .frame(height: 250)

                    sessionsSection
                }
                .padding(24)
            }
        }
        .background(Theme.darkBackground)
        .task {
            await usageVM.fetchUsageData()
        }
    }

    // MARK: - Controls Bar (terminal tab strip with neon underline active)

    private var controlsBar: some View {
        HStack(spacing: 0) {
            // "[ USAGE_MATRIX ]" header
            HStack(spacing: 4) {
                Text("[")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan.opacity(0.6))
                Text("USAGE_MATRIX")
                    .font(Theme.headerFont)
                    .foregroundColor(Theme.neonCyan)
                Text("]")
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.neonCyan.opacity(0.6))
            }
            .padding(.leading, 24)
            .padding(.trailing, 16)

            // Terminal tab strip with neon underline active
            HStack(spacing: 0) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    let isActive = usageVM.dateRange == range
                    Button {
                        usageVM.dateRange = range
                        Task { await usageVM.fetchUsageData() }
                    } label: {
                        Text(range.label.uppercased())
                            .font(Theme.terminalFontSM)
                            .foregroundColor(isActive ? Theme.neonCyan : Theme.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                if isActive {
                                    Rectangle()
                                        .fill(Theme.neonCyan)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.darkSurface.opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.darkBorder.opacity(0.4)).frame(height: 1)
            }

            Spacer()

            Button {
                Task { await usageVM.fetchUsageData() }
            } label: {
                Label("REFRESH", systemImage: "arrow.clockwise")
            }
            .buttonStyle(HQButtonStyle(variant: .secondary))
            .padding(.trailing, 24)
        }
        .padding(.vertical, 10)
        .background(Theme.darkSurface.opacity(0.4))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.neonCyan.opacity(0.15)).frame(height: 1)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard(
                title: "TOTAL_TOKENS",
                value: usageVM.usageData?.totalTokens.compactTokens ?? "—",
                icon: "number",
                color: Theme.neonCyan
            )
            summaryCard(
                title: "TOTAL_COST",
                value: usageVM.usageData?.totalCost.formattedCost ?? "—",
                icon: "dollarsign.circle",
                color: Theme.statusOnline
            )
            summaryCard(
                title: "SESSIONS",
                value: "\(usageVM.usageData?.sessionCount ?? 0)",
                icon: "bubble.left.and.bubble.right",
                color: Theme.scopePurple
            )
            summaryCard(
                title: "ACTIVE_AGENTS",
                value: "\(usageVM.usageData?.byAgent.count ?? 0)",
                icon: "cpu",
                color: Theme.atlasAmber
            )
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        NeonBorderPanel(color: color, cornerRadius: 12, surface: Theme.darkSurface, lineWidth: 1) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(value)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundColor(Theme.textPrimary)
                Text(title)
                    .terminalLabel(color: Theme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }

    // MARK: - Token Chart

    private var tokensByAgentChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("// TOKENS_BY_AGENT")
                .terminalLabel()

            if let byAgent = usageVM.usageData?.byAgent, !byAgent.isEmpty {
                TokenChart(data: byAgent)
            } else {
                emptyChart(message: "No token data available")
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Cost Chart

    private var costByModelChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("// USAGE_BY_MODEL")
                .terminalLabel()

            if let byModel = usageVM.usageData?.byModel, !byModel.isEmpty {
                CostChart(data: byModel)
            } else {
                emptyChart(message: "No model data available")
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Time Series

    private var timeSeriesChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("// TOKEN_USAGE_OVER_TIME")
                .terminalLabel()

            if let timeSeries = usageVM.usageData?.timeSeries, !timeSeries.isEmpty {
                Chart(timeSeries) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.neonCyan.opacity(0.35), Theme.neonCyan.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(Theme.neonCyan)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                            .foregroundStyle(Theme.gridLineColor)
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
            } else {
                emptyChart(message: "No time series data")
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("// RECENT_SESSIONS")
                .terminalLabel()

            if !usageVM.sessions.isEmpty {
                SessionsList(sessions: usageVM.sessions)
            } else {
                EmptyStateView(
                    icon: "clock",
                    title: "No sessions found",
                    subtitle: nil,
                    maxWidth: .infinity,
                    iconSize: 20,
                    contentPadding: 8,
                    showPanel: false
                )
                .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.darkBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func emptyChart(message: String) -> some View {
        EmptyStateView(
            icon: "chart.line.downtrend.xyaxis",
            title: message,
            subtitle: nil,
            maxWidth: .infinity,
            iconSize: 20,
            contentPadding: 8,
            showPanel: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
