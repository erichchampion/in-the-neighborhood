import Foundation

public struct ResultPrioritizer {
    public init() {}
    
    public func prioritize(results: [SearchResult]) -> [SearchResult] {
        // Sort by tier priority: local > regional > online
        // Within local, sort by distance (closer first)
        // Within same tier, maintain original order (or by relevance score if available)
        
        return results.sorted { lhs, rhs in
            // First, prioritize by source type
            let lhsTier = tierPriority(for: lhs.sourceType)
            let rhsTier = tierPriority(for: rhs.sourceType)
            
            if lhsTier != rhsTier {
                return lhsTier < rhsTier
            }
            
            // Within same tier, if both are local, sort by distance
            if lhs.sourceType == .local && rhs.sourceType == .local {
                let lhsDistance = lhs.distance ?? Double.infinity
                let rhsDistance = rhs.distance ?? Double.infinity
                
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
            }
            
            // Maintain original order for same tier and distance
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
