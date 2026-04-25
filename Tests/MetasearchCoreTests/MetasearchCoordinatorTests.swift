import XCTest
@testable import MetasearchCore

final class MetasearchCoordinatorTests: XCTestCase {
    var coordinator: MetasearchCoordinator!
    var mockSources: [MockSearchSource]!
    
    override func setUp() {
        super.setUp()
        mockSources = [
            MockSearchSource(identifier: "source1", sourceType: .local),
            MockSearchSource(identifier: "source2", sourceType: .online)
        ]
        coordinator = MetasearchCoordinator(sources: mockSources)
    }
    
    func test_MetasearchCoordinator_QueriesAllSources() async throws {
        let query = EnhancedQuery(
            original: "test query",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        let results = try await coordinator.search(query: query)
        
        // Should aggregate results from all sources
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.source == "source1" }))
        XCTAssertTrue(results.contains(where: { $0.source == "source2" }))
    }
    
    func test_MetasearchCoordinator_HandlesPartialFailures() async throws {
        let failingSource = MockSearchSource(identifier: "failing", sourceType: .online)
        await failingSource.state.setShouldThrow(true)
        
        let sources: [any SearchSource] = [mockSources[0], failingSource]
        let coordinator = MetasearchCoordinator(sources: sources)
        
        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        // Should still return results from successful sources
        let results = try await coordinator.search(query: query)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.source != "failing" })
    }
    
    func test_MetasearchCoordinator_RespectsTimeout() async throws {
        let slowSource = MockSearchSource(identifier: "slow", sourceType: .online)
        await slowSource.state.setDelay(5.0) // 5 seconds delay
        
        let coordinator = MetasearchCoordinator(
            sources: [slowSource],
            timeout: 1.0 // 1 second timeout
        )
        
        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        let startTime = Date()
        let results = try await coordinator.search(query: query)
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should timeout before 5 seconds
        XCTAssertLessThan(elapsed, 2.0) // Allow some buffer
        // May have empty results or partial results
        XCTAssertNotNil(results)
    }
}
