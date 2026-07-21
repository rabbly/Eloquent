import AppKit
import Speech

@MainActor
class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem()
    private let statsMenuItem = NSMenuItem()
    private var stats: SessionStats
    private var isCallActive = false

    private var flashRevertWorkItem: DispatchWorkItem?

    // Template image: adapts to the menu bar and gets the standard system highlight.
    // We always use a template image and never set button.contentTintColor, because
    // a non-template image OR contentTintColor on an NSStatusBarButton triggers an
    // AppKit bug (FB8530353) that renders the click highlight as an opaque black box.
    private let defaultImage: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Eloquent")?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        return img
    }()

    init(stats: SessionStats) {
        self.stats = stats
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = defaultImage
        }

        buildMenu()
        statusItem.menu = menu
    }

    func setCallActive(_ active: Bool) {
        isCallActive = active
        updateStatusMenuItem()
        // Active state is reflected in the menu's status line, not by tinting the
        // icon (tinting/non-template images cause the black-highlight bug).
        statusItem.button?.image = defaultImage
    }

    func update(stats: SessionStats) {
        self.stats = stats
        updateStatsMenuItem()
    }

    func flashInMenuBar(word: String, count: Int) {
        guard let button = statusItem.button else { return }
        flashRevertWorkItem?.cancel()

        let display = count > 1 ? "\(word) ×\(count)" : word
        let accent = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.20, alpha: 1.0)

        // Keep the waveform icon and append the flagged word in the warm accent color,
        // matching the banner's palette (instead of a stark red text swap).
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .leftToRight
        let noShadow = NSShadow()
        noShadow.shadowColor = .clear

        let textColor = Settings.redFlashText ? accent : NSColor.labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .shadow: noShadow
        ]

        button.image = defaultImage
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(string: "  \(display)", attributes: attrs)

        let revert = DispatchWorkItem { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                button.animator().attributedTitle = NSAttributedString(string: "")
            }
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = self.defaultImage
        }
        flashRevertWorkItem = revert
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: revert)
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        // Manage item enabled-state ourselves so disabled-looking info rows and
        // submenu parents (the stats flyout) behave correctly.
        menu.autoenablesItems = false

        // Branded header: app name in accent, with the waveform mark.
        let titleItem = NSMenuItem(title: "Eloquent", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        let headerCfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let headerIcon = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
            .withSymbolConfiguration(headerCfg)
        headerIcon?.isTemplate = false
        titleItem.image = headerIcon?.tinted(with: NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.20, alpha: 1))
        titleItem.attributedTitle = NSAttributedString(string: "Eloquent", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ])
        menu.addItem(titleItem)
        menu.addItem(.separator())

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        updateStatusMenuItem()

        let manualItem = NSMenuItem(title: "Manual mode (always on)", action: #selector(toggleManualMode(_:)), keyEquivalent: "")
        manualItem.target = self
        manualItem.state = Settings.manualMode ? .on : .off
        manualItem.image = symbolImage("hand.raised.fill")
        menu.addItem(manualItem)

        menu.addItem(.separator())

        menu.addItem(statsMenuItem)
        updateStatsMenuItem()

        menu.addItem(.separator())
        addFillerWordsSubmenu()
        addMonitoredAppsSubmenu()
        addDetectionModeSubmenu()
        addNotificationStyleSubmenu()
        addLanguageSubmenu()
        menu.addItem(.separator())
        addDiagnosticsSection()
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Eloquent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        quit.image = symbolImage("power")
        menu.addItem(quit)

        menu.delegate = self as? NSMenuDelegate
    }

    // A menu-sized, template SF Symbol for menu item icons.
    private func symbolImage(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        return img
    }

    private func updateStatusMenuItem() {
        if Settings.manualMode {
            statusMenuItem.title = "● Monitoring (manual mode)"
        } else {
            statusMenuItem.title = isCallActive ? "● Monitoring call" : "○ Idle — waiting for a call"
        }
    }

    @objc private func toggleManualMode(_ sender: NSMenuItem) {
        let newValue = (sender.state != .on)
        Settings.manualMode = newValue
        sender.state = newValue ? .on : .off
        NotificationCenter.default.post(name: Settings.manualModeChanged, object: nil)
        updateStatusMenuItem()
    }

    private func updateStatsMenuItem() {
        let summary = stats.summary()
        let total = stats.total()

        if summary.isEmpty {
            statsMenuItem.title = "No filler words this session"
            statsMenuItem.submenu = nil
            statsMenuItem.isEnabled = false
            return
        }

        // Parent shows the session total; flyout lists per-word counts + total.
        // The parent must be enabled for its submenu to open on hover.
        statsMenuItem.title = "Filler words this session: \(total)"
        statsMenuItem.isEnabled = true

        let sub = NSMenu(title: "Filler Words")
        sub.autoenablesItems = false

        // Color-rank rows by frequency: most-said = red, fading through orange to yellow.
        let maxCount = summary.first?.count ?? 1
        for entry in summary {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            // Enabled (with no action) so the colored text renders at full opacity
            // instead of the dimmed/greyed look disabled items get.
            item.isEnabled = true
            let color = rankColor(count: entry.count, max: maxCount)
            item.attributedTitle = countRow(label: entry.word, count: entry.count, color: color, bold: false)
            sub.addItem(item)
        }

        sub.addItem(.separator())
        let totalItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        totalItem.isEnabled = true
        totalItem.attributedTitle = countRow(label: "Total", count: total, color: .labelColor, bold: true)
        sub.addItem(totalItem)

        statsMenuItem.submenu = sub
    }

    // Maps a count to a warm color: highest = red, mid = orange, lowest = yellow.
    private func rankColor(count: Int, max: Int) -> NSColor {
        guard max > 0 else { return .systemYellow }
        // 1.0 (most frequent) -> red hue 0.0; 0.0 (least) -> yellow hue ~0.14
        let t = Double(count) / Double(max)
        let hue = 0.14 * (1.0 - t)   // 0 = red, 0.14 ≈ yellow
        return NSColor(hue: CGFloat(hue), saturation: 0.9, brightness: 0.95, alpha: 1.0)
    }

    // Builds a "label ............ count" row with the count right-aligned via a tab stop.
    private func countRow(label: String, count: Int, color: NSColor, bold: Bool) -> NSAttributedString {
        let width: CGFloat = 190
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: width)]

        let size = NSFont.systemFontSize + 1
        let font = bold ? NSFont.systemFont(ofSize: size, weight: .semibold)
                        : NSFont.systemFont(ofSize: size, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: "\(label)\t\(count)", attributes: attrs)
    }

    // MARK: - Filler Words submenu

    private func addFillerWordsSubmenu() {
        let parent = NSMenuItem(title: "Filler Words", action: nil, keyEquivalent: "")
        parent.image = symbolImage("text.bubble")
        let sub = NSMenu(title: "Filler Words")
        sub.autoenablesItems = false

        for filler in Settings.catalog {
            let item = NSMenuItem(title: filler, action: #selector(fillerWordToggled(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = filler
            item.state = Settings.isEnabled(filler) ? .on : .off
            sub.addItem(item)
        }

        let custom = Settings.customFillers
        if !custom.isEmpty {
            sub.addItem(.separator())
            let header = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)

            for filler in custom {
                let wordItem = NSMenuItem(title: filler, action: nil, keyEquivalent: "")
                wordItem.state = Settings.isEnabled(filler) ? .on : .off

                let actions = NSMenu(title: filler)

                let toggle = NSMenuItem(title: "Enabled", action: #selector(fillerWordToggled(_:)), keyEquivalent: "")
                toggle.target = self
                toggle.representedObject = filler
                toggle.state = Settings.isEnabled(filler) ? .on : .off
                actions.addItem(toggle)
                actions.addItem(.separator())

                let edit = NSMenuItem(title: "Edit…", action: #selector(editCustomWord(_:)), keyEquivalent: "")
                edit.target = self
                edit.representedObject = filler
                actions.addItem(edit)

                let delete = NSMenuItem(title: "Delete", action: #selector(removeCustomWord(_:)), keyEquivalent: "")
                delete.target = self
                delete.representedObject = filler
                actions.addItem(delete)

                wordItem.submenu = actions
                sub.addItem(wordItem)
            }
        }

        sub.addItem(.separator())
        let addItem = NSMenuItem(title: "Add Custom Word…", action: #selector(addCustomWord(_:)), keyEquivalent: "")
        addItem.target = self
        sub.addItem(addItem)

        parent.submenu = sub
        menu.addItem(parent)
    }

    @objc private func fillerWordToggled(_ sender: NSMenuItem) {
        guard let filler = sender.representedObject as? String else { return }
        let newEnabled = (sender.state != .on)
        Settings.setEnabled(filler, newEnabled)
        rebuildMenu()
    }

    @objc private func addCustomWord(_ sender: NSMenuItem) {
        presentWordEditor(title: "Add Custom Filler Word", initial: "") { [weak self] text in
            let added = Settings.addCustomFiller(text)
            if !added {
                self?.showSimpleAlert(message: "Couldn't Add Word",
                                      info: "That word is empty or already in the list.")
            }
            self?.rebuildMenu()
        }
    }

    @objc private func editCustomWord(_ sender: NSMenuItem) {
        guard let old = sender.representedObject as? String else { return }
        presentWordEditor(title: "Edit Custom Word", initial: old) { [weak self] text in
            Settings.removeCustomFiller(old)
            let added = Settings.addCustomFiller(text)
            if !added {
                Settings.addCustomFiller(old)   // restore original on failure
                self?.showSimpleAlert(message: "Couldn't Save Word",
                                      info: "That word is empty or already in the list.")
            }
            self?.rebuildMenu()
        }
    }

    @objc private func removeCustomWord(_ sender: NSMenuItem) {
        guard let filler = sender.representedObject as? String else { return }
        Settings.removeCustomFiller(filler)
        rebuildMenu()
    }

    // MARK: - Monitored Apps submenu

    private func addMonitoredAppsSubmenu() {
        let parent = NSMenuItem(title: "Monitored Apps", action: nil, keyEquivalent: "")
        parent.image = symbolImage("app.badge")
        let sub = NSMenu(title: "Monitored Apps")
        sub.autoenablesItems = false

        for app in Settings.appCatalog {
            let item = NSMenuItem(title: app.name, action: #selector(monitoredAppToggled(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.id
            item.state = Settings.isAppEnabled(app.id) ? .on : .off
            sub.addItem(item)
        }

        let custom = Settings.customApps
        if !custom.isEmpty {
            sub.addItem(.separator())
            let header = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)

            for app in custom {
                let appItem = NSMenuItem(title: app.name, action: nil, keyEquivalent: "")
                appItem.state = Settings.isAppEnabled(app.id) ? .on : .off

                let actions = NSMenu(title: app.name)

                let toggle = NSMenuItem(title: "Enabled", action: #selector(monitoredAppToggled(_:)), keyEquivalent: "")
                toggle.target = self
                toggle.representedObject = app.id
                toggle.state = Settings.isAppEnabled(app.id) ? .on : .off
                actions.addItem(toggle)
                actions.addItem(.separator())

                let remove = NSMenuItem(title: "Remove", action: #selector(removeMonitoredApp(_:)), keyEquivalent: "")
                remove.target = self
                remove.representedObject = app.id
                actions.addItem(remove)

                appItem.submenu = actions
                sub.addItem(appItem)
            }
        }

        sub.addItem(.separator())
        let addItem = NSMenuItem(title: "Add App…", action: #selector(addMonitoredApp(_:)), keyEquivalent: "")
        addItem.target = self
        sub.addItem(addItem)

        parent.submenu = sub
        menu.addItem(parent)
    }

    @objc private func monitoredAppToggled(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let newEnabled = (sender.state != .on)
        Settings.setAppEnabled(id, newEnabled)
        rebuildMenu()
    }

    @objc private func removeMonitoredApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Settings.removeCustomApp(id: id)
        rebuildMenu()
    }

    @objc private func addMonitoredApp(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose an app to monitor for filler words when it uses the microphone."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            showSimpleAlert(message: "Couldn't Add App",
                            info: "That item doesn't appear to be a valid application.")
            return
        }

        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")

        let added = Settings.addCustomApp(name: name, bundleID: bundleID)
        if !added {
            showSimpleAlert(message: "Couldn't Add App",
                            info: "\(name) is already in the list.")
        }
        rebuildMenu()
    }

    private static let blankIcon: NSImage = {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        img.unlockFocus()
        return img
    }()

    private func presentWordEditor(title: String, initial: String, onConfirm: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.icon = StatusBarController.blankIcon
        alert.messageText = title
        alert.informativeText = "Enter a word or short phrase to detect (e.g. \"sort of\")."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "filler word"
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm(field.stringValue)
        }
    }

    private func showSimpleAlert(message: String, info: String) {
        let a = NSAlert()
        a.icon = StatusBarController.blankIcon
        a.messageText = message
        a.informativeText = info
        a.runModal()
    }

    // MARK: - Detection Mode submenu

    private func addDetectionModeSubmenu() {
        let parent = NSMenuItem(title: "Detection Mode", action: nil, keyEquivalent: "")
        parent.image = symbolImage("dial.medium")
        let sub = NSMenu(title: "Detection Mode")
        let current = Settings.detectionMode
        for mode in Settings.DetectionMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(detectionModeSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (mode == current) ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        menu.addItem(parent)
    }

    @objc private func detectionModeSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = Settings.DetectionMode(rawValue: raw) else { return }
        Settings.detectionMode = mode
        sender.menu?.items.forEach { $0.state = .off }
        sender.state = .on
    }

    // MARK: - Notification Style submenu

        private func addNotificationStyleSubmenu() {
            let parent = NSMenuItem(title: "Notification Style", action: nil, keyEquivalent: "")
            parent.image = symbolImage("bell.badge")
            let sub = NSMenu(title: "Notification Style")
            let current = Settings.notificationStyle
            for style in Settings.NotificationStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(notificationStyleSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = style.rawValue
                item.state = (style == current) ? .on : .off

                // Attach "Red flash text" as a flyout only on Menu Bar Flash.
                if style == .menuBar {
                    let optSub = NSMenu(title: style.displayName)
                    let toggle = NSMenuItem(title: style.displayName, action: #selector(notificationStyleSelected(_:)), keyEquivalent: "")
                    toggle.target = self
                    toggle.representedObject = style.rawValue
                    toggle.state = (style == current) ? .on : .off
                    optSub.addItem(toggle)
                    optSub.addItem(.separator())
                    let redItem = NSMenuItem(title: "Red flash text", action: #selector(toggleRedFlash(_:)), keyEquivalent: "")
                    redItem.target = self
                    redItem.state = Settings.redFlashText ? .on : .off
                    optSub.addItem(redItem)
                    item.submenu = optSub
                // Do NOT set item.action = nil here — AppKit already opens the flyout
                // instead of firing the action when a submenu is present. Keeping the
                // action set ensures the item stays enabled and its checkmark is tracked
                // correctly by the clearing loop in notificationStyleSelected.
                }

                sub.addItem(item)
            }

            parent.submenu = sub
            menu.addItem(parent)
        }

        @objc private func notificationStyleSelected(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String,
                  let style = Settings.NotificationStyle(rawValue: raw) else { return }
            let previous = Settings.notificationStyle
            Settings.notificationStyle = style
            sender.menu?.items.forEach { item in
                if item.action == #selector(notificationStyleSelected(_:)) {
                    item.state = .off
                }
            }
            sender.state = .on

            // Show or hide the widget when the user switches to/from widget mode.
            if style == .widget && previous != .widget {
                WidgetOverlay.shared.show()
                WidgetOverlay.shared.setCallActive(isCallActive)
            } else if style != .widget && previous == .widget {
                WidgetOverlay.shared.hide()
            }
        }

        @objc private func toggleRedFlash(_ sender: NSMenuItem) {
            let newValue = (sender.state != .on)
            Settings.redFlashText = newValue
            sender.state = newValue ? .on : .off
        }

        // MARK: - Language submenu

        private func addLanguageSubmenu() {
            let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
            languageItem.image = symbolImage("globe")
            let sub = NSMenu(title: "Language")

            let currentLocaleID = FillerWordRecognizer.savedLocale().identifier

            let locales = SFSpeechRecognizer.supportedLocales()
                .sorted { $0.identifier < $1.identifier }

            for locale in locales {
                let displayName = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
                let item = NSMenuItem(title: displayName, action: #selector(languageSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = locale
                item.state = locale.identifier == currentLocaleID ? .on : .off
                sub.addItem(item)
            }

            languageItem.submenu = sub
            menu.addItem(languageItem)
        }

        @objc private func languageSelected(_ sender: NSMenuItem) {
            guard let locale = sender.representedObject as? Locale else { return }
            FillerWordRecognizer.saveLocale(locale)
            FillerWordRecognizer.shared.restartWithNewLocale()
            sender.menu?.items.forEach { $0.state = .off }
            sender.state = .on
        }

        // MARK: - Diagnostics section

        private func addDiagnosticsSection() {
            let verboseItem = NSMenuItem(title: "Verbose logging", action: #selector(toggleVerboseLogging(_:)), keyEquivalent: "")
            verboseItem.target = self
            verboseItem.state = Settings.verboseLogging ? .on : .off
            menu.addItem(verboseItem)

            let testItem = NSMenuItem(title: "Test notification", action: #selector(testNotification(_:)), keyEquivalent: "")
            testItem.target = self
            menu.addItem(testItem)
        }

        @objc private func testNotification(_ sender: NSMenuItem) {
            let samples: [(String, Int)] = [("um", 1), ("like", 3), ("you know", 7)]
            if Settings.notificationStyle == .widget {
                WidgetOverlay.shared.show()
                WidgetOverlay.shared.setCallActive(true)
            }
            for (i, s) in samples.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 2.6) {
                    switch Settings.notificationStyle {
                    case .banner:  BannerOverlay.shared.show(word: s.0, count: s.1)
                    case .menuBar: self.flashInMenuBar(word: s.0, count: s.1)
                    case .widget:  WidgetOverlay.shared.flagWord(s.0, count: s.1)
                    }
                }
            }
        }

        @objc private func toggleVerboseLogging(_ sender: NSMenuItem) {
            let newValue = (sender.state != .on)
            Settings.verboseLogging = newValue
            sender.state = newValue ? .on : .off
        }

        // MARK: - Rebuild

        private func rebuildMenu() {
            menu.removeAllItems()
            buildMenu()
        }
    }

extension NSImage {
    /// Returns a copy of the image filled with the given color (source-atop),
    /// used for colored menu item glyphs.
    func tinted(with color: NSColor) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect)
        rect.fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
