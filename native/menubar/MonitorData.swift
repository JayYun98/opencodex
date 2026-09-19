import Foundation
import Observation

struct MonitorConfig: Codable, Equatable, Sendable {
    var language = "auto"
    var menuWidth: Double = 500
    var menuGraphHeight: Double = 175
    var dashboardGraphHeight: Double = 300
    var graphLineWidth: Double = 2
    var textColor = "primary"
    var secondaryColor = "secondary"
    var quotaGoodColor = "#32D74B"
    var quotaLowColor = "#FF9F0A"
    var quotaUnknownColor = "#8E8E93"
    var graphPalette = ["#0A84FF", "#FF9F0A", "#30D158", "#BF5AF2", "#FF453A", "#64D2FF"]
    var modelColors: [String: String] = [:]
    var todayTitle = "오늘 사용량"
    var todayLines = ["요청 {requests}회", "전체 토큰 {totalTokens}", "입력 {inputTokens} · 출력 {outputTokens}"]
    var costLines = ["추정 비용 ${costUsd} · 실제 청구액 아님", "비용 계산 제외 {excludedRequests}회"]
    var providerUsageTemplate = "오늘 {requests}회 · {totalTokens} 토큰"
    var menuBarTemplate: String? = nil
    var hiddenProviders: [String] = []
    var showToday = true
    var showChart = true
    var showAccounts = true
    var showModels = true
    var showCost = true
    var menuBarMetric = "requests"
    var chartStyle = "line"
    var chartGrouping = "model"
    var chartHours = 24
    var bucketMinutes = 60
    var aggregation = "sum"
    var tokenMetric = "total"
    var models: [String]? = nil

    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/opencodex-monitor/config.json")

    static func decode(_ data: Data) throws -> Self {
        guard let incoming = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self())) as! [String: Any]
        defaults.merge(incoming) { _, new in new }
        var value = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: defaults))
        guard ["auto", "en", "ko"].contains(value.language), ["sum", "average", "max"].contains(value.aggregation), ["line", "stackedBar"].contains(value.chartStyle), ["model", "modelAccount"].contains(value.chartGrouping),
              (320...900).contains(value.menuWidth), (100...500).contains(value.menuGraphHeight),
              (150...800).contains(value.dashboardGraphHeight), (1...6).contains(value.graphLineWidth),
              [value.textColor, value.secondaryColor, value.quotaGoodColor, value.quotaLowColor, value.quotaUnknownColor].allSatisfy(validColor),
              (1...24).contains(value.graphPalette.count), value.graphPalette.allSatisfy(validColor),
              value.modelColors.count <= 100, value.modelColors.values.allSatisfy(validColor),
              value.todayLines.count <= 20, value.costLines.count <= 20,
              (value.todayLines + value.costLines + [value.todayTitle, value.providerUsageTemplate, value.menuBarTemplate ?? ""]).allSatisfy({ $0.count <= 1000 }),
              value.hiddenProviders.count <= 100, value.hiddenProviders.allSatisfy({ $0.count <= 200 }),
              [6, 24, 72, 168].contains(value.chartHours), (1...1440).contains(value.bucketMinutes),
              ["requests", "tokens", "compact"].contains(value.menuBarMetric),
              ["total", "input", "output", "cached"].contains(value.tokenMetric),
              (value.models?.count ?? 0) <= 100, value.models?.allSatisfy({ $0.count <= 500 }) != false else {
            throw CocoaError(.fileReadCorruptFile)
        }
        value.localizeDefaults()
        return value
    }

    func showsProvider(_ name: String) -> Bool { !hiddenProviders.contains(name) }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.file, options: .atomic)
    }
}

struct TokenUsage: Decodable, Sendable {
    var inputTokens: Double?
    var outputTokens: Double?
    var totalTokens: Double?
    var cachedInputTokens: Double?
    var cacheReadInputTokens: Double?
}

struct UsageAttempt: Decodable, Sendable {
    let provider: String
    let model: String
    var usage: TokenUsage?
    var totalTokens: Double?
    var accountLogLabel: String?

