import AppKit

@MainActor
final class WidgetContentView: NSViewController {

    // Drag callbacks
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    private let pillRadius: CGFloat = 28
    private let badgeSize: CGFloat = 36
    private let accent = NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.28, alpha: 1.0)

    // Background
    private let bg = NSView()
    private let effect = NSVisualEffectView()
    private let scrim = NSView()
    private let border = CALayer()

    // Badge
    private let badge = NSView()
    private let badgeGradient = CAGradientLayer()
    private let waveform = WaveformView()

    // State: no-session
    private let noSessionLabel = NSTextField(labelWithString: "No active call")

    // State: listening (session active, no words yet)
    private let listeningLabel = NSTextField(labelWithString: "Listening…")

    // State: words detected
    private let captionLabel = NSTextField(labelWithString: "TOP WORD")
    private let wordLabel = NSTextField(labelWithString: "")
    private let countChip = NSView()
    private let countChipLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")

    private var textStack: NSStackView!

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

        // Badge
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

        // No-session state
        noSessionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        noSessionLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        configure(label: noSessionLabel)
        container.addSubview(noSessionLabel)

        // Listening state
        listeningLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        listeningLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        configure(label: listeningLabel)
        container.addSubview(listeningLabel)

        // Words-detected state
        captionLabel.attributedStringValue = NSAttributedString(string: "TOP WORD", attributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: accent,
            .kern: 1.5
        ])
        configure(label: captionLabel)

        wordLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        wordLabel.textColor = .white
        configure(label: wordLabel)

        totalLabel.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        totalLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        configure(label: totalLabel)

        textStack = NSStackView(views: [captionLabel, wordLabel, totalLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        countChip.wantsLayer = true
        countChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        countChip.layer?.cornerRadius = 10
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

            noSessionLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            noSessionLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            listeningLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            listeningLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

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

        showNoSession()
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        border.frame = bg.bounds
        badgeGradient.frame = badge.bounds
    }

    // MARK: - State transitions

    func showNoSession() {
        guard isViewLoaded else { return }
        noSessionLabel.isHidden = false
        listeningLabel.isHidden = true
        textStack.isHidden = true
        countChip.isHidden = true
    }

    func showListening() {
        guard isViewLoaded else { return }
        noSessionLabel.isHidden = true
        listeningLabel.isHidden = false
        textStack.isHidden = true
        countChip.isHidden = true
    }

    func updateStats(_ stats: SessionStats) {
        guard isViewLoaded else { return }
        noSessionLabel.isHidden = true
        listeningLabel.isHidden = true

        if stats.total() == 0 {
            showListening()
            return
        }

        guard let top = stats.summary().first else { return }
        wordLabel.stringValue = top.word
        countChipLabel.stringValue = "×\(top.count)"
        countChip.isHidden = top.count < 2
        let t = stats.total()
        totalLabel.stringValue = "\(t) total"
        totalLabel.isHidden = false
        textStack.isHidden = false
        waveform.pulse()
    }

    func resetSession() {
        guard isViewLoaded else { return }
        wordLabel.stringValue = ""
        totalLabel.stringValue = ""
        showListening()
    }

    func startWaveform() { guard isViewLoaded else { return }; waveform.startAnimating() }
    func stopWaveform() { guard isViewLoaded else { return }; waveform.stopAnimating() }

    // MARK: - Mouse handling

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
