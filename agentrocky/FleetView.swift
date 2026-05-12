import SwiftUI

struct FleetInstance: Identifiable, Decodable {
    let id: String
    let shortId: String
    let issue: String
    let repo: String
    let session: String?
    let status: String
    let description: String
    let prUrl: String?
    let blockedReason: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, repo, session, status, description, issue
        case shortId       = "short_id"
        case prUrl         = "pr_url"
        case blockedReason = "blocked_reason"
        case createdAt     = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        shortId       = try c.decode(String.self, forKey: .shortId)
        issue         = (try? c.decodeIfPresent(String.self, forKey: .issue)) ?? ""
        repo          = try c.decode(String.self, forKey: .repo)
        session       = try c.decodeIfPresent(String.self, forKey: .session)
        status        = try c.decode(String.self, forKey: .status)
        description   = try c.decode(String.self, forKey: .description)
        let rawPr     = try c.decodeIfPresent(String.self, forKey: .prUrl)
        prUrl         = (rawPr?.isEmpty == false) ? rawPr : nil
        let rawBlocked = try c.decodeIfPresent(String.self, forKey: .blockedReason)
        blockedReason = (rawBlocked?.isEmpty == false) ? rawBlocked : nil

        if let dateStr = try? c.decodeIfPresent(String.self, forKey: .createdAt) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: dateStr) {
                createdAt = d
            } else {
                // Python's datetime.isoformat() omits timezone
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                createdAt = df.date(from: dateStr)
            }
        } else {
            createdAt = nil
        }
    }
}

struct FleetView: View {
    @State private var instances: [FleetInstance] = []
    @State private var lastUpdated: Date = Date()
    @State private var timer: Timer?
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private var availableDays: [Date] {
        let cal = Calendar.current
        let days = Set(instances.compactMap { inst -> Date? in
            guard let d = inst.createdAt else { return nil }
            return cal.startOfDay(for: d)
        })
        return days.sorted()
    }

    private var filtered: [FleetInstance] {
        let cal = Calendar.current
        return instances.filter { inst in
            guard let d = inst.createdAt else { return false }
            return cal.isDate(d, inSameDayAs: selectedDate)
        }
    }

    private var canGoPrev: Bool {
        guard let idx = availableDays.firstIndex(of: selectedDate) else { return false }
        return idx > 0
    }

    private var canGoNext: Bool {
        guard let idx = availableDays.firstIndex(of: selectedDate) else { return false }
        return idx < availableDays.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.1))
            content
        }
        .onAppear { refresh(); startTimer() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            Text("fleet")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button("←") { stepDay(-1) }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(canGoPrev ? .white.opacity(0.7) : .white.opacity(0.15))
                .buttonStyle(.plain)
                .disabled(!canGoPrev)
            Text(dayLabel(selectedDate))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
                .frame(minWidth: 56, alignment: .center)
            Button("→") { stepDay(1) }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(canGoNext ? .white.opacity(0.7) : .white.opacity(0.15))
                .buttonStyle(.plain)
                .disabled(!canGoNext)
            Text("· \(secondsAgo())s")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            Button {
                refresh()
            } label: {
                Text("↺")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            VStack {
                Spacer()
                Text(instances.isEmpty ? "sin instancias activas" : "sin instancias este día")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 1) {
                    ForEach(filtered) { instance in
                        FleetRow(instance: instance)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            refresh()
        }
    }

    private func refresh() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["\(NSHomeDirectory())/.arkan-fleet/fleet.py", "list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.launch()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let decoded = try? JSONDecoder().decode([FleetInstance].self, from: data) else { return }

        let cal = Calendar.current
        let days = Set(decoded.compactMap { inst -> Date? in
            guard let d = inst.createdAt else { return nil }
            return cal.startOfDay(for: d)
        }).sorted()

        DispatchQueue.main.async {
            self.instances = decoded
            self.lastUpdated = Date()
            if !days.contains(self.selectedDate), let last = days.last {
                self.selectedDate = last
            }
        }
    }

    private func stepDay(_ delta: Int) {
        guard let idx = availableDays.firstIndex(of: selectedDate) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0, newIdx < availableDays.count else { return }
        selectedDate = availableDays[newIdx]
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "hoy" }
        if cal.isDateInYesterday(date) { return "ayer" }
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"
        fmt.locale = Locale(identifier: "es_MX")
        return fmt.string(from: date)
    }

    private func secondsAgo() -> Int {
        Int(Date().timeIntervalSince(lastUpdated))
    }
}

// MARK: - FleetRow

struct FleetRow: View {
    let instance: FleetInstance

    private var statusColor: Color {
        switch instance.status {
        case "running":  return Color(red: 0.4, green: 0.9, blue: 0.5)
        case "done":     return Color(red: 0.4, green: 0.8, blue: 1.0)
        case "blocked":  return Color(red: 1.0, green: 0.6, blue: 0.1)
        case "error":    return Color(red: 1.0, green: 0.4, blue: 0.4)
        case "killed":   return Color.white.opacity(0.3)
        default:         return Color.white.opacity(0.5)
        }
    }

    private var statusDot: String {
        switch instance.status {
        case "running":  return "●"
        case "done":     return "✓"
        case "blocked":  return "?"
        case "error":    return "✗"
        case "killed":   return "○"
        default:         return "◌"
        }
    }

    private var label: String {
        if let blocked = instance.blockedReason { return blocked }
        if !instance.description.isEmpty { return instance.description }
        if !instance.issue.isEmpty { return "#\(instance.issue) · \(instance.repo)" }
        return instance.repo
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(statusDot)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(statusColor)
                .frame(width: 10)

            Text(instance.shortId)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 64, alignment: .leading)

            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(instance.status == "blocked" ? Color(red: 1.0, green: 0.6, blue: 0.1) : .white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            if let prUrl = instance.prUrl, let url = URL(string: prUrl) {
                Button("PR↗") {
                    NSWorkspace.shared.open(url)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(red: 0.9, green: 0.7, blue: 0.3))
                .buttonStyle(.plain)
            }

            Button("abrir") {
                openInstance()
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.03))
    }

    private func runFleet(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["\(NSHomeDirectory())/.arkan-fleet/fleet.py"] + args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private func openInstance() {
        if instance.status == "done" {
            runFleet(["resume", instance.id])
        }
        runFleet(["open", instance.id])
    }
}
