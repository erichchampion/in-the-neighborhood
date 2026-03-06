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
        let searchQuery = query.original
        
        // Execute searches in parallel with circuit breaker protection
        async let duckDuckGoResults = searchDuckDuckGo(query: searchQuery)
        async let bingResults = searchBing(query: searchQuery)
        
        // Aggregate results (use try? to handle individual failures gracefully)
        // This ensures one provider failing doesn't block the other
        let duckDuckGo = try? await duckDuckGoResults
        let bing = try? await bingResults
        
        var allResults: [SearchResult] = []
        allResults.append(contentsOf: duckDuckGo ?? [])
        allResults.append(contentsOf: bing ?? [])
        
        return allResults
    }
    
    private func searchDuckDuckGo(query: String) async throws -> [SearchResult] {
        // Check circuit breaker
        guard await duckDuckGoBreaker.canAttempt() else {
            return []
        }
        
        do {
            let results = try await duckDuckGoProvider.search(query: query)
            await duckDuckGoBreaker.recordSuccess()
            return results
        } catch {
            await duckDuckGoBreaker.recordFailure()
            throw error
        }
    }
    
    private func searchBing(query: String) async throws -> [SearchResult] {
        // Check circuit breaker
        guard await bingBreaker.canAttempt() else {
            return []
        }
        
        do {
            let results = try await bingProvider.search(query: query)
            await bingBreaker.recordSuccess()
            return results
        } catch {
            await bingBreaker.recordFailure()
            throw error
        }
    }
}
