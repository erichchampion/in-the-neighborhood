import Foundation

/// Categorizes a search result into a specific bucket for UI and routing.
/// This centralizes the logic that was previously duplicated via string-matching.
public enum ResultCategory: String, Equatable, Hashable, Codable, Sendable {
    case web
    case product
    case local
    case book
}
