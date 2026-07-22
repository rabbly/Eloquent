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
    private var lastTailText = ""

    // Word frequency histogram for candidate filler discovery.
    // Stores counts of all non-stop content words seen during the session.
    // Privacy: only short word tokens (≤12 chars, alpha-only) are tallied — no sentences.
    private(set) var sessionWordFrequencies: [String: Int] = [:]

    private static let stopWords: Set<String> = [
        "i", "you", "we", "he", "she", "they", "it", "me", "him", "her", "us", "them",
        "the", "a", "an", "this", "that", "these", "those",
        "and", "or", "but", "nor", "so", "yet", "for",
        "in", "on", "at", "to", "for", "of", "by", "as", "from", "with", "into", "about",
        "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did",
        "will", "would", "could", "should", "can", "may", "might", "shall", "must",
        "not", "no", "if", "then", "when", "there", "here", "than", "just", "up",
        "out", "what", "how", "who", "which", "where", "my", "your", "his", "our", "their",
        "said", "also", "very", "more", "all", "some", "any", "each", "other", "than",
        "oh", "ok", "okay", "yeah", "yes", "no", "nope", "yep",
    ]

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
        sessionWordFrequencies.removeAll()
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
                    fire(matched, phrase: pair, context: newPortion)
                    i += 2
                    continue
                }
            }
            let single = strip(words[i])
            if let matched = FillerWordMatcher.matchPhrase(single), !matched.contains(" ") {
                // Build a small window (prev + word + next) for contextual filtering
                let prev = i > 0 ? strip(words[i-1]) : ""
                let next = i + 1 < words.count ? strip(words[i+1]) : ""
                let window = [prev, single, next].filter { !$0.isEmpty }.joined(separator: " ")
                fire(matched, phrase: window, context: newPortion)
            }
            i += 1
        }
        // Tally all content words for candidate filler discovery.
        tallyWords(words)
    }

    private func scanTail(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return }
        let tail = words.suffix(3).map(strip).joined(separator: " ")
        guard tail != lastTailText else { return }
        lastTailText = tail
        if let matched = FillerWordMatcher.matchPhrase(tail) {
            fire(matched, phrase: tail, context: tail)
        }
        // Tally the new words in the tail for candidate filler discovery.
        tallyWords(Array(words.suffix(3)))
    }

    private static let letterSet = CharacterSet.letters

    /// Tally content words (1-grams and 2-grams) into the session frequency histogram.
    private func tallyWords(_ words: [String]) {
        let tokens = words.map(strip).filter { w in
            guard !w.isEmpty, w.count >= 2, w.count <= 12 else { return false }
            guard !FillerWordRecognizer.stopWords.contains(w) else { return false }
            // Only keep purely alphabetic tokens (safe scalar check)
            return w.unicodeScalars.allSatisfy { FillerWordRecognizer.letterSet.contains($0) }
        }
        for token in tokens {
            sessionWordFrequencies[token, default: 0] += 1
        }
        guard tokens.count >= 2 else { return }
        for i in 0..<(tokens.count - 1) {
            let bigram = "\(tokens[i]) \(tokens[i+1])"
            sessionWordFrequencies[bigram, default: 0] += 1
        }
    }

    private func strip(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    private func fire(_ word: String, phrase: String = "", context: String = "") {
        guard canFire(word: word) else { return }
        // Contextual check: suppress ambiguous words used grammatically.
        guard ContextualFilter.isFiller(word, inPhrase: phrase, context: context) else {
            Log.verbose("🔇 [FillerWordRecognizer] suppressed '\(word)' (grammatical use in: \"\(phrase)\")")
            return
        }
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
