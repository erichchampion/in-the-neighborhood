import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Product information extracted by FoundationModels from raw HTML.
/// Uses `@Generable` so the on-device model can produce structured output directly.
/// Internal to `SearchSources`; converted to `AmazonProductMetadata` before leaving this module.
#if canImport(FoundationModels)
@Generable
#endif
struct ExtractedProductInfo: Sendable, Equatable {

    #if canImport(FoundationModels)
    @Guide(description: "The product name or title exactly as shown on the page.")
    #endif
    let title: String?

    #if canImport(FoundationModels)
    @Guide(description: "The manufacturer or brand name, e.g. 'Sony', 'Nike'.")
    #endif
    let brand: String?

    #if canImport(FoundationModels)
    @Guide(description: "The displayed price including currency symbol, e.g. '$29.99'.")
    #endif
    let price: String?

    #if canImport(FoundationModels)
    @Guide(description: "The ISBN for books (10 or 13 digits, may include hyphens).")
    #endif
    let isbn: String?

    #if canImport(FoundationModels)
    @Guide(description: "The SKU or model number of the product.")
    #endif
    let sku: String?

    #if canImport(FoundationModels)
    @Guide(description: "The author name for books, e.g. 'Stephen King'.")
    #endif
    let author: String?

    #if canImport(FoundationModels)
    @Guide(description: "The artist name for music or art products.")
    #endif
    let artist: String?

    #if canImport(FoundationModels)
    @Guide(description: "The ASIN (Amazon Standard Identification Number), a 10-character alphanumeric ID.")
    #endif
    let asin: String?

    #if canImport(FoundationModels)
    @Guide(description: "The star rating as a decimal, e.g. 4.5 for '4.5 out of 5 stars'.")
    #endif
    let ratings: Double?

    #if canImport(FoundationModels)
    @Guide(description: "Product availability, e.g. 'In Stock', 'Out of Stock'.")
    #endif
    let availability: String?

    #if canImport(FoundationModels)
    @Guide(description: "URL of the main product image.")
    #endif
    let imageUrl: String?

    init(
        title: String? = nil,
        brand: String? = nil,
        price: String? = nil,
        isbn: String? = nil,
        sku: String? = nil,
        author: String? = nil,
        artist: String? = nil,
        asin: String? = nil,
        ratings: Double? = nil,
        availability: String? = nil,
        imageUrl: String? = nil
    ) {
        self.title = title
        self.brand = brand
        self.price = price
        self.isbn = isbn
        self.sku = sku
        self.author = author
        self.artist = artist
        self.asin = asin
        self.ratings = ratings
        self.availability = availability
        self.imageUrl = imageUrl
    }

    /// Convert to `AmazonProductMetadata` for the existing scraping pipeline.
    func toAmazonProductMetadata() -> AmazonProductMetadata {
        AmazonProductMetadata(
            title: title,
            price: price,
            brand: brand,
            ratings: ratings,
            availability: availability,
            asin: asin,
            imageUrl: imageUrl,
            isbn: isbn,
            sku: sku,
            author: author,
            artist: artist
        )
    }
}
