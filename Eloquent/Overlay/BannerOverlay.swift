import AppKit

@MainActor
class BannerOverlay {
    @MainActor static let shared = BannerOverlay()

    private let panel: NSPanel
    private let contentVC = BannerContentView()
    private var dismissTimer: Timer?

    private let maxWidth: CGFloat = 340
    private let minWidth: CGFloat = 200
    private let dismissDelay: TimeInterval = 2.4

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) // above the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.contentViewController = contentVC
    }

    func show(word: String, count: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let screen = NSScreen.main else { return }
        let notch = ScreenNotch(screen: screen)

        contentVC.word = word
        contentVC.count = count

        if notch.hasNotch {
            showNotch(notch)
        } else {
            showPill(notch)
        }

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        contentVC.animateWaveform()
    }

    // MARK: - Notch mode: grows down out of the notch, hugging the top edge.

    private func showNotch(_ notch: ScreenNotch) {
        // A few extra points below the notch keep the word clear of the notch's
        // rounded underside on real hardware.
        let topInset = notch.topInset + 4
        contentVC.configure(mode: .notch(topInset: topInset))

        let fullHeight = BannerContentView.rowHeight + topInset
        contentVC.view.layoutSubtreeIfNeeded()
        var width = contentVC.view.fittingSize.width
        width = min(max(width, max(notch.notchWidth + 40, minWidth)), maxWidth)

        let x = notch.centerX - width / 2
        let restY = notch.topY - fullHeight        // hug top edge
        // Start collapsed to roughly the notch footprint, then expand out.
        let startWidth = max(notch.notchWidth, 140)
        let startX = notch.centerX - startWidth / 2
        let startY = notch.topY - topInset - 6      // barely peeking below the notch

        let alreadyVisible = panel.isVisible && panel.alphaValue > 0.01
        if alreadyVisible {
            animateFrame(to: NSRect(x: x, y: restY, width: width, height: fullHeight), duration: 0.28, spring: true)
            pulse()
            return
        }

        // Start collapsed to just the notch-inset height so the panel stays entirely
        // within the notch display — no bleed onto whatever display sits above.
        let startHeight = topInset
        panel.setFrame(NSRect(x: startX, y: notch.topY - startHeight, width: startWidth, height: startHeight), display: false)
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        // Expand downward + outward to full size.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.46
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().setFrame(NSRect(x: x, y: restY, width: width, height: fullHeight), display: true)
        }
    }

    // MARK: - Pill mode: drops from top-center on external / no-notch displays.

    private func showPill(_ notch: ScreenNotch) {
        contentVC.configure(mode: .pill)

        let height = BannerContentView.rowHeight
        contentVC.view.layoutSubtreeIfNeeded()
        var width = contentVC.view.fittingSize.width
        width = min(max(width, minWidth), maxWidth)

        let vf = notch.screen.visibleFrame
        let x = vf.midX - width / 2
        let restY = vf.maxY - height - 14
        let startY = vf.maxY - height + 6

        let alreadyVisible = panel.isVisible && panel.alphaValue > 0.01
        if alreadyVisible {
            animateFrame(to: NSRect(x: x, y: restY, width: width, height: height), duration: 0.24, spring: false)
            pulse()
            return
        }

        panel.setFrame(NSRect(x: x, y: startY, width: width, height: height), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.12)
            panel.animator().setFrame(NSRect(x: x, y: restY, width: width, height: height), display: true)
            panel.animator().alphaValue = 1.0
        }
    }

    // MARK: - Helpers

    private func animateFrame(to rect: NSRect, duration: TimeInterval, spring: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = spring
                ? CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                : CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(rect, display: true)
        }
    }

    private func pulse() {
        guard let layer = panel.contentView?.layer else { return }
        let anim = CASpringAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue = 1.05
        anim.autoreverses = true
        anim.duration = 0.16
        anim.damping = 9
        layer.add(anim, forKey: "pulse")
    }

    private func dismiss() {
        guard let screen = NSScreen.main else { panel.orderOut(nil); return }
        let notch = ScreenNotch(screen: screen)
        let f = panel.frame

        // Retract upward toward the top edge / notch, fading out.
        if notch.hasNotch {
            // Collapse the black shape back into the notch footprint. No alpha fade —
            // fading would reveal the desktop around the physical notch. We shrink the
            // height to ~the notch inset so it visually tucks back up into the notch.
            let startWidth = max(notch.notchWidth, 140)
            let collapsedHeight = notch.topInset
            let targetRect = NSRect(x: notch.centerX - startWidth / 2,
                                    y: notch.topY - collapsedHeight,
                                    width: startWidth, height: collapsedHeight)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
                panel.animator().setFrame(targetRect, display: true)
            }, completionHandler: { [weak self] in
                self?.contentVC.stopWaveform()
                self?.panel.orderOut(nil)
            })
            return
        }

        // Pill mode: retract upward and fade out.
        let targetRect = NSRect(x: f.origin.x, y: f.origin.y + 22, width: f.width, height: f.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            panel.animator().setFrame(targetRect, display: true)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.contentVC.stopWaveform()
            self?.panel.orderOut(nil)
        })
    }
}
