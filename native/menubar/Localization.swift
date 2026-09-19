import Foundation

struct MonitorLanguage: Sendable {
    let code: String
    init(_ setting: String = "auto", preferred: [String] = Locale.preferredLanguages) {
        // Follow the first system language; unsupported languages fall back to English.
        let first = (preferred.first ?? "en").lowercased().replacingOccurrences(of: "_", with: "-")
        code = setting == "auto" ? (first == "ko" || first.hasPrefix("ko-") ? "ko" : "en") : setting
    }
    var locale: Locale { Locale(identifier: code == "ko" ? "ko_KR" : "en_US") }
    func date(_ value: Date, date: Date.FormatStyle.DateStyle = .omitted, time: Date.FormatStyle.TimeStyle = .shortened) -> String {
        value.formatted(Date.FormatStyle(date: date, time: time).locale(locale))
    }
    func text(_ korean: String, _ english: String) -> String { code == "ko" ? korean : english }
}

extension MonitorConfig {
    var locale: MonitorLanguage { MonitorLanguage(language) }
    func text(_ korean: String, _ english: String) -> String { locale.text(korean, english) }

    // Only exact built-in defaults are translated. Custom templates remain literal.
    mutating func localizeDefaults() {
        func translated(_ value: String, _ ko: String, _ en: String) -> String {
            value == ko || value == en ? text(ko, en) : value
        }
        todayTitle = translated(todayTitle, "오늘 사용량", "Today’s usage")
        let koToday = ["요청 {requests}회", "전체 토큰 {totalTokens}", "입력 {inputTokens} · 출력 {outputTokens}"]
        let enToday = ["Requests {requests}", "Total tokens {totalTokens}", "Input {inputTokens} · Output {outputTokens}"]
        let koCost = ["추정 비용 ${costUsd} · 실제 청구액 아님", "비용 계산 제외 {excludedRequests}회"]
        let enCost = ["Estimated cost ${costUsd} · not actual charges", "Requests excluded from cost {excludedRequests}"]
        if todayLines == koToday || todayLines == enToday { todayLines = locale.code == "ko" ? koToday : enToday }
        if costLines == koCost || costLines == enCost { costLines = locale.code == "ko" ? koCost : enCost }
        providerUsageTemplate = translated(providerUsageTemplate, "오늘 {requests}회 · {totalTokens} 토큰", "Today {requests} requests · {totalTokens} tokens")
    }
}