    func tokens(_ metric: String) -> Double? {
        let value: Double?
        switch metric {
        case "input": value = usage?.inputTokens
        case "output": value = usage?.outputTokens
        case "cached": value = usage?.cacheReadInputTokens ?? usage?.cachedInputTokens
        default:
            if let input = usage?.inputTokens, let output = usage?.outputTokens {
                value = max(input + output, usage?.totalTokens ?? totalTokens ?? 0)
            } else { value = usage?.totalTokens ?? totalTokens }
        }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

struct UsageRow: Decodable, Sendable {
    let requestId: String
    let timestamp: Double
    let provider: String
    let model: String
    var resolvedModel: String?
    var usage: TokenUsage?
    var totalTokens: Double?
    var attempts: [UsageAttempt]?
    var accountLogLabel: String?
}

struct ChartPoint: Encodable, Identifiable, Sendable {
    var id: String { "\(model)|\(date.timeIntervalSince1970)" }
    let date: Date
    let model: String
    let tokens: Double
}

struct GraphSnapshot: Encodable, Sendable {
    let points: [ChartPoint]
    let availableModels: [String]
    let availableSeries: [String]
    let seriesSources: [String: String]
    let start: Date
    let end: Date
    let aggregation: String
    func valueTitle(_ language: MonitorLanguage) -> String { aggregation == "average" ? language.text("요청당 평균 토큰", "Average tokens per request") : aggregation == "max" ? language.text("요청당 최대 토큰", "Maximum tokens per request") : language.text("토큰 수", "Tokens") }
    let bucketSeconds: Double
    let missing: Int
    let skipped: Int
    let truncated: Bool
}

func aggregate(_ rows: [UsageRow], config: MonitorConfig, now: Date,
               skipped: Int = 0, truncated: Bool = false) -> GraphSnapshot {
    let width = Double(config.bucketMinutes * 60)
    let start = Date(timeIntervalSince1970: floor((now.timeIntervalSince1970 - Double(config.chartHours * 3600)) / width) * width)
    var latest: [String: UsageRow] = [:]
    for row in rows { latest[row.requestId] = row }
    var buckets: [String: [Double: Double]] = [:]
    var counts: [String: [Double: Int]] = [:]
    var maxima: [String: [Double: Double]] = [:]
    var missing = 0
    var sources: Set<String> = []
    var seriesSources: [String: String] = [:]
    for row in latest.values {
        let time = row.timestamp / 1000
        guard time >= start.timeIntervalSince1970, time <= now.timeIntervalSince1970 else { continue }
        let attempts = row.attempts.flatMap { $0.isEmpty ? nil : $0 }
            ?? [UsageAttempt(provider: row.provider, model: row.resolvedModel ?? row.model,
                             usage: row.usage, totalTokens: row.totalTokens, accountLogLabel: row.accountLogLabel)]
        var perRequest: [String: Double] = [:]
        for attempt in attempts {
            let model = "\(attempt.provider)/\(attempt.model)"
            guard let tokens = attempt.tokens(config.tokenMetric) else { missing += 1; continue }
            sources.insert(model)
            let account = attempt.accountLogLabel ?? config.text("계정 미상", "Unknown account")
            let series = config.chartGrouping == "model" ? attempt.model : "\(attempt.model) · \(attempt.provider)/\(account)"
            seriesSources[series] = min(seriesSources[series] ?? model, model)
            guard config.models == nil || config.models!.contains(model) else { continue }
            perRequest[series, default: 0] += tokens
        }
        let bucket = floor(time / width) * width
        for (series, tokens) in perRequest {
            buckets[series, default: [:]][bucket, default: 0] += tokens
            counts[series, default: [:]][bucket, default: 0] += 1
            maxima[series, default: [:]][bucket] = max(maxima[series]?[bucket] ?? 0, tokens)
        }
    }
    let names = buckets.keys.sorted()
    var points: [ChartPoint] = []
    for model in names {
        for time in stride(from: start.timeIntervalSince1970, through: now.timeIntervalSince1970, by: width) {
            let sum = buckets[model]?[time] ?? 0
            let value = config.aggregation == "average" ? sum / Double(max(1, counts[model]?[time] ?? 0))
                : config.aggregation == "max" ? maxima[model]?[time] ?? 0 : sum
            points.append(ChartPoint(date: Date(timeIntervalSince1970: time), model: model, tokens: value))
        }
    }
    return GraphSnapshot(points: points, availableModels: sources.sorted(),
                         availableSeries: seriesSources.keys.sorted(), seriesSources: seriesSources, start: start, end: now, aggregation: config.aggregation, bucketSeconds: width,
                         missing: missing, skipped: skipped, truncated: truncated)
}

func readGraph(home: URL, config: MonitorConfig, now: Date = Date()) throws -> GraphSnapshot {
    let handle = try FileHandle(forReadingFrom: home.appendingPathComponent("usage.jsonl"))
    defer { try? handle.close() }
    let size = try handle.seekToEnd()
    // ponytail: bounded 128 MiB snapshot; use an incremental log index if history outgrows this window.
    let cap: UInt64 = 128 * 1024 * 1024
    let offset = size > cap ? size - cap : 0
    try handle.seek(toOffset: offset)
    var remaining = size - offset
    var buffer = Data()
    var discardFirst = offset > 0
    var rows: [UsageRow] = []
    var skipped = 0
    let decoder = JSONDecoder()
    while remaining > 0 {
        guard let chunk = try handle.read(upToCount: Int(min(remaining, 1024 * 1024))), !chunk.isEmpty else { break }
        remaining -= UInt64(chunk.count)
        buffer.append(chunk)
        var consumed = buffer.startIndex
        while let newline = buffer[consumed...].firstIndex(of: 10) {
            let line = buffer[consumed..<newline]
            consumed = newline + 1
            if discardFirst { discardFirst = false; continue }
            if line.isEmpty { continue }
            if let row = try? decoder.decode(UsageRow.self, from: line) { rows.append(row) }
            else { skipped += 1 }
        }
        if consumed > buffer.startIndex { buffer = Data(buffer[consumed...]) }
    }
    // An unfinished final line is deliberately retried on the next snapshot.
    return aggregate(rows, config: config, now: now, skipped: skipped, truncated: offset > 0)
}

struct Quota: Codable, Sendable {
    let weeklyPercent: Double?
    let weeklyResetAt: Double?
    let shortPercent: Double?
    let shortResetAt: Double?
    let shortObservedAt: Double?
    let shortWindowSeconds: Double?
    let updatedAt: Double?
}
struct QuotaResponse: Decodable { let quotas: [String: Quota] }
struct AccountInfo: Codable, Identifiable, Sendable {
    let id: String
    var email: String?
    var alias: String?
    var logLabel: String?
    var plan: String?
    func name(_ language: MonitorLanguage) -> String { alias ?? logLabel ?? (id == "__main__" ? language.text("Codex 기본 계정", "Codex main account") : email ?? language.text("Codex 계정", "Codex account")) }
}
struct ProviderConnection: Decodable {
    let baseUrl: String?
    let apiKey: String?
    let disabled: Bool?
    var isOpenCodeGo: Bool { baseUrl?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "https://opencode.ai/zen/go/v1" }
}
struct AccountConfig: Decodable {
    let codexAccounts: [AccountInfo]?
    let providers: [String: ProviderConnection]?
}

struct ProviderUsage: Codable, Identifiable {
    var id: String { provider }
    let provider: String
    let requests: Int
    let totalTokens: Int
}
struct ProviderWindow: Encodable, Identifiable {
    var id: String { label }
    let label: String
    let used: Double?
    let reset: Double?
}
func goWindows(_ data: Data, language: MonitorLanguage = MonitorLanguage()) throws -> [ProviderWindow] {
    guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let usage = body["usage"] as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
    return [("rolling", language.text("세션", "Session")), ("weekly", language.text("주간", "Weekly")), ("monthly", language.text("월간", "Monthly"))].map { key, label in
        let window = usage[key] as? [String: Any]
        let percent = (window?["percent"] as? NSNumber)?.doubleValue
            ?? (window?["percent"] as? String).flatMap(Double.init)
        var reset: Double?
        if let number = (window?["resetsAt"] as? NSNumber)?.doubleValue
            ?? (window?["resetsAt"] as? String).flatMap(Double.init), number.isFinite, number > 0 {
            reset = number > 1e12 ? number / 1000 : number
        } else if let string = window?["resetsAt"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            reset = formatter.date(from: string)?.timeIntervalSince1970
            if reset == nil {
                formatter.formatOptions = [.withInternetDateTime]
                reset = formatter.date(from: string)?.timeIntervalSince1970
            }
        }
        return ProviderWindow(label: label, used: percent, reset: reset)
    }
}

func remainingPercent(_ used: Double?) -> Double? {
    guard let used, used.isFinite else { return nil }
    return max(0, min(100, 100 - used))
}
func quotaText(_ used: Double?, reset: Double?, now: Date = Date(), language: MonitorLanguage = MonitorLanguage()) -> String {
    guard let remaining = remainingPercent(used) else { return language.text("확인 불가", "Unavailable") }
    if let reset, reset <= now.timeIntervalSince1970 { return language.text("리셋 경과 · 새 관측 대기", "Reset elapsed · awaiting fresh data") }
    return String(format: language.text("%.0f%% 남음", "%.0f%% remaining"), remaining)
}

@MainActor @Observable
final class MonitorState {
    var config = MonitorConfig()
    var configError: String?
    var graph: GraphSnapshot?
    var graphError: String?
    var providerNames: [String] = []
    var providerWindows: [String: [ProviderWindow]] = [:]
    var providerErrors: [String: String] = [:]
    var accounts: [AccountInfo] = []
    var quotas: [String: Quota] = [:]
    var quotaError: String?
    var usage: Usage?
    var updated: Date?
    var failure: String?
    var refreshing = false
}
