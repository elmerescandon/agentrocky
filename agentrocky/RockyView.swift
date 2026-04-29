//
//  RockyView.swift
//  agentrocky
//

import SwiftUI

struct RockyView: View {
    @ObservedObject var state: RockyState
    @State private var showChat = false
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            state.isChatOpen.toggle()
            showChat = state.isChatOpen
            if showChat {
                NSApp.activate(ignoringOtherApps: true)
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(isHovered ? 0.85 : 0.65))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color.green.opacity(isHovered ? 0.9 : 0.55), lineWidth: 1.5)
                    )
                Text(">_")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showChat, arrowEdge: .top) {
            ChatView(session: state.session)
                .frame(width: 420, height: 520)
        }
        .onChange(of: showChat) { open in
            state.isChatOpen = open
        }
    }
}
