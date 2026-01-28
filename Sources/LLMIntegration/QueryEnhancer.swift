import Foundation
import MetasearchCore

/// Actor that enhances search queries using LLM services
/// Uses ProductMetadata (Sendable) for type-safe metadata passing
public actor QueryEnhancer {
    private let llmService: LLMService
    
    public init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    /// Enhances a search query with product type, categories, and other structured information
    public func enhance(query: String, metadata: ProductMetadata? = nil) async throws -> EnhancedQuery {
        let service = llmService
        do {
            return try await service.enhanceQuery(query, metadata: metadata)
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
    public func determineStoreCategories(for productQuery: String, metadata: ProductMetadata? = nil) async -> [String] {
        let service = llmService
        
        // Try to use LLM if available
        if let llmService = service as? LlamaCppLLMService {
            do {
                return try await llmService.determineStoreTypes(for: productQuery, metadata: metadata)
            } catch {
                // Fallback to empty array if LLM fails
                return []
            }
        }
        
        // Fallback: return empty array if LLM service doesn't support this
        return []
    }
}
