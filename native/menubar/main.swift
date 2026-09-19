import AppKit
import Foundation
import SwiftUI

struct Health: Decodable {
    let service: String
    let status: String
    let version: String
    let pid: Int?
}

struct Usage: Codable {
    struct Totals: Codable {
        let requests: Int
        let totalTokens: Int
        let inputTokens: Int
        let outputTokens: Int
        let estimatedCostUsd: Double?
        let unpricedRequests: Int?
        let unmeteredRequests: Int?
    }
    struct Model: Codable {
        var id: String { "\(provider)/\(model)" }
        let provider: String
        let model: String
        let requests: Int
        let totalTokens: Int
    }
    let summary: Totals
    let models: [Model]
    let providers: [ProviderUsage]?
    let historyTruncated: Bool?
}

func compact(_ value: Int) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
    return String(value)
}

enum ProbeError: LocalizedError {
    case http(Int), wrongService, missingToken
    var errorDescription: String? { message(MonitorLanguage()) }
    func message(_ language: MonitorLanguage) -> String {
        switch self {
        case .http(let code): return language.text("상태 조회 실패 (HTTP \(code))", "Status request failed (HTTP \(code))")
        case .wrongService: return language.text("opencodex 서버를 확인할 수 없습니다", "Could not verify the OpenCodex server")
        case .missingToken: return language.text("opencodex 관리 인증 파일을 읽을 수 없습니다", "Could not read the OpenCodex management credential")
        }
    }
}

