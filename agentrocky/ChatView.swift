//
//  ChatView.swift
//  agentrocky
//

import SwiftUI

private let kIconSize: CGFloat = 14
private let kIconFrame: CGFloat = 28

struct ChatView: View {
    @ObservedObject var state: RockyState
    @Binding var isExpanded: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @FocusState private var inputFocused: Bool
    @State private var showHistory = false

    init(state: RockyState, isExpanded: Binding<Bool>) {
        self.state = state
        self._isExpanded = isExpanded
        self._input = State(initialValue: state.activeSession.draft)
    }

    private var promptLabel: String {
        URL(fileURLWithPath: state.activeSession.workingDirectory).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider().background(Color.white.opacity(0.1))

            if showHistory {
                HistoryList(state: state) {
                    showHistory = false
                    inputFocused = true
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(state.activeLines) { line in
                                TerminalLine(line: line)
                            }
                            if state.activeIsRunning {
                                Text("▋")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white)
                                    .opacity(0.8)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(10)
                    }
                    .onChange(of: state.activeLines.count) { _ in proxy.scrollTo("bottom") }
                    .onChange(of: state.activeIsRunning)   { _ in proxy.scrollTo("bottom") }
                    .onChange(of: state.activeIndex) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo("bottom")
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo("bottom")
                        }
                        inputFocused = true
                    }
                }
            }

            Divider().background(Color.white.opacity(0.15))

            HStack(spacing: 6) {
                Text("❯")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(state.activeIsReady ? .white : .white.opacity(0.3))

                TextField("", text: $input)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.04).opacity(0.8))
        .onExitCommand { dismiss() }
        .onChange(of: input) { newValue in state.activeSession.draft = newValue }
        .onChange(of: state.activeIndex) { _ in input = state.activeSession.draft }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            // Historial — toggle inline
            HeaderButton(label: "◷", active: showHistory) {
                showHistory.toggle()
            }
            .help("Historial  ⌘H")
            .keyboardShortcut("h", modifiers: .command)

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.15))
                .padding(.horizontal, 4)

            // Pestañas
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(state.sessions.enumerated()), id: \.offset) { i, session in
                        TabButton(
                            label: session.name,
                            isActive: i == state.activeIndex,
                            onSelect: {
                                state.switchTo(i)
                                showHistory = false
                            },
                            onClose: state.sessions.count > 1 ? { state.closeSession(at: i) } : nil
                        )
                    }
                }
            }

            // Atajos invisibles
            Button("") { state.switchTo((state.activeIndex - 1 + state.sessions.count) % state.sessions.count) }
                .keyboardShortcut(.leftArrow, modifiers: .command).hidden()
            Button("") { state.switchTo((state.activeIndex + 1) % state.sessions.count) }
                .keyboardShortcut(.rightArrow, modifiers: .command).hidden()
            Button("") { state.closeSession(at: state.activeIndex) }
                .keyboardShortcut("w", modifiers: .command).hidden()

            Spacer()

            if let pct = state.activeContextPercent {
                Text(String(format: "ctx %.0f%%", pct))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(contextColor(pct))
                    .padding(.horizontal, 6)
            }

            // Grupo derecho: nueva sesión + ampliar + reiniciar
            HStack(spacing: 0) {
                HeaderButton(label: "+") {
                    state.addSession()
                    showHistory = false
                }
                .help("Nueva sesión  ⌘T")
                .keyboardShortcut("t", modifiers: .command)

                HeaderButton(label: isExpanded ? "⊟" : "⊞") {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
                .help("Ampliar/reducir  ⌘E")
                .keyboardShortcut("e", modifiers: .command)

                HeaderButton(label: "↺") {
                    state.activeSession.restart()
                }
                .help("Reiniciar sesión  ⌘R")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 4)
    }

    // MARK: - Context color

    private func contextColor(_ pct: Double) -> Color {
        if pct > 80 { return Color(red: 1.0, green: 0.4, blue: 0.4) }
        if pct > 60 { return Color(red: 1.0, green: 0.85, blue: 0.3) }
        return Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.7)
    }

    // MARK: - Send

    private func sendMessage() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !state.activeIsRunning else { return }
        guard state.activeIsReady else {
            state.activeSession.lines.append(ClaudeSession.OutputLine(text: "Still starting… wait a moment", kind: .system))
            return
        }
        state.activeSession.lines.append(ClaudeSession.OutputLine(text: "yo ❯ \(trimmed)", kind: .system))
        input = ""
        state.activeSession.send(prompt: trimmed)
        inputFocused = true
    }
}

// MARK: - Header button (uniforme)

struct HeaderButton: View {
    let label: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: kIconSize, design: .monospaced))
                .foregroundColor(active ? .white : .white.opacity(0.5))
                .frame(width: kIconFrame, height: kIconFrame)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab button

struct TabButton: View {
    let label: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isActive ? .white : .white.opacity(0.4))

            if let onClose {
                Button(action: onClose) {
                    Text("×")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - History list (inline)

struct HistoryList: View {
    @ObservedObject var state: RockyState
    let onDismiss: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.history.isEmpty {
                Spacer()
                Text("No hay sesiones guardadas")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.history) { entry in
                            HistoryRow(entry: entry, formatter: Self.dateFormatter) {
                                state.addSession(resuming: entry.id)
                                onDismiss()
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { state.loadHistory() }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    let formatter: DateFormatter
    let onResume: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                Text(formatter.string(from: entry.modifiedAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            if hovered {
                Text("retomar →")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(hovered ? Color.white.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { onResume() }
    }
}

// MARK: - Terminal line

struct TerminalLine: View {
    let line: ClaudeSession.OutputLine

    var body: some View {
        Text(line.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch line.kind {
        case .text:   return .white
        case .tool:   return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .system: return .white.opacity(0.45)
        case .error:  return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }
}
