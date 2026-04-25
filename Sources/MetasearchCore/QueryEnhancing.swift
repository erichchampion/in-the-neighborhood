/// Protocol for services that can enhance user queries using AI.
public protocol QueryEnhancing: Sendable {
    /// Enhances a raw user query into a structured object.
    /// - Parameter query: The raw text query from the user.
    /// - Returns: A structured `EnhancedQuery` object.
    func enhanceQuery(_ query: String) async throws -> EnhancedQuery
}
