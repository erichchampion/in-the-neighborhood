import Foundation
import MetasearchCore

public protocol WebSearchProvider: Sendable {
    func search(query: String) async throws -> [SearchResult]
    func searchStreaming(query: String, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws
}
