import Foundation
import MetasearchCore

public protocol LLMService: Sendable {
    func enhanceQuery(_ query: String) async throws -> EnhancedQuery
}

public enum LLMServiceError: Error {
    case modelUnavailable
    case modelLoadFailed
    case inferenceFailed
    case timeout
}
