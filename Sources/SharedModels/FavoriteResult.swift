import Foundation
import SwiftData

/// A favorited online product or result the user wants to remember.
@Model
public final class FavoriteResult {
    public var id: String
    public var title: String
    public var source: String
    public var urlString: String?
    public var savedDate: Date
    /// JSON-encoded metadata dictionary (price, isbn, brand, etc.)
    public var metadataJSON: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        source: String,
        urlString: String? = nil,
        savedDate: Date = .now,
        metadataJSON: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.urlString = urlString
        self.savedDate = savedDate
        self.metadataJSON = metadataJSON
    }

    public var url: URL? {
        urlString.flatMap { URL(string: $0) }
    }

    /// Decoded metadata dictionary from JSON storage.
    public var metadata: [String: String] {
        guard let json = metadataJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }
}
