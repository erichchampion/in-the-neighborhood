import Foundation

/// Simple circuit breaker pattern to prevent repeatedly calling failing services
public actor CircuitBreaker {
    private var failureCount: Int = 0
    private var lastFailureTime: Date?
    private let failureThreshold: Int
    private let resetTimeout: TimeInterval
    private var state: State = .closed
    
    public enum State {
        case closed    // Normal operation
        case open      // Failing, not attempting requests
        case halfOpen  // Testing if service recovered
    }
    
    public init(failureThreshold: Int = 5, resetTimeout: TimeInterval = 60.0) {
        self.failureThreshold = failureThreshold
        self.resetTimeout = resetTimeout
    }
    
    /// Check if request should be allowed
    public func canAttempt() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            // Check if enough time has passed to try again
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= resetTimeout {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }
    
    /// Record a successful request
    public func recordSuccess() {
        failureCount = 0
        state = .closed
        lastFailureTime = nil
    }
    
    /// Record a failed request
    public func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()
        
        if failureCount >= failureThreshold {
            state = .open
        }
    }
    
    /// Reset the circuit breaker
    public func reset() {
        failureCount = 0
        lastFailureTime = nil
        state = .closed
    }
}
