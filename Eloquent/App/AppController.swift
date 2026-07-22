import Cocoa
import Combine

@MainActor
class AppController {
    private let callDetector = CallDetector()
    private let statusBar: StatusBarController
    private let banner = BannerOverlay.shared
    private var stats = SessionStats()
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartDate: Date?

    init() {
        statusBar = StatusBarController(stats: stats)
        wireFillerWordCallback()
        observeCallState()

        // If widget mode was persisted, show it immediately at idle opacity.
        if Settings.notificationStyle == .widget {
            WidgetOverlay.shared.show()
        }
    }

    private func wireFillerWordCallback() {
        FillerWordRecognizer.shared.onFillerWordDetected = { [weak self] word in
            Task { @MainActor in
                guard let self else { return }
                self.stats.record(word)
                self.statusBar.update(stats: self.stats)

                let count = self.stats.count(for: word)
                switch Settings.notificationStyle {
                case .banner:
                    self.banner.show(word: word, count: count)
                case .menuBar:
                    self.statusBar.flashInMenuBar(word: word, count: count)
                case .widget:
                    WidgetOverlay.shared.updateStats(self.stats, newWord: word)
                }
            }
        }
    }

    private func observeCallState() {
        callDetector.$callInProgress
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                guard let self else { return }
                Log.verbose("🎯 [AppController] callInProgress changed -> \(active ? "ACTIVE" : "IDLE")")
                if active {
                    self.statusBar.setCallActive(true)
                    self.sessionStartDate = Date()
                    FillerWordRecognizer.shared.start()
                } else {
                    // Capture everything BEFORE stop() clears the recognizer state.
                    let snapshot = self.stats
                    let freqs = FillerWordRecognizer.shared.sessionWordFrequencies
                    let start = self.sessionStartDate ?? Date()
                    AnalyticsStore.shared.recordSession(snapshot, wordFrequencies: freqs,
                                                        startDate: start, endDate: Date())

                    Log.verbose("🎯 [AppController] stopping FillerWordRecognizer")
                    FillerWordRecognizer.shared.stop()
                    self.statusBar.setCallActive(false)
                }
                // Set call state BEFORE show() so the widget reads isCallActive correctly
                if Settings.notificationStyle == .widget {
                    WidgetOverlay.shared.setCallActive(active)
                    if active { WidgetOverlay.shared.show() }
                }
            }
            .store(in: &cancellables)

        // Reset the per-session filler count whenever a new session begins
        // (new detected call, or manual mode toggled either direction).
        callDetector.$sessionID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // A new session is starting — record the outgoing session's data
                // BEFORE stop() clears the recognizer. (This covers mid-call resets,
                // e.g. toggling manual mode while a call is active.)
                let snapshot = self.stats
                let freqs = FillerWordRecognizer.shared.sessionWordFrequencies
                let start = self.sessionStartDate ?? Date()
                // Only record if there's data AND we're still in an active call
                // (if the call already ended, the callInProgress sink recorded it)
                if snapshot.total() > 0 {
                    let callActive = callDetector.callInProgress
                    if callActive {
                        AnalyticsStore.shared.recordSession(snapshot, wordFrequencies: freqs,
                                                            startDate: start, endDate: Date())
                    }
                }
                self.sessionStartDate = Date()
                self.stats.reset()
                self.statusBar.update(stats: self.stats)
                if Settings.notificationStyle == .widget {
                    WidgetOverlay.shared.resetSession()
                }
            }
            .store(in: &cancellables)
    }
}
