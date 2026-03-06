import XCTest
import CoreLocation
@testable import MetasearchCore

final class ResultPrioritizerTests: XCTestCase {
    var prioritizer: ResultPrioritizer!
    
    override func setUp() {
        super.setUp()
        prioritizer = ResultPrioritizer()
    }
    
    func test_ResultPrioritizer_LocalBeforeOnline() {
        let localResult = SearchResult(
            id: "local-1",
            title: "Local Store",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: CLLocation(latitude: 37.7749, longitude: -122.4194),
            distance: 1000.0,
            metadata: [:]
        )
        
        let onlineResult = SearchResult(
            id: "online-1",
            title: "Online Store",
            description: nil,
            source: "websearch",
            sourceType: .online,
            category: .web,
            url: URL(string: "https://example.com"),
            location: nil,
            distance: nil,
            metadata: [:]
        )
        
        let results = [onlineResult, localResult] // Online first
        let prioritized = prioritizer.prioritize(results: results)
        
        // Local should come first
        XCTAssertEqual(prioritized.first?.sourceType, .local)
        XCTAssertEqual(prioritized.first?.id, "local-1")
    }
    
    func test_ResultPrioritizer_TierOrdering() {
        let tier1 = SearchResult(
            id: "tier1",
            title: "Local",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: CLLocation(latitude: 37.7749, longitude: -122.4194),
            distance: 500.0,
            metadata: [:]
        )
        
        let tier2 = SearchResult(
            id: "tier2",
            title: "Regional",
            description: nil,
            source: "bookshop",
            sourceType: .regional,
            category: .book,
            url: URL(string: "https://bookshop.org"),
            location: nil,
            distance: nil,
            metadata: [:]
        )
        
        let tier3 = SearchResult(
            id: "tier3",
            title: "Online",
            description: nil,
            source: "websearch",
            sourceType: .online,
            category: .web,
            url: URL(string: "https://example.com"),
            location: nil,
            distance: nil,
            metadata: [:]
        )
        
        let results = [tier3, tier1, tier2] // Mixed order
        let prioritized = prioritizer.prioritize(results: results)
        
        // Should be: local, regional, online
        XCTAssertEqual(prioritized[0].sourceType, .local)
        XCTAssertEqual(prioritized[1].sourceType, .regional)
        XCTAssertEqual(prioritized[2].sourceType, .online)
    }
    
    func test_ResultPrioritizer_SortsByDistance() {
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        
        let farResult = SearchResult(
            id: "far",
            title: "Far Store",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: location,
            distance: 5000.0, // 5km
            metadata: [:]
        )
        
        let nearResult = SearchResult(
            id: "near",
            title: "Near Store",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: location,
            distance: 500.0, // 500m
            metadata: [:]
        )
        
        let results = [farResult, nearResult]
        let prioritized = prioritizer.prioritize(results: results)
        
        // Nearer should come first
        XCTAssertEqual(prioritized.first?.id, "near")
        XCTAssertEqual(prioritized.first?.distance, 500.0)
    }
}
