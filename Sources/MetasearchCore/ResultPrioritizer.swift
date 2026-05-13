import Foundation

public struct ResultPrioritizer {
    public init() {}

    public func prioritize(
        results: [SearchResult],
        scorer: EthicsScorer? = nil
    ) -> [SearchResult] {
        return results.sorted { lhs, rhs in
            // First, prioritize by source type tier
            let lhsTier = tierPriority(for: lhs.sourceType)
            let rhsTier = tierPriority(for: rhs.sourceType)

            if lhsTier != rhsTier {
                return lhsTier < rhsTier
            }

            // Within the same tier: prefer entries with higher ethics scores
            // (co-op / b-corp / employee-owned > indie > unknown). Falls
            // through silently when no scorer is provided.
            if let scorer {
                let lhsEthics = ethicsScore(for: lhs, scorer: scorer)
                let rhsEthics = ethicsScore(for: rhs, scorer: scorer)
                if lhsEthics != rhsEthics {
                    return lhsEthics > rhsEthics
                }
            }

            // Within same tier and ethics: sort by relevance score (higher first), then distance
            let lhsRelevance = lhs.relevanceScore ?? 0.0
            let rhsRelevance = rhs.relevanceScore ?? 0.0

            if lhsRelevance != rhsRelevance {
                return lhsRelevance > rhsRelevance // Higher relevance first
            }

            // Same relevance: sort by distance (closer first) for local results
            if lhs.sourceType == .local && rhs.sourceType == .local {
                let lhsDistance = lhs.distance ?? Double.infinity
                let rhsDistance = rhs.distance ?? Double.infinity
                return lhsDistance < rhsDistance
            }

            // Maintain original order for same tier, relevance, and distance
            return false
        }
    }

    private func tierPriority(for sourceType: SourceType) -> Int {
        switch sourceType {
        case .local:
            return 1
        case .regional:
            return 2
        case .online:
            return 3
        }
    }

    /// Resolves a result's ethics score from its URL host. Results without
    /// a URL or hostname (e.g. local MapKit places) get the neutral
    /// "unknown" score so they don't outrank or get outranked solely on
    /// ethics within their tier.
    private func ethicsScore(for result: SearchResult, scorer: EthicsScorer) -> Int {
        guard let host = result.url?.host?.lowercased() else {
            return 1 // neutral / unknown
        }
        return scorer.score(forHost: host)
    }
}
