import AppKit

// MARK: - Window manager

@MainActor
final class AnalyticsWindow: NSObject, NSWindowDelegate {
    static let shared = AnalyticsWindow()
    private var window: NSWindow?
    private override init() {}

    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let vc = AnalyticsViewController()
        let win = NSWindow(contentViewController: vc)
        win.title = "Eloquent — Analytics"
        win.setContentSize(NSSize(width: 660, height: 760))
        win.minSize = NSSize(width: 560, height: 500)
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.appearance = NSAppearance(named: .darkAqua)
        win.isMovableByWindowBackground = true
        win.isOpaque = true
        win.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1.0)
        win.center()
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}

// MARK: - Palette

private enum P {
    static let accent    = NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.28, alpha: 1.0)
    static let accentDim = NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.28, alpha: 0.55)
    static let bg        = NSColor(calibratedWhite: 0.09, alpha: 1.0)
    static let card      = NSColor(calibratedWhite: 0.14, alpha: 1.0)
    static let surface   = NSColor(calibratedWhite: 0.17, alpha: 1.0)
    static let sep       = NSColor(calibratedWhite: 1.0, alpha: 0.08)
    static let textPrim  = NSColor.white
    static let textSec   = NSColor(calibratedWhite: 1.0, alpha: 0.55)
    static let textTert  = NSColor(calibratedWhite: 1.0, alpha: 0.30)
    static let good      = NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.47, alpha: 1.0)
    static let bad       = NSColor(calibratedRed: 1.0, green: 0.33, blue: 0.33, alpha: 1.0)
}

// MARK: - Main view controller

