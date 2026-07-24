import AppKit

@MainActor
class BannerOverlay {
    @MainActor static let shared = BannerOverlay()

    private let panel: NSPanel
    private let contentVC = BannerContentView()
    private var dismissTimer: Timer?
    private var showGeneration = 0   // guards stale dismiss completions
    private var isShowing = false    // true from show() until orderOut fires

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

        // Cancel any pending dismiss and stop in-flight animations so a rapid
        // re-show never flickers from a stale fade-out or frame animation.
        dismissTimer?.invalidate()
        dismissTimer = nil
        showGeneration &+= 1
        // Stop any in-flight dismiss animation before starting a new show so a
        // rapid re-show never inherits a half-faded / mid-collapse state.
        if isShowing {
            cancelInFlightAnimations()
        }
        isShowing = true

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

        let alreadyVisible = isShowing && panel.isVisible
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

        let alreadyVisible = isShowing && panel.isVisible
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
        // A subtle inward squeeze, anchored at the TOP-center of the layer.
        //
        // Scaling *up* would push the banner past the window frame, which the
        // window then clips into square corners — the artefact we saw. Scaling
        // *down* stays within bounds, so nothing is ever clipped. Anchoring at
        // the top edge (rather than the center) keeps the notch banner flush to
        // the screen top; only the sides and bottom breathe inward, symmetrically.
        let b = layer.bounds
        let cx = b.midX, topY = b.maxY
        func scaleAboutTop(_ s: CGFloat) -> CATransform3D {
            var t = CATransform3DIdentity
            t = CATransform3DTranslate(t, cx, topY, 0)
            t = CATransform3DScale(t, s, s, 1)
            return CATransform3DTranslate(t, -cx, -topY, 0)
        }
        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = [scaleAboutTop(1.0), scaleAboutTop(0.955), scaleAboutTop(1.0)]
        anim.keyTimes = [0, 0.42, 1.0]
        anim.duration = 0.32
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "pulse")
    }

    private func dismiss() {
        let f = panel.frame
        let gen = showGeneration   // capture; if show() fires before completion, gen won't match

        // Stop the looping waveform up front so no equalizer repaint lands
        // mid-fade (a repaint during the fade reads as a flicker).
        contentVC.stopWaveform()

        // Both modes retract upward toward the top edge while fading out. Keeping
        // full height (rather than collapsing it) avoids an Auto Layout squish of
        // the content row, which was the source of the notch flash. The alpha fade
        // means the final frame is invisible before orderOut, so there's no hard cut.
        let riseBy: CGFloat = 18
        let targetRect = NSRect(x: f.origin.x, y: f.origin.y + riseBy, width: f.width, height: f.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
            panel.animator().setFrame(targetRect, display: true)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self, self.showGeneration == gen else { return }
            self.isShowing = false
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1.0   // reset so the next show starts clean
        })
    }

    /// Halts any in-flight window animation (frame + alpha) and restores the panel
    /// to a fully visible state, so an interrupting show() never inherits a
    /// half-faded frame. Removing implicit animations under a committed
    /// transaction guarantees the alpha snap is applied atomically.
    private func cancelInFlightAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Snap the animator proxy to the current presented state, then clear it.
        panel.animator().alphaValue = panel.alphaValue
        panel.contentView?.layer?.removeAllAnimations()
        panel.alphaValue = 1.0
        CATransaction.commit()
    }
}
