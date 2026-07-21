import AppKit

/// Notch geometry for the current screen. Notch only exists on the built-in display
/// (macOS 12+). Values are in AppKit screen coordinates (bottom-left origin).
struct ScreenNotch {
    let screen: NSScreen
    let hasNotch: Bool
    let topInset: CGFloat      // notch height (≈ menu bar height on notch displays)
    let notchWidth: CGFloat    // physical notch width
    let fullFrame: NSRect      // screen.frame (includes menu bar area)

    init(screen: NSScreen) {
        self.screen = screen
        self.fullFrame = screen.frame

        var inset: CGFloat = 0
        var width: CGFloat = 0
        var notch = false

        if #available(macOS 12.0, *) {
            inset = screen.safeAreaInsets.top
            if inset > 0 {
                notch = true
                if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                    width = screen.frame.width - left.width - right.width
                } else {
                    width = 180   // fallback for MacBook Pro notch
                }
            }
        }

        // Debug override: simulate a notch on non-notch displays for design review.
        if !notch && ProcessInfo.processInfo.environment["ELOQUENT_FAKE_NOTCH"] == "1" {
            notch = true
            inset = 38
            width = 200
        }

        self.hasNotch = notch
        self.topInset = inset
        self.notchWidth = max(width, 0)
    }

    /// Center x of the screen (and of the notch) in screen coordinates.
    var centerX: CGFloat { fullFrame.midX }

    /// The y of the very top edge of the screen.
    var topY: CGFloat { fullFrame.maxY }
}
