import XCTest
@testable import MetasearchCore
import CoreLocation

final class ResultPrioritizerTests: XCTestCase {
    var sut: ResultPrioritizer!
    
    override func setUp() {
        super.setUp()
        sut = ResultPrioritizer()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Tier Prioritization
    func testLocalResultsComeBeforeOnline() {
        // Given
        let localResult = SearchResult(
            id: "1",
            title: "Local Store",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: CLLocation(latitude: 37.7749, longitude: -122.4194),
            distance: 1000,
            relevanceScore: nil,
            metadata: [:]
        )
        
        let onlineResult = SearchResult(
            id: "2",
            title: "Online Store",
            description: nil,
            source: "amazon",
            sourceType: .online,
            category: .product,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            metadata: [:]
        )
        
        // When
        let results = sut.prioritize(results: [onlineResult, localResult])
        
        // Then
        XCTAssertEqual(results.first?.id, "1")
        XCTAssertEqual(results.last?.id, "2")
    }
    
    // MARK: - Relevance Scoring (New Feature)
    func testLocalResultsSortedByRelevanceFirstThenDistance() {
        // Given
        let localHighRelevance = SearchResult(
            id: "1",
            title: "High Relevance Local",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: CLLocation(latitude: 37.7749, longitude: -122.4194),
            distance: 5000, // 5km away
            relevanceScore: 0.9,
            metadata: [:]
        )
        
        let localLowRelevance = SearchResult(
            id: "2",
            title: "Low Relevance Local",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: CLLocation(latitude: 37.7749, longitude: -122.4194),
            distance: 1000, // 1km away (closer)
            relevanceScore: 0.3,
            metadata: [:]
        )
        
        // When
        let results = sut.prioritize(results: [localLowRelevance, localHighRelevance])
        
        // Then: Higher relevance should come first, even if further away
        XCTAssertEqual(results.first?.id, "1") // High relevance
        XCTAssertEqual(results.last?.id, "2") // Low relevance
    }
    
    func testSameRelevanceLocalResultsSortedByDistance() {
        // Given
        let closeResult = SearchResult(
            id: "1",
            title: "Close Store",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: CLLocation(latitude: 37.7749, longitude: -122.4194),
            distance: 1000,
            relevanceScore: 0.5,
            metadata: [:]
        )
        
        let farResult = SearchResult(
            id: "2",
            title: "Far Store",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: CLLocation(latitude: 37.7749, longitude: -122.4194),
            distance: 5000,
            relevanceScore: 0.5,
            metadata: [:]
        )
        
        // When
        let results = sut.prioritize(results: [farResult, closeResult])
        
        // Then: Same relevance, closer comes first
        XCTAssertEqual(results.first?.id, "1") // Closer
        XCTAssertEqual(results.last?.id, "2") // Further
    }
    
    func testOnlineResultsSortedByRelevance() {
        // Given
        let highRelevanceOnline = SearchResult(
            id: "1",
            title: "High Relevance Online",
            description: nil,
            source: "amazon",
            sourceType: .online,
            category: .product,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: 0.9,
            metadata: [:]
        )
        
        let lowRelevanceOnline = SearchResult(
            id: "2",
            title: "Low Relevance Online",
            description: nil,
            source: "amazon",
            sourceType: .online,
            category: .product,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: 0.2,
            metadata: [:]
        )
        
        // When
        let results = sut.prioritize(results: [lowRelevanceOnline, highRelevanceOnline])

        // Then
        XCTAssertEqual(results.first?.id, "1") // High relevance
        XCTAssertEqual(results.last?.id, "2") // Low relevance
    }

    // MARK: - A4: Ethics-score tiebreak within tier

    private func makeOnlineResult(id: String, host: String, relevance: Double) -> SearchResult {
        SearchResult(
            id: id,
            title: "Result \(id)",
            description: nil,
            source: "test",
            sourceType: .online,
            category: .product,
            url: URL(string: "https://\(host)/page"),
            location: nil,
            distance: nil,
            relevanceScore: relevance,
            metadata: [:]
        )
    }

    func test_A4_ethicsBeatsUnknownInSameTier() {
        // bookshop.org (b-corp, score 3) vs unknown-host.example.com (unknown,
        // score 1). With a scorer, the b-corp wins despite identical relevance.
        let scorer = EthicsScorer(ledger: EthicsLedger(version: "t", entries: [
            "bookshop.org": EthicsEntry(ownership: .bCorp)
        ]))
        let bCorp = makeOnlineResult(id: "bcorp", host: "bookshop.org", relevance: 0.5)
        let unknown = makeOnlineResult(id: "unknown", host: "example.com", relevance: 0.5)

        let results = sut.prioritize(results: [unknown, bCorp], scorer: scorer)
        XCTAssertEqual(results.first?.id, "bcorp", "B-Corp should outrank unknown in same tier with same relevance")
    }

    func test_A4_ethicsTakesPrecedenceOverRelevanceInSameTier() {
        // Per the plan: ethics is the tiebreak _between tier and relevance_,
        // so a higher ethics score wins even when relevance is slightly lower.
        let scorer = EthicsScorer(ledger: EthicsLedger(version: "t", entries: [
            "coop.example": EthicsEntry(ownership: .coop)
        ]))
        let coop = makeOnlineResult(id: "coop", host: "coop.example", relevance: 0.5)
        let unknown = makeOnlineResult(id: "unknown", host: "unknown.example", relevance: 0.9)

        let results = sut.prioritize(results: [unknown, coop], scorer: scorer)
        XCTAssertEqual(results.first?.id, "coop", "Co-op should outrank a higher-relevance unknown in the same tier")
    }

    func test_A4_relevanceUsedWhenEthicsTied() {
        // Both results unknown → ethics scores equal → fall through to relevance.
        let scorer = EthicsScorer(ledger: EthicsLedger(version: "t", entries: [:]))
        let highRel = makeOnlineResult(id: "high", host: "a.example", relevance: 0.9)
        let lowRel = makeOnlineResult(id: "low", host: "b.example", relevance: 0.3)

        let results = sut.prioritize(results: [lowRel, highRel], scorer: scorer)
        XCTAssertEqual(results.first?.id, "high")
    }

    func test_A4_noScorerLeavesExistingOrderUnchanged() {
        // Without a scorer, ranking falls through to relevance — preserves
        // backward compatibility with callers that haven't adopted A4.
        let high = makeOnlineResult(id: "high", host: "a.example", relevance: 0.9)
        let low = makeOnlineResult(id: "low", host: "b.example", relevance: 0.3)

        let results = sut.prioritize(results: [low, high]) // no scorer
        XCTAssertEqual(results.first?.id, "high")
    }
}
