import Foundation

enum FillerWordMatcher {
    private static let minConfidence: Float = 0.4

    @MainActor
    static func match(text: String, confidence: Float) -> String? {
        guard confidence >= minConfidence else { return nil }
        return matchPhrase(text.lowercased())
    }

    /// Matches a short phrase/tail against the currently-enabled fillers.
    /// Multi-word phrases are prioritized so "you know" wins over "know".
    @MainActor
    static func matchPhrase(_ phrase: String) -> String? {
        let enabled = Settings.enabledFillers
        // Preserve a stable order; enabled built-ins + custom.
        let fillers = Settings.allFillers.filter { enabled.contains($0) }

        let tokens = tokenize(phrase.lowercased())
        guard !tokens.isEmpty else { return nil }

        // Multi-word phrases first.
        for filler in fillers where filler.contains(" ") {
            let parts = filler.split(separator: " ").map(String.init)
            guard parts.count >= 2, tokens.count >= parts.count else { continue }
            if let _ = firstIndexOfSequence(parts, in: tokens) {
                return filler
            }
        }
        // Single words.
        for filler in fillers where !filler.contains(" ") {
            if tokens.contains(filler) { return filler }
        }
        return nil
    }

    /// Finds the starting index of a contiguous subsequence, or nil.
    private static func firstIndexOfSequence(_ needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            var matched = true
            for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
                matched = false
                break
            }
            if matched { return start }
        }
        return nil
    }

    private static func tokenize(_ text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return text.components(separatedBy: separators).filter { !$0.isEmpty }
    }
}
