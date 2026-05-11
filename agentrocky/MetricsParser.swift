//
//  MetricsParser.swift
//  agentrocky
//

import Foundation

struct UsageMetrics {
    var totalSessions: Int = 0
    var totalQuestions: Int = 0
    var totalTokens: Int = 0
    var topProjects: [(name: String, count: Int)] = []
    var hourDistribution: [Int: Int] = [:]
    var peakHour: Int? = nil
    var streak: Int = 0
    var topSkills: [(name: String, count: Int)] = []
    var firstSessionDate: Date? = nil
    var sessionsToday: Int = 0
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

        var projectCounts: [String: Int] = [:]
        var skillCounts:   [String: Int] = [:]
        var hourCounts:    [Int: Int]    = [:]
        var sessionDays:   Set<String>   = []

        let calendar = Calendar.current
        let todayStr = dayString(calendar.startOfDay(for: Date()))

        for fileURL in jsonlFiles {
            // Modification date → streak + today count
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
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            var projectRecorded = false

            for line in content.components(separatedBy: "\n") {
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                let type = json["type"] as? String ?? ""

                // First cwd found → session's project
                if !projectRecorded, let cwd = json["cwd"] as? String, !cwd.isEmpty {
                    let project = URL(fileURLWithPath: cwd).lastPathComponent
                    if !project.isEmpty {
                        projectCounts[project, default: 0] += 1
                        projectRecorded = true
                    }
                }

                if type == "user" {
                    let text = extractText(from: json)

                    if !text.isEmpty {
                        metrics.totalQuestions += 1

                        // Detect /skill invocations
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("/") {
                            let firstWord = trimmed.components(separatedBy: .whitespaces).first ?? ""
                            let clean = String(firstWord.prefix(while: {
                                $0.isLetter || $0 == "-" || $0 == "/" || $0.isNumber || $0 == "_" || $0 == ":"
                            }))
                            if clean.count > 1 {
                                skillCounts[clean, default: 0] += 1
                            }
                        }
                    }

                    // Hour from timestamp
                    if let tsStr = json["timestamp"] as? String,
                       let date = parseISO8601(tsStr) {
                        let hour = calendar.component(.hour, from: date)
                        hourCounts[hour, default: 0] += 1
                    }
                }

                if type == "result",
                   let usage = json["usage"] as? [String: Any] {
                    metrics.totalTokens += (usage["input_tokens"] as? Int ?? 0)
                        + (usage["output_tokens"] as? Int ?? 0)
                }
            }
        }

        metrics.streak      = calculateStreak(days: sessionDays, calendar: calendar)
        metrics.topProjects = projectCounts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        metrics.topSkills   = skillCounts.sorted   { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        metrics.hourDistribution = hourCounts
        metrics.peakHour    = hourCounts.max(by: { $0.value < $1.value })?.key
        metrics.loadedAt    = Date()

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
