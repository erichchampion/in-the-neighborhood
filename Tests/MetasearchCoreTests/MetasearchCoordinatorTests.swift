import XCTest
@testable import MetasearchCore

// MARK: - Test helpers (thread-safe trackers used by A1 tests)

private final class OrderTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ v: String) {
        lock.lock(); defer { lock.unlock() }
        values.append(v)
    }
    func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}

private final class EmissionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func bump(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        counts[id, default: 0] += 1
    }
    func count(for id: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[id] ?? 0
    }
}

final class MetasearchCoordinatorTests: XCTestCase {
    var coordinator: MetasearchCoordinator!
    var mockSources: [MockSearchSource]!
    
    override func setUp() {
        super.setUp()
        mockSources = [
            MockSearchSource(identifier: "source1", sourceType: .local),
            MockSearchSource(identifier: "source2", sourceType: .online)
        ]
        coordinator = MetasearchCoordinator(sources: mockSources)
    }
    
    // MARK: - Phase C3: queryCategory threading

    func test_EnhancedQuery_withQueryCategory_preservesOtherFields() {
        let q = EnhancedQuery(
            original: "drill bit",
            productType: "drill",
            categories: ["hardware"],
            priceMax: 25.0,
            condition: .new
        )
        let q2 = q.withQueryCategory(.hardware)

        XCTAssertEqual(q2.original, q.original)
        XCTAssertEqual(q2.productType, q.productType)
        XCTAssertEqual(q2.categories, q.categories)
        XCTAssertEqual(q2.priceMax, q.priceMax)
        XCTAssertEqual(q2.condition, q.condition)
        XCTAssertEqual(q2.queryCategory, .hardware)
        XCTAssertNil(q.queryCategory)
    }

