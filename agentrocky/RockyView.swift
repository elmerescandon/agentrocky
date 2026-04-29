//
//  RockyView.swift
//  agentrocky
//

import SwiftUI
import AppKit

struct AnimatedGIFView: NSViewRepresentable {
    let gifName: String

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        if let url = Bundle.main.url(forResource: gifName, withExtension: "gif"),
           let image = NSImage(contentsOf: url) {
            view.image = image
            view.animates = true
        }
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if let url = Bundle.main.url(forResource: gifName, withExtension: "gif"),
           let image = NSImage(contentsOf: url) {
            nsView.image = image
            nsView.animates = true
        }
    }
}

struct RockyView: View {
    @ObservedObject var state: RockyState
    @ObservedObject var session: ClaudeSession
    @State private var showChat = false

    @State private var bounceScale: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0
    @State private var wasRunning = false

    var body: some View {
        Button(action: {
            state.isChatOpen.toggle()
            showChat = state.isChatOpen
            if showChat { NSApp.activate(ignoringOtherApps: true) }
        }) {
            AnimatedGIFView(gifName: session.isRunning ? "snorlax-active" : "snorlax")
                .frame(width: 72, height: 72)
                .scaleEffect(bounceScale)
                .offset(x: shakeOffset)
        }
        .buttonStyle(.plain)
        .onChange(of: session.isRunning) { running in
            if wasRunning && !running {
                bounce()
            }
            wasRunning = running
        }
        .onChange(of: session.errorCount) { _ in
            shake()
        }
        .popover(isPresented: $showChat, arrowEdge: .top) {
            ChatView(session: session)
                .frame(width: 420, height: 520)
        }
        .onChange(of: showChat) { open in
            state.isChatOpen = open
        }
    }

    private func bounce() {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
            bounceScale = 1.25
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                bounceScale = 1.0
            }
        }
    }

    private func shake() {
        let offsets: [CGFloat] = [10, -10, 8, -8, 5, -5, 0]
        var delay = 0.0
        for offset in offsets {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.07)) {
                    shakeOffset = offset
                }
            }
            delay += 0.07
        }
    }
}
