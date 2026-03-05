import Foundation
import MetasearchCore
#if canImport(FoundationModels)
import FoundationModels
#endif

public class FoundationModelQueryEnhancer: QueryEnhancing, @unchecked Sendable {
    public init() {}
    
    public func enhanceQuery(_ query: String) async throws -> EnhancedQuery {
        print("[Intelligence] Enhancing query using FoundationModels: \(query)")
        
        #if canImport(FoundationModels)
        if #available(iOS 18.0, macOS 15.0, *) {
            do {
                let model = SystemLanguageModel.default
                if model.isAvailable {
                    let session = LanguageModelSession(model: model)
                    let prompt = "Extract search query metadata, categorizing the query: '\(query)'"
                    let response = try await session.respond(to: prompt, generating: EnhancedQuery.self)
                    return response.content
                } else {
                    print("[Intelligence] SystemLanguageModel is not available (maybe downloading or not enabled).")
                }
            } catch {
                print("[Intelligence] SystemLanguageModel session failed: \(error.localizedDescription), falling through to local parsing.")
            }
        }
        #endif
        
        // Fallback or earlier OS version
        print("[Intelligence] FoundationModels not available. Using fallback logic.")
        return createFallbackQuery(from: query)
    }
    
    private func createFallbackQuery(from query: String) -> EnhancedQuery {
        let lowercased = query.lowercased()
        
        // Basic keyword matching for fallback
        var condition: ProductCondition?
        if lowercased.contains("used") {
            condition = .used
        } else if lowercased.contains("refurbished") {
            condition = .refurbished
        } else if lowercased.contains("new") {
            condition = .new
        }
        
        // Simple price extraction fallback (e.g., "under 50")
        var priceMax: Double?
        if let underRange = lowercased.range(of: "under ") {
            let possibleNumberStr = lowercased[underRange.upperBound...].split(separator: " ").first?
                .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
            
            if let numStr = possibleNumberStr, let num = Double(numStr) {
                priceMax = num
            }
        }
        
        return EnhancedQuery(
            original: query,
            productType: nil, // Hard to reliably extract without LLM
            categories: ["electronics", "department store", "grocery"], // generic fallback
            priceMax: priceMax,
            condition: condition
        )
    }
}