    func test_MetasearchCoordinator_attachesQueryCategoryFromClassifier() async {
        let recorder = MockSearchSource(identifier: "rec", sourceType: .online)
        let coord = MetasearchCoordinator(sources: [recorder])
        let query = EnhancedQuery(
            original: "wireless headphones",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        await coord.searchStreaming(query: query) { _, _ in }

        let received = await recorder.state.lastQuery
        XCTAssertEqual(received?.queryCategory, .electronics)
    }

    func test_MetasearchCoordinator_preservesPreSetQueryCategory() async {
        // If the caller already classified, the coordinator should not
        // overwrite. Lets tests inject deterministic categories.
        let recorder = MockSearchSource(identifier: "rec", sourceType: .online)
        let coord = MetasearchCoordinator(sources: [recorder])
        let query = EnhancedQuery(
            original: "wireless headphones",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil,
            queryCategory: .book
        )

        await coord.searchStreaming(query: query) { _, _ in }

        let received = await recorder.state.lastQuery
        XCTAssertEqual(received?.queryCategory, .book)
    }

    func test_MetasearchCoordinator_QueriesAllSources() async throws {
        let query = EnhancedQuery(
            original: "test query",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        let results = try await coordinator.search(query: query)
        
        // Should aggregate results from all sources
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.source == "source1" }))
        XCTAssertTrue(results.contains(where: { $0.source == "source2" }))
    }
    
    func test_MetasearchCoordinator_HandlesPartialFailures() async throws {
        let failingSource = MockSearchSource(identifier: "failing", sourceType: .online)
        await failingSource.state.setShouldThrow(true)
        
        let sources: [any SearchSource] = [mockSources[0], failingSource]
        let coordinator = MetasearchCoordinator(sources: sources)
        
        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        // Should still return results from successful sources
        let results = try await coordinator.search(query: query)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.source != "failing" })
    }
    
    func test_MetasearchCoordinator_RespectsTimeout() async throws {
        let slowSource = MockSearchSource(identifier: "slow", sourceType: .online)
        await slowSource.state.setDelay(5.0) // 5 seconds delay

        let coordinator = MetasearchCoordinator(
            sources: [slowSource],
            timeout: 1.0 // 1 second timeout
        )

        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        let startTime = Date()
        let results = try await coordinator.search(query: query)
        let elapsed = Date().timeIntervalSince(startTime)

        // Should timeout before 5 seconds
        XCTAssertLessThan(elapsed, 2.0) // Allow some buffer
        // May have empty results or partial results
        XCTAssertNotNil(results)
    }

    func test_MetasearchCoordinator_PerSourceTimeoutBudget_DropsSlowSourceKeepsFast() async throws {
        // A slow source with a tight per-source budget should be dropped quickly
        // even when the coordinator's global ceiling is very high. Fast peers still return.
        let slow = MockSearchSource(identifier: "slow", sourceType: .online, timeoutBudget: 0.1)
        await slow.state.setDelay(2.0) // 2s artificial work, well past its 0.1s budget

        let fast = MockSearchSource(identifier: "fast", sourceType: .online)
        // fast uses default 4s budget, returns ~immediately

        let coordinator = MetasearchCoordinator(
            sources: [slow, fast],
            timeout: 60.0 // generous global ceiling — per-source budget should still bind
        )

        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        let startTime = Date()
        let results = try await coordinator.search(query: query)
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsed, 1.0, "Search must complete well before slow source's 2s delay")
        XCTAssertTrue(results.contains(where: { $0.source == "fast" }), "Fast source's results must be returned")
        XCTAssertFalse(results.contains(where: { $0.source == "slow" }), "Slow source must be dropped after its 0.1s budget")
    }

    // MARK: - A1: local search runs in parallel with intelligence extraction

    func test_MetasearchCoordinator_A1_LocalEmitsBeforeSlowWebSource() async {
        // With A1, the local tier must not wait for slow web/product sources
        // to finish — it runs in parallel with Phase 1, using the raw query.
        let local = MockSearchSource(identifier: "local-fast", sourceType: .local, category: .local)
        let web = MockSearchSource(identifier: "web-slow", sourceType: .online, category: .web)
        await web.state.setDelay(0.8)

        let coordinator = MetasearchCoordinator(sources: [web, local])

        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        let order = OrderTracker()
        await coordinator.searchStreaming(query: query) { identifier, _ in
            order.append(identifier)
        }

        // Let any pending unstructured Tasks (the dedup chain) flush.
        try? await Task.sleep(nanoseconds: 200_000_000)

        let snapshot = order.snapshot()
        guard let localIndex = snapshot.firstIndex(of: "local-fast"),
              let webIndex = snapshot.firstIndex(of: "web-slow") else {
            XCTFail("Both sources must emit results. Got: \(snapshot)")
            return
        }
        XCTAssertLessThan(localIndex, webIndex, "Local must emit before slow web. Order: \(snapshot)")
    }

    func test_MetasearchCoordinator_A1_DedupsLocalAcrossRawAndRefinedPasses() async {
        // A Phase 1 product source supplies brand="Acme" → after Phase 1 the
        // refined pass fires with "Acme thing". The local source emits the
        // same SearchResult.id on both passes; dedup must collapse them.
        //
        // The product source's title shares the query word "thing" so it
        // passes the brand-relevance check added in the bike-troubleshooting
        // Phase 3 fix.
        let product = MockSearchSource(
            identifier: "prod",
            sourceType: .online,
            category: .product,
            brand: "Acme",
            title: "Acme thing"
        )
        let local = MockSearchSource(identifier: "local", sourceType: .local, category: .local)

        let coordinator = MetasearchCoordinator(sources: [product, local])

        let query = EnhancedQuery(
            original: "thing",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        let counter = EmissionCounter()
        await coordinator.searchStreaming(query: query) { identifier, results in
            guard identifier == "local" else { return }
            for r in results { counter.bump(r.id) }
        }

        // Give pending unstructured Tasks (the dedup chain) time to settle.
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(
            counter.count(for: "mock-local"),
            1,
            "Local result with the same id must be emitted exactly once across the raw and refined passes"
        )
    }

    // MARK: - Brand sanity check (bike-query troubleshooting)

    private func mkProductResult(
        title: String,
        brand: String? = nil
    ) -> SearchResult {
        var metadata: [String: AnyHashable] = [:]
        if let brand { metadata["brand"] = brand }
        return SearchResult(
            id: "x", title: title, description: nil,
            source: "test", sourceType: .online, category: .product,
            url: nil, location: nil, distance: nil,
            relevanceScore: nil, price: nil, metadata: metadata
        )
    }

    func test_intelligenceQueryWords_dropsConnectorsAndPunctuation() {
        XCTAssertEqual(
            MetasearchCoordinator.intelligenceQueryWords(from: "Bike & Tube"),
            ["bike", "tube"]
        )
        XCTAssertEqual(
            MetasearchCoordinator.intelligenceQueryWords(from: "a bike"),
            ["bike"]
        )
        XCTAssertEqual(
            MetasearchCoordinator.intelligenceQueryWords(from: ""),
            []
        )
    }

    func test_productMetadataIsRelated_acceptsTitleMatch() {
        let r = mkProductResult(title: "Bike Tube Patch Kit")
        XCTAssertTrue(MetasearchCoordinator.productMetadataIsRelated(
            r, queryWords: ["bike"], brand: nil))
    }

    func test_productMetadataIsRelated_acceptsBrandOverlapWhenTitleMisses() {
        // "Patch Kit" doesn't contain "balea", but the brand does.
        let r = mkProductResult(title: "Patch Kit", brand: "Balea")
        XCTAssertTrue(MetasearchCoordinator.productMetadataIsRelated(
            r, queryWords: ["balea"], brand: "Balea"))
    }

    func test_productMetadataIsRelated_rejectsOffTopicCienResult() {
        // The exact "Cien" symptom from debug.txt — an Open Beauty Facts
        // result that polluted a "Bike" query's refined Phase 2 local
        // query with the unrelated brand "Cien".
        let cien = mkProductResult(
            title: "Crème de douche soin douceur Cien",
            brand: "Cien"
        )
        XCTAssertFalse(MetasearchCoordinator.productMetadataIsRelated(
            cien, queryWords: ["bike"], brand: "Cien"
        ))
    }

    func test_productMetadataIsRelated_emptyQueryWords_acceptsEverything() {
        // No signal → don't filter, same opt-out semantics as the
        // Open Facts relevance filter.
        let r = mkProductResult(title: "Cocacola original", brand: "Coca-Cola")
        XCTAssertTrue(MetasearchCoordinator.productMetadataIsRelated(
            r, queryWords: [], brand: "Coca-Cola"))
    }

    func test_productMetadataIsRelated_caseInsensitive() {
        let r = mkProductResult(title: "BIKE Pump")
        XCTAssertTrue(MetasearchCoordinator.productMetadataIsRelated(
            r, queryWords: ["bike"], brand: nil))
    }

    // MARK: - Phase B: structured extraction (race fix)

    func test_PhaseB_intelligenceCommitsBeforeStage2_bookSource() async {
        // A book source emits `author: "API Author"`. After Stage 1
        // returns, the refined Phase 2 query must already carry that
        // author — the old fire-and-forget Task pattern would sometimes
        // schedule the actor write after Stage 2 had already built its
        // query from stale intelligence.
        let bookSource = MockSearchSource(
            identifier: "book-src",
            sourceType: .online,
            category: .book,
            author: "API Author"
        )
        let localSource = MockSearchSource(
            identifier: "local-src",
            sourceType: .local,
            category: .local
        )
        let coordinator = MetasearchCoordinator(
            sources: [bookSource, localSource],
            resultCache: nil
        )
        let query = EnhancedQuery(
            original: "some book",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        await coordinator.searchStreaming(query: query) { _, _ in }

        // The local source's most recent query (refined pass) must
        // include the author the book source supplied.
        let received = await localSource.state.lastQuery
        XCTAssertNotNil(received, "Local source must have been invoked at least once")
        XCTAssertTrue(
            (received?.original ?? "").contains("API Author"),
            "Refined local query must include the book-source author. Got: \(received?.original ?? "nil")"
        )
    }

    func test_PhaseB_intelligenceCommitsBeforeStage2_productSource() async {
        // A product source emits `brand: "Acme"`. The refined Phase 2
        // query should pick that brand up before the local source runs.
        //
        // The title contains a word from the query so it passes the
        // bike-Phase-3 relevance check that gates product-source brand
        // extraction. Without this, "Mock Result" (default) doesn't
        // overlap with "wireless headphones" and the brand is rejected.
        let productSource = MockSearchSource(
            identifier: "product-src",
            sourceType: .online,
            category: .product,
            brand: "Acme",
            title: "Acme wireless"
        )
        let localSource = MockSearchSource(
            identifier: "local-src",
            sourceType: .local,
            category: .local
        )
        let coordinator = MetasearchCoordinator(
            sources: [productSource, localSource],
            resultCache: nil
        )
        let query = EnhancedQuery(
            original: "wireless headphones",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        await coordinator.searchStreaming(query: query) { _, _ in }

        let received = await localSource.state.lastQuery
        XCTAssertNotNil(received)
        XCTAssertTrue(
            (received?.original ?? "").contains("Acme"),
            "Refined local query must include the product-source brand. Got: \(received?.original ?? "nil")"
        )
    }

    // MARK: - A5: IntelligenceExtractionState book-priority semantics

    func test_A5_bookSourceForceOverridesEarlierProductAuthor() async {
        // Product source got there first; book source must override.
        let state = IntelligenceExtractionState()
        await state.setAuthor("Scraped Author", force: false)
        await state.setAuthor("API Author", force: true)
        let final = await state.extractedAuthor
        XCTAssertEqual(final, "API Author")
    }

    func test_A5_productSource_doesNotOverrideEarlierBookAuthor() async {
        // Book source latches the flag; a later product source can't overwrite.
        let state = IntelligenceExtractionState()
        await state.setAuthor("API Author", force: true)
        await state.setAuthor("Scraped Author", force: false)
        let final = await state.extractedAuthor
        XCTAssertEqual(final, "API Author", "Book-source-set author must be sticky against later product writes")
    }

    func test_A5_productSource_fillsAuthorWhenNoBookSourceHasSpoken() async {
        // No book source has spoken — product source still gets to set author.
        let state = IntelligenceExtractionState()
        await state.setAuthor("Scraped Author", force: false)
        let final = await state.extractedAuthor
        XCTAssertEqual(final, "Scraped Author")
    }

    func test_A5_productSource_doesNotOverwriteItself() async {
        // First-writer-wins for product sources is preserved.
        let state = IntelligenceExtractionState()
        await state.setAuthor("First", force: false)
        await state.setAuthor("Second", force: false)
        let final = await state.extractedAuthor
        XCTAssertEqual(final, "First")
    }

    func test_A5_bookSource_overridesAnotherBookSource() async {
        // If two book sources speak, the latter wins. This is fine because
        // both are authoritative — we don't want stale info.
        let state = IntelligenceExtractionState()
        await state.setAuthor("First Book API", force: true)
        await state.setAuthor("Second Book API", force: true)
        let final = await state.extractedAuthor
        XCTAssertEqual(final, "Second Book API")
    }

    func test_A5_nilAuthorIsIgnored() async {
        let state = IntelligenceExtractionState()
        await state.setAuthor("Existing", force: false)
        await state.setAuthor(nil, force: true)
        let final = await state.extractedAuthor
        XCTAssertEqual(final, "Existing", "nil author must not overwrite")
    }

    func test_A5_brandStaysFirstWriterWins() async {
        // Brand semantics are unchanged — first writer wins regardless of
        // source category, because books don't carry brands.
        let state = IntelligenceExtractionState()
        await state.setBrand("Acme")
        await state.setBrand("Other")
        let final = await state.extractedBrand
        XCTAssertEqual(final, "Acme")
    }

    // MARK: - A3: result cache

    func test_A3_repeatedSearch_servesFromCacheAndDoesNotReinvokeSource() async throws {
        // With a cache-enabled coordinator, a second `search` for the same
        // query must short-circuit and never invoke the source again.
        let source = MockSearchSource(identifier: "cached-src", sourceType: .online)
        let coordinator = MetasearchCoordinator(
            sources: [source],
            resultCache: ResultCache(ttl: 60, maxEntries: 8)
        )
        let query = EnhancedQuery(
            original: "Sample Query",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        let first = try await coordinator.search(query: query)
        XCTAssertFalse(first.isEmpty)
        let countAfterFirst = await source.state.invocationCount
        XCTAssertEqual(countAfterFirst, 1)

        let second = try await coordinator.search(query: query)
        XCTAssertEqual(second.count, first.count, "Cached result must match the original")
        let countAfterSecond = await source.state.invocationCount
        XCTAssertEqual(countAfterSecond, 1, "Source must not be invoked again on cache hit")
    }

    func test_A3_normalizedKey_treatsWhitespaceAndCaseAsEquivalent() async throws {
        // "  On Tyranny  " and "on tyranny" should hit the same cache slot.
        let source = MockSearchSource(identifier: "n-src", sourceType: .online)
        let coordinator = MetasearchCoordinator(
            sources: [source],
            resultCache: ResultCache()
        )
        let canonical = EnhancedQuery(original: "On Tyranny", productType: nil, categories: [], priceMax: nil, condition: nil)
        let messy = EnhancedQuery(original: "  on tyranny  ", productType: nil, categories: [], priceMax: nil, condition: nil)

        _ = try await coordinator.search(query: canonical)
        _ = try await coordinator.search(query: messy)

        let invocations = await source.state.invocationCount
        XCTAssertEqual(invocations, 1, "Normalized keys must collapse trivial-difference queries to one cache slot")
    }

    func test_A3_disabledCache_alwaysInvokesSources() async throws {
        // Passing `resultCache: nil` opts out of caching entirely.
        let source = MockSearchSource(identifier: "uncached-src", sourceType: .online)
        let coordinator = MetasearchCoordinator(
            sources: [source],
            resultCache: nil
        )
        let query = EnhancedQuery(original: "anything", productType: nil, categories: [], priceMax: nil, condition: nil)

        _ = try await coordinator.search(query: query)
        _ = try await coordinator.search(query: query)

        let invocations = await source.state.invocationCount
        XCTAssertEqual(invocations, 2, "Disabled cache should not memoize")
    }

    func test_A3_clearCache_forcesNextSearchToReinvoke() async throws {
        let source = MockSearchSource(identifier: "clearable-src", sourceType: .online)
        let coordinator = MetasearchCoordinator(
            sources: [source],
            resultCache: ResultCache()
        )
        let query = EnhancedQuery(original: "q", productType: nil, categories: [], priceMax: nil, condition: nil)

        _ = try await coordinator.search(query: query)
        await coordinator.clearCache()
        _ = try await coordinator.search(query: query)

        let invocations = await source.state.invocationCount
        XCTAssertEqual(invocations, 2, "clearCache() should evict the entry so the next search re-invokes the source")
    }

    func test_MetasearchCoordinator_PerSourceTimeoutBudget_CappedByGlobalCeiling() async throws {
        // When the global `timeout` ceiling is below a source's own budget,
        // the ceiling wins — the source can't run longer than the ceiling allows.
        let source = MockSearchSource(identifier: "patient", sourceType: .online, timeoutBudget: 10.0)
        await source.state.setDelay(3.0)

        let coordinator = MetasearchCoordinator(
            sources: [source],
            timeout: 0.2 // ceiling below the source's own budget
        )

        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )

        let startTime = Date()
        _ = try await coordinator.search(query: query)
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsed, 1.0, "Global ceiling must override a source's higher budget")
    }
}
