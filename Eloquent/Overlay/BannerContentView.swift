import AppKit

@MainActor
class BannerContentView: NSViewController {

    // Public API ------------------------------------------------------------
    var word: String = "" { didSet { wordLabel.stringValue = word } }
    var count: Int = 1 { didSet { updateCount() } }

    // Layout constants ------------------------------------------------------
    static let height: CGFloat = 56
    static let cornerRadius: CGFloat = 28   // fully rounded (height/2)
    private let hInset: CGFloat = 8
    private let badgeSize: CGFloat = 40

    // Subviews --------------------------------------------------------------
    private let effect = NSVisualEffectView()
    private let border = CALayer()
    private let badge = NSView()
    private let badgeGradient = CAGradientLayer()
    private let waveform = WaveformView()
    private let captionLabel = NSTextField(labelWithString: "FILLER WORD")
    private let wordLabel = NSTextField(labelWithString: "")
    private let countChip = NSView()
    private let countLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        // Liquid-glass base: dark HUD material, fully rounded, hairline highlight.
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effect)

        // Subtle top highlight border for the "glass" edge.
        border.borderWidth = 1
        border.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        border.cornerRadius = Self.cornerRadius
        effect.layer?.addSublayer(border)

        // Orange gradient badge with a waveform glyph.
        badge.wantsLayer = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeGradient.colors = [
            NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.20, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.95, green: 0.24, blue: 0.19, alpha: 1).cgColor
        ]
        badgeGradient.startPoint = CGPoint(x: 0, y: 0)
        badgeGradient.endPoint = CGPoint(x: 1, y: 1)
        badgeGradient.cornerRadius = badgeSize / 2
        badge.layer?.addSublayer(badgeGradient)
        effect.addSubview(badge)

        waveform.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(waveform)

        // Caption + word stack.
        captionLabel.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        captionLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        captionLabel.alignment = .left
        configureLabel(captionLabel)
        // letter-spaced caption
        captionLabel.attributedStringValue = NSAttributedString(
            string: "FILLER WORD",
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.35, alpha: 1.0),
                .kern: 1.6
            ])

        wordLabel.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        wordLabel.textColor = .white
        configureLabel(wordLabel)

        let textStack = NSStackView(views: [captionLabel, wordLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0
        textStack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(textStack)

        // Count chip (e.g. ×3).
        countChip.wantsLayer = true
        countChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        countChip.layer?.cornerRadius = 12
        countChip.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(countChip)

        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        countLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        configureLabel(countLabel)
        countChip.addSubview(countLabel)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            badge.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: hInset),
            badge.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),

            waveform.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 24),
            waveform.heightAnchor.constraint(equalToConstant: 20),

            textStack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),

            countChip.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 14),
            countChip.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            countChip.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            countChip.heightAnchor.constraint(equalToConstant: 24),
            countChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            countLabel.centerXAnchor.constraint(equalTo: countChip.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: countChip.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: countChip.leadingAnchor, constant: 10),
            countLabel.trailingAnchor.constraint(equalTo: countChip.trailingAnchor, constant: -10),
        ])

        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        border.frame = effect.bounds
        badgeGradient.frame = badge.bounds
    }

    /// Trigger the lively waveform animation (call when the banner appears/updates).
    func animateWaveform() {
        waveform.pulse()
    }

    private func configureLabel(_ l: NSTextField) {
        l.isBezeled = false
        l.isEditable = false
        l.isSelectable = false
        l.drawsBackground = false
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func updateCount() {
        countLabel.stringValue = "×\(count)"
        countChip.isHidden = count < 2
    }
}
