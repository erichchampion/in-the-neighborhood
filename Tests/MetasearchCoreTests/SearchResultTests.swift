import XCTest
@testable import MetasearchCore
import CoreLocation

final class SearchResultTests: XCTestCase {
    
    func test_SearchResult_Initialization() {
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let result = SearchResult(
            id: "test-id",
            title: "Test Store",
            description: "Test description",
            source: "mapkit",
            sourceType: .local,
            url: URL(string: "https://example.com"),
            location: location,
            distance: 1000.0,
            metadata: ["key": "value"]
        )
        
        XCTAssertEqual(result.id, "test-id")
        XCTAssertEqual(result.title, "Test Store")
        XCTAssertEqual(result.description, "Test description")
        XCTAssertEqual(result.source, "mapkit")
        XCTAssertEqual(result.sourceType, .local)
        XCTAssertEqual(result.url?.absoluteString, "https://example.com")
        XCTAssertNotNil(result.location)
        XCTAssertEqual(result.distance, 1000.0)
        XCTAssertEqual(result.metadata["key"] as? String, "value")
    }
    
    func test_SearchResult_Equality() {
        let location1 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let location2 = CLLocation(latitude: 37.7749, longitude: -122.4194)
        
        let result1 = SearchResult(
            id: "test-id",
            title: "Test Store",
            description: "Test description",
            source: "mapkit",
            sourceType: .local,
            url: URL(string: "https://example.com"),
            location: location1,
            distance: 1000.0,
            metadata: [:]
        )
        
        let result2 = SearchResult(
            id: "test-id",
            title: "Test Store",
            description: "Test description",
            source: "mapkit",
            sourceType: .local,
            url: URL(string: "https://example.com"),
            location: location2,
            distance: 1000.0,
            metadata: [:]
        )
        
        XCTAssertEqual(result1, result2)
    }
    
    func test_SearchResult_Equality_DifferentIDs() {
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        
        let result1 = SearchResult(
            id: "test-id-1",
            title: "Test Store",
            description: "Test description",
            source: "mapkit",
            sourceType: .local,
            url: nil,
            location: location,
            distance: nil,
            metadata: [:]
        )
        
        let result2 = SearchResult(
            id: "test-id-2",
            title: "Test Store",
            description: "Test description",
            source: "mapkit",
            sourceType: .local,
            url: nil,
            location: location,
            distance: nil,
            metadata: [:]
        )
        
        XCTAssertNotEqual(result1, result2)
    }
}
