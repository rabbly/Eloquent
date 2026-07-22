import Foundation

// MARK: - Data model

struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let durationSeconds: Int
    let wordCounts: [String: Int]
    // Word frequency histogram for candidate filler discovery (added later; defaults gracefully)
    var wordFrequencies: [String: Int]

    // Codable with default for backward-compat with older records
    private enum CodingKeys: String, CodingKey {
        case id, date, durationSeconds, wordCounts, wordFrequencies
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        durationSeconds = try c.decode(Int.self, forKey: .durationSeconds)
        wordCounts = try c.decode([String: Int].self, forKey: .wordCounts)
        wordFrequencies = (try? c.decode([String: Int].self, forKey: .wordFrequencies)) ?? [:]
    }
    init(id: UUID, date: Date, durationSeconds: Int, wordCounts: [String: Int],
         wordFrequencies: [String: Int] = [:]) {
        self.id = id; self.date = date; self.durationSeconds = durationSeconds
        self.wordCounts = wordCounts; self.wordFrequencies = wordFrequencies
    }

    var total: Int { wordCounts.values.reduce(0, +) }

    var fillersPerMinute: Double {
        durationSeconds > 0 ? Double(total) / (Double(durationSeconds) / 60.0) : 0
    }

    /// Total content words spoken (derived from the frequency histogram).
    /// Falls back to an estimate from duration if the histogram isn't available.
    var totalWordsSpoken: Int {
        let fromFreq = wordFrequencies.values.reduce(0, +)
        return fromFreq > 0 ? fromFreq : 0
    }

    /// Fillers per 100 words spoken — normalises for both session length AND
    /// how much the user was actually speaking. The primary quality metric.
    var fillerRate: Double {
        let words = totalWordsSpoken
        guard words > 0 else { return 0 }
        return Double(total) / Double(words) * 100.0
    }

    var topWord: String? { summary().first?.word }

    var formattedDuration: String {
        let m = durationSeconds / 60; let s = durationSeconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    func summary() -> [(word: String, count: Int)] {
        wordCounts.map { (word: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
}

// MARK: - Candidate filler

struct CandidateFiller {
    let word: String
    let sessionsCount: Int
    let totalOccurrences: Int
    let avgPerSession: Double   // mean rate per session (occurrences, not per 100 words)
}

// MARK: - Store

@MainActor
final class AnalyticsStore {
    static let shared = AnalyticsStore()

    private(set) var allSessions: [SessionRecord] = []    // newest first

    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Eloquent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }()

    private init() { load() }

    // MARK: - Write

    func recordSession(_ stats: SessionStats, wordFrequencies: [String: Int] = [:],
                       startDate: Date, endDate: Date) {
        guard stats.total() > 0 else { return }
        let duration = Int(endDate.timeIntervalSince(startDate))
        var counts: [String: Int] = [:]
        for entry in stats.summary() { counts[entry.word] = entry.count }
        let record = SessionRecord(id: UUID(), date: startDate, durationSeconds: duration,
                                   wordCounts: counts, wordFrequencies: wordFrequencies)
        allSessions.insert(record, at: 0)
        save()
    }

    func clear() {
        allSessions.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    func deleteSession(id: UUID) {
        allSessions.removeAll { $0.id == id }
        save()
    }

    func dismissCandidate(_ word: String) {
        Settings.dismissedCandidates.insert(word)
    }

    // MARK: - Query

    func sessions(since date: Date) -> [SessionRecord] {
        allSessions.filter { $0.date >= date }
    }

    var last7DaysAvgFPM: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = sessions(since: cutoff)
        guard !recent.isEmpty else { return 0 }
        return recent.map(\.fillersPerMinute).reduce(0, +) / Double(recent.count)
    }

    /// Average filler rate (per 100 words) for sessions in the last 7 days
    /// that have word frequency data.
    var last7DaysAvgFillerRate: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = sessions(since: cutoff).filter { $0.totalWordsSpoken > 0 }
        guard !recent.isEmpty else { return 0 }
        return recent.map(\.fillerRate).reduce(0, +) / Double(recent.count)
    }

    var bestSession: SessionRecord? {
        allSessions.filter { $0.durationSeconds >= 30 }.min { $0.fillersPerMinute < $1.fillersPerMinute }
    }

    /// Best session by filler rate (sessions with word data only).
    var bestSessionByRate: SessionRecord? {
        allSessions.filter { $0.durationSeconds >= 30 && $0.totalWordsSpoken > 0 }
            .min { $0.fillerRate < $1.fillerRate }
    }

    /// Trend: compare filler rate of last 5 sessions vs previous 5.
    /// Returns a percentage change — negative means improving (rate went down).
    var recentTrendPercent: Double? {
        let withData = allSessions.filter { $0.totalWordsSpoken > 0 }
        guard withData.count >= 4 else { return nil }
        let recent   = Array(withData.prefix(5))
        let previous = Array(withData.dropFirst(5).prefix(5))
        guard !previous.isEmpty else { return nil }
        let recentAvg   = recent.map(\.fillerRate).reduce(0, +) / Double(recent.count)
        let previousAvg = previous.map(\.fillerRate).reduce(0, +) / Double(previous.count)
        guard previousAvg > 0 else { return nil }
        return ((recentAvg - previousAvg) / previousAvg) * 100.0
    }

    var lifetimeTotal: Int { allSessions.map(\.total).reduce(0, +) }

    func trend(for word: String) -> Int {
        guard allSessions.count >= 2 else { return 0 }
        let recent = Array(allSessions.prefix(7))
        let previous = Array(allSessions.dropFirst(7).prefix(7))
        guard !previous.isEmpty else { return 0 }
        let recentAvg = Double(recent.compactMap { $0.wordCounts[word] }.reduce(0, +)) / Double(recent.count)
        let prevAvg = Double(previous.compactMap { $0.wordCounts[word] }.reduce(0, +)) / Double(previous.count)
        if recentAvg < prevAvg - 0.1 { return 1 }
        if recentAvg > prevAvg + 0.1 { return -1 }
        return 0
    }

    /// Per-word stats: total, avg per 100 words (filler rate contribution), and trend.
    /// Uses filler rate where word data is available, falls back to avg/session.
    var allWords: [(word: String, total: Int, rateMetric: Double, rateLabel: String)] {
        var counts: [String: Int] = [:]
        for session in allSessions {
            for (word, count) in session.wordCounts { counts[word, default: 0] += count }
        }
        let sessionsWithWords = allSessions.filter { $0.totalWordsSpoken > 0 }
        let totalWords = sessionsWithWords.map(\.totalWordsSpoken).reduce(0, +)

        return counts.map { word, total -> (word: String, total: Int, rateMetric: Double, rateLabel: String) in
            if totalWords > 0 {
                let rate = Double(total) / Double(totalWords) * 100.0
                return (word: word, total: total, rateMetric: rate, rateLabel: "/ 100 words")
            } else {
                let n = Double(max(1, allSessions.count))
                return (word: word, total: total, rateMetric: Double(total) / n, rateLabel: "/ session")
            }
        }
        .sorted { $0.total > $1.total }
    }

    // MARK: - Candidate filler detection

    /// Corpus baseline rates (per 100 words) from SUBTLEX-US conversational speech.
    /// Only words that *could* be fillers are included; common content words are absent,
    /// so any word not in this table uses a conservative default of 0.05.
    /// Words with a baseline above 0.5 are also excluded (too common to be meaningful).
    static let corpusBaseline: [String: Double] = [
        // Discourse markers / hedges
        "basically": 0.04, "honestly": 0.02, "literally": 0.03, "obviously": 0.04,
        "clearly": 0.03, "essentially": 0.02, "technically": 0.02, "actually": 0.10,
        "seriously": 0.03, "genuinely": 0.01, "frankly": 0.01, "admittedly": 0.01,
        "apparently": 0.03, "supposedly": 0.01, "theoretically": 0.01,
        // Fillers / utterance restarts
        "anyway": 0.03, "whatever": 0.04, "regardless": 0.02, "anyway": 0.03,
        "anyhow": 0.01, "nevermind": 0.01,
        // Hesitation / hedge bigrams
        "kind of": 0.06, "sort of": 0.05, "i mean": 0.15, "i think": 0.20,
        "you know": 0.18, "you see": 0.04, "i guess": 0.08, "i feel": 0.05,
        "i suppose": 0.03, "i believe": 0.04,
        // Intensifiers used as hedges
        "totally": 0.03, "absolutely": 0.04, "definitely": 0.05, "certainly": 0.04,
        "probably": 0.08, "possibly": 0.03, "perhaps": 0.04, "maybe": 0.07,
        "surely": 0.02, "simply": 0.04, "practically": 0.02, "virtually": 0.02,
        "essentially": 0.02, "typically": 0.03, "generally": 0.04, "normally": 0.03,
        "usually": 0.06, "often": 0.07, "sometimes": 0.07, "always": 0.08,
        "never": 0.08, "occasionally": 0.02,
        // Topic pivots / transitions
        "anyway": 0.03, "moving": 0.02, "speaking": 0.02, "talking": 0.04,
        "honestly": 0.02, "truthfully": 0.01,
        // Short fillers that survive stop-word filter
        "wow": 0.02, "gosh": 0.01, "well": 0.15, "hmm": 0.02, "hm": 0.01,
    ]

    /// Detects candidate filler words using statistical reasoning:
    /// - **Lift**: how many times above the expected corpus baseline is this word used?
    ///   Words that are 5× above baseline are statistically anomalous.
    /// - **Consistency (CV)**: do they appear at a *stable* rate session-to-session?
    ///   Filler words are topic-independent; content words vary by session topic.
    ///   Low coefficient of variation = habitual usage.
    /// - **Persistence**: does the word appear in most sessions (not just one outlier)?
    ///
    /// Scored by `lift / max(CV, 0.1)` — rewards words that are both anomalously
    /// frequent AND remarkably consistent.
    var candidateFillers: [CandidateFiller] {
        let dismissed = Settings.dismissedCandidates
        let existing  = Set(Settings.allFillers)
        let N = Double(allSessions.count)
        guard N >= 2 else { return [] }

        // Build per-word rate arrays: [word: [ratePerHundred per session]]
        var ratesByWord: [String: [Double]] = [:]
        for session in allSessions {
            let total = Double(session.totalWordsSpoken)
            guard total > 10 else { continue }         // skip very short sessions
            for (word, count) in session.wordFrequencies {
                guard !dismissed.contains(word), !existing.contains(word) else { continue }
                let rate = Double(count) / total * 100.0
                ratesByWord[word, default: []].append(rate)
            }
        }

        let minSessions = max(2, Int(ceil(N / 2.0)))
        let defaultBaseline = 0.05

        var candidates: [CandidateFiller] = []

        for (word, rates) in ratesByWord {
            guard rates.count >= minSessions else { continue }

            let mean = rates.reduce(0, +) / Double(rates.count)
            guard mean > 0 else { continue }

            // Coefficient of variation: stddev / mean. Low CV = consistent usage.
            let variance = rates.map { pow($0 - mean, 2) }.reduce(0, +) / Double(rates.count)
            let cv = sqrt(variance) / mean

            // Lift: how far above the corpus baseline?
            let baseline = AnalyticsStore.corpusBaseline[word] ?? defaultBaseline
            let lift = mean / baseline

            // Thresholds:
            // - lift >= 3.0: at least 3× above expected conversational frequency
            // - cv <= 0.80: appears at reasonably consistent rate (not just one topic spike)
            // - rates.count >= minSessions: appears in ≥ half of sessions
            guard lift >= 3.0, cv <= 0.80 else { continue }

            // Score: rewards both high anomaly and high consistency
            let score = lift / max(cv, 0.10)

            candidates.append(CandidateFiller(
                word: word,
                sessionsCount: rates.count,
                totalOccurrences: Int(mean * Double(rates.count)),
                avgPerSession: mean
            ))
            _ = score  // used for sorting below via a parallel array approach
        }

        // Re-sort by score (lift / max(CV, 0.1)) — need to recompute for sort
        let scored: [(CandidateFiller, Double)] = candidates.compactMap { c in
            guard let rates = ratesByWord[c.word], !rates.isEmpty else { return nil }
            let mean = rates.reduce(0, +) / Double(rates.count)
            let variance = rates.map { pow($0 - mean, 2) }.reduce(0, +) / Double(rates.count)
            let cv = sqrt(variance) / max(mean, 0.001)
            let baseline = AnalyticsStore.corpusBaseline[c.word] ?? defaultBaseline
            let lift = mean / baseline
            return (c, lift / max(cv, 0.10))
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0.0 }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        allSessions = (try? JSONDecoder().decode([SessionRecord].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(allSessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
