import Foundation
import MetasearchCore

/// llama.cpp-based LLM service implementation for on-device query enhancement
/// Falls back to rule-based parsing when model is not available
public actor LlamaCppLLMService: LLMService {
    private var modelLoaded = false
    private var useLLM = false  // Set to true when llama.cpp integration is complete
    
    public init() {
        // Check if model is available and trigger download if needed
        Task {
            if !LLMModelDownloadManager.shared.isModelAvailable() {
                LoggingService.shared.info(
                    "Model not found, triggering download",
                    category: "LlamaCppLLMService"
                )
                try? await LLMModelDownloadManager.shared.startDownloadIfNeeded()
            } else {
                // Model available, but llama.cpp integration not complete yet
                // Will use rule-based parsing until integration is done
                LoggingService.shared.info(
                    "Model available but llama.cpp integration pending, using rule-based parsing",
                    category: "LlamaCppLLMService"
                )
            }
        }
    }
    
    public func enhanceQuery(_ query: String) async throws -> EnhancedQuery {
        // TODO: When llama.cpp integration is complete, implement:
        // 1. Load model if not loaded
        // 2. Build query enhancement prompt
        // 3. Call llama.cpp generation
        // 4. Parse JSON response to EnhancedQuery
        
        // For now, use rule-based parsing as fallback
        return try parseQuery(query)
    }
    
    private func parseQuery(_ query: String) throws -> EnhancedQuery {
        // Basic rule-based parsing as fallback
        var productType: String?
        var categories: [String] = []
        var priceMax: Double?
        var condition: ProductCondition?
        
        let lowercased = query.lowercased()
        
        // Extract price constraint
        if let priceMatch = lowercased.range(of: #"under\s+\$?(\d+)"#, options: .regularExpression) {
            let priceString = String(query[priceMatch])
            let numbers = priceString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let price = Double(numbers) {
                priceMax = price
            }
        }
        
        // Extract condition
        if lowercased.contains("used") {
            condition = .used
        } else if lowercased.contains("new") {
            condition = .new
        } else if lowercased.contains("refurbished") {
            condition = .refurbished
        }
        
        // Simple keyword-based category detection
        if lowercased.contains("book") {
            categories.append("bookstore")
        }
        if lowercased.contains("bicycle") || lowercased.contains("bike") {
            categories.append("sporting goods")
        }
        if lowercased.contains("furniture") || lowercased.contains("chair") {
            categories.append("furniture store")
        }
        if lowercased.contains("office") {
            categories.append("office supply")
        }
        
        // Extract product type (simplified - take last noun phrase)
        let words = query.components(separatedBy: .whitespaces)
        if words.count > 1 {
            productType = words.suffix(2).joined(separator: " ")
        } else {
            productType = words.first
        }
        
        return EnhancedQuery(
            original: query,
            productType: productType,
            categories: categories,
            priceMax: priceMax,
            condition: condition
        )
    }
}