@MainActor
final class AnalyticsViewController: NSViewController {
    private let scroll = NSScrollView()
    private let stack  = NSStackView()

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = P.bg.cgColor
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1.0)
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    func reload() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let store = AnalyticsStore.shared
        let sessions = store.allSessions

        // ---- Hero header
        stack.addArrangedSubview(heroHeader())

        // ---- Stat cards
        stack.addArrangedSubview(statRow(store: store, sessions: sessions))
        stack.addArrangedSubview(sep())

        if sessions.isEmpty {
            stack.addArrangedSubview(emptyState())
        } else {
            // ---- Chart
            stack.addArrangedSubview(sectionHeader("TREND"))
            let chart = BarChartView(sessions: Array(sessions.reversed().prefix(30)),
                                     avgFPM: store.last7DaysAvgFPM)
            chart.translatesAutoresizingMaskIntoConstraints = false
            chart.heightAnchor.constraint(equalToConstant: 170).isActive = true
            stack.addArrangedSubview(inset(chart))
            stack.addArrangedSubview(sep())

            // ---- Per-word table
            let words = store.allWords
            if !words.isEmpty {
                stack.addArrangedSubview(sectionHeader("PER-WORD BREAKDOWN"))
                stack.addArrangedSubview(wordTable(words: words, store: store))
                stack.addArrangedSubview(sep())
            }

            // ---- Suggested fillers
            let candidates = store.candidateFillers
            if !candidates.isEmpty {
                stack.addArrangedSubview(sectionHeader("SUGGESTED FILLERS"))
                stack.addArrangedSubview(suggestedFillersNote())
                for candidate in candidates {
                    stack.addArrangedSubview(candidateRow(candidate))
                }
                stack.addArrangedSubview(sep())
            }

            // ---- Sessions
            stack.addArrangedSubview(sectionHeader("SESSIONS"))
            for session in sessions {
                let row = SessionRowView(session: session, controller: self)
                row.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(row)
            }
        }

        // ---- Footer
        stack.addArrangedSubview(sep())
        stack.addArrangedSubview(footer(sessions: sessions))
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    }

    // MARK: - Hero

    private func heroHeader() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let title = tf("Eloquent", size: 22, weight: .bold, color: P.textPrim)
        let sub   = tf("Speech analytics", size: 12, weight: .regular, color: P.accentDim)
        for (l, y) in [(title, CGFloat(34)), (sub, CGFloat(16))] {
            l.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(l)
            NSLayoutConstraint.activate([
                l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
                l.topAnchor.constraint(equalTo: v.topAnchor, constant: y),
            ])
        }

        let refreshBtn = NSButton(title: "", target: self, action: #selector(refreshTapped))
        refreshBtn.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshBtn.bezelStyle = .recessed
        refreshBtn.isBordered = false
        refreshBtn.contentTintColor = P.textTert
        refreshBtn.toolTip = "Refresh analytics"
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(refreshBtn)
        NSLayoutConstraint.activate([
            refreshBtn.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),
            refreshBtn.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            refreshBtn.widthAnchor.constraint(equalToConstant: 28),
            refreshBtn.heightAnchor.constraint(equalToConstant: 28),
        ])
        return v
    }

    @objc private func refreshTapped() { reload() }

    // MARK: - Stat cards

    private func statRow(store: AnalyticsStore, sessions: [SessionRecord]) -> NSView {
        // Primary metric: filler rate (per 100 words) if we have word data, else FPM
        let hasRateData = sessions.contains { $0.totalWordsSpoken > 0 }
        let rateAvg = store.last7DaysAvgFillerRate
        let fpmAvg  = store.last7DaysAvgFPM

        let primaryLabel: String
        let primaryValue: String
        if hasRateData && rateAvg > 0 {
            primaryLabel = "FILLER RATE  7D"
            primaryValue = String(format: "%.1f%%", rateAvg)
        } else {
            primaryLabel = "AVG FPM  7D"
            primaryValue = sessions.isEmpty ? "—" : String(format: "%.1f", fpmAvg)
        }

        // Trend vs prior 5 sessions
        let trendValue: String
        if let pct = store.recentTrendPercent {
            let arrow = pct <= 0 ? "↓" : "↑"
            trendValue = String(format: "%@ %.0f%%", arrow, abs(pct))
        } else {
            trendValue = "—"
        }

        let bestValue: String
        if let best = store.bestSessionByRate {
            bestValue = String(format: "%.1f%%", best.fillerRate)
        } else if let best = store.bestSession {
            bestValue = String(format: "%.1f fpm", best.fillersPerMinute)
        } else {
            bestValue = "—"
        }

        let items: [(String, String, NSColor?, String)] = [
            ("SESSIONS",       "\(sessions.count)", nil,
             "Total number of sessions recorded. A session is one continuous period of active monitoring."),
            (primaryLabel,     primaryValue, nil,
             hasRateData
                ? "Filler rate: fillers ÷ total words spoken × 100. Normalises for both session length and how much you were speaking — a 2-minute and 30-minute session are directly comparable. Average over the last 7 days."
                : "Fillers per minute of session time. Average over the last 7 days. Tip: run more sessions to unlock the more accurate Filler Rate metric."),
            ("TREND  VS PREV", trendValue,
             store.recentTrendPercent.map { $0 <= 0 ? P.good : P.bad },
             store.recentTrendPercent.map { pct in
                 let dir = pct <= 0 ? "lower (better)" : "higher (worse)"
                 return String(format: "Your filler rate in the last 5 sessions is %.0f%% %@ than the 5 sessions before that. ↓ means improving.", abs(pct), dir)
             } ?? "Not enough sessions yet. Need at least 6 sessions with word data to calculate a trend."),
            ("BEST SESSION",   bestValue, nil,
             store.bestSessionByRate != nil
                ? "Your lowest filler rate session: fewest fillers relative to words spoken. Lower % = better."
                : "Your session with the fewest fillers per minute of speaking time. Lower = better."),
        ]
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        items.forEach { row.addArrangedSubview(statCard(label: $0.0, value: $0.1, valueColor: $0.2, tooltip: $0.3)) }
        return inset(row, v: 14)
    }

    private func statCard(label: String, value: String, valueColor: NSColor? = nil, tooltip: String = "") -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = P.card.cgColor
        card.layer?.cornerRadius = 12
        if !tooltip.isEmpty { card.toolTip = tooltip }

        let valL = tf(value, size: 26, weight: .bold, color: valueColor ?? P.textPrim)
        let lblL = tf(label, size: 8.5, weight: .semibold, color: P.accent)
        lblL.attributedStringValue = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: P.accent,
            .kern: 1.3
        ])
        for l in [valL, lblL] { l.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(l) }
        NSLayoutConstraint.activate([
            valL.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            valL.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            lblL.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            lblL.topAnchor.constraint(equalTo: valL.bottomAnchor, constant: 3),
            lblL.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    // MARK: - Word table

    private func wordTable(words: [(word: String, total: Int, rateMetric: Double, rateLabel: String)],
                           store: AnalyticsStore) -> NSView {
        let t = NSStackView()
        t.orientation = .vertical; t.spacing = 0
        // Use the first entry's rateLabel for the header column title
        let rateColHeader = words.first?.rateLabel.uppercased() ?? "RATE"
        let headerRow = wordRow("WORD", "TOTAL", rateColHeader, "TREND", header: true)
        headerRow.toolTip = "WORD: filler word detected  |  TOTAL: all-time count  |  \(rateColHeader): occurrences per 100 words spoken (normalised for speaking time)  |  TREND: comparing last 7 sessions vs previous 7"
        t.addArrangedSubview(headerRow)
        for entry in words {
            let tr = store.trend(for: entry.word)
            let tStr  = tr > 0 ? "↓  better" : tr < 0 ? "↑  worse" : "↔  steady"
            let tCol: NSColor = tr > 0 ? P.good : tr < 0 ? P.bad : P.textTert
            let dataRow = wordRow(entry.word,
                                  "\(entry.total)",
                                  String(format: "%.2f", entry.rateMetric),
                                  tStr, trendColor: tCol)
            let trendDesc = tr > 0 ? "improving (less frequent recently)" : tr < 0 ? "worsening (more frequent recently)" : "steady"
            dataRow.toolTip = "\"\(entry.word)\": said \(entry.total) times total · \(String(format: "%.2f", entry.rateMetric)) \(entry.rateLabel) · trend: \(trendDesc)"
            t.addArrangedSubview(dataRow)
        }
        return inset(t, v: 0)
    }

    private func wordRow(_ word: String, _ total: String, _ avg: String, _ trend: String,
                         header: Bool = false, trendColor: NSColor = P.textTert) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: header ? 28 : 32).isActive = true
        if header {
            row.wantsLayer = true
            row.layer?.backgroundColor = P.surface.cgColor
        }

        let sz: CGFloat = header ? 9 : 12
        let wt: NSFont.Weight = header ? .semibold : .regular
        let colorsAndOffsets: [(String, NSColor, CGFloat)] = [
            (word, header ? P.accent : P.textPrim, 0),
            (total, header ? P.accent : P.textSec, 160),
            (avg,   header ? P.accent : P.textSec, 280),
            (trend, header ? P.accent : trendColor, 380),
        ]
        for (text, color, x) in colorsAndOffsets {
            let l: NSTextField
            if header {
                l = NSTextField(labelWithString: "")
                l.attributedStringValue = NSAttributedString(string: text, attributes: [
                    .font: NSFont.systemFont(ofSize: sz, weight: wt),
                    .foregroundColor: color,
                    .kern: 1.2
                ])
            } else {
                l = tf(text, size: sz, weight: wt, color: color)
            }
            l.frame = NSRect(x: x + 4, y: (header ? 7 : 9), width: 150, height: 16)
            row.addSubview(l)
        }
        return row
    }

    // MARK: - Suggested fillers

    private func suggestedFillersNote() -> NSView {
        let l = tf("Words you use frequently that aren't in your filler word list yet.",
                   size: 11, color: P.textTert)
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 2
        return inset(l, v: 4)
    }

    private func candidateRow(_ candidate: CandidateFiller) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        row.layer?.backgroundColor = P.surface.cgColor
        row.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let wordL = tf(candidate.word, size: 13, weight: .semibold, color: P.textPrim)
        let baseline = AnalyticsStore.corpusBaseline[candidate.word] ?? 0.05
        let ratePerHundred = candidate.avgPerSession   // avgPerSession stores mean rate/100w
        let lift = ratePerHundred / baseline
        let liftStr = lift >= 10 ? String(format: "%.0f×", lift) : String(format: "%.1f×", lift)
        let metaL = tf("~\(liftStr) above typical · \(candidate.sessionsCount) session\(candidate.sessionsCount == 1 ? "" : "s")",
                       size: 11, color: P.textTert)

        let addBtn = NSButton(title: "Add to list", target: self, action: #selector(addCandidateTapped(_:)))
        addBtn.bezelStyle = .rounded
        addBtn.controlSize = .small
        addBtn.contentTintColor = P.good
        addBtn.identifier = NSUserInterfaceItemIdentifier(candidate.word)

        let dismissBtn = NSButton(title: "Dismiss", target: self, action: #selector(dismissCandidateTapped(_:)))
        dismissBtn.bezelStyle = .recessed
        dismissBtn.controlSize = .small
        dismissBtn.contentTintColor = P.textTert
        dismissBtn.identifier = NSUserInterfaceItemIdentifier(candidate.word)

        for v in [wordL, metaL, addBtn, dismissBtn] {
            v.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(v)
        }
        NSLayoutConstraint.activate([
            wordL.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 24),
            wordL.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            metaL.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 24),
            metaL.topAnchor.constraint(equalTo: wordL.bottomAnchor, constant: 2),
            dismissBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            dismissBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            addBtn.trailingAnchor.constraint(equalTo: dismissBtn.leadingAnchor, constant: -8),
            addBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    @objc private func addCandidateTapped(_ sender: NSButton) {
        guard let word = sender.identifier?.rawValue else { return }
        Settings.addCustomFiller(word)
        // Also remove from dismissed if it was there
        var dismissed = Settings.dismissedCandidates
        dismissed.remove(word)
        Settings.dismissedCandidates = dismissed
        reload()
    }

    @objc private func dismissCandidateTapped(_ sender: NSButton) {
        guard let word = sender.identifier?.rawValue else { return }
        AnalyticsStore.shared.dismissCandidate(word)
        reload()
    }

    // MARK: - Empty state

    private func emptyState() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let icon = tf("🎙", size: 36, weight: .regular, color: P.textTert)
        let msg  = tf("No sessions yet", size: 15, weight: .medium, color: P.textSec)
        let sub  = tf("Complete a call to start tracking your progress.", size: 12, color: P.textTert)
        for l in [icon, msg, sub] {
            l.alignment = .center; l.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(l)
        }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -20),
            msg.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            msg.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            sub.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            sub.topAnchor.constraint(equalTo: msg.bottomAnchor, constant: 4),
        ])
        return v
    }

    // MARK: - Footer

    private func footer(sessions: [SessionRecord]) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 48).isActive = true
        if !sessions.isEmpty {
            let btn = NSButton(title: "Reset All History", target: self, action: #selector(resetHistory))
            btn.bezelStyle = .recessed
            btn.controlSize = .small
            btn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 24),
                btn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
        }
        return row
    }

    // MARK: - Helpers

    func sectionHeader(_ text: String) -> NSView {
        let l = NSTextField(labelWithString: "")
        l.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: P.accent,
            .kern: 1.4
        ])
        l.translatesAutoresizingMaskIntoConstraints = false
        return inset(l, v: 12)
    }

    private func sep() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = P.sep.cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func inset(_ child: NSView, v: CGFloat = 8) -> NSView {
        let w = NSView()
        child.translatesAutoresizingMaskIntoConstraints = false
        w.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: w.leadingAnchor, constant: 24),
            child.trailingAnchor.constraint(equalTo: w.trailingAnchor, constant: -24),
            child.topAnchor.constraint(equalTo: w.topAnchor, constant: v),
            child.bottomAnchor.constraint(equalTo: w.bottomAnchor, constant: -v),
        ])
        return w
    }

    func tf(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
            color: NSColor = P.textPrim) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    @objc private func resetHistory() {
        let alert = NSAlert()
        alert.messageText = "Reset All History?"
        alert.informativeText = "This permanently deletes all session records."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AnalyticsStore.shared.clear(); reload()
    }

    func deleteSession(id: UUID) {
        AnalyticsStore.shared.deleteSession(id: id); reload()
    }
}