// Never forward a local management credential through an HTTP redirect.
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let base = URL(string: "http://127.0.0.1:10100")!
    let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".opencodex")
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    var timer: Timer?
    let state = MonitorState()
    var webBridge: MonitorWebBridge?
    var graphTask: Task<Void, Never>?
    var refreshing = false
    var health: Health?
    var usage: Usage?
    var updated: Date?
    var failure: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item.autosaveName = "OpenCodexMonitor"
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.setAccessibilityLabel(state.config.text("OpenCodex 사용량", "OpenCodex usage"))
        loadConfig()
        render()
        if !CommandLine.arguments.contains("--probe") {
            do {
                webBridge = try MonitorWebBridge(state: state, saved: { [weak self] in self?.saveSettings() })
            } catch { state.configError = state.config.text("대시보드 연결을 시작할 수 없습니다. 모니터를 다시 실행해주세요.", "Could not start the dashboard connection. Restart the monitor.") }
        }
        if CommandLine.arguments.contains("--dashboard") { openMonitor() }
        Task {
            await refresh()
            if CommandLine.arguments.contains("--probe") {
                if let error = failure ?? state.graphError ?? state.quotaError ?? state.configError { print("FAIL: \(error)"); exit(1) }
                print("PASS: live opencodex \(health?.version ?? "") · \(usage?.summary.requests ?? 0) requests · \(item.button?.title ?? "") · graph=\(state.graph?.points.count ?? 0) · accounts=\(state.accounts.count)")
                NSApp.terminate(nil)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 5
    }

    func listenerOwnedByCurrentUser(pid: Int) throws -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-a", "-p", String(pid), "-iTCP:10100", "-sTCP:LISTEN", "-Fpu"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        return task.terminationStatus == 0 && lines.contains("p\(pid)") && lines.contains("u\(getuid())")
    }

    func get<T: Decodable>(_ path: String, token: String? = nil) async throws -> T {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ProbeError.http(code) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        state.refreshing = true
        loadConfig()
        defer {
            refreshing = false
            state.refreshing = false
            state.usage = usage
            state.updated = updated
            state.failure = failure
            render()
        }
        do {
            let live: Health = try await get("/healthz")
            guard live.service == "opencodex", live.status == "ok" else { throw ProbeError.wrongService }
            // A health response alone does not identify the listener. Verify the live
            // PID and OS user before forwarding the user's management credential.
            guard let pid = live.pid, try listenerOwnedByCurrentUser(pid: pid) else { throw ProbeError.wrongService }
            health = live
            guard let token = try? String(contentsOf: home.appendingPathComponent("admin-api-token"),
                                          encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty else { throw ProbeError.missingToken }
            let result: Usage = try await get("/api/usage?range=today", token: token)
            usage = result
            updated = Date()
            failure = nil
            do {
                let quota: QuotaResponse = try await get("/api/codex-auth/quota", token: token)
                let configured = try JSONDecoder().decode(AccountConfig.self, from: Data(contentsOf: home.appendingPathComponent("config.json")))
                var accounts = configured.codexAccounts ?? []
                if !accounts.contains(where: { $0.id == "__main__" }) {
                    accounts.insert(AccountInfo(id: "__main__"), at: 0)
                }
                state.accounts = accounts
                state.quotas = quota.quotas
                state.quotaError = nil
            } catch { state.quotaError = state.config.text("계정 잔여량 조회 실패 · 이전 관측값입니다", "Could not refresh account limits · showing previous readings") }
        } catch {
            // Preserve the previous reading, but explicitly mark it stale.
            failure = (error as? ProbeError)?.message(state.config.locale) ?? state.config.text("연결 또는 응답 오류 — 잠시 후 재시도합니다", "Connection or response error — retrying shortly")
            state.quotaError = state.config.text("연결 실패 · 계정 값은 이전 관측입니다", "Connection failed · account readings are stale")
        }
        await refreshProviders()
        await refreshGraph()
    }

    func refreshProviders() async {
        guard let configured = try? JSONDecoder().decode(AccountConfig.self,
            from: Data(contentsOf: home.appendingPathComponent("config.json"))) else { return }
        state.providerNames = Array(Set((configured.providers ?? [:]).filter { $0.value.disabled != true }.map(\.key)
            + (usage?.providers ?? []).map(\.provider) + ["openai"])).sorted()
        for (name, connection) in configured.providers ?? [:]
            where connection.disabled != true && connection.isOpenCodeGo && state.config.showsProvider(name) {
            do {
                guard let key = connection.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !key.isEmpty, !key.hasPrefix("keychain:"), !key.hasPrefix("env:"), !key.hasPrefix("${") else {
                    state.providerErrors[name] = state.config.text("인증 정보 확인 필요", "Check provider credentials")
                    state.providerWindows[name] = nil
                    continue
                }
                var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!)
                request.timeoutInterval = 10
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("OpenCodexMonitor/0.1", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw ProbeError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                guard data.count <= 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                state.providerWindows[name] = try goWindows(data, language: state.config.locale)
                state.providerErrors[name] = nil
            } catch {
                state.providerWindows[name] = nil
                state.providerErrors[name] = state.config.text("잔여 한도 조회 불가", "Remaining limits unavailable")
            }
        }
    }

    func loadConfig() {
        do {
            if !FileManager.default.fileExists(atPath: MonitorConfig.file.path) { try state.config.save() }
            state.config = try MonitorConfig.decode(Data(contentsOf: MonitorConfig.file))
            state.configError = nil
        } catch { state.configError = state.config.text("config.json을 읽을 수 없습니다. 마지막 정상 설정을 유지합니다.", "Could not read config.json. Keeping the last valid settings.") }
    }

    func refreshGraph() async {
        let config = state.config
        guard config.showChart else { return }
        let home = home
        do {
            let graph = try await Task.detached(priority: .utility) { try readGraph(home: home, config: config) }.value
            guard state.config == config else { return }
            state.graph = graph
            state.graphError = nil
        } catch { state.graphError = state.config.text("사용 기록을 읽을 수 없습니다. 이전 그래프가 있으면 그대로 표시합니다.", "Could not read usage history. Keeping the previous graph if available.") }
    }

    func saveSettings() {
        state.config.localizeDefaults()
        do { try state.config.save(); state.configError = nil }
        catch { state.configError = state.config.text("설정을 저장하지 못했습니다. 디스크 접근 권한을 확인하세요.", "Could not save settings. Check disk permissions.") }
        render()
        graphTask?.cancel()
        graphTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await refreshProviders()
            await refreshGraph()
            render()
        }
    }

    func render() {
        item.button?.setAccessibilityLabel(state.config.text("OpenCodex 사용량", "OpenCodex usage"))
        let metric = state.config.menuBarMetric
        let value = usage.map { compact(metric == "tokens" ? $0.summary.totalTokens : $0.summary.requests) } ?? "…"
        item.button?.title = failure != nil ? "OCX !" : metric == "compact" ? "OCX" : "OCX \(value)"
        if failure == nil, let template = state.config.menuBarTemplate, let usage {
            item.button?.title = renderTemplate(template, values: todayFields(usage, language: state.config.locale))
        }
        item.button?.toolTip = failure ?? "OpenCodex · \(metric == "tokens" ? state.config.text("오늘 토큰 수", "Today’s tokens") : state.config.text("오늘 요청 수", "Today’s requests")) · \(state.config.text("60초마다 갱신", "updates every 60 seconds"))"
        let menu = NSMenu()
        menu.autoenablesItems = false
        func label(_ title: String) {
            let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.addItem(row)
        }
        func action(_ title: String, _ selector: Selector, key: String = "") {
            let row = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            row.target = self
            menu.addItem(row)
        }
        label("OpenCodex  \(health.map { "v\($0.version)" } ?? "")")
        label(failure == nil ? (usage == nil ? state.config.text("연결 확인 중…", "Connecting…") : state.config.text("● 연결됨 · 읽기 전용 모니터", "● Connected · read-only monitor")) : "⚠ \(failure!)")
        menu.addItem(.separator())
        if state.config.showToday, let usage {
            if failure != nil { label(state.config.text("이전 조회 값 · 현재 상태 아님", "Previous reading · not current")) }
            let row = NSMenuItem()
            row.view = NSHostingView(rootView: TodaySummary(usage: usage, config: state.config)
                .padding(.horizontal, 12).padding(.vertical, 7).frame(width: state.config.menuWidth))
            if let view = row.view { view.setFrameSize(NSSize(width: state.config.menuWidth, height: view.fittingSize.height)) }
            menu.addItem(row)
            if usage.historyTruncated == true { label(state.config.text("⚠ 기록 일부만 집계됨", "⚠ Only part of the history is included")) }
        }
        if state.config.showModels, let usage {
            menu.addItem(.separator())
            label(state.config.text("모델별 · 요청 수 순", "Models · sorted by requests"))
            for model in usage.models.sorted(by: { $0.requests > $1.requests }).prefix(8) {
                label("\(model.provider) / \(model.model)")
                label(state.config.text("    \(model.requests.formatted(.number.locale(state.config.locale.locale)))회 · \(compact(model.totalTokens)) 토큰", "    \(model.requests.formatted(.number.locale(state.config.locale.locale))) requests · \(compact(model.totalTokens)) tokens"))
            }
        }
        if state.config.showChart {
            menu.addItem(.separator())
            label("\(state.config.text("시간별 모델 토큰", "Model tokens over time")) · \(state.config.chartHours)h / \(state.config.bucketMinutes)min · \(state.config.aggregation == "average" ? state.config.text("요청당 평균", "Average per request") : state.config.aggregation == "max" ? state.config.text("요청당 최대", "Maximum per request") : state.config.text("합계", "Sum"))")
            if let graph = state.graph, !graph.points.isEmpty {
                let chart = NSMenuItem()
                chart.view = NSHostingView(rootView: TokenChart(graph: graph, config: state.config, compact: true).environment(\.locale, state.config.locale.locale).padding(12).frame(width: state.config.menuWidth))
                if let view = chart.view { view.setFrameSize(NSSize(width: state.config.menuWidth, height: view.fittingSize.height)) }
                menu.addItem(chart)
                label(state.config.text("그래프 기준 \(state.config.locale.date(graph.end))", "Graph as of \(state.config.locale.date(graph.end))"))
                if graph.truncated || graph.skipped > 0 { label(state.config.text("일부 기록만 집계 · 대시보드에서 상세 확인", "Partial history · see dashboard for details")) }
            } else { label(state.config.text("그래프 데이터 없음 · 대시보드에서 확인", "No graph data · check the dashboard")) }
            if let error = state.graphError { label(error) }
        }
        if state.config.showAccounts {
            menu.addItem(.separator())
            label(state.config.text("프로바이더 사용량", "Provider usage"))
            if let error = state.quotaError { label(error) }
            for account in state.accounts where state.config.showsProvider("openai") {
                let row = NSMenuItem()
                row.view = NSHostingView(rootView: AccountCard(account: account, quota: state.quotas[account.id])
                    .environment(\.monitorTheme, state.config)
                    .padding(.horizontal, 12).padding(.vertical, 7).frame(width: state.config.menuWidth))
                if let view = row.view { view.setFrameSize(NSSize(width: state.config.menuWidth, height: view.fittingSize.height)) }
                menu.addItem(row)
            }
        }
        if state.config.showAccounts {
            for name in state.providerNames where name != "openai" && state.config.showsProvider(name) {
                let row = NSMenuItem()
                row.view = NSHostingView(rootView: ProviderCard(name: name,
                    usage: usage?.providers?.first { $0.provider == name }, windows: state.providerWindows[name],
                    error: state.providerErrors[name])
                    .environment(\.monitorTheme, state.config)
                    .padding(.horizontal, 12).padding(.vertical, 7).frame(width: state.config.menuWidth))
                if let view = row.view { view.setFrameSize(NSSize(width: state.config.menuWidth, height: view.fittingSize.height)) }
                menu.addItem(row)
            }
        }
        menu.addItem(.separator())
        if let error = state.configError { label(error) }
        action(state.config.text("OpenCodex 대시보드 · 표시 설정…", "OpenCodex dashboard · display settings…"), #selector(openMonitor), key: "d")
        if let updated { label(state.config.text("마지막 갱신 \(state.config.locale.date(updated, time: .standard)) · 60초 간격", "Updated \(state.config.locale.date(updated, time: .standard)) · every 60 seconds")) }
        let languageMenu = NSMenu()
        for (code, title) in [("auto", state.config.text("시스템 설정 따르기", "Follow system")), ("en", "English"), ("ko", "한국어")] {
            let choice = NSMenuItem(title: title, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = code
            choice.state = state.config.language == code ? .on : .off
            languageMenu.addItem(choice)
        }
        let languageItem = NSMenuItem(title: state.config.text("언어", "Language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        action(state.config.text("지금 새로고침", "Refresh now"), #selector(refreshClicked), key: "r")
        menu.addItem(.separator())
        action(state.config.text("모니터 종료", "Quit monitor"), #selector(quit), key: "q")
        item.menu = menu
    }

    @objc func changeLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String, ["auto", "en", "ko"].contains(language) else { return }
        let previous = state.config
        state.config.language = language
        state.config.localizeDefaults()
        do { try state.config.save() }
        catch { state.config = previous; state.configError = previous.text("설정을 저장하지 못했습니다", "Could not save settings"); render(); return }
        render()
        Task { await refresh() }
    }

    @objc func openMonitor() {
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:10100/#usage/monitor")!)
    }
    @objc func refreshClicked() { Task { await refresh() } }
    @objc func openDashboard() { NSWorkspace.shared.open(base) }
    @objc func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--self-test") {
    precondition(compact(0) == "0")
    precondition(compact(999) == "999")
    precondition(compact(1_000) == "1.0k")
    precondition(compact(2_500_000) == "2.5M")
    let fixture = #"{"summary":{"requests":12,"totalTokens":1400,"inputTokens":1000,"outputTokens":400},"models":[{"provider":"test","model":"example","requests":12,"totalTokens":1400}]}"#
    let parsed = try JSONDecoder().decode(Usage.self, from: Data(fixture.utf8))
    precondition(parsed.summary.requests == 12 && parsed.summary.estimatedCostUsd == nil)
    precondition(parsed.models.first?.provider == "test")
    do {
        _ = try JSONDecoder().decode(Usage.self, from: Data("{}".utf8))
        fatalError("Malformed responses must fail instead of showing zero usage")
    } catch { precondition(error is DecodingError, "Expected a usage decoding error, got: \(error)") }
    try dataSelfTest()
    print("PASS: formatting, usage decoding, absent pricing, malformed response, graph aggregation, quotas, config")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
