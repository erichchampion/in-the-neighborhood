import Foundation

public actor MetasearchCoordinator {
    private let sources: [any SearchSource]
    private let timeout: TimeInterval
    private let resultAggregator: ResultAggregator
    private let resultPrioritizer: ResultPrioritizer
    private var denyListFilter: DenyListFilter
    private let ethicsScorer: EthicsScorer
    private let resultCache: ResultCache?
    private let queryClassifier: QueryClassifier

    public init(
        sources: [any SearchSource],
        timeout: TimeInterval = 60.0,
        denyListFilter: DenyListFilter = DenyListFilter(),
        ethicsScorer: EthicsScorer = EthicsScorer(),
        resultCache: ResultCache? = ResultCache(),
        queryClassifier: QueryClassifier = QueryClassifier()
    ) {
        self.sources = sources
        self.timeout = timeout
        self.resultAggregator = ResultAggregator()
        self.resultPrioritizer = ResultPrioritizer()
        self.denyListFilter = denyListFilter
        self.ethicsScorer = ethicsScorer
        self.resultCache = resultCache
        self.queryClassifier = queryClassifier
    }

    /// Attaches a classifier-derived `queryCategory` if one isn't already
    /// set on the query. Tests can pre-set the category on the input to
    /// keep classification deterministic.
    private func classifyIfNeeded(_ query: EnhancedQuery) -> EnhancedQuery {
        guard query.queryCategory == nil else { return query }
        return query.withQueryCategory(queryClassifier.classify(query.original))
    }

    /// Clear the in-memory cache (e.g. when the user explicitly wants fresh
    /// results, or in tests).
    public func clearCache() async {
        await resultCache?.clear()
    }

    public func updateDenyList(_ denyList: DenyListFilter) {
        self.denyListFilter = denyList
    }

    /// Shared source-selection logic used by both `search()` and
    /// `searchStreaming()`. Drops excluded sources, then applies the Phase C3
    /// category-affinity gate: when a classified `category` is present, a
    /// source runs only if its `categoryAffinity` is empty (general-purpose)
    /// or contains the category. A `nil` category runs everything, preserving
    /// pre-C3 coverage under uncertainty. Kept `nonisolated static` so both
    /// entry points (and tests) share one definition.
    nonisolated static func selectSources(
        _ sources: [any SearchSource],
        excluding excludingSources: Set<String>,
        category: QueryCategory?
    ) -> [any SearchSource] {
        let excludedFiltered = excludingSources.isEmpty
            ? sources
            : sources.filter { !excludingSources.contains($0.identifier) }
        guard let category else { return excludedFiltered }
        return excludedFiltered.filter {
            $0.categoryAffinity.isEmpty || $0.categoryAffinity.contains(category)
        }
    }

    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        return try await search(query: query, excludingSources: [])
    }
    
    public func search(query rawQuery: EnhancedQuery, excludingSources: Set<String>) async throws -> [SearchResult] {
        let query = classifyIfNeeded(rawQuery)
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
        let sourcesToSearch = Self.selectSources(sources, excluding: excludingSources, category: query.queryCategory)
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
                allResults.append(contentsOf: results)
            }
        }

        // Aggregate, filter, and prioritize results
        // Even if some sources failed, we return what we have
        var filteredResults = resultAggregator.filter(results: allResults, denyList: denyListFilter, scorer: ethicsScorer)
        filteredResults = resultAggregator.aggregate(results: filteredResults)
        filteredResults = resultPrioritizer.prioritize(results: filteredResults, scorer: ethicsScorer)

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
        query rawQuery: EnhancedQuery,
        excludingSources: Set<String> = [],
        excludeLocal: Bool = false,
        onResults externalOnResults: @escaping @Sendable (String, [SearchResult]) -> Void
    ) async {
        let query = classifyIfNeeded(rawQuery)

        // Phase C3: shared with the non-streaming path — drops excluded
        // sources, then gates specialty sources by category affinity.
        let sourcesToSearch = Self.selectSources(sources, excluding: excludingSources, category: query.queryCategory)

        // Capture the deny list and scorer into actor-isolated locals so the
        // @Sendable streaming callbacks below read immutable copies instead of
        // touching the actor's mutable `denyListFilter` from a nonisolated
        // context (removes the former `nonisolated(unsafe)` hazard).
        let effectiveDenyList = denyListFilter
        let effectiveScorer = ethicsScorer

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
        
        let intelligenceState = IntelligenceExtractionState()

        // Dedupes SearchResult IDs across passes so a later pass doesn't
        // re-emit results the user already saw from an earlier one. One
        // instance tracks the local raw/refined passes; a second tracks the
        // Stage 1.5 targeted online pass.
        actor SeenResultIDs {
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
        let seenLocalIds = SeenResultIDs()
        let seenOnlineIds = SeenResultIDs()

        // Stage 1: Phase 1 (web/product) AND the raw local pass run in parallel.
        // The local pass must not wait for intelligence extraction — that was the old
        // behavior and pushed the mission-critical tier to the end of the search.
        await withTaskGroup(of: Void.self) { group in
            for source in phase1Sources {
                let sourceIdentifier = source.identifier
                let sourceCategory = source.category

                let runQuery = query
                let timeoutValue = timeout
                let sourceToRun = source
                let sourceBudget = min(sourceToRun.timeoutBudget, timeoutValue)

                group.addTask {
                    // Per-source accumulator: every raw batch the source
                    // emits gets buffered here synchronously, then iterated
                    // once after the source returns. This replaces the older
                    // pattern of scheduling an unstructured
                    // `Task { await intelligenceState.setAuthor(...) }` from
                    // inside the rawResults callback — that fired-and-forgot
                    // the extraction work, so Stage 1's `waitForAll` could
                    // return before the Task had actually committed the
                    // brand/author. The refined Phase 2 query would then be
                    // built from stale intelligence (race).
                    let rawAccumulator = StreamingEmissionBuffer()
                    do {
                        try await self.withTimeout(seconds: sourceBudget) {
                            try await sourceToRun.searchStreaming(query: runQuery) { rawResults in
                                rawAccumulator.append(rawResults)

                                // Process and yield results immediately
                                var filtered = self.resultAggregator.filter(results: rawResults, denyList: effectiveDenyList, scorer: effectiveScorer)
                                filtered = self.resultAggregator.aggregate(results: filtered)

                                if !filtered.isEmpty {
                                    onResults(sourceIdentifier, filtered)
                                }
                            }
                        }
                    } catch {
                        // Ignore individual timeout or source failures.
                        // We still run the extraction below over whatever
                        // results the source managed to emit before failing.
                    }

                    // Structured intelligence extraction — runs *inside* the
                    // task before it returns, so the enclosing `waitForAll`
                    // on Stage 1 cannot release until the extracted
                    // brand/author have been awaited into `intelligenceState`.
                    //
                    // A5: book-category sources are authoritative for the
                    // author field (their data is structured, not scraped).
                    // Product sources fill in author only if no book source
                    // has spoken; they still own the brand field, which
                    // books don't carry.
                    let accumulated = rawAccumulator.snapshot()
                    if !accumulated.isEmpty {
                        switch sourceCategory {
                        case .book:
                            // Books stay authoritative: API book sources return
                            // structured author + ISBN metadata that we trust as-is.
                            if let author = accumulated.compactMap({ $0.metadata["author"] as? String }).first {
                                await intelligenceState.setAuthor(author, force: true)
                            }
                            if let isbn = accumulated.compactMap({ $0.metadata["isbn"] as? String })
                                .first(where: { Self.isValidISBN($0) }) {
                                await intelligenceState.setISBN(isbn, force: true)
                            }
                        case .product:
                            // Product sources (especially the Open Facts
                            // siblings) frequently return off-topic results
                            // when the query doesn't match their database.
                            // Only adopt brand/author from a product whose
                            // title shares a word with the user query OR
                            // whose brand string overlaps with the query —
                            // otherwise a "bike" search would inherit
                            // "Cien" from an Open Beauty Facts result and
                            // poison the refined local query.
                            let queryWords = Self.intelligenceQueryWords(from: query.original)
                            if let relatedForBrand = accumulated.first(where: {
                                Self.productMetadataIsRelated($0, queryWords: queryWords, brand: $0.metadata["brand"] as? String)
                            }),
                               await intelligenceState.extractedBrand == nil,
                               let brand = relatedForBrand.metadata["brand"] as? String {
                                await intelligenceState.setBrand(brand)
                            }
                            if let relatedForAuthor = accumulated.first(where: {
                                Self.productMetadataIsRelated($0, queryWords: queryWords, brand: nil)
                            }),
                               let author = relatedForAuthor.metadata["author"] as? String {
                                await intelligenceState.setAuthor(author, force: false)
                            }

                            // W3: mine structured identifiers from the same
                            // related product so Stage 1.5 can do an exact
                            // ethical-online lookup. Every field is gated by
                            // the relevance guard AND format-validated, so an
                            // off-topic or malformed code can't poison the
                            // authoritative exact-lookup endpoints.
                            let relatedForIds = accumulated.first(where: {
                                Self.productMetadataIsRelated($0, queryWords: queryWords, brand: $0.metadata["brand"] as? String)
                            })
                            if let isbn = relatedForIds?.metadata["isbn"] as? String, Self.isValidISBN(isbn) {
                                await intelligenceState.setISBN(isbn, force: false)
                            }
                            if let upc = relatedForIds?.metadata["barcode"] as? String, Self.isValidUPC(upc) {
                                await intelligenceState.setUPC(upc)
                            }
                            if let model = (relatedForIds?.metadata["model"] as? String)
                                ?? (relatedForIds?.metadata["sku"] as? String) {
                                await intelligenceState.setModel(model)
                            }
                            if let categoryHint = relatedForIds?.metadata["category"] as? String {
                                await intelligenceState.setCategoryHint(categoryHint)
                            }
                            // W2: if this metadata came from a deny-listed mega
                            // source, record the product title so the ethical
                            // results we surface downstream can be tagged as
                            // "alternative to <that product>".
                            if Self.megaMetadataSourceIDs.contains(sourceIdentifier),
                               let seed = relatedForIds?.title {
                                await intelligenceState.setMegaSeed(seed)
                            }
                        case .web, .local:
                            break
                        }
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
                                var filtered = self.resultAggregator.filter(results: rawResults, denyList: effectiveDenyList, scorer: effectiveScorer)
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

        // Stage 1.5: Targeted ethical-online refinement. When Phase 1 mined an
        // exact identifier from the deny-listed scrapers / Open Facts, re-run
        // the ethical online source that can use it — Open Library for an ISBN,
        // the Open Facts siblings for a UPC/EAN — with an identifier-bearing
        // query. This turns a brittle free-text guess into an exact lookup on
        // values extracted "behind the scenes", the core mission payoff. Gated:
        // it issues zero extra network calls when no identifier was extracted
        // or no matching source survived the category gate.
        let identifiers = await intelligenceState.snapshot()
        // When the identifiers were seeded by a deny-listed mega source, the
        // ethical results below are genuine alternatives to that product —
        // tag them so the UI can say "ethical alternative to <X>".
        let megaSeed = identifiers.megaSeedTitle
        if identifiers.hasOnlineIdentifier {
            let refinedOnlineQuery = query.withIdentifiers(
                isbn: identifiers.isbn,
                upcEan: identifiers.upcEan,
                model: identifiers.model
            )
            let targetedSources = phase1Sources.filter { source in
                (identifiers.isbn != nil && source.identifier == SourceIdentifier.openlibrary) ||
                (identifiers.upcEan != nil && Self.openFactsSourceIDs.contains(source.identifier))
            }
            if !targetedSources.isEmpty {
                await withTaskGroup(of: Void.self) { group in
                    for source in targetedSources {
                        let sourceIdentifier = source.identifier
                        let sourceToRun = source
                        let sourceBudget = min(sourceToRun.timeoutBudget, timeout)
                        group.addTask {
                            do {
                                try await self.withTimeout(seconds: sourceBudget) {
                                    try await sourceToRun.searchStreaming(query: refinedOnlineQuery) { rawResults in
                                        var filtered = self.resultAggregator.filter(results: rawResults, denyList: effectiveDenyList, scorer: effectiveScorer)
                                        filtered = self.resultAggregator.aggregate(results: filtered)
                                        if !filtered.isEmpty {
                                            Task {
                                                let fresh = await seenOnlineIds.filterAndTrack(filtered)
                                                if !fresh.isEmpty {
                                                    onResults(sourceIdentifier, Self.tagAlternatives(fresh, seed: megaSeed))
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
            }
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
                                var filtered = self.resultAggregator.filter(results: rawResults, denyList: effectiveDenyList, scorer: effectiveScorer)
                                filtered = self.resultAggregator.aggregate(results: filtered)
                                if !filtered.isEmpty {
                                    Task {
                                        let fresh = await seenLocalIds.filterAndTrack(filtered)
                                        if !fresh.isEmpty {
                                            onResults(sourceIdentifier, Self.tagAlternatives(fresh, seed: megaSeed))
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

    /// Splits a user query into comparison-ready words ≥ 3 chars,
    /// stripping case and punctuation. Mirrors
    /// `OpenFactsSearchSource.queryWords(from:)` and is similarly
    /// `nonisolated` for testability.
    nonisolated static func intelligenceQueryWords(from query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    /// `true` when the product result has a plausible connection to
    /// the user's query: either its title shares a word with the
    /// query, or the brand string itself overlaps with the query.
    /// Used to gate Phase 1 intelligence extraction — without this,
    /// off-topic Open Facts results poison the refined Phase 2 query
    /// (the "Cien Bike" symptom).
    ///
    /// An empty `queryWords` array means "no signal to filter on" —
    /// fall back to letting everything through, same opt-out
    /// behavior as `OpenFactsSearchSource.isRelevant`.
    nonisolated static func productMetadataIsRelated(
        _ result: SearchResult,
        queryWords: [String],
        brand: String?
    ) -> Bool {
        guard !queryWords.isEmpty else { return true }
        let titleLower = result.title.lowercased()
        if queryWords.contains(where: { titleLower.contains($0) }) {
            return true
        }
        if let brand, !brand.isEmpty {
            let brandLower = brand.lowercased()
            if queryWords.contains(where: { brandLower.contains($0) }) {
                return true
            }
        }
        return false
    }

    /// `true` if `raw` is a syntactically valid ISBN-10 or ISBN-13 once
    /// hyphens/spaces are stripped (ISBN-10 may end in `X`). Gates ISBN
    /// extraction so a malformed value can't drive the exact Open Library
    /// `isbn:` lookup.
    nonisolated static func isValidISBN(_ raw: String) -> Bool {
        let stripped = raw.filter { $0.isNumber || $0 == "X" || $0 == "x" }
        switch stripped.count {
        case 10: return stripped.dropLast().allSatisfy(\.isNumber)
        case 13: return stripped.allSatisfy(\.isNumber)
        default: return false
        }
    }

    /// `true` if `raw` is a plausible GTIN/UPC/EAN — all digits after
    /// stripping spaces/hyphens, length in the GTIN family (8/12/13/14).
    /// Gates UPC extraction so a malformed code can't drive the exact
    /// Open Facts `/product/<code>.json` lookup.
    nonisolated static func isValidUPC(_ raw: String) -> Bool {
        let stripped = raw.filter { $0 != " " && $0 != "-" }
        guard stripped.allSatisfy(\.isNumber) else { return false }
        return [8, 12, 13, 14].contains(stripped.count)
    }

    /// Identifiers of the four Open Facts sibling sources — the UPC/EAN
    /// exact-lookup targets for Stage 1.5.
    nonisolated static let openFactsSourceIDs: Set<String> = [
        SourceIdentifier.openfoodfacts,
        SourceIdentifier.openbeautyfacts,
        SourceIdentifier.openproductsfacts,
        SourceIdentifier.openpetfoodfacts
    ]

    /// Deny-listed sources used only for behind-the-scenes metadata. When one
    /// of these seeds the extraction, the ethical results the refined passes
    /// surface are genuine "alternatives to" that mega product.
    nonisolated static let megaMetadataSourceIDs: Set<String> = [
        SourceIdentifier.amazon,
        SourceIdentifier.bestbuy
    ]

    /// Tags each result with `ethicalAlternativeFor` when a mega seed exists,
    /// so a card can render "ethical alternative to <product>". A nil seed
    /// returns the results unchanged.
    nonisolated static func tagAlternatives(_ results: [SearchResult], seed: String?) -> [SearchResult] {
        guard let seed else { return results }
        return results.map { $0.withMetadata(["ethicalAlternativeFor": seed]) }
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
}

/// Holds brand/author intelligence extracted during Phase 1 of
/// `MetasearchCoordinator.searchStreaming`. A5: book-category sources
/// (Open Library / Google Books / Bookshop) are authoritative for the
/// `extractedAuthor` field — their author metadata is structured, not
/// scraped, and should override any author that an Amazon scraper may
/// have written earlier. Once a book source has claimed the author, the
/// `authorSetByBookSource` latch blocks any later product-source write
/// from overwriting it. Brand stays first-writer-wins because books
/// don't carry brand metadata, and the product scrapers remain the best
/// signal there.
///
/// Internal (not nested in `searchStreaming`) so the priority semantics
/// can be unit-tested directly without standing up the whole streaming
/// pipeline.
actor IntelligenceExtractionState {
    var extractedBrand: String?
    var extractedAuthor: String?
    private var authorSetByBookSource = false

    // W3: structured identifiers mined from Phase 1 results. ISBN follows
    // the same book-source-authoritative latch as author (book APIs return
    // structured ISBNs; scrapers don't). UPC/EAN and model are
    // first-writer-wins — the first related, format-valid value sticks.
    var extractedISBN: String?
    var extractedUPC: String?
    var extractedModel: String?
    var extractedCategoryHint: String?
    private var isbnSetByBookSource = false

    /// Title of the deny-listed (mega) product whose metadata seeded this
    /// extraction, if any. When set, the ethical results that the refined
    /// passes surface are genuinely "alternatives to" this product, and get
    /// tagged as such for the UI. First-writer-wins.
    var megaSeedTitle: String?

    init() {}

    func setBrand(_ brand: String?) {
        if extractedBrand == nil { extractedBrand = brand }
    }

    func setAuthor(_ author: String?) {
        if extractedAuthor == nil { extractedAuthor = author }
    }

    /// Overrides any previously-set author when `force == true`. A book
    /// source claiming the author also latches the flag so later
    /// product-source writes can't overwrite.
    func setAuthor(_ author: String?, force: Bool) {
        guard let author else { return }
        if force {
            extractedAuthor = author
            authorSetByBookSource = true
        } else if extractedAuthor == nil && !authorSetByBookSource {
            extractedAuthor = author
        }
    }

    /// Book sources latch the ISBN (`force: true`); product sources only
    /// fill it if no book source has and no ISBN is set yet.
    func setISBN(_ isbn: String?, force: Bool) {
        guard let isbn else { return }
        if force {
            extractedISBN = isbn
            isbnSetByBookSource = true
        } else if extractedISBN == nil && !isbnSetByBookSource {
            extractedISBN = isbn
        }
    }

    func setUPC(_ upc: String?) {
        guard let upc else { return }
        if extractedUPC == nil { extractedUPC = upc }
    }

    func setModel(_ model: String?) {
        guard let model else { return }
        if extractedModel == nil { extractedModel = model }
    }

    func setCategoryHint(_ hint: String?) {
        guard let hint else { return }
        if extractedCategoryHint == nil { extractedCategoryHint = hint }
    }

    func setMegaSeed(_ title: String?) {
        guard let title, !title.isEmpty else { return }
        if megaSeedTitle == nil { megaSeedTitle = title }
    }

    /// Immutable view of everything extracted so far, for building the
    /// Stage 1.5 identifier-bearing query.
    func snapshot() -> ExtractedIdentifiers {
        ExtractedIdentifiers(
            brand: extractedBrand,
            author: extractedAuthor,
            isbn: extractedISBN,
            upcEan: extractedUPC,
            model: extractedModel,
            categoryHint: extractedCategoryHint,
            megaSeedTitle: megaSeedTitle
        )
    }
}

/// Snapshot of the identifiers mined during Phase 1, used to drive the
/// targeted ethical-online lookup (Stage 1.5).
public struct ExtractedIdentifiers: Sendable, Equatable {
    public var brand: String?
    public var author: String?
    public var isbn: String?
    public var upcEan: String?
    public var model: String?
    public var categoryHint: String?
    /// Title of the mega product whose mined metadata produced these
    /// identifiers, when the seed came from a deny-listed source. nil when
    /// the metadata came only from ethical sources.
    public var megaSeedTitle: String?

    public init(
        brand: String? = nil,
        author: String? = nil,
        isbn: String? = nil,
        upcEan: String? = nil,
        model: String? = nil,
        categoryHint: String? = nil,
        megaSeedTitle: String? = nil
    ) {
        self.brand = brand
        self.author = author
        self.isbn = isbn
        self.upcEan = upcEan
        self.model = model
        self.categoryHint = categoryHint
        self.megaSeedTitle = megaSeedTitle
    }

    /// `true` when at least one identifier supports an exact ethical-online
    /// lookup (ISBN → Open Library, UPC → Open Facts). Model alone only
    /// refines free-text local search, so it doesn't count here.
    public var hasOnlineIdentifier: Bool { isbn != nil || upcEan != nil }
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
