import Foundation

public struct EnhancedQuery: Equatable, Hashable, Sendable {
    public let original: String
    public let productType: String?
    public let categories: [String]
    public let priceMax: Double?
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
