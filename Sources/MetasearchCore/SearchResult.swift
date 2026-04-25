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
        self.metadata = metadata
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

// Note: Using @unchecked Sendable because metadata contains AnyHashable which can hold non-Sendable types
// In practice, we ensure only Sendable types (String, Int, Double, Bool) are stored in metadata
extension SearchResult: @unchecked Sendable {}
