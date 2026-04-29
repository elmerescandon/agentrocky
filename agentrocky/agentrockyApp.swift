//
//  agentrockyApp.swift
//  agentrocky
//

import SwiftUI
import AppKit

@main
struct agentrockyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var rockyWindow: NSPanel?
    var rockyState = RockyState()

    private let panelWidth: CGFloat = 56
    private let panelHeight: CGFloat = 56

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupWindow()
    }

    private func setupWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        if let screen = NSScreen.main {
            let dockTop = screen.visibleFrame.minY
            let startX = screen.frame.midX - panelWidth / 2
            panel.setFrameOrigin(NSPoint(x: startX, y: dockTop))
        }

        let contentView = NSHostingView(rootView: RockyView(state: rockyState))
        contentView.frame = panel.contentView!.bounds
        contentView.autoresizingMask = [.width, .height]
        panel.contentView = contentView

        panel.makeKeyAndOrderFront(nil)
        rockyWindow = panel
    }
}
