//
//  RockyView.swift
//  agentrocky
//

import SwiftUI
import AppKit


struct RockyView: View {
    @ObservedObject var state: RockyState

    @State private var showChat       = false
    @State private var wasRunning     = false
    @State private var isExpanded     = false
    @State private var bounceScale: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0
    @State private var isDragging     = false
    @State private var dragWindowOrigin: NSPoint = .zero
    @State private var dragMouseStart:  NSPoint  = .zero

    var body: some View {
        Button(action: {
            guard !isDragging else { return }
            state.isChatOpen.toggle()
            showChat = state.isChatOpen
            if showChat { NSApp.activate(ignoringOtherApps: true) }
        }) {
            SpriteAnimView(gifName: state.activeIsRunning ? "snorlax-active" : "snorlax")
                .frame(width: 96, height: 96)
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
        .popover(isPresented: $showChat, arrowEdge: .top) {
            ChatView(state: state, isExpanded: $isExpanded)
                .frame(width: isExpanded ? 720 : 420, height: isExpanded ? 800 : 520)
        }
        .onChange(of: showChat) { open in state.isChatOpen = open }
        .onChange(of: state.activeIsRunning) { running in
            if wasRunning && !running { bounce() }
            wasRunning = running
        }
        .onChange(of: state.activeErrorCount) { _ in shake() }
    }

    private func bounce() {
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 8)) {
            bounceScale = 1.25
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.interpolatingSpring(stiffness: 200, damping: 10)) {
                bounceScale = 1.0
            }
        }
    }

    private func shake() {
        let offsets: [CGFloat] = [0, -8, 8, -6, 6, -3, 3, 0]
        for (i, offset) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = offset }
            }
        }
    }
}
