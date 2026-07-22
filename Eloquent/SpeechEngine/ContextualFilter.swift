import Foundation
import NaturalLanguage

/// Checks whether a matched filler word is being used as a genuine filler/hedge
/// rather than in a grammatically meaningful role, using on-device NLTagger.
///
/// Words like "like", "so", "right", "actually" are ambiguous — they can be
/// fillers ("I was like, really?") or grammatical ("it's like the other one").
/// This filter suppresses the fire for grammatical usages.
///
/// Privacy: text is analysed in-process only, never stored or transmitted.
@MainActor
enum ContextualFilter {

    /// Words that need contextual checking (all others are always fired).
    private static let ambiguousWords: Set<String> = ["like", "so", "right", "actually"]

    /// NLTagger instance — reused across calls to avoid repeated initialisation overhead.
    private static let tagger: NLTagger = {
        let t = NLTagger(tagSchemes: [.lexicalClass])
        t.setLanguage(.english, range: "".startIndex..<"".endIndex)
        return t
    }()

    /// Returns true if the word should fire as a filler given the surrounding context.
    ///
    /// - Parameters:
    ///   - word: The matched filler word (e.g. "like").
    ///   - phrase: The short phrase being scanned (2-3 words including the matched word).
    ///   - fullContext: The broader text available (last sentence or tail).
    static func isFiller(_ word: String, inPhrase phrase: String, context fullContext: String) -> Bool {
        // For words not in the ambiguous set, always fire.
        guard ambiguousWords.contains(word) else { return true }

        switch word {
        case "like":
            return checkLike(phrase: phrase, context: fullContext)
        case "so":
            return checkSo(phrase: phrase, context: fullContext)
        case "right":
            return checkRight(phrase: phrase, context: fullContext)
        case "actually":
            // "actually" as a filler appears at clause boundaries (sentence start or after a pause).
            // As a content word it typically appears mid-clause before the verb's object.
            // Heuristic: fire unless it's followed immediately by a noun (suggests "actually X happened").
            return !followedByNoun(word: word, in: phrase)
        default:
            return true
        }
    }

    // MARK: - Word-specific rules

    /// "like" is a filler when:
    /// - It appears standalone or before a clause ("I was like, yeah")
    /// - It appears after a verb as a hedge ("it was like really good")
    ///
    /// "like" is NOT a filler when:
    /// - It is a preposition/comparator followed by a noun phrase ("like the other one", "not like apples")
    /// - It is a verb ("I like this")
    private static func checkLike(phrase: String, context: String) -> Bool {
        let tokens = tokenize(phrase)
        guard let idx = tokens.firstIndex(of: "like") else { return true }

        // If "like" is preceded by "not" → clearly comparative ("not like...")
        if idx > 0 && tokens[idx - 1] == "not" { return false }

        // Check what follows "like"
        if idx + 1 < tokens.count {
            let nextWord = tokens[idx + 1]
            // If followed by "a", "an", "the", or another determiner → comparative/prepositional
            if ["a", "an", "the", "this", "that", "these", "those"].contains(nextWord) {
                return false
            }
            // If followed by a noun (via NLTagger) → comparative
            if tokenIsNoun(nextWord) { return false }
        }

        return true
    }

    /// "so" is a filler when used as an intensifier or topic opener ("so, I was thinking...")
    /// "so" is NOT a filler when it's a conjunction ("I did this so that you could...").
    private static func checkSo(phrase: String, context: String) -> Bool {
        let tokens = tokenize(phrase)
        guard let idx = tokens.firstIndex(of: "so") else { return true }

        // "so that", "so as" → conjunction, suppress
        if idx + 1 < tokens.count {
            let next = tokens[idx + 1]
            if next == "that" || next == "as" || next == "when" || next == "if" { return false }
            // "so" followed by an adjective/adverb → intensifier filler ("so good", "so great")
            // which IS a filler use in speech coaching context — fire it
        }

        return true
    }

    /// "right" is a filler when used as a discourse marker or tag ("right?", "...right?")
    /// "right" is NOT a filler when it's an adjective/adverb ("the right answer", "turn right").
    private static func checkRight(phrase: String, context: String) -> Bool {
        let tokens = tokenize(phrase)
        guard let idx = tokens.firstIndex(of: "right") else { return true }

        // "right" preceded by "turn", "go", "move" → directional, suppress
        if idx > 0 {
            let prev = tokens[idx - 1]
            if ["turn", "go", "move", "step", "look", "swing"].contains(prev) { return false }
        }

        // "the right ..." or "a right ..." → adjectival, suppress
        if idx > 0 && (tokens[idx - 1] == "the" || tokens[idx - 1] == "a") { return false }

        // "right now", "right here", "right there" → adverb, but in coaching these
        // are still legitimate uses, not fillers — suppress
        if idx + 1 < tokens.count {
            let next = tokens[idx + 1]
            if ["now", "here", "there", "away", "after"].contains(next) { return false }
        }

        return true
    }

    // MARK: - NLTagger helpers

    private static func tokenIsNoun(_ word: String) -> Bool {
        tagger.string = word
        let range = word.startIndex..<word.endIndex
        var isNoun = false
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass) { tag, _ in
            if let t = tag, [.noun, .personalName, .placeName, .organizationName].contains(t) {
                isNoun = true
            }
            return true
        }
        return isNoun
    }

    private static func followedByNoun(word: String, in phrase: String) -> Bool {
        let tokens = tokenize(phrase)
        guard let idx = tokens.firstIndex(of: word), idx + 1 < tokens.count else { return false }
        return tokenIsNoun(tokens[idx + 1])
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
    }
}
