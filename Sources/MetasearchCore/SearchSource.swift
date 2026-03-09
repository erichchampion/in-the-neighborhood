import Foundation

public protocol SearchSource: Sendable {
    var identifier: String { get }
    var sourceType: SourceType { get }
    var category: ResultCategory { get }
    
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
