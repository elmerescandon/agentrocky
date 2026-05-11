//
//  RockyState.swift
//  agentrocky
//

import Foundation
import Combine
import Darwin

class RockyState: ObservableObject {
    @Published var isChatOpen: Bool = false
    @Published var sessions: [ClaudeSession] = []
    @Published var activeIndex: Int = 0

    // Forwarded from active session so views don't need to re-subscribe on tab switch
    @Published var activeIsRunning: Bool = false
    @Published var activeErrorCount: Int = 0
    @Published var activeIsReady: Bool = false
    @Published var activeLines: [ClaudeSession.OutputLine] = []
    @Published var activeContextPercent: Double? = nil

    @Published var history: [HistoryEntry] = []
    @Published var metrics: UsageMetrics? = nil
    @Published var isLoadingMetrics = false

    private var sessionCancellables = Set<AnyCancellable>()

    init() {
        loadHistory()
        // Reanudar la sesión más reciente si existe, si no crear una nueva
        if let latest = history.first {
            addSession(resuming: latest.id)
        } else {
            addSession()
        }
    }

    var activeSession: ClaudeSession { sessions[activeIndex] }

    // MARK: - Session management

    func addSession(resuming sessionId: String? = nil) {
        let session = ClaudeSession(workingDirectory: realHome + "/Documents/ArkangelAI/arkangel-vault", resumeSessionId: sessionId)
        sessions.append(session)
        switchTo(sessions.count - 1)
    }

    func closeSession(at index: Int) {
        guard sessions.count > 1 else { return }
        sessions[index].terminate()
        sessions.remove(at: index)
        // If we closed a tab before the active one, shift index down
        let newIndex = index < activeIndex ? activeIndex - 1 : min(activeIndex, sessions.count - 1)
        switchTo(newIndex)
    }

    func switchTo(_ index: Int) {
        guard index < sessions.count else { return }
        activeIndex = index
        subscribeToActiveSession()
    }

    // MARK: - Metrics

    func loadMetrics() {
        guard !isLoadingMetrics else { return }
        isLoadingMetrics = true
        Task {
            let m = await MetricsParser.load(from: historyDir)
            await MainActor.run {
                self.metrics = m
                self.isLoadingMetrics = false
            }
        }
    }

    // MARK: - History

    func loadHistory() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: historyDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        history = items
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { HistoryEntry(url: $0) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Private

    private func subscribeToActiveSession() {
        sessionCancellables.removeAll()
        let active = sessions[activeIndex]

        active.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.activeIsRunning = v }
            .store(in: &sessionCancellables)

        active.$errorCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.activeErrorCount = v }
            .store(in: &sessionCancellables)

        active.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.activeIsReady = v }
            .store(in: &sessionCancellables)

        active.$lines
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.activeLines = v }
            .store(in: &sessionCancellables)

        active.$contextPercent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in self?.activeContextPercent = v }
            .store(in: &sessionCancellables)
    }

    var historyDir: URL {
        URL(fileURLWithPath: realHome)
            .appendingPathComponent(".claude/projects/\(projectKey)")
    }

    private var projectKey: String {
        (realHome + "/Documents/ArkangelAI/arkangel-vault")
            .replacingOccurrences(of: "/", with: "-")
    }

    private var realHome: String {
        getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? NSHomeDirectory()
    }
}

// MARK: - History entry

struct HistoryEntry: Identifiable {
    let id: String        // UUID del archivo .jsonl
    let modifiedAt: Date
    let preview: String   // primer mensaje del usuario

    init?(url: URL) {
        let filename = url.deletingPathExtension().lastPathComponent
        // Solo UUIDs (36 chars con guiones)
        guard filename.count == 36, filename.filter({ $0 == "-" }).count == 4 else { return nil }
        id = filename

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        modifiedAt = attrs?[.modificationDate] as? Date ?? .distantPast

        // Leer solo los primeros 8KB para extraer el primer mensaje del usuario
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let data = handle.readData(ofLength: 8192)
        try? handle.close()
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let firstUser = content.components(separatedBy: "\n").lazy.compactMap { line -> String? in
            guard !line.isEmpty,
                  let d = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  json["type"] as? String == "user",
                  let msg = json["message"] as? [String: Any]
            else { return nil }
            if let s = msg["content"] as? String, !s.isEmpty { return s }
            if let arr = msg["content"] as? [[String: Any]] {
                return arr.compactMap { $0["text"] as? String }.first
            }
            return nil
        }.first

        preview = firstUser ?? filename
    }
}
