import Foundation

/// Bridges `@Tool` invocations from the agent to existing `SearchSource` implementations.
/// On iOS 26+ this class is driven by `AgentSearchCoordinator`.
/// On older OS versions it is not instantiated.
public final class SearchToolExecutor: @unchecked Sendable {

    private let sources: [any SearchSource]
    private let resultAggregator: ResultAggregator
    private let denyListFilter: DenyListFilter
    
    public init(
        sources: [any SearchSource],
        resultAggregator: ResultAggregator = ResultAggregator(),
        denyListFilter: DenyListFilter = DenyListFilter(defaultDomains: [
            "amazon.com",
            "walmart.com",
            "target.com",
            "homedepot.com",
            "lowes.com",
            "bestbuy.com"
        ])
    ) {
        self.sources = sources
        self.resultAggregator = resultAggregator
        self.denyListFilter = denyListFilter
    }

    // MARK: - Source Lookup Helpers

    /// Execute a search against sources matching a given identifier prefix.
    public func execute(query: EnhancedQuery, sourceIds: [String]) async -> [SearchResult] {
        var results: [SearchResult] = []
        let matchedSources = sources.filter { source in
            sourceIds.contains(where: { source.identifier.hasPrefix($0) })
        }
        await withTaskGroup(of: [SearchResult].self) { group in
            for source in matchedSources {
                group.addTask {
                    (try? await source.search(query: query)) ?? []
                }
            }
            for await batch in group {
                results.append(contentsOf: batch)
            }
        }
        
        let filtered = resultAggregator.filter(results: results, denyList: denyListFilter)
        return resultAggregator.aggregate(results: filtered)
    }

    /// Execute all sources of a given `ResultCategory`.
    public func execute(query: EnhancedQuery, category: ResultCategory) async -> [SearchResult] {
        var results: [SearchResult] = []
        let matchedSources = sources.filter { $0.category == category }
        
        await withTaskGroup(of: [SearchResult].self) { group in
            for source in matchedSources {
                group.addTask {
                    (try? await source.search(query: query)) ?? []
                }
            }
            for await batch in group {
                results.append(contentsOf: batch)
            }
        }
        
        let filtered = resultAggregator.filter(results: results, denyList: denyListFilter)
        return resultAggregator.aggregate(results: filtered)
    }

    /// Execute all sources of a given `ResultCategory` incrementally.
    public func executeStreaming(query: EnhancedQuery, category: ResultCategory, onResults: @escaping @Sendable (String, [SearchResult]) -> Void) async {
        let matchedSources = sources.filter { $0.category == category }
        
        await withTaskGroup(of: Void.self) { group in
            for source in matchedSources {
                let identifier = source.identifier
                group.addTask {
                    do {
                        try await source.searchStreaming(query: query) { rawResults in
                            // Only filter by deny list for web and local results
                            // Product results are scraped for metadata only (author, brand, etc.)
                            // and are never turned into direct shopping links, so they shouldn't be filtered
                            let finalResults: [SearchResult]
                            if category == .product {
                                finalResults = rawResults // Don't filter products
                            } else {
                                let filtered = self.resultAggregator.filter(results: rawResults, denyList: self.denyListFilter)
                                finalResults = self.resultAggregator.aggregate(results: filtered)
                            }
                            if !finalResults.isEmpty {
                                onResults(identifier, finalResults)
                            }
                        }
                    } catch {
                        // ignore error
                    }
                }
            }
            await group.waitForAll()
        }
    }

    /// Execute all sources of a given `SourceType`.
    public func execute(query: EnhancedQuery, sourceType: SourceType) async -> [SearchResult] {
        let ids = sources.filter { $0.sourceType == sourceType }.map { $0.identifier }
        return await execute(query: query, sourceIds: ids)
    }

    /// Execute web search sources.
    public func searchWeb(query: String) async -> [SearchResult] {
        let enhancedQuery = EnhancedQuery(original: query, productType: nil, categories: [], priceMax: nil, condition: nil)
        return await execute(query: enhancedQuery, category: .web)
    }

    /// Execute web search sources streaming.
    public func searchWebStreaming(query: String, onResults: @escaping @Sendable (String, [SearchResult]) -> Void) async {
        let enhancedQuery = EnhancedQuery(original: query, productType: nil, categories: [], priceMax: nil, condition: nil)
        await executeStreaming(query: enhancedQuery, category: .web, onResults: onResults)
    }

    /// Execute product search sources.
    public func searchProducts(query: String, maxPrice: Double?, condition: String?) async -> [SearchResult] {
        var productCondition: ProductCondition?
        if let cond = condition?.lowercased() {
            switch cond {
            case "used": productCondition = .used
            case "refurbished": productCondition = .refurbished
            default: productCondition = .new
            }
        }
        let enhancedQuery = EnhancedQuery(
            original: query,
            productType: nil,
            categories: ["electronics", "books", "clothing"],
            priceMax: maxPrice,
            condition: productCondition
        )
        return await execute(query: enhancedQuery, category: .product)
    }

    /// Execute product search sources streaming.
    public func searchProductsStreaming(query: String, maxPrice: Double?, condition: String?, onResults: @escaping @Sendable (String, [SearchResult]) -> Void) async {
        var productCondition: ProductCondition?
        if let cond = condition?.lowercased() {
            switch cond {
            case "used": productCondition = .used
            case "refurbished": productCondition = .refurbished
            default: productCondition = .new
            }
        }
        let enhancedQuery = EnhancedQuery(
            original: query,
            productType: nil,
            categories: ["electronics", "books", "clothing"],
            priceMax: maxPrice,
            condition: productCondition
        )
        await executeStreaming(query: enhancedQuery, category: .product, onResults: onResults)
    }

    /// Execute local store search.
    public func searchLocalStores(storeType: String, radiusKm: Double?) async -> [SearchResult] {
        let enhancedQuery = EnhancedQuery(
            original: storeType,
            productType: nil,
            categories: [storeType],
            priceMax: nil,
            condition: nil
        )
        return await execute(query: enhancedQuery, category: .local)
    }

    /// Execute local store search streaming.
    public func searchLocalStoresStreaming(storeType: String, radiusKm: Double?, onResults: @escaping @Sendable (String, [SearchResult]) -> Void) async {
        let enhancedQuery = EnhancedQuery(
            original: storeType,
            productType: nil,
            categories: [storeType],
            priceMax: nil,
            condition: nil
        )
        await executeStreaming(query: enhancedQuery, category: .local, onResults: onResults)
    }

    /// Execute book search sources.
    public func searchBooks(query: String) async -> [SearchResult] {
        let enhancedQuery = EnhancedQuery(
            original: query,
            productType: "book",
            categories: ["bookstore", "books"],
            priceMax: nil,
            condition: nil
        )
        return await execute(query: enhancedQuery, category: .book)
    }

    /// Execute book search sources streaming.
    public func searchBooksStreaming(query: String, onResults: @escaping @Sendable (String, [SearchResult]) -> Void) async {
        let enhancedQuery = EnhancedQuery(
            original: query,
            productType: "book",
            categories: ["bookstore", "books"],
            priceMax: nil,
            condition: nil
        )
        await executeStreaming(query: enhancedQuery, category: .book, onResults: onResults)
    }
}
