import Foundation

public struct ResultPrioritizer {
    public init() {}
    
    public func prioritize(results: [SearchResult]) -> [SearchResult] {
        return results.sorted { lhs, rhs in
            // First, prioritize by source type tier
            let lhsTier = tierPriority(for: lhs.sourceType)
            let rhsTier = tierPriority(for: rhs.sourceType)
            
            if lhsTier != rhsTier {
                return lhsTier < rhsTier
            }
            
            // Within same tier: sort by relevance score (higher first), then distance
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
}
