import Foundation

public actor MetasearchCoordinator {
    private let sources: [any SearchSource]
    private let timeout: TimeInterval
    private let resultAggregator: ResultAggregator
    private let resultPrioritizer: ResultPrioritizer
    private nonisolated(unsafe) var denyListFilter: DenyListFilter
    private let ethicsScorer: EthicsScorer
    private let resultCache: ResultCache?

    public init(
        sources: [any SearchSource],
        timeout: TimeInterval = 60.0,
        denyListFilter: DenyListFilter = DenyListFilter(),
        ethicsScorer: EthicsScorer = EthicsScorer(),
        resultCache: ResultCache? = ResultCache()
    ) {
        self.sources = sources
        self.timeout = timeout
        self.resultAggregator = ResultAggregator()
        self.resultPrioritizer = ResultPrioritizer()
        self.denyListFilter = denyListFilter
        self.ethicsScorer = ethicsScorer
        self.resultCache = resultCache
    }

    /// Clear the in-memory cache (e.g. when the user explicitly wants fresh
    /// results, or in tests).
    public func clearCache() async {
        await resultCache?.clear()
    }

    public func updateDenyList(_ denyList: DenyListFilter) {
        self.denyListFilter = denyList
    }

    private nonisolated func getEffectiveDenyList() -> DenyListFilter {
        return denyListFilter
    }

    private nonisolated func getEthicsScorer() -> EthicsScorer {
        return ethicsScorer
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        return try await search(query: query, excludingSources: [])
    }
    
    public func search(query: EnhancedQuery, excludingSources: Set<String>) async throws -> [SearchResult] {
        // Cache hit: skip the network entirely. We key on the normalized
        // raw query string; `excludingSources` would change the result set,
        // so only cache the no-exclusions case.
        let cacheKey = ResultCache.normalizedKey(query.original)
        if excludingSources.isEmpty,
           let cache = resultCache,
           let cached = await cache.get(key: cacheKey) {
            return cached
        }

        // Execute searches in parallel with timeout
        // Each source is independent - failures are handled gracefully
        var allResults: [SearchResult] = []
        let sourcesToSearch = excludingSources.isEmpty ? sources : sources.filter { !excludingSources.contains($0.identifier) }
        let queryToSearch = query
        let timeoutValue = timeout
        
        try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            for i in sourcesToSearch.indices {
                let source = sourcesToSearch[i]
                let sourceBudget = min(source.timeoutBudget, timeoutValue)
                group.addTask {
                    do {
                        return try await self.withTimeout(seconds: sourceBudget) {
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
        var filteredResults = resultAggregator.filter(results: allResults, denyList: getEffectiveDenyList(), scorer: ethicsScorer)
        
        // #region agent log
        print("[DEBUG] MetasearchCoordinator.swift:70 - After filter: total results: \(filteredResults.count), Amazon results: \(filteredResults.filter { $0.source.lowercased() == SourceIdentifier.amazon }.count)")
        // #endregion
        
        filteredResults = resultAggregator.aggregate(results: filteredResults)
        
        // #region agent log
        print("[DEBUG] MetasearchCoordinator.swift:75 - After aggregate: total results: \(filteredResults.count), Amazon results: \(filteredResults.filter { $0.source.lowercased() == SourceIdentifier.amazon }.count)")
        // #endregion
        
        filteredResults = resultPrioritizer.prioritize(results: filteredResults, scorer: ethicsScorer)

        // #region agent log
        print("[DEBUG] MetasearchCoordinator.swift:80 - After prioritize: total results: \(filteredResults.count), Amazon results: \(filteredResults.filter { $0.source.lowercased() == SourceIdentifier.amazon }.count)")
        // #endregion

        // Populate the cache so the next identical query short-circuits.
        // Skip empty results so a transient outage doesn't poison the cache.
        if excludingSources.isEmpty, !filteredResults.isEmpty, let cache = resultCache {
            await cache.set(key: cacheKey, results: filteredResults)
        }

        return filteredResults
    }
    
    /// Streaming variant: yields (sourceIdentifier, results) as each source completes.
    /// Applies filter and aggregate per batch; caller is responsible for merging/deduplicating across batches.
    /// Integrates the intelligence pipeline: Amazon & BestBuy are used to extract accurate brand/author metadata before yielding to MapKit.
    public func searchStreaming(
        query: EnhancedQuery,
        excludingSources: Set<String> = [],
        excludeLocal: Bool = false,
        onResults externalOnResults: @escaping @Sendable (String, [SearchResult]) -> Void
    ) async {
        let sourcesToSearch = excludingSources.isEmpty ? sources : sources.filter { !excludingSources.contains($0.identifier) }

        // Split sources into distinct phases
        // Phase 1: Web sources and Product Intelligence sources (Amazon, BestBuy)
        let phase1Sources = sourcesToSearch.filter { $0.category != .local }
        let phase2Sources = excludeLocal ? [] : sourcesToSearch.filter { $0.category == .local }

        // Cache: only valid when the caller asked for the full source set.
        // Partial searches would otherwise serve a cached superset and the
        // user would see results from sources they wanted excluded.
        let cacheKey = ResultCache.normalizedKey(query.original)
        let useCache = excludingSources.isEmpty && !excludeLocal

        // Cache hit: emit grouped-by-source and return. The caller sees one
        // burst per source instead of staged emissions, which is fine
        // because the ViewModel dedupes by id on its end.
        if useCache, let cache = resultCache, let cached = await cache.get(key: cacheKey) {
            let grouped = Dictionary(grouping: cached, by: { $0.source })
            for (sourceId, results) in grouped {
                externalOnResults(sourceId, results)
            }
            return
        }

        // Cache miss: wrap onResults so every emission also lands in a
        // thread-safe buffer that we write to the cache after both stages
        // finish. The buffer is lock-based (not actor-based) so it can be
        // updated synchronously from inside the @Sendable rawResults
        // callback without scheduling another unstructured task.
        let emissionBuffer = StreamingEmissionBuffer()
        let onResults: @Sendable (String, [SearchResult]) -> Void = { sourceId, results in
            emissionBuffer.append(results)
            externalOnResults(sourceId, results)
        }
        
        // Create an actor to hold extraction state safely across tasks
        actor IntelligenceExtractionState {
            var extractedBrand: String? = nil
            var extractedAuthor: String? = nil
            func setBrand(_ brand: String?) {
                if extractedBrand == nil { extractedBrand = brand }
            }
            func setAuthor(_ author: String?) {
                if extractedAuthor == nil { extractedAuthor = author }
            }
        }
        let intelligenceState = IntelligenceExtractionState()

        // Dedupes local SearchResult IDs across the raw and refined passes so the
        // refined pass doesn't re-emit places the user already saw from the raw pass.
        actor LocalSeenIDs {
            private var ids: Set<String> = []
            func filterAndTrack(_ results: [SearchResult]) -> [SearchResult] {
                var fresh: [SearchResult] = []
                for result in results where !ids.contains(result.id) {
                    ids.insert(result.id)
                    fresh.append(result)
                }
                return fresh
            }
        }
        let seenLocalIds = LocalSeenIDs()

        // Stage 1: Phase 1 (web/product) AND the raw local pass run in parallel.
        // The local pass must not wait for intelligence extraction — that was the old
        // behavior and pushed the mission-critical tier to the end of the search.
        await withTaskGroup(of: Void.self) { group in
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
                let sourceBudget = min(sourceToRun.timeoutBudget, timeoutValue)

                group.addTask {
                    do {
                        try await self.withTimeout(seconds: sourceBudget) {
                            try await sourceToRun.searchStreaming(query: runQuery) { rawResults in
                                // Process and yield results immediately
                                var filtered = self.resultAggregator.filter(results: rawResults, denyList: self.getEffectiveDenyList(), scorer: self.getEthicsScorer())
                                filtered = self.resultAggregator.aggregate(results: filtered)

                                if !filtered.isEmpty {
                                    // Extract intelligence async if possible
                                    let currentResults = rawResults
                                    Task {
                                        if (sourceCategory == .product || sourceCategory == .book) {
                                            if await intelligenceState.extractedBrand == nil, let brand = currentResults.compactMap({ $0.metadata["brand"] as? String }).first {
                                                await intelligenceState.setBrand(brand)
                                            }
                                            if await intelligenceState.extractedAuthor == nil, let author = currentResults.compactMap({ $0.metadata["author"] as? String }).first {
                                                await intelligenceState.setAuthor(author)
                                            }
                                        }
                                    }

                                    onResults(sourceIdentifier, filtered)
                                }
                            }
                        }
                    } catch {
                        // Ignore individual timeout or source failures
                    }
                }
            }

            // Raw local pass — runs in parallel with Phase 1, uses the user's
            // unmodified query so results can appear as quickly as the source allows.
            for source in phase2Sources {
                let sourceIdentifier = source.identifier
                let timeoutValue = timeout
                let sourceToRun = source
                let sourceBudget = min(sourceToRun.timeoutBudget, timeoutValue)

                group.addTask {
                    do {
                        try await self.withTimeout(seconds: sourceBudget) {
                            try await sourceToRun.searchStreaming(query: query) { rawResults in
                                var filtered = self.resultAggregator.filter(results: rawResults, denyList: self.getEffectiveDenyList(), scorer: self.getEthicsScorer())
                                filtered = self.resultAggregator.aggregate(results: filtered)
                                if !filtered.isEmpty {
                                    Task {
                                        let fresh = await seenLocalIds.filterAndTrack(filtered)
                                        if !fresh.isEmpty {
                                            onResults(sourceIdentifier, fresh)
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        // Ignore individual timeouts/errors
                    }
                }
            }

            await group.waitForAll()
        }

        // Stage 2: Refined local pass — only worth running if Phase 1 extracted
        // brand/author intelligence that actually changes the query.
        guard !phase2Sources.isEmpty else {
            await populateCache(key: cacheKey, useCache: useCache, buffer: emissionBuffer)
            return
        }

        var originalWithIntelligence = query.original
        let finalBrand = await intelligenceState.extractedBrand
        let finalAuthor = await intelligenceState.extractedAuthor

        if let brand = finalBrand, !originalWithIntelligence.lowercased().contains(brand.lowercased()) {
            originalWithIntelligence = "\(brand) \(originalWithIntelligence)"
        } else if let author = finalAuthor, !originalWithIntelligence.lowercased().contains(author.lowercased()) {
            originalWithIntelligence = "\(originalWithIntelligence) \(author)"
        }

        // Skip the refined pass if intelligence did not change the query — it
        // would just duplicate the raw pass and waste source budget.
        guard originalWithIntelligence != query.original else {
            await populateCache(key: cacheKey, useCache: useCache, buffer: emissionBuffer)
            return
        }

        let exampleCategories = Set(["furniture store", "electronics store"])
        let categoriesToUse = query.categories.filter { !exampleCategories.contains($0.lowercased()) }

        let mapKitQuery = EnhancedQuery(
            original: originalWithIntelligence,
            productType: query.productType,
            categories: categoriesToUse,
            priceMax: query.priceMax,
            condition: query.condition
        )

        await withTaskGroup(of: Void.self) { group in
            for source in phase2Sources {
                let sourceIdentifier = source.identifier
                let timeoutValue = timeout
                let sourceToRun = source
                let sourceBudget = min(sourceToRun.timeoutBudget, timeoutValue)
                group.addTask {
                    do {
                        try await self.withTimeout(seconds: sourceBudget) {
                            try await sourceToRun.searchStreaming(query: mapKitQuery) { rawResults in
                                var filtered = self.resultAggregator.filter(results: rawResults, denyList: self.getEffectiveDenyList(), scorer: self.getEthicsScorer())
                                filtered = self.resultAggregator.aggregate(results: filtered)
                                if !filtered.isEmpty {
                                    Task {
                                        let fresh = await seenLocalIds.filterAndTrack(filtered)
                                        if !fresh.isEmpty {
                                            onResults(sourceIdentifier, fresh)
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        // Ignore individual timeouts/errors
                    }
                }
            }

            await group.waitForAll()
        }

        // Final cache write — both stages have committed everything they're
        // going to emit synchronously into the buffer.
        await populateCache(key: cacheKey, useCache: useCache, buffer: emissionBuffer)
    }

    /// Writes the buffered streaming emissions to the cache. Skips empty
    /// snapshots so a transient outage doesn't poison the cache.
    private func populateCache(key: String, useCache: Bool, buffer: StreamingEmissionBuffer) async {
        guard useCache, let cache = resultCache else { return }
        let total = buffer.snapshot()
        guard !total.isEmpty else { return }
        await cache.set(key: key, results: total)
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

/// Lock-protected accumulator for `searchStreaming`'s emissions. Used by the
/// streaming cache to capture every result handed to `onResults` so the
/// total can be written to `ResultCache` after both stages complete.
///
/// Lock-based (not actor-based) so the streaming callbacks — which are
/// synchronous `@Sendable` closures — can record emissions without
/// scheduling unstructured Tasks that might not finish before the function
/// returns. That race would cause the very next search to miss the cache.
private final class StreamingEmissionBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SearchResult] = []

    func append(_ results: [SearchResult]) {
        lock.lock(); defer { lock.unlock() }
        items.append(contentsOf: results)
    }

    func snapshot() -> [SearchResult] {
        lock.lock(); defer { lock.unlock() }
        return items
    }
}

private struct TimeoutError: Error {}
