import XCTest
@testable import MetasearchCore

final class ResultCacheTests: XCTestCase {
    var cache: ResultCache!
    
    override func setUp() {
        super.setUp()
        cache = ResultCache(ttl: 60) // 1 minute TTL for testing
    }
    
    func test_ResultCache_StoresAndRetrieves() async {
        let results: [SearchResult] = [
            SearchResult(
                id: "test-1",
                title: "Test",
                description: nil,
                source: "test",
                sourceType: .online,
                category: .web,
                url: nil,
                location: nil,
                distance: nil,
                metadata: [:]
            )
        ]
        
        await cache.set(key: "test-key", results: results)
        
        let retrieved = await cache.get(key: "test-key")
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.count, 1)
        XCTAssertEqual(retrieved?.first?.id, "test-1")
    }
    
    func test_ResultCache_ExpiresAfterTTL() async {
        let cache = ResultCache(ttl: 0.1) // Very short TTL

        let results: [SearchResult] = []
        await cache.set(key: "test", results: results)

        // Wait for expiration
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        let retrieved = await cache.get(key: "test")

        // Should be expired
        XCTAssertNil(retrieved)
    }

    // MARK: - A3 additions

    func test_normalizedKey_trimsAndLowercases() {
        XCTAssertEqual(ResultCache.normalizedKey("  On Tyranny  "), "on tyranny")
        XCTAssertEqual(ResultCache.normalizedKey("BOOKS"), "books")
        XCTAssertEqual(ResultCache.normalizedKey("\nhello\t"), "hello")
    }

    func test_normalizedKey_preservesInternalWhitespaceAndPunctuation() {
        // Internal whitespace is significant — "on tyranny" vs "ontyranny"
        // are genuinely different queries.
        XCTAssertEqual(ResultCache.normalizedKey("On Tyranny by Timothy Snyder"),
                       "on tyranny by timothy snyder")
        XCTAssertEqual(ResultCache.normalizedKey("isbn:9780804190114"), "isbn:9780804190114")
    }

    func test_maxEntries_evictsOldestOnOverflow() async {
        // Capacity of 2: inserting a third entry should drop the oldest.
        let cache = ResultCache(ttl: 60, maxEntries: 2)

        let mkResult: (String) -> [SearchResult] = { id in
            [SearchResult(
                id: id,
                title: id,
                description: nil,
                source: "test",
                sourceType: .online,
                category: .web,
                url: nil,
                location: nil,
                distance: nil,
                metadata: [:]
            )]
        }

        await cache.set(key: "first",  results: mkResult("first"))
        // Ensure distinct timestamps so eviction order is deterministic.
        try? await Task.sleep(nanoseconds: 20_000_000)
        await cache.set(key: "second", results: mkResult("second"))
        try? await Task.sleep(nanoseconds: 20_000_000)
        await cache.set(key: "third",  results: mkResult("third"))

        let firstCount = await cache.count
        XCTAssertEqual(firstCount, 2, "Cache should be capped at maxEntries=2")

        let first = await cache.get(key: "first")
        XCTAssertNil(first, "Oldest entry must be evicted on overflow")

        let second = await cache.get(key: "second")
        let third = await cache.get(key: "third")
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
    }

    func test_setExistingKey_doesNotTriggerEviction() async {
        // Re-setting an existing key should refresh the entry, not push the
        // cache over capacity.
        let cache = ResultCache(ttl: 60, maxEntries: 1)

        let result: [SearchResult] = [SearchResult(
            id: "1", title: "t", description: nil,
            source: "s", sourceType: .online, category: .web,
            url: nil, location: nil, distance: nil, metadata: [:]
        )]

        await cache.set(key: "k", results: result)
        await cache.set(key: "k", results: result) // same key

        let countAfter = await cache.count
        XCTAssertEqual(countAfter, 1)
        let got = await cache.get(key: "k")
        XCTAssertNotNil(got)
    }
}
