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
}
