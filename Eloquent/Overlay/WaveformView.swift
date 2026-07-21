import AppKit

/// A small set of vertical bars that animate like an audio waveform.
/// Used as the accent glyph inside the banner badge.
@MainActor
final class WaveformView: NSView {
    private var bars: [CALayer] = []
    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        buildBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        buildBars()
    }

    private func buildBars() {
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = barWidth / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    override func layout() {
        super.layout()
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2
        for (i, bar) in bars.enumerated() {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let h = baseHeight(for: i)
            bar.frame = CGRect(x: x, y: (bounds.height - h) / 2, width: barWidth, height: h)
        }
    }

    // Static heights giving a symmetric "peak in the middle" shape.
    private func baseHeight(for index: Int) -> CGFloat {
        let mid = bounds.height
        switch index {
        case 0, 4: return mid * 0.35
        case 1, 3: return mid * 0.6
        default:   return mid * 0.9
        }
    }

    /// Animate the bars once (a lively pulse when a filler word is flagged).
    func pulse() {
        for (i, bar) in bars.enumerated() {
            let base = baseHeight(for: i)
            let peak = min(bounds.height * 0.95, base * 1.8)
            let anim = CAKeyframeAnimation(keyPath: "bounds.size.height")
            anim.values = [base, peak, base * 0.7, base]
            anim.keyTimes = [0, 0.35, 0.7, 1.0]
            anim.duration = 0.7
            anim.beginTime = CACurrentMediaTime() + Double(i) * 0.05
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(anim, forKey: "pulse")
        }
    }

    /// Continuously oscillate the bars while the banner is visible, so the badge
    /// feels "alive" (like an equalizer). Each bar runs its own looping cycle with a
    /// staggered phase and slightly different period.
    func startAnimating() {
        for (i, bar) in bars.enumerated() {
            let base = baseHeight(for: i)
            let high = min(bounds.height * 0.95, base * 1.7)
            let low = max(bounds.height * 0.22, base * 0.5)
            let anim = CAKeyframeAnimation(keyPath: "bounds.size.height")
            anim.values = [base, high, low, base]
            anim.keyTimes = [0, 0.33, 0.66, 1.0]
            anim.duration = 0.9 + Double(i) * 0.07     // varied periods → organic feel
            anim.repeatCount = .infinity
            anim.autoreverses = false
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.beginTime = CACurrentMediaTime() + Double(i) * 0.08
            bar.add(anim, forKey: "equalize")
        }
    }

    func stopAnimating() {
        for bar in bars { bar.removeAnimation(forKey: "equalize") }
    }
}
