import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@Generable
#endif
public struct EnhancedQuery: Equatable, Hashable, Sendable {
    
    #if canImport(FoundationModels)
    @Guide(description: "The original search query provided by the user.")
    #endif
    public let original: String
    
    #if canImport(FoundationModels)
    @Guide(description: "The core product being searched for, e.g., 'headphones', 'coffee maker'.")
    #endif
    public let productType: String?
    
    #if canImport(FoundationModels)
    @Guide(description: "Store categories that might sell this item. e.g., 'electronics', 'grocery'. Pick from: grocery, electronics, clothing, sporting goods, home goods, hardware, pharmacy, bookstore, pet supplies, auto parts, toy store, hobby shop, jewelry, office supplies, music store, sporting goods, department store.")
    #endif
    public let categories: [String]
    
    #if canImport(FoundationModels)
    @Guide(description: "The maximum price the user is willing to pay, if specified.")
    #endif
    public let priceMax: Double?
    
    #if canImport(FoundationModels)
    @Guide(description: "The desired condition of the product.")
    #endif
    public let condition: ProductCondition?
    
    public init(
        original: String,
        productType: String?,
        categories: [String],
        priceMax: Double?,
        condition: ProductCondition?
    ) {
        self.original = original
        self.productType = productType
        self.categories = categories
        self.priceMax = priceMax
        self.condition = condition
    }
}
