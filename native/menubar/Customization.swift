import Foundation
import SwiftUI

func validColor(_ value: String) -> Bool {
    ["primary", "secondary"].contains(value)
        || value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
}
func themeColor(_ value: String) -> Color {
    if value == "primary" { return .primary }
    if value == "secondary" { return .secondary }
    guard let rgb = UInt32(value.dropFirst(), radix: 16) else { return .primary }
    return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                 blue: Double(rgb & 255) / 255)
}

// A single substitution pass: literal text only, never evaluate code or recursively expand values.
func renderTemplate(_ template: String, values: [String: String]) -> String {
    let regex = try! NSRegularExpression(pattern: #"\{\{|\}\}|\{([A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z]+)?)\}"#)
    let source = template as NSString
    var output = ""
    var cursor = 0
    for match in regex.matches(in: template, range: NSRange(location: 0, length: source.length)) {
        output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
        let token = source.substring(with: match.range)
        if token == "{{" { output += "{" }
        else if token == "}}" { output += "}" }
        else { output += values[source.substring(with: match.range(at: 1))] ?? token }
        cursor = NSMaxRange(match.range)
    }
    output += source.substring(from: cursor)
    return output
}

func numberFields(_ numbers: [String: Int], language: MonitorLanguage = MonitorLanguage()) -> [String: String] {
    var result: [String: String] = [:]
    for (name, value) in numbers {
        result[name] = name.lowercased().contains("tokens") ? compact(value) : value.formatted(.number.locale(language.locale))
        result[name + ".raw"] = String(value)
        result[name + ".compact"] = compact(value)
        result[name + ".formatted"] = value.formatted(.number.locale(language.locale))
    }
    return result
}

func todayFields(_ usage: Usage, language: MonitorLanguage = MonitorLanguage()) -> [String: String] {
    var fields = numberFields([
        "requests": usage.summary.requests, "totalTokens": usage.summary.totalTokens,
        "inputTokens": usage.summary.inputTokens, "outputTokens": usage.summary.outputTokens,
        "unpricedRequests": usage.summary.unpricedRequests ?? 0,
        "unmeteredRequests": usage.summary.unmeteredRequests ?? 0,
        "excludedRequests": (usage.summary.unpricedRequests ?? 0) + (usage.summary.unmeteredRequests ?? 0)
    ], language: language)
    fields["costUsd"] = usage.summary.estimatedCostUsd.map { String(format: "%.2f", $0) } ?? "—"
    fields["date"] = language.date(Date(), date: .abbreviated, time: .omitted)
    return fields
}

func legendName(_ full: String, among models: [String]) -> String {
    let short = full.split(separator: "/", maxSplits: 1).last.map(String.init) ?? full
    let duplicates = models.filter { ($0.split(separator: "/", maxSplits: 1).last.map(String.init) ?? $0) == short }
    return duplicates.count > 1 ? full : short
}

struct TodaySummary: View {
    let usage: Usage
    let config: MonitorConfig
    var body: some View {
        let fields = todayFields(usage, language: config.locale)
        VStack(alignment: .leading, spacing: 6) {
            Text(renderTemplate(config.todayTitle, values: fields)).font(.headline)
            ForEach(Array(config.todayLines.enumerated()), id: \.offset) { _, line in
                Text(renderTemplate(line, values: fields)).monospacedDigit()
            }
            if config.showCost {
                ForEach(Array(config.costLines.enumerated()), id: \.offset) { _, line in
                    Text(renderTemplate(line, values: fields))
                        .font(.caption).foregroundStyle(themeColor(config.secondaryColor))
                }
            }
        }
        .foregroundStyle(themeColor(config.textColor))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MonitorThemeKey: EnvironmentKey {
    static let defaultValue = MonitorConfig()
}
extension EnvironmentValues {
    var monitorTheme: MonitorConfig {
        get { self[MonitorThemeKey.self] }
        set { self[MonitorThemeKey.self] = newValue }
    }
}

func axisTokens(_ value: Double) -> String {
    guard value.isFinite else { return "—" }
    for (scale, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "k")] where abs(value) >= scale {
        return String(format: "%.1f", value / scale).replacingOccurrences(of: ".0", with: "") + suffix
    }
    return String(format: "%.0f", value)
}
