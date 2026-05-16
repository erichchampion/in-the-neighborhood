import Foundation

public protocol SearchSource: Sendable {
    var identifier: String { get }
    var sourceType: SourceType { get }
    var category: ResultCategory { get }

    /// Max seconds this source is allowed to run before the coordinator drops it.
    /// Sources may override; the default scales with `sourceType` (see extension below).
    var timeoutBudget: TimeInterval { get }

    /// QueryCategory values for which this source is relevant. Empty set
    /// means "no affinity, always run" — that's the default for
    /// general-purpose sources (web search, local POI lookups). A
    /// specialty source like OpenLibrary declares `[.book]` so the
    /// coordinator skips it for unrelated queries like "shampoo".
    /// Phase C3 contract: when the coordinator has a classified
    /// `query.queryCategory`, sources with a non-empty affinity set
    /// that doesn't contain the category are excluded from the fan-out.
    var categoryAffinity: Set<QueryCategory> { get }

    func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws

    // Default synchronous-like interface for backward compatibility
    func search(query: EnhancedQuery) async throws -> [SearchResult]
}

// Helper actor for aggregating results safely
public actor SearchResultsCollector {
    public var allResults: [SearchResult] = []
    
    public init() {}
    
    public func append(_ results: [SearchResult]) {
        allResults.append(contentsOf: results)
    }
}

// Provide generic default implementation for legacy search
public extension SearchSource {
    var timeoutBudget: TimeInterval {
        switch sourceType {
        case .local:    return 2.5
        case .regional: return 4.0
        case .online:   return 4.0
        }
    }

    /// Default: no affinity — source runs for every query regardless of
    /// classification. Sources that should be category-gated must
    /// override (e.g. `categoryAffinity: Set<QueryCategory> { [.book] }`).
    var categoryAffinity: Set<QueryCategory> { [] }

    func search(query: EnhancedQuery) async throws -> [SearchResult] {
        let (stream, continuation) = AsyncStream.makeStream(of: [SearchResult].self)
        let collector = SearchResultsCollector()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.searchStreaming(query: query) { partialResults in
                    continuation.yield(partialResults)
                }
                continuation.finish()
            }
            
            group.addTask {
                for await partialResults in stream {
                    await collector.append(partialResults)
                }
            }
            
            try await group.waitForAll()
        }
        
        return await collector.allResults
    }
}
