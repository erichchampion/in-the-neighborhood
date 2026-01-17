import Foundation
import MetasearchCore

public protocol WebSearchProvider: Sendable {
    func search(query: String) async throws -> [SearchResult]
}
