import XCTest
@testable import SearchSources

final class CircuitBreakerTests: XCTestCase {
    func test_CircuitBreaker_StartsClosed() async {
        let breaker = CircuitBreaker()
        let canAttempt = await breaker.canAttempt()
        XCTAssertTrue(canAttempt)
    }
    
    func test_CircuitBreaker_OpensAfterThresholdFailures() async {
        let breaker = CircuitBreaker(failureThreshold: 3, resetTimeout: 1.0)
        
        // Record failures up to threshold
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        // Should still be closed (below threshold)
        let canAttempt1 = await breaker.canAttempt()
        XCTAssertTrue(canAttempt1)
        
        // Record one more failure (reaches threshold)
        await breaker.recordFailure()
        
        // Should now be open
        let canAttempt2 = await breaker.canAttempt()
        XCTAssertFalse(canAttempt2)
    }
    
    func test_CircuitBreaker_ResetsOnSuccess() async {
        let breaker = CircuitBreaker(failureThreshold: 2, resetTimeout: 1.0)
        
        // Record failures
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        // Should be open
        let canAttempt1 = await breaker.canAttempt()
        XCTAssertFalse(canAttempt1)
        
        // Record success
        await breaker.recordSuccess()
        
        // Should be closed again
        let canAttempt2 = await breaker.canAttempt()
        XCTAssertTrue(canAttempt2)
    }
    
    func test_CircuitBreaker_ResetsAfterTimeout() async throws {
        let breaker = CircuitBreaker(failureThreshold: 2, resetTimeout: 0.5)
        
        // Record failures to open circuit
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        // Should be open
        let canAttempt1 = await breaker.canAttempt()
        XCTAssertFalse(canAttempt1)
        
        // Wait for timeout
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        // Should allow attempt (half-open)
        let canAttempt2 = await breaker.canAttempt()
        XCTAssertTrue(canAttempt2)
    }
    
    func test_CircuitBreaker_ManualReset() async {
        let breaker = CircuitBreaker(failureThreshold: 2, resetTimeout: 1.0)
        
        // Record failures
        await breaker.recordFailure()
        await breaker.recordFailure()
        
        // Should be open
        let canAttempt1 = await breaker.canAttempt()
        XCTAssertFalse(canAttempt1)
        
        // Manual reset
        await breaker.reset()
        
        // Should be closed
        let canAttempt2 = await breaker.canAttempt()
        XCTAssertTrue(canAttempt2)
    }
}
