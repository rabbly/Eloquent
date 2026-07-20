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