// MARK: - Session row (interactive)

@MainActor
private final class SessionRowView: NSView {
    private let session: SessionRecord
    private weak var controller: AnalyticsViewController?
    private var isHovered = false
    private var isExpanded = false
    private let deleteBtn = NSButton()
    private let chevron = NSTextField()
    private let detailContainer = NSView()
    private var detailHeightConstraint: NSLayoutConstraint!
    private let rowHeight: CGFloat = 52

    init(session: SessionRecord, controller: AnalyticsViewController) {
        self.session = session
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        buildRow()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildRow() {
        // Row content area
        let rowArea = NSView()
        rowArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowArea)

        let df = DateFormatter()
        df.dateStyle = .medium; df.timeStyle = .short

        let dateL = lbl(df.string(from: session.date), size: 13, weight: .medium, color: .white)
        let durL  = lbl(session.formattedDuration, size: 11, color: .init(calibratedWhite: 1, alpha: 0.5))
        let totL  = lbl("\(session.total) words", size: 12, color: P.textSec)
        let rateStr = session.totalWordsSpoken > 0
            ? String(format: "%.1f%%/100w", session.fillerRate)
            : String(format: "%.1f fpm", session.fillersPerMinute)
        let fpmL  = lbl(rateStr, size: 11, color: P.textTert)
        let topL  = lbl(session.topWord.map { "top: \($0)" } ?? "", size: 11, color: P.accentDim)

        // Chevron
        chevron.stringValue = "›"
        chevron.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        chevron.textColor = P.textTert
        chevron.isBezeled = false; chevron.isEditable = false; chevron.isSelectable = false
        chevron.drawsBackground = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        rowArea.addSubview(chevron)

        // Delete button (hidden until hover)
        deleteBtn.title = ""
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteBtn.imageScaling = .scaleProportionallyDown
        deleteBtn.bezelStyle = .recessed
        deleteBtn.isBordered = false
        deleteBtn.contentTintColor = P.bad
        deleteBtn.alphaValue = 0
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteTapped)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        rowArea.addSubview(deleteBtn)

