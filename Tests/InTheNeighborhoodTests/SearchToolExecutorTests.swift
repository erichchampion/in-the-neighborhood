import XCTest
@testable import InTheNeighborhood
import MetasearchCore

/// Thread-safe state for mock source
actor MockSearchSourceState {
    var invokedQueries: [EnhancedQuery] = []
    var stubbedResults: [SearchResult] = []
    
    func addQuery(_ query: EnhancedQuery) {
        invokedQueries.append(query)
    }
    
    func setStubbedResults(_ results: [SearchResult]) {
        stubbedResults = results
    }
}

/// Mock search source for testing the executor
private final class MockSearchSource: SearchSource, @unchecked Sendable {
    let identifier: String
    let sourceType: SourceType
    let category: ResultCategory
    let state = MockSearchSourceState()
    
    init(identifier: String, sourceType: SourceType, category: ResultCategory = .web) {
        self.identifier = identifier
        self.sourceType = sourceType
        self.category = category
    }
    
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
    
    func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        await state.addQuery(query)
        let results = await state.stubbedResults
        await Task.yield() // Yield to allow collectors to attach
        onResults(results)
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
        await bing.state.setStubbedResults([makeResult(id: "1", title: "Bing", source: "bing", category: .web)])
        
        let ddg = MockSearchSource(identifier: "duckduckgo", sourceType: .online, category: .web)
        await ddg.state.setStubbedResults([makeResult(id: "2", title: "DDG", source: "duckduckgo", category: .web)])
        
        let amazon = MockSearchSource(identifier: "amazon", sourceType: .online, category: .product)
        
        let executor = SearchToolExecutor(sources: [bing, ddg, amazon])
        let results = await executor.searchWeb(query: "test query")
        
        XCTAssertEqual(results.count, 2)
        
        let bingQueries = await bing.state.invokedQueries
        let ddgQueries = await ddg.state.invokedQueries
        let amazonQueries = await amazon.state.invokedQueries
        
        XCTAssertEqual(bingQueries.count, 1)
        XCTAssertEqual(ddgQueries.count, 1)
        XCTAssertEqual(amazonQueries.count, 0) // Should not be invoked
        XCTAssertEqual(bingQueries.first?.original, "test query")
    }

    func test_searchProducts_invokesProductSourcesAndPassesCondition() async {
        let amazon = MockSearchSource(identifier: "amazon", sourceType: .online, category: .product)
        await amazon.state.setStubbedResults([makeResult(id: "1", title: "Amz", source: "amazon", category: .product)])
        
        let executor = SearchToolExecutor(sources: [amazon])
        let results = await executor.searchProducts(query: "laptop", maxPrice: 500, condition: "used")
        
        XCTAssertEqual(results.count, 1)
        
        let amazonQueries = await amazon.state.invokedQueries
        XCTAssertEqual(amazonQueries.count, 1)
        let query = amazonQueries.first
        XCTAssertEqual(query?.original, "laptop")
        XCTAssertEqual(query?.priceMax, 500)
        XCTAssertEqual(query?.condition, .used)
    }

    func test_searchLocalStores_invokesMapKitWithStoreType() async {
        let mapkit = MockSearchSource(identifier: "mapkit", sourceType: .local, category: .local)
        await mapkit.state.setStubbedResults([makeResult(id: "1", title: "Local", source: "mapkit", category: .local)])
        
        let executor = SearchToolExecutor(sources: [mapkit])
        let results = await executor.searchLocalStores(storeType: "bookstore", radiusKm: 10)
        
        XCTAssertEqual(results.count, 1)
        
        let mapkitQueries = await mapkit.state.invokedQueries
        XCTAssertEqual(mapkitQueries.count, 1)
        let query = mapkitQueries.first
        XCTAssertEqual(query?.original, "bookstore")
        XCTAssertEqual(query?.categories, ["bookstore"])
    }

    func test_searchBooks_invokesBookSources() async {
        let googlebooks = MockSearchSource(identifier: "googlebooks", sourceType: .online, category: .book)
        await googlebooks.state.setStubbedResults([makeResult(id: "1", title: "GB", source: "googlebooks", category: .book)])
        
        let openlibrary = MockSearchSource(identifier: "openlibrary", sourceType: .online, category: .book)
        
        let executor = SearchToolExecutor(sources: [googlebooks, openlibrary])
        let results = await executor.searchBooks(query: "swift programming")
        
        XCTAssertEqual(results.count, 1)
        
        let googlebooksQueries = await googlebooks.state.invokedQueries
        XCTAssertEqual(googlebooksQueries.count, 1)
        let query = googlebooksQueries.first
        XCTAssertEqual(query?.original, "swift programming")
        XCTAssertEqual(query?.productType, "book")
    }
}
