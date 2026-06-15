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

    /// High-level product category produced by `QueryClassifier`.
    /// Intentionally NOT a `@Guide`-annotated field — the FoundationModel
    /// `@Generable` LLM schema should not try to populate it; that's the
    /// classifier's job and only the classifier's. nil = "no confident
    /// classification, sources should not be category-gated."
    public let queryCategory: QueryCategory?

    /// Structured product identifiers extracted from Phase 1 intelligence
    /// (deny-listed scrapers + Open Facts). These let identifier-aware
    /// sources do an exact lookup instead of a free-text search:
    /// `isbn` → Open Library `isbn:` query, `upcEan` → Open Facts exact
    /// GTIN endpoint. Like `queryCategory`, these are NOT `@Guide` fields —
    /// they're populated by the coordinator's metadata loop, never by the
    /// LLM. nil = "no identifier extracted; use free-text `original`."
    public let isbn: String?
    public let upcEan: String?
    public let model: String?

    public init(
        original: String,
        productType: String?,
        categories: [String],
        priceMax: Double?,
        condition: ProductCondition?,
        queryCategory: QueryCategory? = nil,
        isbn: String? = nil,
        upcEan: String? = nil,
        model: String? = nil
    ) {
        self.original = original
        self.productType = productType
        self.categories = categories
        self.priceMax = priceMax
        self.condition = condition
        self.queryCategory = queryCategory
        self.isbn = isbn
        self.upcEan = upcEan
        self.model = model
    }

    /// Returns a copy with `queryCategory` replaced. Mirrors
    /// `SearchResult.withMetadata(_:)`.
    public func withQueryCategory(_ category: QueryCategory?) -> EnhancedQuery {
        EnhancedQuery(
            original: original,
            productType: productType,
            categories: categories,
            priceMax: priceMax,
            condition: condition,
            queryCategory: category,
            isbn: isbn,
            upcEan: upcEan,
            model: model
        )
    }

    /// Returns a copy with structured identifiers attached. Only non-nil
    /// arguments replace the existing values, so callers can layer in one
    /// identifier without clearing the others.
    public func withIdentifiers(
        isbn: String? = nil,
        upcEan: String? = nil,
        model: String? = nil
    ) -> EnhancedQuery {
        EnhancedQuery(
            original: original,
            productType: productType,
            categories: categories,
            priceMax: priceMax,
            condition: condition,
            queryCategory: queryCategory,
            isbn: isbn ?? self.isbn,
            upcEan: upcEan ?? self.upcEan,
            model: model ?? self.model
        )
    }
}
