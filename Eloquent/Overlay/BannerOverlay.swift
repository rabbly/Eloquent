import AppKit

@MainActor
class BannerOverlay {
    @MainActor static let shared = BannerOverlay()

    private let panel: NSPanel
    private let contentVC = BannerContentView()
    private var dismissTimer: Timer?

    private let maxWidth: CGFloat = 340
    private let minWidth: CGFloat = 190
    private let dismissDelay: TimeInterval = 2.2

    private init() {
        let height = BannerContentView.height
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.contentViewController = contentVC
    }

    func show(word: String, count: Int) {
        dispatchPrecondition(condition: .onQueue(.main))

        contentVC.word = word
        contentVC.count = count

        // Size the panel to fit its content, clamped to a tasteful range.
        contentVC.view.layoutSubtreeIfNeeded()
        var fitting = contentVC.view.fittingSize.width
        fitting = min(max(fitting, minWidth), maxWidth)
        let height = BannerContentView.height

        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let targetX = vf.midX - fitting / 2
        let restY = vf.maxY - height - 14          // resting position (clear of the menu bar)
        let startY = vf.maxY - height + 6          // start tucked up (as if from the notch)

        let alreadyVisible = panel.isVisible && panel.alphaValue > 0.01

        if alreadyVisible {
            // Re-trigger: quick pop without re-sliding, keep it lively.
            resizeVisible(toWidth: fitting, height: height, at: targetX, y: restY)
            pulse()
        } else {
            panel.setFrame(NSRect(x: targetX, y: startY, width: fitting, height: height), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()

            // Spring down + fade in.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.42
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.15) // slight overshoot
                panel.animator().setFrame(
                    NSRect(x: targetX, y: restY, width: fitting, height: height), display: true)
                panel.animator().alphaValue = 1.0
            }
        }

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }

        // Kick off the waveform animation each time.
        contentVC.animateWaveform()
    }

    private func resizeVisible(toWidth width: CGFloat, height: CGFloat, at x: CGFloat, y: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }

    // A subtle scale pulse when the same banner updates.
    private func pulse() {
        guard let layer = panel.contentView?.layer else { return }
        let anim = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 1.06
        anim.autoreverses = true
        anim.duration = 0.18
        anim.damping = 8
        layer.add(anim, forKey: "pulse")
    }

    private func dismiss() {
        guard let screen = NSScreen.main else { panel.orderOut(nil); return }
        let vf = screen.visibleFrame
        let f = panel.frame
        let upY = vf.maxY - f.height + 8   // retract upward toward the notch

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            panel.animator().setFrame(NSRect(x: f.origin.x, y: upY, width: f.width, height: f.height), display: true)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}
