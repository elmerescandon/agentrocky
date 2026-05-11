import SwiftUI

struct FleetInstance: Identifiable, Decodable {
    let id: String
    let shortId: String
    let repo: String
    let session: String
    let status: String
    let description: String
    let prUrl: String?
    let blockedReason: String?

    enum CodingKeys: String, CodingKey {
        case id, repo, session, status, description
        case shortId      = "short_id"
        case prUrl        = "pr_url"
        case blockedReason = "blocked_reason"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        shortId       = try c.decode(String.self, forKey: .shortId)
        repo          = try c.decode(String.self, forKey: .repo)
        session       = try c.decode(String.self, forKey: .session)
        status        = try c.decode(String.self, forKey: .status)
        description   = try c.decode(String.self, forKey: .description)
        let rawPr     = try c.decodeIfPresent(String.self, forKey: .prUrl)
        prUrl         = (rawPr?.isEmpty == false) ? rawPr : nil
        let rawBlocked = try c.decodeIfPresent(String.self, forKey: .blockedReason)
        blockedReason = (rawBlocked?.isEmpty == false) ? rawBlocked : nil
    }
}

struct FleetView: View {
    @State private var instances: [FleetInstance] = []
    @State private var lastUpdated: Date = Date()
    @State private var timer: Timer?

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
        HStack {
            Text("fleet")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text("actualizado \(secondsAgo())s")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
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
        if instances.isEmpty {
            VStack {
                Spacer()
                Text("sin instancias activas")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(instances) { instance in
                        FleetRow(instance: instance)
                    }
                }
                .padding(.vertical, 6)
            }
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
        process.arguments = [
            "\(NSHomeDirectory())/.arkan-fleet/fleet.py", "list"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.launch()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let decoded = try? JSONDecoder().decode([FleetInstance].self, from: data) {
            DispatchQueue.main.async {
                instances = decoded
                lastUpdated = Date()
            }
        }
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

            Text(instance.blockedReason ?? (instance.description.isEmpty ? instance.repo : instance.description))
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
