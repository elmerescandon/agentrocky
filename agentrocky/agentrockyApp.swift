//
//  agentrockyApp.swift
//  agentrocky
//

import SwiftUI
import AppKit
import Combine

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
    var statusItem: NSStatusItem?

    private let panelWidth: CGFloat = 156
    private let panelHeight: CGFloat = 156
    private let idleTimeout: TimeInterval = 120
    private let dimmedAlpha: CGFloat = 0.25

    private var idleTimer: Timer?
    private var lastInteractionDate = Date()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupWindow()
        setupStatusItem()
        setupIdleTimer()
        observeInteractions()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "r.circle.fill", accessibilityDescription: "Rocky")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Reiniciar", action: #selector(restartApp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func restartApp() {
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
        NSApp.terminate(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
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
            let centerX = screen.frame.midX - panelWidth / 2
            panel.setFrameOrigin(NSPoint(x: centerX, y: dockTop))
        }

        let contentView = NSHostingView(rootView: RockyView(state: rockyState))
        contentView.frame = panel.contentView!.bounds
        contentView.autoresizingMask = [.width, .height]
        panel.contentView = contentView

        panel.makeKeyAndOrderFront(nil)
        rockyWindow = panel
    }

    private func setupIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdleState()
        }
    }

    private func observeInteractions() {
        rockyState.$isChatOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOpen in
                if isOpen { self?.resetIdle() }
            }
            .store(in: &cancellables)

        rockyState.$activeIsRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                if isRunning { self?.resetIdle() }
            }
            .store(in: &cancellables)
    }

    private func resetIdle() {
        lastInteractionDate = Date()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            rockyWindow?.animator().alphaValue = 1.0
        }
    }

    private func checkIdleState() {
        guard !(rockyWindow?.alphaValue == dimmedAlpha) else { return }
        let idle = Date().timeIntervalSince(lastInteractionDate)
        if idle >= idleTimeout {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 1.5
                rockyWindow?.animator().alphaValue = dimmedAlpha
            }
        }
    }
}
