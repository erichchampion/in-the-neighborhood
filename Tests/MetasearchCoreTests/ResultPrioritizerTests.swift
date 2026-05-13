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
}
