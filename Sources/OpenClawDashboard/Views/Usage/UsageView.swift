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
                    // Summary cards
                    summaryCards

                    // Charts
                    HStack(spacing: 20) {
                        tokensByAgentChart
                        costByModelChart
                    }
                    .frame(height: 300)

                    // Time series
                    timeSeriesChart
                        .frame(height: 250)

                    // Sessions list
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

    private var controlsBar: some View {
        HStack(spacing: 12) {
            Picker("Range", selection: $usageVM.dateRange) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .onChange(of: usageVM.dateRange) { _, _ in
                Task { await usageVM.fetchUsageData() }
            }

            Button {
                Task { await usageVM.fetchUsageData() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            summaryCard(
                title: "Total Tokens",
                value: usageVM.usageData?.totalTokens.compactTokens ?? "—",
                icon: "number",
                color: Theme.jarvisBlue
            )
            summaryCard(
                title: "Total Cost",
                value: usageVM.usageData?.totalCost.formattedCost ?? "—",
                icon: "dollarsign.circle",
                color: Theme.statusOnline
            )
            summaryCard(
                title: "Sessions",
                value: "\(usageVM.usageData?.sessionCount ?? 0)",
                icon: "bubble.left.and.bubble.right",
                color: Theme.scopePurple
            )
            summaryCard(
                title: "Active Agents",
                value: "\(usageVM.usageData?.byAgent.count ?? 0)",
                icon: "cpu",
                color: Theme.atlasAmber
            )
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.darkSurface)
        .cornerRadius(12)
    }

    // MARK: - Token Chart

    private var tokensByAgentChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tokens by Agent")
                .font(.headline)
                .foregroundColor(.white)

            if let byAgent = usageVM.usageData?.byAgent, !byAgent.isEmpty {
                Chart(byAgent) { usage in
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
                            .foregroundStyle(Theme.darkBorder.opacity(0.7))
                        AxisValueLabel()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                emptyChart(message: "No token data available")
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .cornerRadius(12)
    }

    // MARK: - Cost Chart

    private var costByModelChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage by Model")
                .font(.headline)
                .foregroundColor(.white)

            if let byModel = usageVM.usageData?.byModel, !byModel.isEmpty {
                Chart(byModel) { usage in
                    SectorMark(
                        angle: .value("Tokens", usage.tokens),
                        innerRadius: .ratio(0.5),
                        angularInset: 2.0
                    )
                    .foregroundStyle(by: .value("Model", usage.model.truncated(to: 20)))
                    .cornerRadius(4)
                }
                .chartLegend(position: .bottom, alignment: .center, spacing: 8)
            } else {
                emptyChart(message: "No model data available")
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .cornerRadius(12)
    }

    // MARK: - Time Series

    private var timeSeriesChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token Usage Over Time")
                .font(.headline)
                .foregroundColor(.white)

            if let timeSeries = usageVM.usageData?.timeSeries, !timeSeries.isEmpty {
                Chart(timeSeries) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.jarvisBlue.opacity(0.4), Theme.jarvisBlue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(Theme.jarvisBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                            .foregroundStyle(Theme.darkBorder.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                            .foregroundStyle(Theme.darkBorder.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                emptyChart(message: "No time series data")
            }
        }
        .padding(16)
        .background(Theme.darkSurface)
        .cornerRadius(12)
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
                .foregroundColor(.white)

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
        .cornerRadius(12)
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
