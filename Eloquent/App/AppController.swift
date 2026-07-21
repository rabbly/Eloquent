import Cocoa
import Combine

@MainActor
class AppController {
    private let callDetector = CallDetector()
    private let statusBar: StatusBarController
    private let banner = BannerOverlay.shared
    private var stats = SessionStats()
    private var cancellables = Set<AnyCancellable>()

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
                    WidgetOverlay.shared.flagWord(word, count: count)
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
                    FillerWordRecognizer.shared.start()
                } else {
                    Log.verbose("🎯 [AppController] stopping FillerWordRecognizer")
                    FillerWordRecognizer.shared.stop()
                    self.statusBar.setCallActive(false)
                }
                // Set call state BEFORE show() so the widget reads isCallActive correctly
                // and animates directly to the right alpha, avoiding an idle→active flicker.
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
                self.stats.reset()
                self.statusBar.update(stats: self.stats)
            }
            .store(in: &cancellables)
    }
}
