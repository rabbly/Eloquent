import AppKit

@MainActor
class BannerContentView: NSViewController {

    enum Mode {
        case pill                 // all corners rounded, floats below the top edge
        case notch(topInset: CGFloat)  // square top, rounded bottom, hugs the top edge
    }

    // Public API ------------------------------------------------------------
    var word: String = "" { didSet { wordLabel.stringValue = word } }
    var count: Int = 1 { didSet { updateCount() } }

    // Layout ----------------------------------------------------------------
    static let rowHeight: CGFloat = 56          // height of the content row
    private let pillRadius: CGFloat = 27
    private let notchBottomRadius: CGFloat = 22
    private let hInset: CGFloat = 8
    private let badgeSize: CGFloat = 40

    private var mode: Mode = .pill
    private var topInsetConstraint: NSLayoutConstraint!

    // Background layers (ordered back→front): effect → scrim → specular → border
    private let bg = NSView()                    // clips everything to the shape
    private let effect = NSVisualEffectView()
    private let scrim = NSView()                 // opaque dark substrate → guarantees contrast
    private let specular = CAGradientLayer()     // faint top highlight
    private let border = CALayer()

    // Content
    private let badge = NSView()
    private let badgeGradient = CAGradientLayer()
    private let waveform = WaveformView()
    private let captionLabel = NSTextField(labelWithString: "FILLER WORD")
    private let wordLabel = NSTextField(labelWithString: "")
    private let countChip = NSView()
    private let countLabel = NSTextField(labelWithString: "")
    private let contentRow = NSView()

    private let accent = NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.28, alpha: 1.0)

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        // Shape container clips the glass + scrim to the rounded shape.
        bg.wantsLayer = true
        bg.layer?.masksToBounds = true
        bg.layer?.cornerRadius = pillRadius
        bg.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bg)

        // 1) Glass blur (bottom layer) — keeps a subtle liquid-glass quality.
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(effect)

        // 2) Opaque dark scrim ON TOP of the glass — this is what fixes contrast on
        //    light desktops. Text always has a dark substrate underneath it.
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.92).cgColor
        scrim.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(scrim)

        // 3) Faint specular highlight along the top edge (the "glass" sheen).
        specular.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        specular.startPoint = CGPoint(x: 0.5, y: 1.0)
        specular.endPoint = CGPoint(x: 0.5, y: 0.6)
        scrim.layer?.addSublayer(specular)

        // 4) Hairline border for the glass edge.
        border.borderWidth = 1
        border.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        border.cornerRadius = pillRadius
        bg.layer?.addSublayer(border)

        // ---- Content row -------------------------------------------------
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentRow)

        // Orange gradient badge with animated waveform.
        badge.wantsLayer = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badgeGradient.colors = [
            NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.20, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.95, green: 0.24, blue: 0.19, alpha: 1).cgColor
        ]
        badgeGradient.startPoint = CGPoint(x: 0, y: 1)
        badgeGradient.endPoint = CGPoint(x: 1, y: 0)
        badgeGradient.cornerRadius = badgeSize / 2
        badge.layer?.addSublayer(badgeGradient)
        contentRow.addSubview(badge)

        waveform.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(waveform)

        captionLabel.attributedStringValue = captionString()
        configureLabel(captionLabel)

        wordLabel.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        wordLabel.textColor = .white
        // Subtle shadow so the word stays crisp even over the specular sheen.
        wordLabel.wantsLayer = true
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.5)
        sh.shadowBlurRadius = 3
        sh.shadowOffset = NSSize(width: 0, height: -1)
        wordLabel.shadow = sh
        configureLabel(wordLabel)

        let textStack = NSStackView(views: [captionLabel, wordLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentRow.addSubview(textStack)

        countChip.wantsLayer = true
        countChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        countChip.layer?.cornerRadius = 12
        countChip.translatesAutoresizingMaskIntoConstraints = false
        contentRow.addSubview(countChip)

        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        countLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        configureLabel(countLabel)
        countChip.addSubview(countLabel)

        // top inset for content (0 for pill, notch height for notch mode)
        topInsetConstraint = contentRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 0)

        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bg.topAnchor.constraint(equalTo: container.topAnchor),
            bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            effect.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            effect.topAnchor.constraint(equalTo: bg.topAnchor),
            effect.bottomAnchor.constraint(equalTo: bg.bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: bg.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: bg.bottomAnchor),

            topInsetConstraint,
            contentRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentRow.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            contentRow.heightAnchor.constraint(equalToConstant: Self.rowHeight),

            badge.leadingAnchor.constraint(equalTo: contentRow.leadingAnchor, constant: hInset),
            badge.centerYAnchor.constraint(equalTo: contentRow.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),

            waveform.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 24),
            waveform.heightAnchor.constraint(equalToConstant: 20),

            textStack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentRow.centerYAnchor),

            countChip.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 14),
            countChip.trailingAnchor.constraint(equalTo: contentRow.trailingAnchor, constant: -12),
            countChip.centerYAnchor.constraint(equalTo: contentRow.centerYAnchor),
            countChip.heightAnchor.constraint(equalToConstant: 24),
            countChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            countLabel.centerXAnchor.constraint(equalTo: countChip.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: countChip.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: countChip.leadingAnchor, constant: 10),
            countLabel.trailingAnchor.constraint(equalTo: countChip.trailingAnchor, constant: -10),
        ])

        self.view = container
    }

    func configure(mode: Mode) {
        self.mode = mode
        guard isViewLoaded else { return }
        switch mode {
        case .pill:
            topInsetConstraint.constant = 0
            bg.layer?.cornerRadius = pillRadius
            bg.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                       .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            border.cornerRadius = pillRadius
            border.isHidden = false
        case .notch(let topInset):
            topInsetConstraint.constant = topInset
            bg.layer?.cornerRadius = notchBottomRadius
            // Round only the BOTTOM corners (layer coords: minY = bottom).
            bg.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            border.cornerRadius = notchBottomRadius
            border.isHidden = true   // no rim in notch mode; it reads as part of the notch
        }
        view.needsLayout = true
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        border.frame = bg.bounds
        badgeGradient.frame = badge.bounds
        // Specular occupies the top third of the scrim.
        specular.frame = CGRect(x: 0, y: scrim.bounds.height * 0.66,
                                width: scrim.bounds.width, height: scrim.bounds.height * 0.34)
    }

    func animateWaveform() { waveform.pulse() }

    private func captionString() -> NSAttributedString {
        NSAttributedString(string: "FILLER WORD", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: accent,
            .kern: 1.6
        ])
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
