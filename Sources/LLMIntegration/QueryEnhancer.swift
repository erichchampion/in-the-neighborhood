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
    
    /// Determines what types of local stores would carry a given product
    /// Returns an array of store category names (e.g., ["bookstore", "furniture store"])
    public func determineStoreCategories(for productQuery: String) async -> [String] {
        let service = llmService
        
        // Try to use LLM if available
        if let llmService = service as? LlamaCppLLMService {
            do {
                return try await llmService.determineStoreTypes(for: productQuery)
            } catch {
                // Fallback to empty array if LLM fails
                return []
            }
        }
        
        // Fallback: return empty array if LLM service doesn't support this
        return []
    }
}
