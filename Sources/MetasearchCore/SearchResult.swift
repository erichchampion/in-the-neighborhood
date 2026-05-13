import Foundation
@preconcurrency import CoreLocation

public struct SearchResult: Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let description: String?
    public let source: String
    public let sourceType: SourceType
    public let category: ResultCategory
    public let url: URL?
    public let location: CLLocation?
    public let distance: Double? // meters
    public let relevanceScore: Double? // 0.0 to 1.0, higher = more relevant
    public let price: String? // Display price (e.g., "$199.99", "$10-20")
    public let metadata: [String: AnyHashable]
    
    public init(
        id: String,
        title: String,
        description: String?,
        source: String,
        sourceType: SourceType,
        category: ResultCategory,
        url: URL?,
        location: CLLocation?,
        distance: Double?,
        relevanceScore: Double? = nil,
        price: String? = nil,
        metadata: [String: AnyHashable]
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.source = source
        self.sourceType = sourceType
        self.category = category
        self.url = url
        self.location = location
        self.distance = distance
        self.relevanceScore = relevanceScore
        self.price = price
        self.metadata = metadata
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }

    /// Returns a copy with the given metadata keys merged into the existing
    /// metadata dictionary. New keys overwrite existing ones with the same
    /// name. All other fields are preserved.
    public func withMetadata(_ additions: [String: AnyHashable]) -> SearchResult {
        var merged = metadata
        for (key, value) in additions { merged[key] = value }
        return SearchResult(
            id: id,
            title: title,
            description: description,
            source: source,
            sourceType: sourceType,
            category: category,
            url: url,
            location: location,
            distance: distance,
            relevanceScore: relevanceScore,
            price: price,
            metadata: merged
        )
    }
}

// Note: Using @unchecked Sendable because metadata contains AnyHashable which can hold non-Sendable types
// In practice, we ensure only Sendable types (String, Int, Double, Bool) are stored in metadata
extension SearchResult: @unchecked Sendable {}
