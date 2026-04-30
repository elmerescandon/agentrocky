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
    @State private var isExpanded = false
    @State private var isDragging = false
    @State private var dragWindowOrigin: NSPoint = .zero
    @State private var dragMouseStart: NSPoint = .zero

    var body: some View {
        Button(action: {
            guard !isDragging else { return }
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                        dragMouseStart = NSEvent.mouseLocation
                        if let window = NSApp.windows.first(where: { $0 is NSPanel }) {
                            dragWindowOrigin = window.frame.origin
                        }
                    }
                    let mouse = NSEvent.mouseLocation
                    if let window = NSApp.windows.first(where: { $0 is NSPanel }) {
                        window.setFrameOrigin(NSPoint(
                            x: dragWindowOrigin.x + (mouse.x - dragMouseStart.x),
                            y: dragWindowOrigin.y + (mouse.y - dragMouseStart.y)
                        ))
                    }
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isDragging = false }
                }
        )
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
            ChatView(session: session, isExpanded: $isExpanded)
                .frame(width: isExpanded ? 720 : 420, height: isExpanded ? 800 : 520)
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
