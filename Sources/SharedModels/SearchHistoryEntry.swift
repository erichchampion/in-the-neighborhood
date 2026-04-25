import Foundation
import SwiftData

/// A record of a user's past search query, persisted for history and suggestions.
@Model
public final class SearchHistoryEntry {
    public var id: String
    public var query: String
    public var timestamp: Date
    public var resultCount: Int

    public init(
        id: String = UUID().uuidString,
        query: String,
        timestamp: Date = .now,
        resultCount: Int = 0
    ) {
        self.id = id
        self.query = query
        self.timestamp = timestamp
        self.resultCount = resultCount
    }
}
