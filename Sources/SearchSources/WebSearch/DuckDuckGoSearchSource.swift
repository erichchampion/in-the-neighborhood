import Foundation
import MetasearchCore

/// SearchSource wrapping DuckDuckGo; enables incremental display when used as a separate coordinator source.
public final class DuckDuckGoSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = SourceIdentifier.duckduckgo
    public let sourceType: SourceType = .online
    public let category: ResultCategory = .web
    
    private let provider: WebSearchProvider
    private let circuitBreaker: CircuitBreaker
    
    public init(
        provider: WebSearchProvider? = nil,
        session: URLSession = .shared,
        circuitBreaker: CircuitBreaker? = nil
    ) {
        self.provider = provider ?? DuckDuckGoProvider(session: session)
        self.circuitBreaker = circuitBreaker ?? CircuitBreaker()
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        let collector = SearchResultsCollector()
        try await searchStreaming(query: query) { results in
            Task {
                await collector.append(results)
            }
        }
        return await collector.allResults
    }
    
    public func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        let searchQuery = query.original
        
        guard await circuitBreaker.canAttempt() else {
            return
        }
        
        do {
            try await provider.searchStreaming(query: searchQuery, onResults: onResults)
            await circuitBreaker.recordSuccess()
        } catch {
            await circuitBreaker.recordFailure()
            throw error
        }
    }
}
