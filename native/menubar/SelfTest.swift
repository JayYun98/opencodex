import Foundation

func dataSelfTest() throws {
    precondition(MonitorLanguage("auto", preferred: ["ko-KR"]).code == "ko")
    precondition(MonitorLanguage("auto", preferred: ["en-US", "ko"]).code == "en")
    precondition(MonitorLanguage("auto", preferred: ["fr-FR"]).code == "en")
    precondition(MonitorLanguage("en", preferred: ["ko-KR"]).code == "en")
    var english = try MonitorConfig.decode(Data(#"{"language":"en"}"#.utf8))
    precondition(english.todayTitle == "Today’s usage" && english.todayLines[0] == "Requests {requests}")
    english.language = "ko"
    let korean = try MonitorConfig.decode(JSONEncoder().encode(english))
    precondition(korean.todayTitle == "오늘 사용량" && korean.todayLines[0] == "요청 {requests}회")
    english.todayTitle = "My {requests} calls"
    english.todayLines = ["Custom {totalTokens}"]
    english.menuBarTemplate = "My OCX {requests}"
    let custom = try MonitorConfig.decode(JSONEncoder().encode(english))
    precondition(custom.todayTitle == english.todayTitle && custom.todayLines == english.todayLines && custom.menuBarTemplate == english.menuBarTemplate)
    let migrated = try MonitorConfig.decode(Data(#"{"language":"en","todayTitle":"오늘 사용량"}"#.utf8))
    precondition(migrated.todayTitle == "Today’s usage")
    do { _ = try MonitorConfig.decode(Data(#"{"language":"unsupported"}"#.utf8)); fatalError("Invalid language accepted") } catch { precondition(error is CocoaError || error is DecodingError, "Unexpected validation error: \(error)") }
    precondition(AccountInfo(id: "__main__").name(MonitorLanguage("en")) == "Codex main account")
    precondition(quotaText(nil, reset: nil, language: MonitorLanguage("en")) == "Unavailable")
    let englishWindows = try goWindows(Data(#"{"usage":{}}"#.utf8), language: MonitorLanguage("en"))
    precondition(englishWindows.map(\.label) == ["Session", "Weekly", "Monthly"])

    let requestBytes = Data("GET /state HTTP/1.1\r\nHost: 127.0.0.1:10101\r\nOrigin: http://127.0.0.1:10100\r\n\r\n".utf8)
    precondition(tryBridge(requestBytes))
    let foreign = Data("GET /state HTTP/1.1\r\nHost: 127.0.0.1:10101\r\nOrigin: https://example.com\r\n\r\n".utf8)
    let foreignRequest = try MonitorHTTPRequest.parse(foreign)
    precondition(foreignRequest?.allowedOrigin == nil)
    let partial = try MonitorHTTPRequest.parse(Data(requestBytes.prefix(10)))
    precondition(partial == nil)
    for invalid in ["POST /config HTTP/1.1\r\nContent-Length: -1\r\n\r\n", "GET /state HTTP/1.1\r\nHost: x\r\nHost: y\r\n\r\n", "GET /state HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"] {
        do { _ = try MonitorHTTPRequest.parse(Data(invalid.utf8)); fatalError("Invalid HTTP accepted") } catch { precondition(error is CocoaError || error is DecodingError, "Unexpected validation error: \(error)") }
    }
    var config = try MonitorConfig.decode(Data(#"{"bucketMinutes":15,"menuBarMetric":"tokens"}"#.utf8))
    precondition(config.showToday && config.bucketMinutes == 15 && config.menuBarMetric == "tokens")
    do {
        _ = try MonitorConfig.decode(Data(#"{"bucketMinutes":0}"#.utf8))
        fatalError("Invalid config accepted")
    } catch { precondition(error is CocoaError || error is DecodingError, "Unexpected validation error: \(error)") }
    config.hiddenProviders = ["opencode-go"]
    let providerConfig = try MonitorConfig.decode(JSONEncoder().encode(config))
    precondition(!providerConfig.showsProvider("opencode-go") && providerConfig.showsProvider("openai"))
    let windows = try goWindows(Data(#"{"usage":{"rolling":{"percent":17,"resetsAt":"2026-09-18T11:23:56.254Z"},"weekly":{"percent":"61","resetsAt":1800000000000}}}"#.utf8))
    precondition(windows.count == 3 && remainingPercent(windows[0].used) == 83)
    precondition(windows[0].reset != nil && windows[1].reset == 1_800_000_000 && windows[2].used == nil)
    let safe = try JSONDecoder().decode(ProviderConnection.self, from: Data(#"{"baseUrl":"https://opencode.ai/zen/go/v1/"}"#.utf8))
    let unsafe = try JSONDecoder().decode(ProviderConnection.self, from: Data(#"{"baseUrl":"https://opencode.ai.evil.example/zen/go/v1"}"#.utf8))
    precondition(safe.isOpenCodeGo && !unsafe.isOpenCodeGo)
    precondition(renderTemplate("요청 {requests}회 {{고정}} {unknown}", values: ["requests": "1,234"]) == "요청 1,234회 {고정} {unknown}")
    precondition(renderTemplate("{a}", values: ["a": "{b}", "b": "bad"]) == "{b}")
    precondition(renderTemplate("{totalTokens.raw} / {totalTokens.compact}", values: numberFields(["totalTokens": 25000000])) == "25000000 / 25.0M")
    precondition(axisTokens(75000000) == "75M" && axisTokens(0) == "0")
    precondition(legendName("a/model", among: ["a/model", "b/other"]) == "model")
    precondition(legendName("a/model", among: ["a/model", "b/model"]) == "a/model")
    let styled = try MonitorConfig.decode(Data(##"{"menuWidth":420,"menuGraphHeight":140,"textColor":"#EEEEEE","modelColors":{"test/a":"#AA00FF"},"todayLines":["호출 {requests}번"]}"##.utf8))
    precondition(styled.menuWidth == 420 && styled.todayLines == ["호출 {requests}번"] && styled.modelColors["test/a"] == "#AA00FF")
    for bad in [##"{"textColor":"red"}"##, ##"{"graphPalette":[]}"##, ##"{"menuWidth":0}"##] {
        do { _ = try MonitorConfig.decode(Data(bad.utf8)); fatalError("Invalid appearance accepted") }
        catch { precondition(error is CocoaError || error is DecodingError, "Unexpected validation error: \(error)") }
    }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let row = UsageRow(requestId: "one", timestamp: now.timeIntervalSince1970 * 1000,
                       provider: "test", model: "example", usage: TokenUsage(inputTokens: 100, outputTokens: 20, cachedInputTokens: 80))
    var revised = row
    revised.usage?.outputTokens = 30
    let graph = aggregate([row, revised], config: config, now: now)
    precondition(graph.points.reduce(0) { $0 + $1.tokens } == 130, "Latest revision wins; cache must not double-count")
    config.tokenMetric = "output"
    precondition(aggregate([row], config: config, now: now).points.reduce(0) { $0 + $1.tokens } == 20)
    config.tokenMetric = "total"
    var retried = row
    retried.attempts = [UsageAttempt(provider: "test", model: "a", totalTokens: 10), UsageAttempt(provider: "test", model: "b", totalTokens: 30)]
    let attributed = aggregate([retried], config: config, now: now)
    precondition(attributed.availableModels == ["test/a", "test/b"])
    precondition(attributed.points.reduce(0) { $0 + $1.tokens } == 40, "Attempts replace parent totals")
    config.models = ["test/a"]
    precondition(aggregate([retried], config: config, now: now).points.reduce(0) { $0 + $1.tokens } == 10)
    config.models = []
    precondition(aggregate([retried], config: config, now: now).points.isEmpty)
    let roundTrip = try MonitorConfig.decode(JSONEncoder().encode(config))
    precondition(roundTrip.models == [], "Empty selection must survive persistence")
    config.models = ["test/a"]
    precondition(remainingPercent(nil) == nil && remainingPercent(61) == 39)
    precondition(remainingPercent(-10) == 100 && remainingPercent(120) == 0)
    precondition(quotaText(50, reset: now.timeIntervalSince1970 - 1, now: now, language: MonitorLanguage("ko")).contains("대기"))
    var grouped = MonitorConfig()
    grouped.language = "ko"
    var accountOne = row
    accountOne.accountLogLabel = "p1"
    var accountTwo = row
    accountTwo = UsageRow(requestId: "two", timestamp: row.timestamp, provider: row.provider, model: row.model,
                          usage: row.usage, accountLogLabel: "p2")
    let merged = aggregate([accountOne, accountTwo], config: grouped, now: now)
    precondition(merged.availableSeries == ["example"])
    precondition(merged.points.reduce(0) { $0 + $1.tokens } == 240)
    grouped.chartGrouping = "modelAccount"
    let split = aggregate([accountOne, accountTwo], config: grouped, now: now)
    precondition(split.availableSeries.count == 2 && split.availableSeries.contains("example · test/p1"))
    precondition(split.points.reduce(0) { $0 + $1.tokens } == 240)
    precondition(aggregate([row], config: grouped, now: now).availableSeries.first?.contains("계정 미상") == true)
    grouped.chartStyle = "stackedBar"
    let persisted = try MonitorConfig.decode(JSONEncoder().encode(grouped))
    precondition(persisted.chartStyle == "stackedBar" && persisted.chartGrouping == "modelAccount")
    for invalid in [#"{"chartStyle":"pie"}"#, #"{"chartGrouping":"bad"}"#] {
        do { _ = try MonitorConfig.decode(Data(invalid.utf8)); fatalError("Invalid chart option") } catch { precondition(error is CocoaError || error is DecodingError, "Unexpected validation error: \(error)") }
    }
    let customInterval = try MonitorConfig.decode(Data(#"{"bucketMinutes":7}"#.utf8))
    precondition(customInterval.bucketMinutes == 7)
    precondition(aggregate([row], config: customInterval, now: now).bucketSeconds == 420)
    precondition(aggregate([row], config: customInterval, now: now).points.reduce(0) { $0 + $1.tokens } == 120)
    for invalid in [#"{"bucketMinutes":1441}"#, #"{"bucketMinutes":-1}"#, #"{"bucketMinutes":1.5}"#] {
        do { _ = try MonitorConfig.decode(Data(invalid.utf8)); fatalError("Invalid bucket interval") } catch { precondition(error is CocoaError || error is DecodingError, "Unexpected validation error: \(error)") }
    }
    var calculated = MonitorConfig()
    var retrySame = row
    retrySame.attempts = [UsageAttempt(provider: "test", model: "example", totalTokens: 10),
                          UsageAttempt(provider: "test", model: "example", totalTokens: 30)]
    var other = accountTwo
    other.usage = TokenUsage(inputTokens: 50, outputTokens: 10)
    let unmeasured = UsageRow(requestId: "missing", timestamp: row.timestamp, provider: "test", model: "example")
    calculated.aggregation = "average"
    let average = aggregate([row, retrySame, other, unmeasured], config: calculated, now: now)
    precondition(average.points.reduce(0) { $0 + $1.tokens } == 50, "Count each measured request once after summing retries and deduplicating revisions")
    precondition(average.points.contains { $0.tokens == 0 }, "Empty buckets remain zero")
    calculated.aggregation = "max"
    precondition(aggregate([retrySame, other], config: calculated, now: now).points.reduce(0) { $0 + $1.tokens } == 60)
    let calculationRoundTrip = try MonitorConfig.decode(JSONEncoder().encode(calculated))
    precondition(calculationRoundTrip.aggregation == "max")
    do { _ = try MonitorConfig.decode(Data(#"{"aggregation":"median"}"#.utf8)); fatalError("Invalid calculation") } catch { precondition(error is CocoaError || error is DecodingError, "Unexpected validation error: \(error)") }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let raw = #"{"requestId":"one","timestamp":1800000000000,"provider":"test","model":"a","totalTokens":42}"#
    try Data((raw + "\ninvalid\n" + raw.prefix(20)).utf8).write(to: folder.appendingPathComponent("usage.jsonl"))
    let loaded = try readGraph(home: folder, config: config, now: now)
    precondition(loaded.skipped == 1 && loaded.points.reduce(0) { $0 + $1.tokens } == 42)
}

private func tryBridge(_ data: Data) -> Bool {
    guard let request = try? MonitorHTTPRequest.parse(data) else { return false }
    return request.path == "/state" && request.allowedOrigin == "http://127.0.0.1:10100"
}
