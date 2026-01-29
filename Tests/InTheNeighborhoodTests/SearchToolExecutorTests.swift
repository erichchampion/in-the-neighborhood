import XCTest
@testable import InTheNeighborhood
import MetasearchCore
import CoreLocation

/// Thread-safe capture for executor callback args (tests run sequentially).
private final class Capture<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

final class SearchToolExecutorTests: XCTestCase {

    private func makeResult(id: String, title: String, source: String) -> SearchResult {
        SearchResult(
            id: id,
            title: title,
            description: nil,
            source: source,
            sourceType: .online,
            url: nil,
            location: nil,
            distance: nil,
            metadata: [:]
        )
    }

    @MainActor
    func test_executeSearchWeb_callsWebSearchWithExpectedQueryAndExcludingSources() async throws {
        let lastQuery = Capture<EnhancedQuery?>(nil)
        let lastExcluding = Capture<Set<String>?>(nil)
        let webResults = [makeResult(id: "w1", title: "Web Result", source: "web")]
        let executor = SearchToolExecutor(
            webSearch: { (query: EnhancedQuery, excluding: Set<String>) async -> [SearchResult] in
                lastQuery.value = query
                lastExcluding.value = excluding
                return webResults
            },
            productSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] },
            localSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] }
        )
        let results = try await executor.execute(toolName: "search_web", arguments: ["query": "test"])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].source, "web")
        XCTAssertEqual(lastQuery.value?.original, "test")
        XCTAssertEqual(lastExcluding.value, ["amazon", "mapkit", "googlebooks"])
    }

    @MainActor
    func test_executeSearchProducts_callsProductSearchAndReturnsCombinedResults() async throws {
        let called = Capture(false)
        let productResults = [makeResult(id: "p1", title: "Product", source: "amazon")]
        let executor = SearchToolExecutor(
            webSearch: { (_: EnhancedQuery, _: Set<String>) async -> [SearchResult] in [] },
            productSearch: { (query: EnhancedQuery) async -> [SearchResult] in
                called.value = true
                XCTAssertEqual(query.original, "book")
                return productResults
            },
            localSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] }
        )
        let results = try await executor.execute(toolName: "search_products", arguments: ["query": "book"])
        XCTAssertTrue(called.value)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].source, "amazon")
    }

    @MainActor
    func test_executeSearchLocalStores_callsLocalSearchWithCategories() async throws {
        let lastQuery = Capture<EnhancedQuery?>(nil)
        let localResults = [makeResult(id: "l1", title: "Store", source: "mapkit")]
        let executor = SearchToolExecutor(
            webSearch: { _, _ in [] },
            productSearch: { _ in [] },
            localSearch: { query in
                lastQuery.value = query
                return localResults
            }
        )
        let results = try await executor.execute(toolName: "search_local_stores", arguments: ["query": "books", "categories": ["bookstore"]])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(lastQuery.value?.original, "books")
        XCTAssertEqual(lastQuery.value?.categories, ["bookstore"])
    }

    @MainActor
    func test_unknownToolName_throws() async {
        let executor = SearchToolExecutor(
            webSearch: { (_: EnhancedQuery, _: Set<String>) async -> [SearchResult] in [] },
            productSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] },
            localSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] }
        )
        do {
            _ = try await executor.execute(toolName: "unknown_tool", arguments: [:])
            XCTFail("Expected error for unknown tool")
        } catch {
            // Expected
        }
    }
}
