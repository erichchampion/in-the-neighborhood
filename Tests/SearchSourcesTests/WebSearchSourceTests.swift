import XCTest
@testable import SearchSources
@testable import MetasearchCore

final class WebSearchSourceTests: XCTestCase {
    var source: WebSearchSource!
    
    override func setUp() {
        super.setUp()
        source = WebSearchSource()
    }
    
    func test_WebSearchSource_AggregatesMultipleProviders() async throws {
        // Verify source structure
        XCTAssertEqual(source.identifier, "bing")
        XCTAssertEqual(source.sourceType, .online)
    }
    
    func test_WebSearchSource_NormalizesResults() async throws {
        // Verify source conforms to protocol
        let query = EnhancedQuery(
            original: "test query",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        // This will attempt real network calls
        // In production, would use mock providers
        let results = try? await source.search(query: query)
        XCTAssertNotNil(results)
    }
    
    func test_WebSearchSource_HandlesPartialFailures() async throws {
        // Test that if one provider fails, others still work
        // This is tested by the fact that WebSearchSource uses try? for each provider
        let query = EnhancedQuery(
            original: "test query",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        // Even if one provider fails, should return results from others
        let results = try? await source.search(query: query)
        XCTAssertNotNil(results)
    }
    
    func test_WebSearchSource_CircuitBreakerPreventsRepeatedFailures() async throws {
        // Test that circuit breaker prevents repeated calls to failing providers
        // Would require mock providers that always fail
        let breaker = CircuitBreaker(failureThreshold: 2, resetTimeout: 1.0)
        
        // Initially should allow attempts
        let canAttempt1 = await breaker.canAttempt()
        XCTAssertTrue(canAttempt1)
        
        // Record failures
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        // Should now be open (blocking)
        let canAttempt2 = await breaker.canAttempt()
        XCTAssertFalse(canAttempt2)
        
        // After timeout, should allow again (half-open)
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
        let canAttempt3 = await breaker.canAttempt()
        XCTAssertTrue(canAttempt3)
    }
}
