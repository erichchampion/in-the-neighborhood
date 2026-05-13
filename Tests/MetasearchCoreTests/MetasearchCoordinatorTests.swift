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

    func test_MetasearchCoordinator_PerSourceTimeoutBudget_DropsSlowSourceKeepsFast() async throws {
        // A slow source with a tight per-source budget should be dropped quickly
        // even when the coordinator's global ceiling is very high. Fast peers still return.
        let slow = MockSearchSource(identifier: "slow", sourceType: .online, timeoutBudget: 0.1)
        await slow.state.setDelay(2.0) // 2s artificial work, well past its 0.1s budget

        let fast = MockSearchSource(identifier: "fast", sourceType: .online)
        // fast uses default 4s budget, returns ~immediately

        let coordinator = MetasearchCoordinator(
            sources: [slow, fast],
            timeout: 60.0 // generous global ceiling — per-source budget should still bind
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

        XCTAssertLessThan(elapsed, 1.0, "Search must complete well before slow source's 2s delay")
        XCTAssertTrue(results.contains(where: { $0.source == "fast" }), "Fast source's results must be returned")
        XCTAssertFalse(results.contains(where: { $0.source == "slow" }), "Slow source must be dropped after its 0.1s budget")
    }

    func test_MetasearchCoordinator_PerSourceTimeoutBudget_CappedByGlobalCeiling() async throws {
        // When the global `timeout` ceiling is below a source's own budget,
        // the ceiling wins — the source can't run longer than the ceiling allows.
        let source = MockSearchSource(identifier: "patient", sourceType: .online, timeoutBudget: 10.0)
        await source.state.setDelay(3.0)

        let coordinator = MetasearchCoordinator(
            sources: [source],
            timeout: 0.2 // ceiling below the source's own budget
        )

        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        let startTime = Date()
        _ = try await coordinator.search(query: query)
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsed, 1.0, "Global ceiling must override a source's higher budget")
    }
}
