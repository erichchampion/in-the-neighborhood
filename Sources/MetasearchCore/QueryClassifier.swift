import Foundation
@preconcurrency import NaturalLanguage

/// Classifies a raw search query into a single `QueryCategory` using
/// Apple's pretrained English word embeddings (`NLEmbedding`). For each
/// category we hold a small seed-word set; at classify-time we score
/// each category by the **average over query tokens of (min distance to
/// any seed)** — this rewards categories that cover every token, not
/// just one.
///
/// Two earlier algorithms were tried and rejected:
///   1. *Mean over all (token, seed) pairs* — too noisy; one weakly-
///      related token (e.g. "bit" in "drill bit") pulled the mean
///      above threshold even when the strong signal was tight.
///   2. *Single min pair distance* — fails on cross-category queries
///      like "dog food": "food"↔"food" (grocery) and "dog"↔"dog"
///      (petFood) both score 0, so neither beats the other by the
///      margin and the classifier rejects both.
///
/// Returns `nil` when the classifier isn't confident, or when the
/// embedding model isn't available at runtime. `nil` is the safe answer:
/// `MetasearchCoordinator` interprets it as "run every source," matching
/// today's pre-C3 behavior.
public struct QueryClassifier: Sendable {

    /// Maximum per-token-min average distance to consider a query
    /// "matched" to a category. Lower is stricter.
    static let maxMatchDistance: Double = 0.9

    /// Minimum gap between best and runner-up averages.
    /// Prevents picking a winner when two categories tie.
    static let minRunnerUpMargin: Double = 0.05

    /// Tokens shorter than this are dropped (mostly connector words).
    static let minTokenLength: Int = 3

    static let stopwords: Set<String> = ["the", "and", "for", "with", "from", "into"]

    /// Per-category seed words. Kept small (~10) and intentionally
    /// generic so the embedding distance — not exact-string match —
    /// does the work.
    static let seeds: [QueryCategory: [String]] = [
        .book: ["book", "novel", "paperback", "hardcover", "textbook", "audiobook", "memoir", "biography", "fiction", "literature"],
        .grocery: ["food", "bread", "milk", "cereal", "vegetable", "fruit", "snack", "beverage", "coffee", "tea"],
        .hardware: ["drill", "hammer", "wrench", "screw", "tool", "pipe", "lumber", "paint", "saw", "nail"],
        .electronics: ["laptop", "headphones", "monitor", "camera", "speaker", "charger", "phone", "tablet", "router", "keyboard"],
        .clothing: ["shirt", "pants", "jacket", "shoes", "hat", "dress", "sweater", "jeans", "socks", "coat"],
        .media: ["album", "vinyl", "movie", "film", "game", "cd", "dvd", "soundtrack", "record", "videogame"],
        .personalCare: ["shampoo", "soap", "lotion", "toothpaste", "deodorant", "cosmetic", "makeup", "perfume", "razor", "conditioner"],
        .petFood: ["dog", "cat", "kibble", "petfood", "treats", "puppy", "kitten", "biscuits", "pet", "feeding"]
    ]

    private let embedding: NLEmbedding?

    public init() {
        self.embedding = NLEmbedding.wordEmbedding(for: .english)
    }

    public func classify(_ query: String) -> QueryCategory? {
        guard let embedding else { return nil }
        let tokens = Self.tokenize(query)
        guard !tokens.isEmpty else { return nil }

        var scoresByCategory: [(category: QueryCategory, score: Double)] = []

        for (category, seedWords) in Self.seeds {
            var perTokenMins: [Double] = []
            for token in tokens {
                guard embedding.contains(token) else { continue }
                var minForToken = Double.infinity
                for seed in seedWords where embedding.contains(seed) {
                    let d = embedding.distance(between: token, and: seed)
                    if d.isFinite && d < minForToken {
                        minForToken = d
                    }
                }
                if minForToken.isFinite {
                    perTokenMins.append(minForToken)
                }
            }
            guard !perTokenMins.isEmpty else { continue }
            let avg = perTokenMins.reduce(0, +) / Double(perTokenMins.count)
            scoresByCategory.append((category, avg))
        }

        guard !scoresByCategory.isEmpty else { return nil }
        scoresByCategory.sort { $0.score < $1.score }

        let best = scoresByCategory[0]
        guard best.score <= Self.maxMatchDistance else { return nil }

        if scoresByCategory.count >= 2 {
            let runnerUp = scoresByCategory[1]
            guard runnerUp.score - best.score >= Self.minRunnerUpMargin else { return nil }
        }

        return best.category
    }

    static func tokenize(_ query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= minTokenLength && !stopwords.contains($0) }
    }
}
