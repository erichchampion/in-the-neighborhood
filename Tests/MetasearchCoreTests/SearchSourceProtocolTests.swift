import XCTest
@testable import MetasearchCore

final class SearchSourceProtocolTests: XCTestCase {
    
    func test_SearchSource_ProtocolRequirement() {
        // This test verifies the protocol exists and can be implemented
        let mockSource = MockSearchSource(
            identifier: "test-source",
            sourceType: .online
        )
        
        XCTAssertEqual(mockSource.identifier, "test-source")
        XCTAssertEqual(mockSource.sourceType, .online)
    }
    
    func test_SearchSource_SearchMethod() async throws {
        let mockSource = MockSearchSource(
            identifier: "test-source",
            sourceType: .online
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

// MARK: - Mock Search Source

final class MockSearchSource: SearchSource, @unchecked Sendable {
    let identifier: String
    let sourceType: SourceType
    var shouldThrow = false
    var delay: TimeInterval = 0.0
    
    init(identifier: String, sourceType: SourceType) {
        self.identifier = identifier
        self.sourceType = sourceType
    }
    
    func search(query: EnhancedQuery) async throws -> [SearchResult] {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        if shouldThrow {
            throw NSError(domain: "MockError", code: 1)
        }
        
        return [
            SearchResult(
                id: "mock-\(identifier)",
                title: "Mock Result",
                description: "Mock description",
                source: identifier,
                sourceType: sourceType,
                url: URL(string: "https://example.com/\(identifier)"),
                location: nil,
                distance: nil,
                metadata: [:]
            )
        ]
    }
}
