import AppKit

@MainActor
final class WidgetContentView: NSViewController {

    // Drag/tap callbacks
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

    // Collapsed states
    private let noSessionLabel = NSTextField(labelWithString: "No active call")
    private let listeningLabel = NSTextField(labelWithString: "Listening…")
    private let captionLabel = NSTextField(labelWithString: "TOP WORD")
    private let wordLabel = NSTextField(labelWithString: "")
    private let countChip = NSView()
    private let countChipLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private var textStack: NSStackView!

    // Expanded state: vertical list of word rows
    private let expandedContainer = NSView()

    // Flash state
    private var flashRevert: DispatchWorkItem?
    private var lastFlashedWord = ""

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

        // No-session
        noSessionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        noSessionLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        configure(label: noSessionLabel)
        container.addSubview(noSessionLabel)

        // Listening
        listeningLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        listeningLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        configure(label: listeningLabel)
        container.addSubview(listeningLabel)

        // Words-detected (collapsed)
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

        // Expanded container (hidden by default)
        expandedContainer.translatesAutoresizingMaskIntoConstraints = false
        expandedContainer.isHidden = true
        container.addSubview(expandedContainer)

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
            badge.centerYAnchor.constraint(equalTo: container.topAnchor, constant: 28), // always 28pt from top
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),

            waveform.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 20),
            waveform.heightAnchor.constraint(equalToConstant: 16),

            noSessionLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            noSessionLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            listeningLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            listeningLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            countChip.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 10),
            countChip.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            countChip.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            countChip.heightAnchor.constraint(equalToConstant: 22),
            countChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            countChipLabel.centerXAnchor.constraint(equalTo: countChip.centerXAnchor),
            countChipLabel.centerYAnchor.constraint(equalTo: countChip.centerYAnchor),
            countChipLabel.leadingAnchor.constraint(equalTo: countChip.leadingAnchor, constant: 8),
            countChipLabel.trailingAnchor.constraint(equalTo: countChip.trailingAnchor, constant: -8),

            expandedContainer.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            expandedContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            expandedContainer.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 8),
            expandedContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        showNoSession()
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        border.frame = bg.bounds
        badgeGradient.frame = badge.bounds
    }

    // MARK: - Collapsed state transitions

    func showNoSession() {
        guard isViewLoaded else { return }
        noSessionLabel.isHidden = false
        listeningLabel.isHidden = true
        textStack.isHidden = true
        countChip.isHidden = true
        expandedContainer.isHidden = true
    }

    func showListening() {
        guard isViewLoaded else { return }
        noSessionLabel.isHidden = true
        listeningLabel.isHidden = false
        textStack.isHidden = true
        countChip.isHidden = true
        expandedContainer.isHidden = true
    }

    // MARK: - updateStats with new-word flash

    func updateStats(_ stats: SessionStats, newWord: String? = nil) {
        guard isViewLoaded else { return }
        noSessionLabel.isHidden = true
        listeningLabel.isHidden = true

        if stats.total() == 0 {
            showListening()
            return
        }

        guard let top = stats.summary().first else { return }
        let t = stats.total()
        totalLabel.stringValue = "\(t) total"
        totalLabel.isHidden = false
        textStack.isHidden = false
        countChip.isHidden = top.count < 2
        countChipLabel.stringValue = "×\(top.count)"

        // Flash the newly detected word in accent before settling to top word.
        if let new = newWord, !new.isEmpty {
            flashRevert?.cancel()
            wordLabel.stringValue = new
            wordLabel.textColor = accent
            waveform.pulse()

            let revert = DispatchWorkItem { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    ctx.allowsImplicitAnimation = true
                }
                self.wordLabel.stringValue = top.word
                self.wordLabel.textColor = .white
                self.countChipLabel.stringValue = "×\(top.count)"
                self.countChip.isHidden = top.count < 2
            }
            flashRevert = revert
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: revert)
        } else {
            wordLabel.stringValue = top.word
            wordLabel.textColor = .white
        }
    }

    // MARK: - Expanded state

    /// Returns the height the expanded content needs (for the overlay to resize the panel).
    func showExpanded(stats: SessionStats) -> CGFloat {
        guard isViewLoaded else { return 0 }
        expandedContainer.subviews.forEach { $0.removeFromSuperview() }

        let summary = stats.summary()
        let rowH: CGFloat = 20
        let gap: CGFloat = 4
        var y = CGFloat(summary.count - 1) * (rowH + gap)  // NSView bottom-up

        for entry in summary {
            let row = makeExpandedRow(word: entry.word, count: entry.count)
            row.frame = NSRect(x: 0, y: y, width: 160, height: rowH)
            expandedContainer.addSubview(row)
            y -= rowH + gap
        }

        // Total separator line
        let sep = NSBox()
        sep.boxType = .separator
        sep.frame = NSRect(x: 0, y: y, width: 160, height: 1)
        expandedContainer.addSubview(sep)
        y -= rowH

        let totalRow = makeExpandedRow(word: "Total", count: stats.total(), bold: true)
        totalRow.frame = NSRect(x: 0, y: y, width: 160, height: rowH)
        expandedContainer.addSubview(totalRow)

        // Show expanded, hide collapsed word/count
        expandedContainer.isHidden = false
        textStack.isHidden = true
        countChip.isHidden = true

        // Height = collapsed row (56) + expanded content
        let expandedH = CGFloat(summary.count + 2) * (rowH + gap) + 24
        return expandedH
    }

    func showCollapsed() {
        guard isViewLoaded else { return }
        expandedContainer.isHidden = true
        // Restore normal word display if we have content
        if !wordLabel.stringValue.isEmpty {
            textStack.isHidden = false
        }
    }

    private func makeExpandedRow(word: String, count: Int, bold: Bool = false) -> NSView {
        let container = NSView()
        let wordF = NSTextField(labelWithString: word)
        wordF.font = NSFont.systemFont(ofSize: 11, weight: bold ? .semibold : .regular)
        wordF.textColor = bold ? .white : NSColor.white.withAlphaComponent(0.75)
        wordF.frame = NSRect(x: 0, y: 2, width: 110, height: 16)
        container.addSubview(wordF)

        let countF = NSTextField(labelWithString: "×\(count)")
        countF.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: bold ? .semibold : .regular)
        countF.textColor = bold ? accent : NSColor.white.withAlphaComponent(0.55)
        countF.alignment = .right
        countF.frame = NSRect(x: 114, y: 2, width: 46, height: 16)
        container.addSubview(countF)

        return container
    }

    func startWaveform() { guard isViewLoaded else { return }; waveform.startAnimating() }
    func stopWaveform() { guard isViewLoaded else { return }; waveform.stopAnimating() }

    func resetSession() {
        guard isViewLoaded else { return }
        flashRevert?.cancel()
        flashRevert = nil
        wordLabel.stringValue = ""
        totalLabel.stringValue = ""
        showListening()
    }

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
