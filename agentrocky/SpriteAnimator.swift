//
//  SpriteAnimator.swift
//  agentrocky
//

import AppKit
import Combine

class SpriteAnimator: ObservableObject {
    @Published var currentFrame: NSImage = NSImage()

    private var frames: [NSImage] = []
    private var durations: [TimeInterval] = []
    private var frameIndex = 0
    private var timer: Timer?
    private var loops = true
    private var onComplete: (() -> Void)?

    // PMD animations run at 24 fps
    private static let tickDuration: TimeInterval = 1.0 / 24.0

    func configure(imageName: String, frameWidth: Int, frameHeight: Int, durations: [Int], direction: Int = 0) {
        stop()
        guard let image = NSImage(named: imageName),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let rowCount = cg.height / frameHeight
        let row = min(direction, rowCount - 1)

        frames = (0..<durations.count).compactMap { col in
            let rect = CGRect(x: col * frameWidth, y: row * frameHeight,
                              width: frameWidth, height: frameHeight)
            guard let cropped = cg.cropping(to: rect) else { return nil }
            return NSImage(cgImage: cropped, size: NSSize(width: frameWidth, height: frameHeight))
        }

        self.durations = durations.map { Double($0) * SpriteAnimator.tickDuration }
        frameIndex = 0
        currentFrame = frames.first ?? NSImage()
    }

    func play(loops: Bool = true, onComplete: (() -> Void)? = nil) {
        self.loops = loops
        self.onComplete = onComplete
        frameIndex = 0
        advance()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        currentFrame = frames[frameIndex]
        let duration = durations[frameIndex]
        frameIndex += 1

        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.frameIndex >= self.frames.count {
                if self.loops {
                    self.frameIndex = 0
                    self.advance()
                } else {
                    self.onComplete?()
                }
            } else {
                self.advance()
            }
        }
    }
}
