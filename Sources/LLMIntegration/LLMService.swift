import Foundation
import MetasearchCore

public protocol LLMService: Sendable {
    func enhanceQuery(_ query: String) async throws -> EnhancedQuery
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
