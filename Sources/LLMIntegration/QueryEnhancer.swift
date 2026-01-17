import Foundation
import MetasearchCore

public actor QueryEnhancer {
    private let llmService: LLMService
    
    public init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    public func enhance(query: String) async throws -> EnhancedQuery {
        let service = llmService
        do {
            return try await service.enhanceQuery(query)
        } catch {
            // Fallback to basic query without enhancement
            return EnhancedQuery(
                original: query,
                productType: nil,
                categories: [],
                priceMax: nil,
                condition: nil
            )
        }
    }
}
