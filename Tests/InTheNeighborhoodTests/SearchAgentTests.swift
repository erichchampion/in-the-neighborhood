import XCTest
@testable import InTheNeighborhood
import MetasearchCore

/// Thread-safe sequence of LLM responses for mocking.
private actor MockLLMSequence {
    private var responses: [String]
    init(responses: [String]) { self.responses = responses }
    func next() -> String {
        guard !responses.isEmpty else { return #"{"action": "done"}"# }
        return responses.removeFirst()
    }
}

final class SearchAgentTests: XCTestCase {

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
    func test_oneToolCallThenDone_returnsResultsInCorrectBucket() async throws {
        let sequence = MockLLMSequence(responses: [
            #"{"action": "call_tool", "tool": "search_web", "arguments": {"query": "books"}}"#,
            #"{"action": "done"}"#
        ])
        let generate: @Sendable ([(role: String, content: String)]) async throws -> String = { _ in
            await sequence.next()
        }
        let webResults = [makeResult(id: "w1", title: "Web Result", source: "web")]
        let executor = SearchToolExecutor(
            webSearch: { (_: EnhancedQuery, _: Set<String>) async -> [SearchResult] in webResults },
            productSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] },
            localSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] }
        )
        let fallbackResult = AgentSearchResult(webResults: [], amazonResults: [], localResults: [], localStoreCategories: [])
        let agent = SearchAgent(
            generateFromMessages: generate,
            toolExecutor: executor,
            classicFallback: { fallbackResult }
        )
        let result = try await agent.run(userQuery: "books", metadata: nil)
        XCTAssertEqual(result.webResults.count, 1)
        XCTAssertEqual(result.webResults[0].source, "web")
        XCTAssertTrue(result.amazonResults.isEmpty)
        XCTAssertTrue(result.localResults.isEmpty)
    }

    @MainActor
    func test_doneOnFirstTurn_returnsImmediatelyWithEmptyResults() async throws {
        let sequence = MockLLMSequence(responses: [#"{"action": "done"}"#])
        let generate: @Sendable ([(role: String, content: String)]) async throws -> String = { _ in
            await sequence.next()
        }
        let executor = SearchToolExecutor(
            webSearch: { (_: EnhancedQuery, _: Set<String>) async -> [SearchResult] in [] },
            productSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] },
            localSearch: { (_: EnhancedQuery) async -> [SearchResult] in [] }
        )
        let fallbackResult = AgentSearchResult(webResults: [], amazonResults: [], localResults: [], localStoreCategories: [])
        let agent = SearchAgent(
            generateFromMessages: generate,
            toolExecutor: executor,
            classicFallback: { fallbackResult }
        )
        let result = try await agent.run(userQuery: "books", metadata: nil)
        XCTAssertTrue(result.webResults.isEmpty)
        XCTAssertTrue(result.amazonResults.isEmpty)
        XCTAssertTrue(result.localResults.isEmpty)
    }

    @MainActor
    func test_invalidJSONTwice_fallsBackToClassicSearch() async throws {
        let sequence = MockLLMSequence(responses: ["not valid json", "not valid json"])
        let generate: @Sendable ([(role: String, content: String)]) async throws -> String = { _ in
            await sequence.next()
        }
        let executor = SearchToolExecutor(
            webSearch: { _, _ in [] },
            productSearch: { _ in [] },
            localSearch: { _ in [] }
        )
        let fallbackWeb = makeResult(id: "f1", title: "Fallback", source: "fallback")
        let fallbackResult = AgentSearchResult(
            webResults: [fallbackWeb],
            amazonResults: [],
            localResults: [],
            localStoreCategories: []
        )
        let agent = SearchAgent(
            generateFromMessages: generate,
            toolExecutor: executor,
            classicFallback: { fallbackResult }
        )
        let result = try await agent.run(userQuery: "books", metadata: nil)
        XCTAssertEqual(result.webResults.count, 1)
        XCTAssertEqual(result.webResults[0].id, "f1")
    }

    @MainActor
    func test_threeToolCallsThenDone_accumulatesAllBuckets() async throws {
        let sequence = MockLLMSequence(responses: [
            #"{"action": "call_tool", "tool": "search_web", "arguments": {"query": "books"}}"#,
            #"{"action": "call_tool", "tool": "search_products", "arguments": {"query": "books"}}"#,
            #"{"action": "call_tool", "tool": "search_local_stores", "arguments": {"query": "books", "categories": ["bookstore"]}}"#,
            #"{"action": "done"}"#
        ])
        let generate: @Sendable ([(role: String, content: String)]) async throws -> String = { _ in
            await sequence.next()
        }
        let webR = [makeResult(id: "w1", title: "Web", source: "web")]
        let productR = [makeResult(id: "p1", title: "Product", source: "amazon")]
        let localR = [makeResult(id: "l1", title: "Store", source: "mapkit")]
        let executor = SearchToolExecutor(
            webSearch: { (_: EnhancedQuery, _: Set<String>) async -> [SearchResult] in webR },
            productSearch: { (_: EnhancedQuery) async -> [SearchResult] in productR },
            localSearch: { (_: EnhancedQuery) async -> [SearchResult] in localR }
        )
        let fallbackResult = AgentSearchResult(webResults: [], amazonResults: [], localResults: [], localStoreCategories: [])
        let agent = SearchAgent(
            generateFromMessages: generate,
            toolExecutor: executor,
            classicFallback: { fallbackResult }
        )
        let result = try await agent.run(userQuery: "books", metadata: nil)
        XCTAssertEqual(result.webResults.count, 1)
        XCTAssertEqual(result.webResults[0].source, "web")
        XCTAssertEqual(result.amazonResults.count, 1)
        XCTAssertEqual(result.amazonResults[0].source, "amazon")
        XCTAssertEqual(result.localResults.count, 1)
        XCTAssertEqual(result.localResults[0].source, "mapkit")
        XCTAssertEqual(result.localStoreCategories, ["bookstore"])
    }
}
