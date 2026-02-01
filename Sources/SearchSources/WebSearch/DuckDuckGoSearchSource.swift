import Foundation
import MetasearchCore

/// SearchSource wrapping DuckDuckGo; enables incremental display when used as a separate coordinator source.
public final class DuckDuckGoSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = "duckduckgo"
    public let sourceType: SourceType = .online
    
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
        let searchQuery = query.original
        
        guard await circuitBreaker.canAttempt() else {
            return []
        }
        
        do {
            let results = try await provider.search(query: searchQuery)
            await circuitBreaker.recordSuccess()
            return results
        } catch {
            await circuitBreaker.recordFailure()
            throw error
        }
    }
}
