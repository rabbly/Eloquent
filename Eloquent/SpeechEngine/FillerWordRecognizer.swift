import Speech
import AVFoundation
import AppKit

@MainActor
class FillerWordRecognizer {
    @MainActor static let shared = FillerWordRecognizer()

    var onFillerWordDetected: ((String) -> Void)?

    private var analyzerTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    private var lastFiredAt: [String: Date] = [:]
    private let cooldownSeconds: TimeInterval = 1.5

    // Deduplication for end-of-sentence mode: tracks the last finalized text scanned.
    private var lastFinalText = ""

    // Deduplication for real-time mode: tracks the last tail string seen.
    // If the tail hasn't changed (no new words arrived) we skip re-scanning,
    // preventing double-counts when SpeechTranscriber re-delivers the same volatile result.
    private var lastTailText = ""

    private init() {}

    func start() {
        stop()
        analyzerTask = Task { await runSession() }
    }

    func stop() {
        // Tear down audio capture first so no more buffers are produced.
        AudioCaptureEngine.shared.stop()

        // End the async input stream and cancel the analyzer task.
        inputContinuation?.finish()
        inputContinuation = nil
        analyzerTask?.cancel()
        analyzerTask = nil

        lastFiredAt.removeAll()
        lastFinalText = ""
        lastTailText = ""
    }

    func restartWithNewLocale() {
        let wasRunning = analyzerTask != nil
        stop()
        if wasRunning { start() }
    }

    // MARK: - Session

    private func runSession() async {
        let requested = FillerWordRecognizer.savedLocale()
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            Log.info("⚠️ [FillerWordRecognizer] Locale \(requested.identifier) not supported")
            await MainActor.run { showOnDeviceUnavailableAlert() }
            return
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            Log.info("❌ [FillerWordRecognizer] Asset installation failed: \(error)")
            await MainActor.run { showOnDeviceUnavailableAlert() }
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            Log.info("❌ [FillerWordRecognizer] Could not determine required audio format")
            return
        }

        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        let resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    await self.processResult(result)
                }
            } catch is CancellationError {
                // Expected during stop().
            } catch {
                Log.info("❌ [FillerWordRecognizer] results error: \(error)")
            }
        }

        do {
            AudioCaptureEngine.shared.startCapture(targetFormat: targetFormat) { [weak self] input in
                self?.inputContinuation?.yield(input)
            }
            _ = try await analyzer.analyzeSequence(inputSequence)
        } catch is CancellationError {
            Log.verbose("🎙️ [FillerWordRecognizer] analyzer cancelled (expected on stop)")
        } catch {
            Log.info("❌ [FillerWordRecognizer] analyzeSequence error: \(error)")
        }

        resultsTask.cancel()
    }

    // MARK: - Result handling

    @MainActor
    private func processResult(_ result: SpeechTranscriber.Result) {
        switch Settings.detectionMode {
        case .endOfSentence:
            guard result.isFinal else { return }
            scanFullPhrase(result)
        case .realtime:
            scanTail(result)
        }
    }

    private func scanFullPhrase(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).lowercased()
        guard !text.isEmpty else { return }

        // Determine the genuinely-new portion. If this final accumulates on top of the
        // previous one (shares its prefix), scan only the appended tail; otherwise it's
        // a fresh segment and we scan all of it. This prevents recounting the same "um".
        let newPortion: String
        if !lastFinalText.isEmpty && text.hasPrefix(lastFinalText) {
            newPortion = String(text.dropFirst(lastFinalText.count))
        } else {
            newPortion = text
        }
        lastFinalText = text

        let words = newPortion
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return }

        var i = 0
        while i < words.count {
            if i + 1 < words.count {
                let pair = "\(strip(words[i])) \(strip(words[i + 1]))"
                if let matched = FillerWordMatcher.matchPhrase(pair), matched.contains(" ") {
                    fire(matched)
                    i += 2
                    continue
                }
            }
            let single = strip(words[i])
            if let matched = FillerWordMatcher.matchPhrase(single), !matched.contains(" ") {
                fire(matched)
            }
            i += 1
        }
    }

    private func scanTail(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return }
        let tail = words.suffix(3).map(strip).joined(separator: " ")
        // Skip if the tail hasn't changed — same volatile result re-delivered.
        guard tail != lastTailText else { return }
        lastTailText = tail
        if let matched = FillerWordMatcher.matchPhrase(tail) {
            fire(matched)
        }
    }

    private func strip(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    private func fire(_ word: String) {
        guard canFire(word: word) else { return }
        lastFiredAt[word] = Date()
        onFillerWordDetected?(word)
    }

    private func canFire(word: String) -> Bool {
        guard let last = lastFiredAt[word] else { return true }
        return Date().timeIntervalSince(last) >= cooldownSeconds
    }

    // MARK: - Locale persistence

    private static let localeKey = "Eloquent.SpeechLocale"

    static func savedLocale() -> Locale {
        if let id = UserDefaults.standard.string(forKey: localeKey) {
            return Locale(identifier: id)
        }
        return Locale.current
    }

    static func saveLocale(_ locale: Locale) {
        UserDefaults.standard.set(locale.identifier, forKey: localeKey)
    }

    // MARK: - On-device unavailable

    private func showOnDeviceUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "On-Device Speech Recognition Unavailable"
        alert.informativeText = "Your device does not have an on-device speech recognition model for the selected language. Try a different language in the Eloquent menu, or ensure Siri is set up in System Settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
