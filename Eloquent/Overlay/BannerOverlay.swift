import AppKit

@MainActor
class BannerOverlay {
    @MainActor static let shared = BannerOverlay()

    private let panel: NSPanel
    private let contentVC = BannerContentView()
    private var dismissTimer: Timer?

    private let panelWidth: CGFloat = 280
    private let panelHeight: CGFloat = 64
    private let dismissDelay: TimeInterval = 1.5

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar          // higher than .floating; sits above most windows
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true   // let clicks pass through the banner
        panel.contentViewController = contentVC
    }

    func show(word: String, count: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        print("[BannerOverlay] show word=\(word) count=\(count)")

        let display = count > 1 ? "\(word)  ×\(count)" : word
        contentVC.text = display

        positionPanel()

        // Show even though this is an accessory (non-active) app.
        panel.orderFrontRegardless()
        print("[BannerOverlay] panel isVisible=\(panel.isVisible) frame=\(panel.frame)")

        dismissTimer?.invalidate()

        // Set alpha directly first (guaranteed visible), then animate as a nicety.
        panel.alphaValue = 1.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1.0
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else {
            print("[BannerOverlay] no NSScreen.main")
            return
        }
        let frame = screen.visibleFrame
        let x = frame.midX - panelWidth / 2
        let y = frame.maxY - panelHeight - 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
