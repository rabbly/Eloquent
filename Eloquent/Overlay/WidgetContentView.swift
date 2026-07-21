import AppKit

@MainActor
final class WidgetContentView: NSViewController {

    // Drag callbacks (set by WidgetOverlay)
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    private let pillRadius: CGFloat = 28
    private let badgeSize: CGFloat = 36
    private let accent = NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.28, alpha: 1.0)

    // Background layers
    private let bg = NSView()
    private let effect = NSVisualEffectView()
    private let scrim = NSView()
    private let border = CALayer()

    // Badge
    private let badge = NSView()
    private let badgeGradient = CAGradientLayer()
    private let waveform = WaveformView()

    // Text
    private let captionLabel = NSTextField(labelWithString: "FILLER WORD")
    private let wordLabel = NSTextField(labelWithString: "")
    private let countChip = NSView()
    private let countChipLabel = NSTextField(labelWithString: "")

    // Idle-state label shown when no word has been flagged yet
    private let idleLabel = NSTextField(labelWithString: "Listening…")

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        bg.wantsLayer = true
        bg.layer?.masksToBounds = true
        bg.layer?.cornerRadius = pillRadius
        bg.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bg)

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(effect)

        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.92).cgColor
        scrim.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(scrim)

        border.borderWidth = 1
        border.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        border.cornerRadius = pillRadius
        bg.layer?.addSublayer(border)

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
        container.addSubview(badge)

        waveform.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(waveform)

        // Idle label (shown before any word is detected)
        idleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        idleLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        configure(label: idleLabel)
        container.addSubview(idleLabel)

        // Active: caption + word
        captionLabel.attributedStringValue = NSAttributedString(string: "FILLER WORD", attributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: accent,
            .kern: 1.5
        ])
        configure(label: captionLabel)

        wordLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        wordLabel.textColor = .white
        configure(label: wordLabel)

        let textStack = NSStackView(views: [captionLabel, wordLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        countChip.wantsLayer = true
        countChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        countChip.layer?.cornerRadius = 10
        countChip.isHidden = true
        countChip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(countChip)

        countChipLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        countChipLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        configure(label: countChipLabel)
        countChip.addSubview(countChipLabel)

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

            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),

            waveform.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 20),
            waveform.heightAnchor.constraint(equalToConstant: 16),

            idleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            idleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            countChip.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 10),
            countChip.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            countChip.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            countChip.heightAnchor.constraint(equalToConstant: 22),
            countChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            countChipLabel.centerXAnchor.constraint(equalTo: countChip.centerXAnchor),
            countChipLabel.centerYAnchor.constraint(equalTo: countChip.centerYAnchor),
            countChipLabel.leadingAnchor.constraint(equalTo: countChip.leadingAnchor, constant: 8),
            countChipLabel.trailingAnchor.constraint(equalTo: countChip.trailingAnchor, constant: -8),
        ])

        // Show idle state by default
        textStack.isHidden = true
        countChip.isHidden = true

        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        border.frame = bg.bounds
        badgeGradient.frame = badge.bounds
    }

    func setListening(_ listening: Bool) {
        guard isViewLoaded else { return }
        idleLabel.isHidden = !listening || !wordLabel.stringValue.isEmpty
    }

    func flag(word: String, count: Int) {
        guard isViewLoaded else { return }
        wordLabel.stringValue = word
        idleLabel.isHidden = true
        if let stack = wordLabel.superview {
            stack.isHidden = false
        }
        countChipLabel.stringValue = "×\(count)"
        countChip.isHidden = count < 2
        waveform.pulse()
    }

    func startWaveform() { guard isViewLoaded else { return }; waveform.startAnimating() }
    func stopWaveform() { guard isViewLoaded else { return }; waveform.stopAnimating() }

    // MARK: - Mouse handling for drag

    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }

    private func configure(label l: NSTextField) {
        l.isBezeled = false
        l.isEditable = false
        l.isSelectable = false
        l.drawsBackground = false
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.required, for: .horizontal)
    }
}
