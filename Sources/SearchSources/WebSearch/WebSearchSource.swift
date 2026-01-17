import Foundation
import MetasearchCore

public final class WebSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = "websearch"
    public let sourceType: SourceType = .online
    
    private let duckDuckGoProvider: WebSearchProvider
    private let bingProvider: WebSearchProvider
    private let session: URLSession
    
    public init(
        duckDuckGoProvider: WebSearchProvider? = nil,
        bingProvider: WebSearchProvider? = nil,
        session: URLSession = .shared
    ) {
        self.duckDuckGoProvider = duckDuckGoProvider ?? DuckDuckGoProvider(session: session)
        self.bingProvider = bingProvider ?? BingProvider(session: session)
        self.session = session
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        let searchQuery = query.original
        
        // Execute searches in parallel
        async let duckDuckGoResults = searchDuckDuckGo(query: searchQuery)
        async let bingResults = searchBing(query: searchQuery)
        
        // Aggregate results (use try? to handle individual failures)
        let duckDuckGo = try? await duckDuckGoResults
        let bing = try? await bingResults
        
        var allResults: [SearchResult] = []
        allResults.append(contentsOf: duckDuckGo ?? [])
        allResults.append(contentsOf: bing ?? [])
        
        return allResults
    }
    
    private func searchDuckDuckGo(query: String) async throws -> [SearchResult] {
        return try await duckDuckGoProvider.search(query: query)
    }
    
    private func searchBing(query: String) async throws -> [SearchResult] {
        return try await bingProvider.search(query: query)
    }
}
