//
//  ChatView.swift
//  agentrocky
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var session: ClaudeSession
    @Binding var isExpanded: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    private var promptLabel: String {
        URL(fileURLWithPath: session.workingDirectory).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Text(isExpanded ? "⊟" : "⊞")
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("e", modifiers: .command)
                .help("Ampliar/reducir chat  ⌘E")

                Button(action: { session.restart() }) {
                    Text("↺")
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .help("Reiniciar sesión  ⌘R")
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)

            Divider().background(Color.white.opacity(0.1))

            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.lines) { line in
                            TerminalLine(line: line)
                        }
                        if session.isRunning {
                            Text("▋")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                                .opacity(0.8)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(10)
                }
                .onChange(of: session.lines.count) { _ in proxy.scrollTo("bottom") }
                .onChange(of: session.isRunning)   { _ in proxy.scrollTo("bottom") }
            }

            Divider().background(Color.white.opacity(0.15))

            // Input row
            HStack(spacing: 6) {
                Text(promptLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.head)

                Text("❯")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(session.isReady ? .white : .white.opacity(0.3))

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
        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
        .onAppear { inputFocused = true }
        .onExitCommand { dismiss() }
    }

    private func sendMessage() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.isRunning else { return }
        guard session.isReady else {
            session.lines.append(.init(text: "Still starting… wait a moment", kind: .system))
            return
        }
        session.lines.append(.init(text: "\(promptLabel) ❯ \(trimmed)", kind: .system))
        input = ""
        session.send(prompt: trimmed)
        inputFocused = true
    }
}

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
