import XCTest
@testable import MetasearchCore

final class SearchSourceProtocolTests: XCTestCase {
    
    func test_SearchSource_ProtocolRequirement() {
        // This test verifies the protocol exists and can be implemented
        let mockSource = MockSearchSource(
            identifier: "test-source",
            sourceType: .online,
            category: .web
        )
        
        XCTAssertEqual(mockSource.identifier, "test-source")
        XCTAssertEqual(mockSource.sourceType, .online)
    }
    
    func test_SearchSource_SearchMethod() async throws {
        let mockSource = MockSearchSource(
            identifier: "test-source",
            sourceType: .online,
            category: .web
        )
        
        let query = EnhancedQuery(
            original: "test query",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        let results = try await mockSource.search(query: query)
        
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.source, "test-source")
    }
}

// MARK: - Mock Search Source State

actor MockSearchSourceState {
    var shouldThrow = false
    var delay: TimeInterval = 0.0
    var invocationCount = 0
    /// The query most recently passed to `searchStreaming`. Used by e2e
    /// tests to verify that the refined Phase 2 query carries
    /// intelligence extracted from Phase 1.
    var lastQuery: EnhancedQuery?

    func setShouldThrow(_ throwError: Bool) {
        shouldThrow = throwError
    }

    func setDelay(_ d: TimeInterval) {
        delay = d
    }

    func recordInvocation() {
        invocationCount += 1
    }

    func recordQuery(_ query: EnhancedQuery) {
        lastQuery = query
    }
}

// MARK: - Mock Search Source

final class MockSearchSource: SearchSource, @unchecked Sendable {
    let identifier: String
    let sourceType: SourceType
    let category: ResultCategory
    let categoryAffinity: Set<QueryCategory>
    let state = MockSearchSourceState()
    private let customTimeoutBudget: TimeInterval?
    private let customBrand: String?
    private let customAuthor: String?
    private let customTitle: String?

    var timeoutBudget: TimeInterval {
        if let customTimeoutBudget { return customTimeoutBudget }
        switch sourceType {
        case .local:    return 2.5
        case .regional: return 4.0
        case .online:   return 4.0
        }
    }

    init(
        identifier: String,
        sourceType: SourceType,
        category: ResultCategory = .web,
        timeoutBudget: TimeInterval? = nil,
        brand: String? = nil,
        author: String? = nil,
        title: String? = nil,
        categoryAffinity: Set<QueryCategory> = []
    ) {
        self.identifier = identifier
        self.sourceType = sourceType
        self.category = category
        self.categoryAffinity = categoryAffinity
        self.customTimeoutBudget = timeoutBudget
        self.customBrand = brand
        self.customAuthor = author
        self.customTitle = title
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
        await state.recordInvocation()
        await state.recordQuery(query)

        let d = await state.delay
        if d > 0 {
            try await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
        }

        let throwsErr = await state.shouldThrow
        if throwsErr {
            throw NSError(domain: "MockError", code: 1)
        }

        await Task.yield() // Yield to allow collectors to attach
        var metadata: [String: AnyHashable] = [:]
        if let customBrand { metadata["brand"] = customBrand }
        if let customAuthor { metadata["author"] = customAuthor }
        onResults([
            SearchResult(
                id: "mock-\(identifier)",
                title: customTitle ?? "Mock Result",
                description: "Mock description",
                source: identifier,
                sourceType: sourceType,
                category: category,
                url: URL(string: "https://example.com/\(identifier)"),
                location: nil,
                distance: nil,
                metadata: metadata
            )
        ])
    }
}