        for l in [dateL, durL, totL, fpmL, topL] {
            l.translatesAutoresizingMaskIntoConstraints = false
            rowArea.addSubview(l)
        }

        NSLayoutConstraint.activate([
            rowArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowArea.topAnchor.constraint(equalTo: topAnchor),
            rowArea.heightAnchor.constraint(equalToConstant: rowHeight),

            dateL.leadingAnchor.constraint(equalTo: rowArea.leadingAnchor, constant: 24),
            dateL.centerYAnchor.constraint(equalTo: rowArea.centerYAnchor),

            durL.leadingAnchor.constraint(equalTo: rowArea.leadingAnchor, constant: 200),
            durL.centerYAnchor.constraint(equalTo: rowArea.centerYAnchor),

            totL.leadingAnchor.constraint(equalTo: rowArea.leadingAnchor, constant: 280),
            totL.centerYAnchor.constraint(equalTo: rowArea.centerYAnchor),

            fpmL.leadingAnchor.constraint(equalTo: rowArea.leadingAnchor, constant: 370),
            fpmL.centerYAnchor.constraint(equalTo: rowArea.centerYAnchor),

            topL.leadingAnchor.constraint(equalTo: rowArea.leadingAnchor, constant: 450),
            topL.centerYAnchor.constraint(equalTo: rowArea.centerYAnchor),

            deleteBtn.trailingAnchor.constraint(equalTo: rowArea.trailingAnchor, constant: -24),
            deleteBtn.centerYAnchor.constraint(equalTo: rowArea.centerYAnchor),
            deleteBtn.widthAnchor.constraint(equalToConstant: 24),
            deleteBtn.heightAnchor.constraint(equalToConstant: 24),

            chevron.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: rowArea.centerYAnchor),
        ])

        // Detail container (hidden, height=0)
        detailContainer.wantsLayer = true
        detailContainer.layer?.backgroundColor = P.surface.cgColor
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.clipsToBounds = true
        addSubview(detailContainer)

        detailHeightConstraint = detailContainer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            detailContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailContainer.topAnchor.constraint(equalTo: rowArea.bottomAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            detailHeightConstraint,
        ])

        updateTrackingAreas()

        // Click gesture
        let click = NSClickGestureRecognizer(target: self, action: #selector(toggleDetail))
        rowArea.addGestureRecognizer(click)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.04).cgColor
            deleteBtn.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            layer?.backgroundColor = .clear
            deleteBtn.animator().alphaValue = 0
        }
    }

    @objc private func toggleDetail() {
        isExpanded.toggle()
        if isExpanded { buildDetail() }

        let newH = isExpanded ? detailContentHeight() : 0
        let angle = isExpanded ? -90.0 : 0.0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            detailHeightConstraint.animator().constant = newH

            // Rotate chevron
            let rotation = CATransform3DRotate(CATransform3DIdentity, angle * .pi / 180, 0, 0, 1)
            if let layer = chevron.layer { layer.transform = rotation }
        }
        if !isExpanded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                self?.detailContainer.subviews.forEach { $0.removeFromSuperview() }
            }
        }
    }

    private func detailContentHeight() -> CGFloat {
        let rowH: CGFloat = 28
        return CGFloat(session.summary().count + 1) * rowH + 48   // rows + top/bottom padding
    }

    private func buildDetail() {
        detailContainer.subviews.forEach { $0.removeFromSuperview() }

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 2
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: detailContainer.topAnchor, constant: 12),
        ])

        let maxCount = CGFloat(session.summary().first?.count ?? 1)
        for entry in session.summary() {
            let rowV = NSView()
            rowV.translatesAutoresizingMaskIntoConstraints = false
            rowV.heightAnchor.constraint(equalToConstant: 26).isActive = true

            let wdL = lbl(entry.word, size: 11, color: .white)
            wdL.translatesAutoresizingMaskIntoConstraints = false
            rowV.addSubview(wdL)

            // Mini bar
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = P.accent.withAlphaComponent(0.6).cgColor
            bar.layer?.cornerRadius = 3
            bar.translatesAutoresizingMaskIntoConstraints = false
            rowV.addSubview(bar)

            let cntL = lbl("×\(entry.count)", size: 11, color: P.accentDim)
            cntL.alignment = .right
            cntL.translatesAutoresizingMaskIntoConstraints = false
            rowV.addSubview(cntL)

            let barFrac = max(0.04, CGFloat(entry.count) / maxCount)
            NSLayoutConstraint.activate([
                wdL.leadingAnchor.constraint(equalTo: rowV.leadingAnchor),
                wdL.centerYAnchor.constraint(equalTo: rowV.centerYAnchor),
                wdL.widthAnchor.constraint(equalToConstant: 110),

                bar.leadingAnchor.constraint(equalTo: rowV.leadingAnchor, constant: 118),
                bar.centerYAnchor.constraint(equalTo: rowV.centerYAnchor),
                bar.heightAnchor.constraint(equalToConstant: 8),
                bar.widthAnchor.constraint(equalTo: rowV.widthAnchor, multiplier: barFrac * 0.5),

                cntL.trailingAnchor.constraint(equalTo: rowV.trailingAnchor),
                cntL.centerYAnchor.constraint(equalTo: rowV.centerYAnchor),
                cntL.widthAnchor.constraint(equalToConstant: 40),
            ])
            contentStack.addArrangedSubview(rowV)
        }

        // Delete button in detail
        let delBtn = NSButton(title: "Delete Session", target: self, action: #selector(deleteTapped))
        delBtn.bezelStyle = .rounded
        delBtn.contentTintColor = P.bad
        delBtn.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(delBtn)
        NSLayoutConstraint.activate([
            delBtn.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -24),
            delBtn.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -10),
        ])
    }

    @objc private func deleteTapped() {
        let alert = NSAlert()
        alert.messageText = "Delete this session?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        controller?.deleteSession(id: session.id)
    }

    private func lbl(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                     color: NSColor = P.textPrim) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }
}

