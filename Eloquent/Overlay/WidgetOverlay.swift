import AppKit

@MainActor
final class WidgetOverlay {
    static let shared = WidgetOverlay()

    private let panel: NSPanel
    private let contentVC: WidgetContentView

    // Drag/tap state
    private var mouseDownPoint: NSPoint?
    private var frameAtDrag: NSPoint?
    private var didDrag = false

    // Expand state
    private var isExpanded = false
    private var collapseTimer: Timer?
    private var lastStats: SessionStats = SessionStats()

    private let collapsedHeight: CGFloat = 56
    private let width: CGFloat = 220
    private let idleAlpha: CGFloat = 0.08
    private let activeAlpha: CGFloat = 1.0

    private var isCallActive = false
    private var isShowing = false

    private init() {
        contentVC = WidgetContentView()
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = false
        panel.contentViewController = contentVC

        installMouseHandlers()
        restorePosition()
    }

    // MARK: - Public API

    func show() {
        guard !isShowing else { return }
        isShowing = true
        restorePosition()
        contentVC.loadViewIfNeeded()
        if isCallActive { contentVC.showListening() } else { contentVC.showNoSession() }
        panel.setContentSize(NSSize(width: width, height: collapsedHeight))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = isCallActive ? activeAlpha : idleAlpha
        }
    }

    func hide() {
        guard isShowing else { return }
        collapseTimer?.invalidate()
        collapseTimer = nil
        isExpanded = false
        isShowing = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    func setCallActive(_ active: Bool) {
        isCallActive = active
        guard isShowing else { return }
        if active {
            collapseIfExpanded()
            contentVC.resetSession()
            contentVC.showListening()
            contentVC.startWaveform()
        } else {
            collapseIfExpanded()
            contentVC.showNoSession()
            contentVC.stopWaveform()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = active ? activeAlpha : idleAlpha
        }
    }

    func updateStats(_ stats: SessionStats, newWord: String? = nil) {
        guard isShowing, isCallActive else { return }
        lastStats = stats
        contentVC.updateStats(stats, newWord: newWord)
        // If currently expanded, refresh the expanded rows too.
        if isExpanded { expandToShowSummary() }
    }

    func resetSession() {
        guard isShowing else { return }
        lastStats = SessionStats()
        collapseIfExpanded()
        contentVC.resetSession()
    }

    // MARK: - Expand / collapse

    private func toggleExpand() {
        guard isCallActive, lastStats.total() > 0 else { return }
        if isExpanded { collapseIfExpanded() } else { expandToShowSummary() }
    }

    private func expandToShowSummary() {
        collapseTimer?.invalidate()
        isExpanded = true

        let expandedH = contentVC.showExpanded(stats: lastStats)
        let totalH = collapsedHeight + expandedH
        let origin = panel.frame.origin
        let newOrigin = NSPoint(x: origin.x, y: origin.y - (totalH - collapsedHeight))

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(
                NSRect(x: newOrigin.x, y: newOrigin.y, width: width, height: totalH),
                display: true
            )
        }

        collapseTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.collapseIfExpanded()
        }
    }

    private func collapseIfExpanded() {
        guard isExpanded else { return }
        collapseTimer?.invalidate()
        collapseTimer = nil
        isExpanded = false

        let origin = panel.frame.origin
        let currentH = panel.frame.height
        let newOrigin = NSPoint(x: origin.x, y: origin.y + (currentH - collapsedHeight))

        contentVC.showCollapsed()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(
                NSRect(x: newOrigin.x, y: newOrigin.y, width: width, height: collapsedHeight),
                display: true
            )
        }
    }

    // MARK: - Mouse: tap vs drag

    private func installMouseHandlers() {
        contentVC.onMouseDown = { [weak self] event in
            guard let self else { return }
            self.mouseDownPoint = NSEvent.mouseLocation
            self.frameAtDrag = self.panel.frame.origin
            self.didDrag = false
        }
        contentVC.onMouseDragged = { [weak self] event in
            guard let self,
                  let start = self.mouseDownPoint,
                  let origin = self.frameAtDrag else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - start.x
            let dy = current.y - start.y
            if !self.didDrag && (abs(dx) > 4 || abs(dy) > 4) {
                self.didDrag = true
                self.collapseIfExpanded()   // collapse on drag start
            }
            if self.didDrag {
                self.panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            }
        }
        contentVC.onMouseUp = { [weak self] _ in
            guard let self else { return }
            if self.didDrag {
                // Persist the new position
                Settings.widgetOrigin = self.panel.frame.origin
            } else {
                // No drag: treat as tap → toggle expand
                self.toggleExpand()
            }
            self.mouseDownPoint = nil
            self.frameAtDrag = nil
            self.didDrag = false
        }
    }

    // MARK: - Position

    private func restorePosition() {
        let origin: NSPoint
        if let saved = Settings.widgetOrigin,
           NSScreen.screens.contains(where: { $0.frame.contains(saved) }) {
            origin = saved
        } else {
            origin = defaultOrigin()
        }
        panel.setFrameOrigin(origin)
    }

    private func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let vf = screen.visibleFrame
        return NSPoint(x: vf.maxX - width - 24, y: vf.minY + 80)
    }
}
