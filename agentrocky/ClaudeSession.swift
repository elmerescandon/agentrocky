//
//  ClaudeSession.swift
//  agentrocky
//

import Foundation
import Combine
import Darwin

class ClaudeSession: ObservableObject, Identifiable {
    let id = UUID()
    let createdAt = Date()
    let workingDirectory: String

    @Published var lines: [OutputLine] = []
    @Published var isReady: Bool = false
    @Published var isRunning: Bool = false
    @Published var errorCount: Int = 0
    @Published var contextPercent: Double? = nil

    var draft: String = ""

    private(set) var sessionId: String?
    private let resumeSessionId: String?
    private var hasAutoRun = false

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readBuffer = Data()
    private var isCancelling = false
    private var isTerminating = false
    private let queue = DispatchQueue(label: "rocky.session", qos: .userInitiated)

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case text, tool, system, error }
    }

    var name: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: createdAt)
    }

    init(workingDirectory: String, resumeSessionId: String? = nil) {
        self.workingDirectory = workingDirectory
        self.resumeSessionId = resumeSessionId
        start()
    }

    deinit { process?.terminate() }

    // MARK: - Public

    func terminate() {
        isTerminating = true
        process?.terminate()
        process = nil
    }

    func restart() {
        isTerminating = true
        process?.terminate()
        process = nil
        stdinHandle = nil
        readBuffer = Data()
        DispatchQueue.main.async {
            self.lines = []
            self.isReady = false
            self.isRunning = false
            self.contextPercent = nil
        }
        start()
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        DispatchQueue.main.async {
            self.append("^C", kind: .system)
            self.isRunning = false
            // isReady se mantiene true — el input queda disponible de inmediato
        }
        // Solo SIGINT. Si Claude lo maneja sin morir, emitirá un result y continuará.
        // Si muere, terminationHandler se encarga del restart silencioso.
        process?.interrupt()
    }

    func send(prompt: String) {
        guard !isRunning else { return }
        isRunning = true

        let payload: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": prompt]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }

        queue.async { [weak self] in
            self?.stdinHandle?.write(Data((json + "\n").utf8))
        }
    }

    // MARK: - Process lifecycle

    private func start(resuming overrideId: String? = nil) {
        guard let claudePath = findClaude() else {
            append("arkan binary not found — checked:\n" + searchPaths().joined(separator: "\n"), kind: .error)
            return
        }

        let proc = Process()
        let stdinPipe  = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: claudePath)
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--input-format",  "stream-json",
            "--verbose",
            "--dangerously-skip-permissions"
        ]
        let resumeId = overrideId ?? resumeSessionId
        if let resume = resumeId {
            args += ["--resume", resume]
        }
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        proc.environment = env

        proc.standardInput  = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe

        stdinHandle = stdinPipe.fileHandleForWriting

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.receive(data) }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async { self?.append(trimmed, kind: .error) }
        }

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            let savedSessionId = self.sessionId
            let wasCancelling  = self.isCancelling
            let wasTerminating = self.isTerminating
            self.isCancelling  = false
            self.isTerminating = false
            self.process       = nil
            self.stdinHandle   = nil
            self.readBuffer    = Data()

            DispatchQueue.main.async {
                self.isRunning = false
                if wasTerminating {
                    // Stop intencional — no reiniciar
                    self.isReady = false
                } else if wasCancelling {
                    // El proceso murió por SIGINT — restart silencioso preservando sesión
                    self.start(resuming: savedSessionId)
                } else {
                    // Exit inesperado — mostrar error
                    self.isReady = false
                    self.append("Process exited (code \(p.terminationStatus))", kind: .system)
                    if p.terminationStatus != 0 { self.errorCount += 1 }
                }
            }
        }

        do {
            try proc.run()
            self.process = proc

            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, !self.isReady else { return }
                self.isReady = true
            }
        } catch {
            append("Failed to launch arkan: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: - Output parsing

    private func receive(_ data: Data) {
        readBuffer.append(data)
        while let idx = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = readBuffer[readBuffer.startIndex..<idx]
            readBuffer.removeSubrange(readBuffer.startIndex...idx)
            guard let str = String(data: lineData, encoding: .utf8),
                  !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            parse(str)
        }
    }

    private func parse(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            DispatchQueue.main.async { [weak self] in
                self?.append("[raw] \(raw)", kind: .system)
            }
            return
        }

        let type    = json["type"]    as? String ?? ""
        let subtype = json["subtype"] as? String ?? ""

        DispatchQueue.main.async { [weak self] in
            switch type {

            case "system" where subtype == "init":
                self?.sessionId = json["session_id"] as? String
                self?.isReady = true
                if self?.hasAutoRun == false && self?.resumeSessionId == nil {
                    self?.hasAutoRun = true
                    self?.send(prompt: "/arkan-pocket")
                }

            case "assistant":
                guard let message = json["message"] as? [String: Any],
                      let content = message["content"] as? [[String: Any]] else { return }
                for block in content { self?.renderBlock(block) }

            case "result":
                if let usage = json["usage"] as? [String: Any] {
                    let input   = usage["input_tokens"]                as? Int ?? 0
                    let created = usage["cache_creation_input_tokens"] as? Int ?? 0
                    let read    = usage["cache_read_input_tokens"]     as? Int ?? 0
                    let total   = input + created + read

                    var window = 400_000
                    if let modelUsage = json["modelUsage"] as? [String: Any],
                       let model = modelUsage.values.first as? [String: Any],
                       let w = model["contextWindow"] as? Int { window = w }

                    self?.contextPercent = min(Double(total) / Double(window) * 100.0, 100.0)
                }
                self?.isCancelling = false
                self?.isRunning = false
                self?.append("", kind: .text)

            default: break
            }
        }
    }

    private func renderBlock(_ block: [String: Any]) {
        switch block["type"] as? String ?? "" {

        case "text":
            if let text = block["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                append("Arkán: \(text)", kind: .text)
            }

        case "tool_use":
            let name  = block["name"] as? String ?? "tool"
            let input = block["input"] as? [String: Any] ?? [:]
            let detail: String
            if      let cmd  = input["command"]     as? String { detail = cmd }
            else if let path = input["path"]        as? String { detail = path }
            else if let desc = input["description"] as? String { detail = desc }
            else { detail = input.keys.joined(separator: ", ") }
            append("[\(name)] \(detail)", kind: .tool)

        default: break
        }
    }

    // MARK: - Helpers

    private func append(_ text: String, kind: OutputLine.Kind) {
        DispatchQueue.main.async { [weak self] in
            self?.lines.append(OutputLine(text: text, kind: kind))
        }
    }

    private func findClaude() -> String? {
        searchPaths().first { FileManager.default.fileExists(atPath: $0) }
    }

    private func searchPaths() -> [String] {
        let home = realHome
        return [
            "\(home)/.local/bin/arkan",
            "\(home)/.npm-global/bin/arkan",
            "/opt/homebrew/bin/arkan",
            "/usr/local/bin/arkan",
            "/usr/bin/arkan",
        ]
    }

    private var realHome: String {
        getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? NSHomeDirectory()
    }
}
