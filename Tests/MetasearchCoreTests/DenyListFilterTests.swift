import XCTest
@testable import MetasearchCore

final class DenyListFilterTests: XCTestCase {
    
    // MARK: - DenyListFilter Behavior Tests
    
    func testWebResultsFromDeniedDomainAreFiltered() {
        // Given: A deny list with amazon.com
        let denyList = DenyListFilter(defaultDomains: ["amazon.com"])
        
        // And: A web result with amazon.com URL (using .online source type)
        let webResult = SearchResult(
            id: "1",
            title: "Book Title",
            description: "A book",
            source: "duckduckgo",
            sourceType: .online,
            category: .web,
            url: URL(string: "https://www.amazon.com/dp/1234567890"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: [:]
        )
        
        // When: Filtering web results
        let aggregator = ResultAggregator()
        let filtered = aggregator.filter(results: [webResult], denyList: denyList)
        
        // Then: The amazon result should be filtered out
        XCTAssertEqual(filtered.count, 0, "Web results from denied domains should be filtered")
    }
    
    func testProductResultsFromDeniedDomainAreNotFiltered() {
        // Given: A deny list with amazon.com
        let denyList = DenyListFilter(defaultDomains: ["amazon.com"])
        
        // And: A product result with amazon.com URL containing ISBN metadata
        let productResult = SearchResult(
            id: "1",
            title: "On Tyranny",
            description: "Timothy Snyder",
            source: "amazon",
            sourceType: .online,
            category: .product,
            url: URL(string: "https://www.amazon.com/dp/0804190119"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: "$14.99",
            metadata: ["isbn": "0804190119", "author": "Timothy Snyder"]
        )
        
        // When: Filtering product results (which should NOT be filtered)
        let aggregator = ResultAggregator()
        let filtered = aggregator.filter(results: [productResult], denyList: denyList)
        
        // Then: The product result should NOT be filtered (used for metadata extraction)
        XCTAssertEqual(filtered.count, 1, "Product results should NOT be filtered even from denied domains")
    }
    
    func testWebResultsFromAllowedDomainAreNotFiltered() {
        // Given: A deny list with amazon.com
        let denyList = DenyListFilter(defaultDomains: ["amazon.com"])
        
        // And: A web result from example.com (not in deny list)
        let webResult = SearchResult(
            id: "1",
            title: "Book Review",
            description: "A review",
            source: "duckduckgo",
            sourceType: .online,
            category: .web,
            url: URL(string: "https://example.com/review"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: [:]
        )
        
        // When: Filtering web results
        let aggregator = ResultAggregator()
        let filtered = aggregator.filter(results: [webResult], denyList: denyList)
        
        // Then: The example.com result should NOT be filtered
        XCTAssertEqual(filtered.count, 1, "Web results from allowed domains should not be filtered")
    }
    
    func testLocalResultsFromDeniedDomainAreFiltered() {
        // Given: A deny list with amazon.com
        let denyList = DenyListFilter(defaultDomains: ["amazon.com"])
        
        // And: A local result with amazon.com URL (e.g., if a local store has an amazon link)
        let localResult = SearchResult(
            id: "1",
            title: "Local Bookstore",
            description: "A local store",
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: URL(string: "https://www.amazon.com/local-store"),
            location: nil,
            distance: 1000,
            relevanceScore: nil,
            price: nil,
            metadata: [:]
        )
        
        // When: Filtering local results
        let aggregator = ResultAggregator()
        let filtered = aggregator.filter(results: [localResult], denyList: denyList)
        
        // Then: The result should be filtered out
        XCTAssertEqual(filtered.count, 0, "Local results with denied domain URLs should be filtered")
    }
    
    func testBookResultsFromDeniedDomainAreFiltered() {
        // Given: A deny list with amazon.com
        let denyList = DenyListFilter(defaultDomains: ["amazon.com"])
        
        // And: A book result from amazon.com
        let bookResult = SearchResult(
            id: "1",
            title: "On Tyranny",
            description: "A book",
            source: "openlibrary",
            sourceType: .online,
            category: .book,
            url: URL(string: "https://www.amazon.com/book/123"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: [:]
        )
        
        // When: Filtering book results
        let aggregator = ResultAggregator()
        let filtered = aggregator.filter(results: [bookResult], denyList: denyList)
        
        // Then: The result should be filtered out
        XCTAssertEqual(filtered.count, 0, "Book results from denied domains should be filtered")
    }
    
    // MARK: - SearchToolExecutor Tests
    
    func testSearchToolExecutorFiltersWebButNotProducts() async throws {
        // Given: A deny list with amazon.com
        let denyList = DenyListFilter(defaultDomains: ["amazon.com"])
        
        // Create an aggregator that uses our deny list
        let aggregator = ResultAggregator()
        
        // When: Filtering web category with amazon.com URL
        let webResults = [
            SearchResult(
                id: "web1",
                title: "Web Result",
                description: "From web",
                source: "duckduckgo",
                sourceType: .online,
                category: .web,
                url: URL(string: "https://amazon.com/page"),
                location: nil,
                distance: nil,
                relevanceScore: nil,
                price: nil,
                metadata: [:]
            )
        ]
        
        // Then: Web results should be filtered
        let filteredWeb = aggregator.filter(results: webResults, denyList: denyList)
        XCTAssertEqual(filteredWeb.count, 0, "Web results from denied domains should be filtered")
        
        // When: Filtering product category with amazon.com URL
        let productResults = [
            SearchResult(
                id: "prod1",
                title: "Product Result",
                description: "From product",
                source: "amazon",
                sourceType: .online,
                category: .product,
                url: URL(string: "https://amazon.com/product"),
                location: nil,
                distance: nil,
                relevanceScore: nil,
                price: "$10",
                metadata: ["isbn": "123456789"]
            )
        ]
        
        // Then: Product results should NOT be filtered (for metadata extraction)
        let filteredProduct = aggregator.filter(results: productResults, denyList: denyList)
        XCTAssertEqual(filteredProduct.count, 1, "Product results from denied domains should NOT be filtered")
    }
}

// MARK: - Mock Search Source for Testing

struct MockDenyListSearchSource: SearchSource, @unchecked Sendable {
    let identifier: String
    let sourceType: SourceType
    let category: ResultCategory
    
    var mockResults: [SearchResult] = []
    
    func search(query: EnhancedQuery) async throws -> [SearchResult] {
        return mockResults
    }
    
    func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        onResults(mockResults)
    }
}