import SwiftUI
import Charts

struct TokenChart: View {
    let graph: GraphSnapshot
    let config: MonitorConfig
    var compact = false
    var body: some View {
        let colors = graph.availableSeries.enumerated().map { index, model in
            themeColor(config.modelColors[model] ?? config.modelColors[graph.seriesSources[model] ?? ""] ?? config.graphPalette[index % config.graphPalette.count])
        }
        let visible = Set(graph.points.map(\.model))
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
            Chart(graph.points) { point in
                if config.chartStyle == "stackedBar" {
                    BarMark(x: .value(config.text("시간", "Time"), point.date.addingTimeInterval(graph.bucketSeconds / 2)),
                            y: .value(graph.valueTitle(config.locale), point.tokens), width: .fixed(max(1, (geometry.size.width - 60) * graph.bucketSeconds / (graph.end.timeIntervalSince(graph.start) + graph.bucketSeconds) * 0.85)), stacking: .standard)
                        .foregroundStyle(by: .value(config.text("범례", "Legend"), point.model))
                } else {
                    LineMark(x: .value(config.text("시간", "Time"), point.date), y: .value(graph.valueTitle(config.locale), point.tokens))
                        .foregroundStyle(by: .value(config.text("범례", "Legend"), point.model))
                        .lineStyle(StrokeStyle(lineWidth: config.graphLineWidth))
                        .interpolationMethod(.linear)
                }
            }
            .chartForegroundStyleScale(domain: graph.availableSeries, range: colors)
            .chartXScale(domain: graph.start...(config.chartStyle == "stackedBar"
                ? Date(timeIntervalSince1970: (floor(graph.end.timeIntervalSince1970 / graph.bucketSeconds) + 1) * graph.bucketSeconds)
                : graph.end))
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) { Text(axisTokens(number)) }
                    }
                }
            }
            .chartXAxisLabel(config.text("시간 · 현지 시간대", "Time · local time zone"))
            .chartYAxisLabel(graph.valueTitle(config.locale))
            .chartLegend(.hidden)
            .accessibilityLabel(config.text("시간별 모델 토큰 사용량 그래프", "Model token usage over time"))
            }
            .frame(height: compact ? config.menuGraphHeight : config.dashboardGraphHeight)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 5) {
                ForEach(Array(graph.availableSeries.enumerated()).filter { visible.contains($0.element) }, id: \.element) { index, model in
                    HStack(spacing: 5) {
                        Circle().fill(colors[index]).frame(width: 7, height: 7)
                        Text(model).font(.caption)
                            .foregroundStyle(themeColor(config.textColor))
                            .lineLimit(1).truncationMode(.middle)
                    }.help(model + "\n" + (graph.seriesSources[model] ?? "")).accessibilityLabel(model)
                }
            }
        }
    }
}

struct QuotaWindow: View {
    @Environment(\.monitorTheme) private var theme
    let title: String
    let used: Double?
    let reset: Double?
    var body: some View {
        let remaining = remainingPercent(used)
        let expired = reset.map { $0 <= Date().timeIntervalSince1970 } ?? false
        HStack(spacing: 8) {
            Text(title).foregroundStyle(themeColor(theme.secondaryColor)).frame(width: 58, alignment: .leading)
            Text(expired ? theme.text("갱신 대기", "Pending") : remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit().frame(width: 60, alignment: .trailing)
            ProgressView(value: expired ? 0 : remaining ?? 0, total: 100)
                .tint(themeColor(expired || remaining == nil ? theme.quotaUnknownColor : remaining! < 20 ? theme.quotaLowColor : theme.quotaGoodColor))
                .accessibilityLabel("\(title) \(quotaText(used, reset: reset, language: theme.locale))")
        }
        .help(reset.map { theme.text("리셋 \(theme.locale.date(Date(timeIntervalSince1970: $0), date: .abbreviated))", "Resets \(theme.locale.date(Date(timeIntervalSince1970: $0), date: .abbreviated))") }
              ?? theme.text("잔여량 · —는 정보 없음", "Remaining · — means unavailable"))
    }
}

struct AccountCard: View {
    @Environment(\.monitorTheme) private var theme
    let account: AccountInfo
    let quota: Quota?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name(theme.locale)).font(.headline)
                    if let email = account.email, email != account.name(theme.locale) {
                        Text(email).font(.caption).foregroundStyle(themeColor(theme.secondaryColor))
                    }
                }
                Spacer()
                if let plan = account.plan {
                    Text(plan).font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            QuotaWindow(title: theme.text("세션", "Session"), used: quota?.shortPercent, reset: quota?.shortResetAt)
            QuotaWindow(title: theme.text("주간", "Weekly"), used: quota?.weeklyPercent, reset: quota?.weeklyResetAt)
        }
        .foregroundStyle(themeColor(theme.textColor))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProviderCard: View {
    @Environment(\.monitorTheme) private var theme
    let name: String
    let usage: ProviderUsage?
    let windows: [ProviderWindow]?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            if let usage {
                Text(renderTemplate(theme.providerUsageTemplate, values: numberFields([
                    "requests": usage.requests, "totalTokens": usage.totalTokens
                ], language: theme.locale))).monospacedDigit().foregroundStyle(themeColor(theme.secondaryColor))
            } else { Text(theme.text("오늘 기록 없음", "No usage recorded today")).font(.caption).foregroundStyle(themeColor(theme.secondaryColor)) }
            if let windows {
                ForEach(windows) { window in
                    QuotaWindow(title: window.label, used: window.used, reset: window.reset)
                }
            } else {
                Text(error ?? theme.text("잔여 한도 미지원", "Remaining limits not supported")).font(.caption).foregroundStyle(themeColor(theme.secondaryColor))
            }
        }.foregroundStyle(themeColor(theme.textColor))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
