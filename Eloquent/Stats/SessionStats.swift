import Foundation

struct SessionStats {
    private var counts: [String: Int] = [:]

    mutating func record(_ word: String) {
        counts[word, default: 0] += 1
    }

    mutating func reset() {
        counts.removeAll()
    }

    func count(for word: String) -> Int {
        counts[word] ?? 0
    }

    func total() -> Int {
        counts.values.reduce(0, +)
    }

    // Returns [(word, count)] sorted highest count first
    func summary() -> [(word: String, count: Int)] {
        counts.map { (word: $0.key, count: $0.value) }
              .sorted { $0.count > $1.count }
    }
}
