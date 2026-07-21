import AppKit

/// A persistent, draggable always-on-top widget that shows real-time filler word
/// counts. Transparent when no call is in progress; opaque and live when active.
@MainActor
final class WidgetOverlay {
    static let shared = WidgetOverlay()

    private let panel: NSPanel
    private let contentVC: WidgetContentView

    // Drag state
    private var dragStart: NSPoint?       // mouse-down point in screen coords
    private var frameAtDrag: NSPoint?     // panel origin at mouse-down

    private let width: CGFloat = 220
    private let height: CGFloat = 56
    private let idleAlpha: CGFloat = 0.08
    private let activeAlpha: CGFloat = 1.0

    private var isCallActive = false
    private var isShowing = false

    private init() {
        contentVC = WidgetContentView()
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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
        panel.alphaValue = 0           // always start hidden
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = false
        panel.contentViewController = contentVC

        installDragHandlers()
        restorePosition()
    }

    // MARK: - Public API

    func show() {
        guard !isShowing else { return }
        isShowing = true
        restorePosition()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = isCallActive ? activeAlpha : idleAlpha
        }
    }

    func hide() {
        guard isShowing else { return }
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
        contentVC.setListening(active)
        guard isShowing else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = active ? activeAlpha : idleAlpha
        }
        if active { contentVC.startWaveform() } else { contentVC.stopWaveform() }
    }

    func flagWord(_ word: String, count: Int) {
        guard isShowing, isCallActive else { return }
        contentVC.flag(word: word, count: count)
    }

    // MARK: - Drag

    private func installDragHandlers() {
        // Subclass NSPanel to handle mouse events natively is complex in Swift;
        // instead we add a tracking area and intercept via the content view.
        contentVC.onMouseDown = { [weak self] event in self?.handleMouseDown(event) }
        contentVC.onMouseDragged = { [weak self] event in self?.handleDragged(event) }
        contentVC.onMouseUp = { [weak self] _ in self?.savePosition() }
    }

    private func handleMouseDown(_ event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        frameAtDrag = panel.frame.origin
    }

    private func handleDragged(_ event: NSEvent) {
        guard let start = dragStart, let origin = frameAtDrag else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    private func savePosition() {
        dragStart = nil
        frameAtDrag = nil
        Settings.widgetOrigin = panel.frame.origin
    }

    private func restorePosition() {
        let origin: NSPoint
        if let saved = Settings.widgetOrigin {
            // Validate it's still on a screen.
            if NSScreen.screens.contains(where: { $0.frame.contains(saved) }) {
                origin = saved
            } else {
                origin = defaultOrigin()
            }
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
