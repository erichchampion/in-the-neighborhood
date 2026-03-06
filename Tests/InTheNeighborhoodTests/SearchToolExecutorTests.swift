import XCTest
@testable import InTheNeighborhood
import MetasearchCore

/// Mock search source for testing the executor
private final class MockSearchSource: SearchSource, @unchecked Sendable {
    let identifier: String
    let sourceType: SourceType
    let category: ResultCategory
    var invokedQueries: [EnhancedQuery] = []
    var stubbedResults: [SearchResult] = []
    
    init(identifier: String, sourceType: SourceType, category: ResultCategory = .web) {
        self.identifier = identifier
        self.sourceType = sourceType
        self.category = category
    }
    
    func search(query: EnhancedQuery) async throws -> [SearchResult] {
        invokedQueries.append(query)
        return stubbedResults
    }
}

final class SearchToolExecutorTests: XCTestCase {

    private func makeResult(id: String, title: String, source: String, category: ResultCategory = .web) -> SearchResult {
        SearchResult(
            id: id,
            title: title,
            description: nil,
            source: source,
            sourceType: .online,
            category: category,
            url: nil,
            location: nil,
            distance: nil,
            metadata: [:]
        )
    }

    func test_searchWeb_invokesBingAndDuckDuckGo() async {
        let bing = MockSearchSource(identifier: "bing", sourceType: .online, category: .web)
        bing.stubbedResults = [makeResult(id: "1", title: "Bing", source: "bing", category: .web)]
        
        let ddg = MockSearchSource(identifier: "duckduckgo", sourceType: .online, category: .web)
        ddg.stubbedResults = [makeResult(id: "2", title: "DDG", source: "duckduckgo", category: .web)]
        
        let amazon = MockSearchSource(identifier: "amazon", sourceType: .online, category: .product)
        
        let executor = SearchToolExecutor(sources: [bing, ddg, amazon])
        let results = await executor.searchWeb(query: "test query")
        
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(bing.invokedQueries.count, 1)
        XCTAssertEqual(ddg.invokedQueries.count, 1)
        XCTAssertEqual(amazon.invokedQueries.count, 0) // Should not be invoked
        XCTAssertEqual(bing.invokedQueries.first?.original, "test query")
    }

    func test_searchProducts_invokesProductSourcesAndPassesCondition() async {
        let amazon = MockSearchSource(identifier: "amazon", sourceType: .online, category: .product)
        amazon.stubbedResults = [makeResult(id: "1", title: "Amz", source: "amazon", category: .product)]
        
        let executor = SearchToolExecutor(sources: [amazon])
        let results = await executor.searchProducts(query: "laptop", maxPrice: 500, condition: "used")
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(amazon.invokedQueries.count, 1)
        let query = amazon.invokedQueries.first
        XCTAssertEqual(query?.original, "laptop")
        XCTAssertEqual(query?.priceMax, 500)
        XCTAssertEqual(query?.condition, .used)
    }

    func test_searchLocalStores_invokesMapKitWithStoreType() async {
        let mapkit = MockSearchSource(identifier: "mapkit", sourceType: .local, category: .local)
        mapkit.stubbedResults = [makeResult(id: "1", title: "Local", source: "mapkit", category: .local)]
        
        let executor = SearchToolExecutor(sources: [mapkit])
        let results = await executor.searchLocalStores(storeType: "bookstore", radiusKm: 10)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(mapkit.invokedQueries.count, 1)
        let query = mapkit.invokedQueries.first
        XCTAssertEqual(query?.original, "bookstore")
        XCTAssertEqual(query?.categories, ["bookstore"])
    }

    func test_searchBooks_invokesBookSources() async {
        let googlebooks = MockSearchSource(identifier: "googlebooks", sourceType: .online, category: .book)
        googlebooks.stubbedResults = [makeResult(id: "1", title: "GB", source: "googlebooks", category: .book)]
        
        let openlibrary = MockSearchSource(identifier: "openlibrary", sourceType: .online, category: .book)
        
        let executor = SearchToolExecutor(sources: [googlebooks, openlibrary])
        let results = await executor.searchBooks(query: "swift programming")
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(googlebooks.invokedQueries.count, 1)
        XCTAssertEqual(openlibrary.invokedQueries.count, 1)
        let query = googlebooks.invokedQueries.first
        XCTAssertEqual(query?.original, "swift programming")
        XCTAssertEqual(query?.productType, "book")
    }
}
