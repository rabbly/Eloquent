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
    let avgPerSession: Double
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

    /// Words appearing frequently in sessions that aren't yet in the filler word list.
    var candidateFillers: [CandidateFiller] {
        let dismissed = Settings.dismissedCandidates
        let existing = Set(Settings.allFillers)

        var byWord: [String: (sessions: Int, total: Int)] = [:]
        for session in allSessions {
            for (word, count) in session.wordFrequencies {
                if dismissed.contains(word) || existing.contains(word) { continue }
                let prev = byWord[word] ?? (0, 0)
                byWord[word] = (prev.sessions + 1, prev.total + count)
            }
        }

        return byWord.compactMap { (word, stats) -> CandidateFiller? in
            // Must appear in ≥2 sessions OR ≥3 times in a single session, AND ≥3 total.
            let meetsThreshold = stats.sessions >= 2 ||
                allSessions.contains { ($0.wordFrequencies[word] ?? 0) >= 3 }
            guard meetsThreshold && stats.total >= 3 else { return nil }
            return CandidateFiller(
                word: word,
                sessionsCount: stats.sessions,
                totalOccurrences: stats.total,
                avgPerSession: Double(stats.total) / Double(max(1, stats.sessions))
            )
        }
        .sorted { $0.totalOccurrences > $1.totalOccurrences }
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
