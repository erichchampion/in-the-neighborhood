import Foundation
import MetasearchCore

/// Executes agent tool calls: search_web, search_products, search_local_stores.
/// Uses injected closures so tests can mock coordinator and sources.
public final class SearchToolExecutor: Sendable {

    public enum ExecutorError: Error, Sendable {
        case unknownTool(String)
    }

    private let webSearch: @Sendable (EnhancedQuery, Set<String>) async -> [SearchResult]
    private let productSearch: @Sendable (EnhancedQuery) async -> [SearchResult]
    private let localSearch: @Sendable (EnhancedQuery) async -> [SearchResult]

    public init(
        webSearch: @escaping @Sendable (EnhancedQuery, Set<String>) async -> [SearchResult],
        productSearch: @escaping @Sendable (EnhancedQuery) async -> [SearchResult],
        localSearch: @escaping @Sendable (EnhancedQuery) async -> [SearchResult]
    ) {
        self.webSearch = webSearch
        self.productSearch = productSearch
        self.localSearch = localSearch
    }

    /// Builds an EnhancedQuery from tool arguments (query string and optional categories).
    private func query(from arguments: [String: Any]) -> EnhancedQuery {
        let original = (arguments["query"] as? String) ?? ""
        let categories = (arguments["categories"] as? [String]) ?? []
        return EnhancedQuery(
            original: original,
            productType: nil,
            categories: categories,
            priceMax: nil,
            condition: nil
        )
    }

    /// Executes the named tool with the given arguments; returns combined results for that tool.
    public func execute(toolName: String, arguments: [String: Any]) async throws -> [SearchResult] {
        switch toolName {
        case "search_web":
            let query = query(from: arguments)
            let excluding: Set<String> = ["amazon", "mapkit", "googlebooks"]
            return await webSearch(query, excluding)
        case "search_products":
            let query = query(from: arguments)
            return await productSearch(query)
        case "search_local_stores":
            let query = query(from: arguments)
            return await localSearch(query)
        default:
            throw ExecutorError.unknownTool(toolName)
        }
    }
}
