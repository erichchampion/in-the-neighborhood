import Foundation

/// Sendable metadata structure for product information
/// Used to safely pass metadata across actor boundaries in Swift 6
public struct ProductMetadata: Sendable, Equatable {
    // Product identification
    public let isbn: String?
    public let author: String?
    public let sku: String?
    public let asin: String?
    public let brand: String?
    public let artist: String?
    
    // Product details
    public let price: String?
    public let imageUrl: String?
    public let publisher: String?
    public let publishedDate: String?
    public let pageCount: String?
    public let averageRating: Double?
    public let ratingsCount: Int?
    public let buyLink: String?
    public let availability: String?
    public let ratings: Double?
    
    // Additional fields
    public let phone: String?
    public let url: String?
    public let displayUrl: String?
    public let dateLastCrawled: String?
    public let shoppingDomain: String?
    public let isShoppingResult: Bool?
    public let attribution: String?
    public let source: String?
    
    public init(
        isbn: String? = nil,
        author: String? = nil,
        sku: String? = nil,
        asin: String? = nil,
        brand: String? = nil,
        artist: String? = nil,
        price: String? = nil,
        imageUrl: String? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        pageCount: String? = nil,
        averageRating: Double? = nil,
        ratingsCount: Int? = nil,
        buyLink: String? = nil,
        availability: String? = nil,
        ratings: Double? = nil,
        phone: String? = nil,
        url: String? = nil,
        displayUrl: String? = nil,
        dateLastCrawled: String? = nil,
        shoppingDomain: String? = nil,
        isShoppingResult: Bool? = nil,
        attribution: String? = nil,
        source: String? = nil
    ) {
        self.isbn = isbn
        self.author = author
        self.sku = sku
        self.asin = asin
        self.brand = brand
        self.artist = artist
        self.price = price
        self.imageUrl = imageUrl
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.pageCount = pageCount
        self.averageRating = averageRating
        self.ratingsCount = ratingsCount
        self.buyLink = buyLink
        self.availability = availability
        self.ratings = ratings
        self.phone = phone
        self.url = url
        self.displayUrl = displayUrl
        self.dateLastCrawled = dateLastCrawled
        self.shoppingDomain = shoppingDomain
        self.isShoppingResult = isShoppingResult
        self.attribution = attribution
        self.source = source
    }
    
    /// Initialize from a dictionary (for backward compatibility)
    public init?(from dictionary: [String: AnyHashable]?) {
        guard let dict = dictionary else { return nil }
        
        self.isbn = dict["isbn"] as? String
        self.author = dict["author"] as? String
        self.sku = dict["sku"] as? String
        self.asin = dict["asin"] as? String
        self.brand = dict["brand"] as? String
        self.artist = dict["artist"] as? String
        self.price = dict["price"] as? String
        self.imageUrl = dict["imageUrl"] as? String
        self.publisher = dict["publisher"] as? String
        self.publishedDate = dict["publishedDate"] as? String
        self.pageCount = dict["pageCount"] as? String
        self.averageRating = dict["averageRating"] as? Double
        self.ratingsCount = dict["ratingsCount"] as? Int
        self.buyLink = dict["buyLink"] as? String
        self.availability = dict["availability"] as? String
        self.ratings = dict["ratings"] as? Double
        self.phone = dict["phone"] as? String
        self.url = dict["url"] as? String
        self.displayUrl = dict["displayUrl"] as? String
        self.dateLastCrawled = dict["dateLastCrawled"] as? String
        self.shoppingDomain = dict["shoppingDomain"] as? String
        self.isShoppingResult = dict["isShoppingResult"] as? Bool
        self.attribution = dict["attribution"] as? String
        self.source = dict["source"] as? String
    }
    
    /// Convert to dictionary format (for backward compatibility with SearchResult)
    public func toDictionary() -> [String: AnyHashable] {
        var dict: [String: AnyHashable] = [:]
        
        if let isbn = isbn { dict["isbn"] = isbn }
        if let author = author { dict["author"] = author }
        if let sku = sku { dict["sku"] = sku }
        if let asin = asin { dict["asin"] = asin }
        if let brand = brand { dict["brand"] = brand }
        if let artist = artist { dict["artist"] = artist }
        if let price = price { dict["price"] = price }
        if let imageUrl = imageUrl { dict["imageUrl"] = imageUrl }
        if let publisher = publisher { dict["publisher"] = publisher }
        if let publishedDate = publishedDate { dict["publishedDate"] = publishedDate }
        if let pageCount = pageCount { dict["pageCount"] = pageCount }
        if let averageRating = averageRating { dict["averageRating"] = averageRating }
        if let ratingsCount = ratingsCount { dict["ratingsCount"] = ratingsCount }
        if let buyLink = buyLink { dict["buyLink"] = buyLink }
        if let availability = availability { dict["availability"] = availability }
        if let ratings = ratings { dict["ratings"] = ratings }
        if let phone = phone { dict["phone"] = phone }
        if let url = url { dict["url"] = url }
        if let displayUrl = displayUrl { dict["displayUrl"] = displayUrl }
        if let dateLastCrawled = dateLastCrawled { dict["dateLastCrawled"] = dateLastCrawled }
        if let shoppingDomain = shoppingDomain { dict["shoppingDomain"] = shoppingDomain }
        if let isShoppingResult = isShoppingResult { dict["isShoppingResult"] = isShoppingResult }
        if let attribution = attribution { dict["attribution"] = attribution }
        if let source = source { dict["source"] = source }
        
        return dict
    }
    
    /// Check if metadata is empty (all fields are nil)
    public var isEmpty: Bool {
        return isbn == nil && author == nil && sku == nil && asin == nil &&
               brand == nil && artist == nil && price == nil && imageUrl == nil &&
               publisher == nil && publishedDate == nil && pageCount == nil &&
               averageRating == nil && ratingsCount == nil && buyLink == nil &&
               availability == nil && ratings == nil && phone == nil &&
               url == nil && displayUrl == nil && dateLastCrawled == nil &&
               shoppingDomain == nil && isShoppingResult == nil &&
               attribution == nil && source == nil
    }
}
