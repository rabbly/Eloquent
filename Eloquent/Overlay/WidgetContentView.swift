import AppKit

@MainActor
final class WidgetContentView: NSViewController {

    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    private let pillRadius: CGFloat = 28
    private let badgeSize: CGFloat = 36
    private let collapsedRowHeight: CGFloat = 56
    private let accent = NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.28, alpha: 1.0)

    // Background
    private let bg = NSView()
    private let effect = NSVisualEffectView()
    private let scrim = NSView()
    private let border = CALayer()

    // Badge (always in the top row, vertically centered within collapsedRowHeight)
    private let badge = NSView()
    private let badgeGradient = CAGradientLayer()
    private let waveform = WaveformView()

    // Collapsed-row content (all share the same centerY as the badge)
    private let noSessionLabel = NSTextField(labelWithString: "No active call")
    private let listeningLabel = NSTextField(labelWithString: "Listening…")
    private let captionLabel = NSTextField(labelWithString: "TOP WORD")
    private let wordLabel = NSTextField(labelWithString: "")
    private let countChip = NSView()
    private let countChipLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private var textStack: NSStackView!

    // Expanded section (appears below the collapsed row on click)
    private let expandedContainer = NSView()
    private var expandedRowsStack: NSStackView?

    // Flash
    private var flashRevert: DispatchWorkItem?

    // Track latest stats so showCollapsed can restore
    private var latestStats = SessionStats()
    private var latestNewWord: String?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        // Background pill
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

        // Badge — always anchored to the center of the top 56pt row
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

        // Status labels
        noSessionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        noSessionLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        configure(label: noSessionLabel)
        container.addSubview(noSessionLabel)

        listeningLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        listeningLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        configure(label: listeningLabel)
        container.addSubview(listeningLabel)

        // Word stack (caption + word + total)
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

        textStack = NSStackView(views: [captionLabel, wordLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        // Count chip
        countChip.wantsLayer = true
        countChip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        countChip.layer?.cornerRadius = 10
        countChip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(countChip)

        countChipLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        countChipLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        configure(label: countChipLabel)
        countChip.addSubview(countChipLabel)

        // Expanded container — sits below the collapsed row
        expandedContainer.translatesAutoresizingMaskIntoConstraints = false
        expandedContainer.isHidden = true
        container.addSubview(expandedContainer)

        // The badge centerY is always at collapsedRowHeight/2 from the top.
        // This keeps it in the same position whether collapsed or expanded.
        let badgeCenterY = collapsedRowHeight / 2

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

            // Badge always vertically centered in the top 56pt row
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: container.topAnchor, constant: badgeCenterY),
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),

            waveform.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 20),
            waveform.heightAnchor.constraint(equalToConstant: 16),

            // All collapsed-state content shares the badge centerY
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

            // Expanded container starts immediately below the collapsed row
            expandedContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            expandedContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            expandedContainer.topAnchor.constraint(equalTo: container.topAnchor, constant: collapsedRowHeight),
            expandedContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        showNoSession()
        self.view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        border.frame = bg.bounds
        badgeGradient.frame = badge.bounds
    }

    // MARK: - Collapsed states

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

    func showCollapsed() {
        guard isViewLoaded else { return }
        expandedContainer.isHidden = true
        // Restore the correct collapsed state based on what we last had
        if latestStats.total() > 0 {
            updateStats(latestStats, newWord: nil)
        } else {
            showListening()
        }
    }

    // MARK: - Stats + flash

    func updateStats(_ stats: SessionStats, newWord: String? = nil) {
        guard isViewLoaded else { return }
        latestStats = stats
        noSessionLabel.isHidden = true
        listeningLabel.isHidden = true

        if stats.total() == 0 {
            showListening()
            return
        }

        guard let top = stats.summary().first else { return }
        textStack.isHidden = false
        countChip.isHidden = top.count < 2
        countChipLabel.stringValue = "×\(top.count)"

        if let new = newWord, !new.isEmpty {
            flashRevert?.cancel()
            wordLabel.stringValue = new
            wordLabel.textColor = accent
            waveform.pulse()

            let revert = DispatchWorkItem { [weak self] in
                guard let self else { return }
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

    /// Builds the expanded rows and returns the extra height needed.
    func showExpanded(stats: SessionStats) -> CGFloat {
        guard isViewLoaded else { return 0 }
        latestStats = stats

        // Clear previous rows
        expandedRowsStack?.removeFromSuperview()
        expandedRowsStack = nil

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        expandedContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor),
            stack.topAnchor.constraint(equalTo: expandedContainer.topAnchor),
        ])

        // Header
        let header = makeLabel("THIS SESSION", size: 8, weight: .bold, color: accent, kern: 1.5)
        stack.addArrangedSubview(header)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Word rows
        for entry in stats.summary() {
            stack.addArrangedSubview(makeRow(word: entry.word, count: entry.count, bold: false))
        }

        // Total row
        stack.addArrangedSubview(NSView()) // small spacer
        stack.addArrangedSubview(makeRow(word: "Total", count: stats.total(), bold: true))

        expandedRowsStack = stack
        expandedContainer.isHidden = false
        // Keep the top row (badge + word + count chip) visible — don't hide textStack/countChip.

        // Calculate height: header + divider + (rows * rowHeight) + total + padding
        let rowCount = CGFloat(stats.summary().count + 1) // words + total
        let expandedH = 20 + 1 + 6 + rowCount * 22 + 16
        return expandedH
    }

    private func makeRow(word: String, count: Int, bold: Bool) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let wordF = makeLabel(word, size: 11, weight: bold ? .semibold : .regular,
                              color: bold ? .white : NSColor.white.withAlphaComponent(0.8))
        wordF.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(wordF)

        let countF = makeLabel("×\(count)", size: 11, weight: bold ? .semibold : .regular,
                                color: bold ? accent : NSColor.white.withAlphaComponent(0.5))
        countF.alignment = .right
        countF.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(countF)

        NSLayoutConstraint.activate([
            wordF.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            wordF.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            countF.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            countF.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            countF.leadingAnchor.constraint(greaterThanOrEqualTo: wordF.trailingAnchor, constant: 8),
        ])
        return row
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight,
                           color: NSColor, kern: CGFloat = 0) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        if kern != 0 {
            l.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .kern: kern
            ])
        }
        l.isBezeled = false; l.isEditable = false; l.isSelectable = false; l.drawsBackground = false
        return l
    }

    func resetSession() {
        guard isViewLoaded else { return }
        flashRevert?.cancel()
        flashRevert = nil
        latestStats = SessionStats()
        wordLabel.stringValue = ""
        showListening()
    }

    func startWaveform() { guard isViewLoaded else { return }; waveform.startAnimating() }
    func stopWaveform()  { guard isViewLoaded else { return }; waveform.stopAnimating() }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(event) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(event) }

    private func configure(label l: NSTextField) {
        l.isBezeled = false; l.isEditable = false; l.isSelectable = false; l.drawsBackground = false
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.required, for: .horizontal)
    }
}
