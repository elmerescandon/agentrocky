//
//  RockyView.swift
//  agentrocky
//

import SwiftUI
import AppKit

struct RockyView: View {
    @ObservedObject var state: RockyState
    @ObservedObject var session: ClaudeSession
    @StateObject private var animator = SpriteAnimator()

    @State private var showChat = false
    @State private var wasRunning = false
    @State private var isExpanded = false
    @State private var isDragging = false
    @State private var dragWindowOrigin: NSPoint = .zero
    @State private var dragMouseStart: NSPoint = .zero

    // MARK: - Animation configs

    enum Anim {
        case idle, walking, sleeping, hopping, hurting, tripping, fainting, floating
    }

    struct AnimConfig {
        let name: String
        let fw: Int, fh: Int
        let durations: [Int]
        let loops: Bool
    }

    static let configs: [Anim: AnimConfig] = [
        .idle:     AnimConfig(name: "alakazam-idle",   fw: 32, fh: 48, durations: [6,6,6,6,6,6,6,6],         loops: true),
        .walking:  AnimConfig(name: "alakazam-walk",   fw: 32, fh: 40, durations: [8,12,8,12],               loops: true),
        .sleeping: AnimConfig(name: "alakazam-sleep",  fw: 24, fh: 32, durations: [30,35],                   loops: true),
        .hopping:  AnimConfig(name: "alakazam-charge",   fw: 40, fh: 48, durations: [2,2,2,2,2,2,2,2,2,2], loops: false),
        .hurting:  AnimConfig(name: "alakazam-hurt",   fw: 48, fh: 64, durations: [2,8],                     loops: false),
        .tripping: AnimConfig(name: "alakazam-rotate", fw: 32, fh: 40, durations: [2,2,2,2,2,2,2,2,2],      loops: false),
        .fainting: AnimConfig(name: "alakazam-hurt",   fw: 48, fh: 64, durations: [2,8],                     loops: false),
        .floating: AnimConfig(name: "alakazam-idle",   fw: 32, fh: 48, durations: [6,6,6,6,6,6,6,6],        loops: true),
    ]

    // MARK: - Body

    var body: some View {
        Button(action: {
            guard !isDragging else { return }
            state.isChatOpen.toggle()
            showChat = state.isChatOpen
            if showChat { NSApp.activate(ignoringOtherApps: true) }
        }) {
            Image(nsImage: animator.currentFrame)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 144, height: 144)
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
                        transition(to: .tripping)
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
            ChatView(session: session, isExpanded: $isExpanded)
                .frame(width: isExpanded ? 720 : 420, height: isExpanded ? 800 : 520)
        }
        .onChange(of: showChat) { open in state.isChatOpen = open }
        .onChange(of: session.isRunning) { running in
            if running {
                transition(to: .walking)
            } else if wasRunning {
                transition(to: .hopping) { transition(to: .idle) }
            }
            wasRunning = running
        }
        .onChange(of: session.errorCount) { _ in
            transition(to: .hurting) { transition(to: .idle) }
        }
        .onAppear {
            transition(to: .idle)
        }
    }

    // MARK: - Helpers

    private func transition(to anim: Anim, onComplete: (() -> Void)? = nil) {
        guard let cfg = Self.configs[anim] else { return }
        animator.configure(imageName: cfg.name, frameWidth: cfg.fw, frameHeight: cfg.fh,
                           durations: cfg.durations, direction: 0)
        animator.play(loops: cfg.loops, onComplete: onComplete)
    }
}
