//
//  RockyView.swift
//  agentrocky
//

import SwiftUI
import AppKit


private func spriteFrame(named: String, frameWidth: Int, frameHeight: Int, col: Int = 0, row: Int = 0) -> Image {
    guard let src = NSImage(named: named),
          let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let cropped = cg.cropping(to: CGRect(x: col * frameWidth, y: row * frameHeight,
                                               width: frameWidth, height: frameHeight))
    else { return Image(named) }
    return Image(nsImage: NSImage(cgImage: cropped, size: NSSize(width: frameWidth, height: frameHeight)))
}

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

    private var sprite: Image {
        if state.activeIsRunning {
            return spriteFrame(named: "alakazam-charge", frameWidth: 40, frameHeight: 48)
        } else {
            return spriteFrame(named: "alakazam-idle", frameWidth: 32, frameHeight: 48)
        }
    }

    var body: some View {
        Button(action: {
            guard !isDragging else { return }
            state.isChatOpen.toggle()
            showChat = state.isChatOpen
            if showChat { NSApp.activate(ignoringOtherApps: true) }
        }) {
            sprite
                .resizable()
                .scaledToFit()
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
