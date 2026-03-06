import Foundation

public actor MetasearchCoordinator {
    private let sources: [any SearchSource]
    private let timeout: TimeInterval
    private let resultAggregator: ResultAggregator
    private let resultPrioritizer: ResultPrioritizer
    private let denyListFilter: DenyListFilter
    
    public init(
        sources: [any SearchSource],
        timeout: TimeInterval = 60.0, // Increased timeout to allow Amazon scraping with series page detection to complete
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
        self.timeout = timeout
        self.resultAggregator = ResultAggregator()
        self.resultPrioritizer = ResultPrioritizer()
        self.denyListFilter = denyListFilter
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        return try await search(query: query, excludingSources: [])
    }
    
    public func search(query: EnhancedQuery, excludingSources: Set<String>) async throws -> [SearchResult] {
        // Execute searches in parallel with timeout
        // Each source is independent - failures are handled gracefully
        var allResults: [SearchResult] = []
        let sourcesToSearch = excludingSources.isEmpty ? sources : sources.filter { !excludingSources.contains($0.identifier) }
        let queryToSearch = query
        let timeoutValue = timeout
        
        try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            for i in sourcesToSearch.indices {
                let source = sourcesToSearch[i]
                group.addTask {
                    do {
                        return try await self.withTimeout(seconds: timeoutValue) {
                            try await source.search(query: queryToSearch)
                        }
                    } catch {
                        // Return empty results on timeout or error
                        // This allows other sources to continue and return results
                        // Partial failures are expected and handled gracefully
                        return []
                    }
                }
            }
            
            // Collect results from all sources, even if some failed
            for try await results in group {
                // #region agent log
                let sourceName = results.first?.source ?? "unknown"
                print("[DEBUG] MetasearchCoordinator.swift:59 - Collected results from source: \(sourceName), count: \(results.count)")
                if results.isEmpty && sourceName == "unknown" {
                    print("[DEBUG] MetasearchCoordinator.swift:59 - WARNING: Empty results with unknown source - this may indicate a timeout or error")
                }
                for result in results {
                    print("[DEBUG] MetasearchCoordinator.swift:59 - Result: source=\(result.source), title=\(result.title)")
                }
                // #endregion
                allResults.append(contentsOf: results)
            }
        }
        
        // #region agent log
        print("[DEBUG] MetasearchCoordinator.swift:66 - Before filter: total results: \(allResults.count), Amazon results: \(allResults.filter { $0.source.lowercased() == SourceIdentifier.amazon }.count)")
        // #endregion
        
        // Aggregate, filter, and prioritize results
        // Even if some sources failed, we return what we have
        var filteredResults = resultAggregator.filter(results: allResults, denyList: denyListFilter)
        
        // #region agent log
        print("[DEBUG] MetasearchCoordinator.swift:70 - After filter: total results: \(filteredResults.count), Amazon results: \(filteredResults.filter { $0.source.lowercased() == SourceIdentifier.amazon }.count)")
        // #endregion
        
        filteredResults = resultAggregator.aggregate(results: filteredResults)
        
        // #region agent log
        print("[DEBUG] MetasearchCoordinator.swift:75 - After aggregate: total results: \(filteredResults.count), Amazon results: \(filteredResults.filter { $0.source.lowercased() == SourceIdentifier.amazon }.count)")
        // #endregion
        
        filteredResults = resultPrioritizer.prioritize(results: filteredResults)
        
        // #region agent log
        print("[DEBUG] MetasearchCoordinator.swift:80 - After prioritize: total results: \(filteredResults.count), Amazon results: \(filteredResults.filter { $0.source.lowercased() == SourceIdentifier.amazon }.count)")
        // #endregion
        
        return filteredResults
    }
    
    /// Streaming variant: yields (sourceIdentifier, results) as each source completes.
    /// Applies filter and aggregate per batch; caller is responsible for merging/deduplicating across batches.
    /// Integrates the intelligence pipeline: Amazon & BestBuy are used to extract accurate brand/author metadata before yielding to MapKit.
    public func searchStreaming(
        query: EnhancedQuery,
        excludingSources: Set<String> = [],
        onResults: @escaping @Sendable (String, [SearchResult]) -> Void
    ) async {
        let sourcesToSearch = excludingSources.isEmpty ? sources : sources.filter { !excludingSources.contains($0.identifier) }
        
        // Split sources into distinct phases
        // Phase 1: Web sources and Product Intelligence sources (Amazon, BestBuy)
        let phase1Sources = sourcesToSearch.filter { $0.category != .local }
        let phase2Sources = sourcesToSearch.filter { $0.category == .local }
        
        var extractedBrand: String? = nil
        var extractedAuthor: String? = nil
        
        // Execute Phase 1
        await withTaskGroup(of: (String, ResultCategory, [SearchResult]).self) { group in
            for source in phase1Sources {
                let sourceIdentifier = source.identifier
                let sourceCategory = source.category
                
                // If the product is detected as a book, inject bookshop.org into the online query
                var effectiveQuery = query
                let isBook = query.isBook
                
                if isBook && sourceCategory != .book && sourceCategory != .local {
                    effectiveQuery = EnhancedQuery(
                        original: "\(query.original) bookshop.org",
                        productType: query.productType,
                        categories: query.categories,
                        priceMax: query.priceMax,
                        condition: query.condition
                    )
                }
                
                let runQuery = effectiveQuery
                let timeoutValue = timeout
                let sourceToRun = source
                
                group.addTask {
                    do {
                        let results = try await self.withTimeout(seconds: timeoutValue) {
                            try await sourceToRun.search(query: runQuery)
                        }
                        return (sourceIdentifier, sourceCategory, results)
                    } catch {
                        return (sourceIdentifier, sourceCategory, [])
                    }
                }
            }
            
            for await (sourceIdentifier, sourceCategory, rawResults) in group {
                // Determine if this batch contains intelligence we can use
                if (sourceCategory == .product || sourceCategory == .book) && !rawResults.isEmpty {
                    if extractedBrand == nil {
                        extractedBrand = rawResults.compactMap { $0.metadata["brand"] as? String }.first
                    }
                    if extractedAuthor == nil {
                        extractedAuthor = rawResults.compactMap { $0.metadata["author"] as? String }.first
                    }
                }
                
                var filtered = resultAggregator.filter(results: rawResults, denyList: denyListFilter)
                filtered = resultAggregator.aggregate(results: filtered)
                if !filtered.isEmpty {
                    onResults(sourceIdentifier, filtered)
                }
            }
        }
        
        // Compile MapKit query with extracted intelligence
        var originalWithIntelligence = query.original
        if let brand = extractedBrand, !originalWithIntelligence.lowercased().contains(brand.lowercased()) {
            originalWithIntelligence = "\(brand) \(originalWithIntelligence)"
        } else if let author = extractedAuthor, !originalWithIntelligence.lowercased().contains(author.lowercased()) {
            originalWithIntelligence = "\(originalWithIntelligence) \(author)"
        }
        
        // Filter out fuzzy categories before MapKit execution
        let exampleCategories = Set(["furniture store", "electronics store"])
        let categoriesToUse = query.categories.filter { !exampleCategories.contains($0.lowercased()) }
        
        let mapKitQuery = EnhancedQuery(
            original: originalWithIntelligence,
            productType: query.productType,
            categories: categoriesToUse,
            priceMax: query.priceMax,
            condition: query.condition
        )
        
        // Execute Phase 2 (Local)
        await withTaskGroup(of: (String, [SearchResult]).self) { group in
            for source in phase2Sources {
                let sourceIdentifier = source.identifier
                let timeoutValue = timeout
                group.addTask {
                    do {
                        let results = try await self.withTimeout(seconds: timeoutValue) {
                            try await source.search(query: mapKitQuery)
                        }
                        return (sourceIdentifier, results)
                    } catch {
                        return (sourceIdentifier, [])
                    }
                }
            }
            
            for await (sourceIdentifier, rawResults) in group {
                var filtered = resultAggregator.filter(results: rawResults, denyList: denyListFilter)
                filtered = resultAggregator.aggregate(results: filtered)
                if !filtered.isEmpty {
                    onResults(sourceIdentifier, filtered)
                }
            }
        }
    }
    
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    public func updateDenyList(filter: DenyListFilter) {
        // Note: This would need proper actor synchronization
        // For now, deny list is set at initialization
    }
}

private struct TimeoutError: Error {}
