import Combine
import Foundation

@MainActor
class CallDetector: ObservableObject {
    @Published private(set) var callInProgress: Bool = false

    /// Increments each time a new monitoring session begins: a newly detected call
    /// (mic goes active) or manual mode toggled either direction. Observers use this
    /// to reset per-session state such as the filler-word count.
    @Published private(set) var sessionID: Int = 0

    private let micWatcher = MicActivityWatcher()
    private var cancellables = Set<AnyCancellable>()

    private var previousMicActive = false

    init() {
        micWatcher.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in self?.micActivityChanged(to: active) }
            .store(in: &cancellables)

        // Toggling manual mode from the menu should take effect immediately and
        // always starts a fresh session.
        NotificationCenter.default.publisher(for: Settings.manualModeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.startNewSession()
                self?.recompute()
            }
            .store(in: &cancellables)

        previousMicActive = micWatcher.isActive
        recompute()
    }

    private func micActivityChanged(to active: Bool) {
        // A new call = mic transitioning from idle to active.
        if active && !previousMicActive {
            startNewSession()
        }
        previousMicActive = active
        recompute()
    }

    private func startNewSession() {
        sessionID &+= 1
    }

    private func recompute() {
        let manual = Settings.manualMode
        let mic = micWatcher.isActive
        let inCall = manual || mic
        Log.verbose("👀 [CallDetector] manual=\(manual ? "YES" : "no") mic=\(mic ? "YES" : "no") -> callInProgress=\(inCall ? "YES" : "no")")
        callInProgress = inCall
    }
}
