import Foundation
import MetasearchCore

/// Protocol for LLM services that enhance search queries
/// Uses ProductMetadata (Sendable) for type-safe metadata passing
public protocol LLMService: Sendable {
    func enhanceQuery(_ query: String, metadata: ProductMetadata?) async throws -> EnhancedQuery
}

public enum LLMServiceError: Error {
    case modelUnavailable
    case modelLoadFailed(String)
    case inferenceFailed(String, reason: InferenceFailureReason? = nil)
    case invalidInput(String)
    case modelNotFound
    case modelNotLoaded
    case timeout
    
    public enum InferenceFailureReason: Sendable {
        case transientFailure
        case modelStateCorruption
        case decodingError
    }
}
