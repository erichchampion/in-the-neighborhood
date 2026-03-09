import Foundation
import MetasearchCore

public final class WebSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = SourceIdentifier.bing // Use bing as composite identifier or add a new one
    public let sourceType: SourceType = .online
    public let category: ResultCategory = .web
    
    private let duckDuckGoProvider: WebSearchProvider
    private let bingProvider: WebSearchProvider
    private let session: URLSession
    private let duckDuckGoBreaker: CircuitBreaker
    private let bingBreaker: CircuitBreaker
    
    public init(
        duckDuckGoProvider: WebSearchProvider? = nil,
        bingProvider: WebSearchProvider? = nil,
        session: URLSession = .shared,
        duckDuckGoBreaker: CircuitBreaker? = nil,
        bingBreaker: CircuitBreaker? = nil
    ) {
        self.duckDuckGoProvider = duckDuckGoProvider ?? DuckDuckGoProvider(session: session)
        self.bingProvider = bingProvider ?? BingProvider(session: session)
        self.session = session
        self.duckDuckGoBreaker = duckDuckGoBreaker ?? CircuitBreaker()
        self.bingBreaker = bingBreaker ?? CircuitBreaker()
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
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.searchDuckDuckGoStreaming(query: searchQuery, onResults: onResults)
            }
            group.addTask {
                try await self.searchBingStreaming(query: searchQuery, onResults: onResults)
            }
            try await group.waitForAll()
        }
    }
    
    private func searchDuckDuckGo(query: String) async throws -> [SearchResult] {
        let collector = SearchResultsCollector()
        try await searchDuckDuckGoStreaming(query: query) { results in
            Task {
                await collector.append(results)
            }
        }
        return await collector.allResults
    }
    
    private func searchDuckDuckGoStreaming(query: String, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        // Check circuit breaker
        guard await duckDuckGoBreaker.canAttempt() else {
            return
        }
        
        do {
            try await duckDuckGoProvider.searchStreaming(query: query, onResults: onResults)
            await duckDuckGoBreaker.recordSuccess()
        } catch {
            await duckDuckGoBreaker.recordFailure()
            throw error
        }
    }
    
    private func searchBing(query: String) async throws -> [SearchResult] {
        let collector = SearchResultsCollector()
        try await searchBingStreaming(query: query) { results in
            Task {
                await collector.append(results)
            }
        }
        return await collector.allResults
    }
    
    private func searchBingStreaming(query: String, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        // Check circuit breaker
        guard await bingBreaker.canAttempt() else {
            return
        }
        
        do {
            try await bingProvider.searchStreaming(query: query, onResults: onResults)
            await bingBreaker.recordSuccess()
        } catch {
            await bingBreaker.recordFailure()
            throw error
        }
    }
}
