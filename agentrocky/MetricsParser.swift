//
//  MetricsParser.swift
//  agentrocky
//

import Foundation

struct MonthMetrics {
    var totalTokens: Int = 0
    var totalQuestions: Int = 0
    var totalSessions: Int = 0
    var hourDistribution: [Int: Int] = [:]
    var dailyQuestions: [String: Int] = [:]

    var peakHour: Int? { hourDistribution.max(by: { $0.value < $1.value })?.key }
    var peakDay:  String? { dailyQuestions.max(by: { $0.value < $1.value })?.key }
}

struct UsageMetrics {
    var totalSessions: Int = 0
    var totalQuestions: Int = 0
    var totalTokens: Int = 0
    var hourDistribution: [Int: Int] = [:]
    var peakHour: Int? = nil
    var streak: Int = 0
    var firstSessionDate: Date? = nil
    var sessionsToday: Int = 0
    var dailyQuestions: [String: Int] = [:]
    var months: [String: MonthMetrics] = [:]       // "yyyy-MM" → MonthMetrics
    var availableMonths: [String] = []             // sorted descending
    var loadedAt: Date = Date()
}

enum MetricsParser {

    static func load(from dir: URL) async -> UsageMetrics {
        await Task.detached(priority: .userInitiated) { loadSync(from: dir) }.value
    }

    // MARK: - Core parser

    private static func loadSync(from dir: URL) -> UsageMetrics {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return UsageMetrics() }

        let jsonlFiles = items.filter {
            let name = $0.deletingPathExtension().lastPathComponent
            return $0.pathExtension == "jsonl"
                && name.count == 36
                && name.filter({ $0 == "-" }).count == 4
        }

        var metrics = UsageMetrics()
        metrics.totalSessions = jsonlFiles.count

        var hourCounts:     [Int: Int]    = [:]
        var dailyQuestions: [String: Int] = [:]
        var sessionDays:    Set<String>   = []
        var monthData:      [String: MonthMetrics] = [:]

        let calendar = Calendar.current
        let todayStr = dayString(calendar.startOfDay(for: Date()))

        for fileURL in jsonlFiles {
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            if let modDate = attrs?[.modificationDate] as? Date {
                let ds = dayString(calendar.startOfDay(for: modDate))
                sessionDays.insert(ds)
                if ds == todayStr { metrics.sessionsToday += 1 }
                if let prev = metrics.firstSessionDate {
                    if modDate < prev { metrics.firstSessionDate = modDate }
                } else {
                    metrics.firstSessionDate = modDate
                }
                monthData[month(from: ds), default: MonthMetrics()].totalSessions += 1
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") {
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                let type = json["type"] as? String ?? ""

                if type == "user" {
                    let text = extractText(from: json)
                    if let tsStr = json["timestamp"] as? String,
                       let date = parseISO8601(tsStr) {
                        let hour = calendar.component(.hour, from: date)
                        let ds   = dayString(calendar.startOfDay(for: date))
                        let mk   = month(from: ds)

                        hourCounts[hour, default: 0] += 1
                        dailyQuestions[ds, default: 0] += 1

                        monthData[mk, default: MonthMetrics()].hourDistribution[hour, default: 0] += 1
                        monthData[mk, default: MonthMetrics()].dailyQuestions[ds, default: 0] += 1

                        if !text.isEmpty {
                            metrics.totalQuestions += 1
                            monthData[mk, default: MonthMetrics()].totalQuestions += 1
                        }
                    }
                }

                if type == "assistant",
                   let message = json["message"] as? [String: Any],
                   let usage   = message["usage"] as? [String: Any] {
                    let output = usage["output_tokens"] as? Int ?? 0
                    metrics.totalTokens += output

                    if let tsStr = json["timestamp"] as? String,
                       let date = parseISO8601(tsStr) {
                        let mk = month(from: dayString(calendar.startOfDay(for: date)))
                        monthData[mk, default: MonthMetrics()].totalTokens += output
                    }
                }
            }
        }

        metrics.streak           = calculateStreak(days: sessionDays, calendar: calendar)
        metrics.hourDistribution = hourCounts
        metrics.peakHour         = hourCounts.max(by: { $0.value < $1.value })?.key
        metrics.dailyQuestions   = dailyQuestions
        metrics.months           = monthData
        metrics.availableMonths  = monthData.keys.sorted().reversed()
        metrics.loadedAt         = Date()

        return metrics
    }

    // MARK: - Helpers

    private static func extractText(from json: [String: Any]) -> String {
        guard let msg = json["message"] as? [String: Any] else { return "" }
        if let s = msg["content"] as? String { return s }
        if let arr = msg["content"] as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    private static func dayString(_ date: Date) -> String { dayFmt.string(from: date) }
    private static func month(from ds: String) -> String  { String(ds.prefix(7)) }

    private static let isoA: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoB: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISO8601(_ s: String) -> Date? {
        isoA.date(from: s) ?? isoB.date(from: s)
    }

    private static func calculateStreak(days: Set<String>, calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        var current = calendar.startOfDay(for: Date())

        if !days.contains(dayString(current)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: current),
                  days.contains(dayString(yesterday))
            else { return 0 }
            current = yesterday
        }

        var streak = 0
        while days.contains(dayString(current)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: current) else { break }
            current = prev
        }
        return streak
    }
}