// MARK: - Bar chart

@MainActor
private final class BarChartView: NSView {
    private let sessions: [SessionRecord]
    private let avgFPM: Double

    init(sessions: [SessionRecord], avgFPM: Double) {
        self.sessions = sessions; self.avgFPM = avgFPM
        super.init(frame: .zero); wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !sessions.isEmpty else { return }

        let hPad: CGFloat = 4
        let vPad: CGFloat = 28
        let chartRect = NSRect(x: hPad, y: vPad, width: bounds.width - hPad * 2, height: bounds.height - vPad * 2)
        let maxTotal = CGFloat(sessions.map(\.total).max() ?? 1)

        // Grid lines
        for frac in [0.25, 0.5, 0.75, 1.0] {
            let y = chartRect.minY + CGFloat(frac) * chartRect.height
            let p = NSBezierPath()
            p.move(to: NSPoint(x: chartRect.minX, y: y))
            p.line(to: NSPoint(x: chartRect.maxX, y: y))
            p.lineWidth = 1
            NSColor(calibratedWhite: 1, alpha: 0.06).setStroke()
            p.stroke()
        }

        let n = CGFloat(sessions.count)
        let gap: CGFloat = 4
        let barW = min(20, max(4, (chartRect.width - gap * (n - 1)) / n))

        for (i, session) in sessions.enumerated() {
            let barH = (CGFloat(session.total) / maxTotal) * chartRect.height
            let x = chartRect.minX + CGFloat(i) * (barW + gap)
            let rect = NSRect(x: x, y: chartRect.minY, width: barW, height: max(2, barH))

            // Use filler rate for colouring if available, else FPM
            let metric = session.totalWordsSpoken > 0 ? session.fillerRate : session.fillersPerMinute
            let avgMetric = avgFPM   // avgFPM is used as the baseline regardless
            let color: NSColor = avgMetric == 0 || metric <= avgMetric * 0.85
                ? P.good.withAlphaComponent(0.8)
                : metric <= avgMetric * 1.15
                    ? P.accent.withAlphaComponent(0.85)
                    : P.bad.withAlphaComponent(0.8)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }

        // Average line
        if avgFPM > 0, let maxFpm = sessions.map(\.fillersPerMinute).max(), maxFpm > 0 {
            let y = chartRect.minY + CGFloat(avgFPM / maxFpm) * chartRect.height
            let p = NSBezierPath(); p.lineWidth = 1
            p.setLineDash([5, 4], count: 2, phase: 0)
            p.move(to: NSPoint(x: chartRect.minX, y: y))
            p.line(to: NSPoint(x: chartRect.maxX, y: y))
            P.textTert.setStroke(); p.stroke()
            ("avg" as NSString).draw(at: NSPoint(x: chartRect.maxX + 4, y: y - 5),
                withAttributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: P.textTert])
        }

        // Y max label
        ("\(Int(maxTotal))" as NSString).draw(
            at: NSPoint(x: hPad, y: chartRect.maxY - 10),
            withAttributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: P.textTert])
    }
}
