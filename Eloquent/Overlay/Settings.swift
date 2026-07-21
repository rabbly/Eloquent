import Foundation

@MainActor
enum Settings {

    // MARK: - Detection mode

    enum DetectionMode: String, CaseIterable {
        case realtime
        case endOfSentence

        var displayName: String {
            switch self {
            case .realtime:      return "Real-time"
            case .endOfSentence: return "End of sentence"
            }
        }
    }

    private static let modeKey = "Eloquent.DetectionMode"

    static var detectionMode: DetectionMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: modeKey),
               let mode = DetectionMode(rawValue: raw) { return mode }
            return .endOfSentence
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    // MARK: - Notification style

    enum NotificationStyle: String, CaseIterable {
        case banner
        case menuBar
        case widget

        var displayName: String {
            switch self {
            case .banner:  return "Notification banner"
            case .menuBar: return "Menu bar flash"
            case .widget:  return "Permanent widget"
            }
        }
    }

    private static let notificationStyleKey = "Eloquent.NotificationStyle"

    static var notificationStyle: NotificationStyle {
        get {
            if let raw = UserDefaults.standard.string(forKey: notificationStyleKey),
               let style = NotificationStyle(rawValue: raw) { return style }
            return .banner
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: notificationStyleKey) }
    }

    // MARK: - Permanent widget position

    private static let widgetOriginXKey = "Eloquent.WidgetOriginX"
    private static let widgetOriginYKey = "Eloquent.WidgetOriginY"

    /// Saved on-screen origin of the permanent widget (global screen coordinates),
    /// or nil if it has never been placed.
    static var widgetOrigin: CGPoint? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: widgetOriginXKey) != nil,
                  d.object(forKey: widgetOriginYKey) != nil else { return nil }
            return CGPoint(x: d.double(forKey: widgetOriginXKey),
                           y: d.double(forKey: widgetOriginYKey))
        }
        set {
            let d = UserDefaults.standard
            if let p = newValue {
                d.set(p.x, forKey: widgetOriginXKey)
                d.set(p.y, forKey: widgetOriginYKey)
            } else {
                d.removeObject(forKey: widgetOriginXKey)
                d.removeObject(forKey: widgetOriginYKey)
            }
        }
    }

    // MARK: - Red flash text

    private static let redFlashKey = "Eloquent.RedFlashText"

    static var redFlashText: Bool {
        get {
            if UserDefaults.standard.object(forKey: redFlashKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: redFlashKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: redFlashKey) }
    }

    // MARK: - Verbose logging

    private static let verboseLoggingKey = "Eloquent.VerboseLogging"

    /// When on, `Log.verbose(...)` messages are printed. Off by default.
    static var verboseLogging: Bool {
        get { UserDefaults.standard.bool(forKey: verboseLoggingKey) }
        set { UserDefaults.standard.set(newValue, forKey: verboseLoggingKey) }
    }

    // MARK: - Built-in catalog

    static let catalog: [String] = [
        "um", "uh", "like", "you know", "basically", "literally", "actually", "right", "so"
    ]

    // MARK: - Custom words

    private static let customKey = "Eloquent.CustomFillers"

    static var customFillers: [String] {
        get { (UserDefaults.standard.array(forKey: customKey) as? [String]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: customKey) }
    }

    @discardableResult
    static func addCustomFiller(_ raw: String) -> Bool {
        let word = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return false }
        guard !allFillers.contains(word) else { return false }
        var list = customFillers
        list.append(word)
        customFillers = list
        setEnabled(word, true)
        return true
    }

    static func removeCustomFiller(_ word: String) {
        customFillers = customFillers.filter { $0 != word }
        var set = enabledFillers
        set.remove(word)
        enabledFillers = set
    }

    static var allFillers: [String] { catalog + customFillers }

    // MARK: - Enabled filler words

    private static let enabledKey = "Eloquent.EnabledFillers"

    static var enabledFillers: Set<String> {
        get {
            if let stored = UserDefaults.standard.array(forKey: enabledKey) as? [String] {
                return Set(stored)
            }
            return Set(catalog)
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: enabledKey) }
    }

    static func isEnabled(_ filler: String) -> Bool { enabledFillers.contains(filler) }

    static func setEnabled(_ filler: String, _ enabled: Bool) {
        var set = enabledFillers
        if enabled { set.insert(filler) } else { set.remove(filler) }
        enabledFillers = set
    }

    // MARK: - Manual mode

    /// Posted whenever `manualMode` changes so the detector can re-evaluate immediately.
    static let manualModeChanged = Notification.Name("Eloquent.ManualModeChanged")

    private static let manualModeKey = "Eloquent.ManualMode"

    static var manualMode: Bool {
        get { UserDefaults.standard.bool(forKey: manualModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: manualModeKey) }
    }

    // MARK: - Monitored apps

    struct MonitoredApp: Identifiable {
        let id: String            // catalog id ("teams") or bundle ID for custom apps
        let name: String          // display name
        let bundlePrefixes: [String]
    }

    static let appCatalog: [MonitoredApp] = [
        .init(id: "teams",    name: "Microsoft Teams", bundlePrefixes: ["com.microsoft.teams"]),
        .init(id: "slack",    name: "Slack",           bundlePrefixes: ["com.tinyspeck.slackmacgap"]),
        .init(id: "zoom",     name: "Zoom",            bundlePrefixes: ["us.zoom.xos"]),
        .init(id: "webex",    name: "Webex",           bundlePrefixes: ["com.cisco.webexmeetingsapp", "Cisco-Systems.Spark"]),
        .init(id: "discord",  name: "Discord",         bundlePrefixes: ["com.hnc.Discord"]),
        .init(id: "facetime", name: "FaceTime",        bundlePrefixes: ["com.apple.FaceTime"]),
    ]

    // Custom apps persisted as [["name": ..., "bundleID": ...], ...]
    private static let customAppsKey = "Eloquent.CustomApps"

    static var customApps: [MonitoredApp] {
        get {
            let raw = (UserDefaults.standard.array(forKey: customAppsKey) as? [[String: String]]) ?? []
            return raw.compactMap { dict in
                guard let bundleID = dict["bundleID"], !bundleID.isEmpty else { return nil }
                let name = dict["name"] ?? bundleID
                return MonitoredApp(id: bundleID, name: name, bundlePrefixes: [bundleID])
            }
        }
        set {
            let raw = newValue.map { ["name": $0.name, "bundleID": $0.id] }
            UserDefaults.standard.set(raw, forKey: customAppsKey)
        }
    }

    static var allApps: [MonitoredApp] { appCatalog + customApps }

    /// Adds a custom app. Returns false if empty or a duplicate of a catalog id or existing custom app.
    @discardableResult
    static func addCustomApp(name: String, bundleID: String) -> Bool {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        guard !allApps.contains(where: { $0.id == id }) else { return false }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = customApps
        list.append(MonitoredApp(id: id, name: cleanName.isEmpty ? id : cleanName, bundlePrefixes: [id]))
        customApps = list
        setAppEnabled(id, true)
        return true
    }

    static func removeCustomApp(id: String) {
        customApps = customApps.filter { $0.id != id }
        var set = enabledApps
        set.remove(id)
        enabledApps = set
    }

    static func isCustomApp(_ id: String) -> Bool { customApps.contains { $0.id == id } }

    // MARK: - Enabled apps

    private static let enabledAppsKey = "Eloquent.EnabledApps"

    static var enabledApps: Set<String> {
        get {
            if let stored = UserDefaults.standard.array(forKey: enabledAppsKey) as? [String] {
                return Set(stored)
            }
            return ["teams"]   // default: Microsoft Teams only
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: enabledAppsKey) }
    }

    static func isAppEnabled(_ id: String) -> Bool { enabledApps.contains(id) }

    static func setAppEnabled(_ id: String, _ enabled: Bool) {
        var set = enabledApps
        if enabled { set.insert(id) } else { set.remove(id) }
        enabledApps = set
    }

    /// Bundle-ID prefixes for all currently-enabled monitored apps.
    static var monitoredBundlePrefixes: [String] {
        allApps.filter { enabledApps.contains($0.id) }.flatMap { $0.bundlePrefixes }
    }
}
