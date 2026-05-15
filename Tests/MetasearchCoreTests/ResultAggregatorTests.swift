import XCTest
import CoreLocation
@testable import MetasearchCore

final class ResultAggregatorTests: XCTestCase {
    var aggregator: ResultAggregator!
    
    override func setUp() {
        super.setUp()
        aggregator = ResultAggregator()
    }
    
    func test_ResultAggregator_DeduplicatesResults() {
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        
        let result1 = SearchResult(
            id: "same-id",
            title: "Test Store",
            description: "Description",
            source: "source1",
            sourceType: .local,
            category: .local,
            url: URL(string: "https://example.com"),
            location: location,
            distance: 1000.0,
            metadata: [:]
        )
        
        let result2 = SearchResult(
            id: "same-id", // Same ID
            title: "Test Store",
            description: "Description",
            source: "source2",
            sourceType: .online,
            category: .web,
            url: URL(string: "https://example.com"),
            location: location,
            distance: 1000.0,
            metadata: [:]
        )
        
        let result3 = SearchResult(
            id: "different-id",
            title: "Another Store",
            description: nil,
            source: "source1",
            sourceType: .local,
            category: .local,
            url: nil,
            location: nil,
            distance: nil,
            metadata: [:]
        )
        
        let results = [result1, result2, result3]
        let aggregated = aggregator.aggregate(results: results)
        
        // Should have only 2 unique results
        XCTAssertEqual(aggregated.count, 2)
        XCTAssertTrue(aggregated.contains(where: { $0.id == "same-id" }))
        XCTAssertTrue(aggregated.contains(where: { $0.id == "different-id" }))
    }
    
    func test_ResultAggregator_CollapsesNearDuplicateLocalsAcrossSources() {
        let loc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let mapkit = SearchResult(
            id: "mapkit-1",
            title: "Joe's Bike Shop",
            description: nil,
            source: SourceIdentifier.mapkit,
            sourceType: .local,
            category: .local,
            url: nil,
            location: loc,
            distance: 0,
            metadata: [:]
        )
        let overpass = SearchResult(
            id: "overpass-1",
            title: "Joe's Bikes",
            description: nil,
            source: SourceIdentifier.overpass,
            sourceType: .local,
            category: .local,
            url: nil,
            location: loc,
            distance: 0,
            metadata: [:]
        )

        let aggregated = aggregator.aggregate(results: [mapkit, overpass])

        XCTAssertEqual(aggregated.count, 1)
        XCTAssertEqual(aggregated.first?.id, "mapkit-1")
    }

    func test_ResultAggregator_FiltersDenyList() {
        let filter = DenyListFilter(defaultDomains: ["amazon.com", "walmart.com"])
        
        let localResult = SearchResult(
            id: "local-1",
            title: "Local Store",
            description: nil,
            source: "mapkit",
            sourceType: .local,
            category: .local,
            url: nil,
            location: nil,
            distance: nil,
            metadata: [:]
        )
        
        let amazonResult = SearchResult(
            id: "amazon-1",
            title: "Amazon Product",
            description: nil,
            source: "websearch",
            sourceType: .online,
            category: .product,
            url: URL(string: "https://amazon.com/product"),
            location: nil,
            distance: nil,
            metadata: [:]
        )
        
        let walmartResult = SearchResult(
            id: "walmart-1",
            title: "Walmart Product",
            description: nil,
            source: "websearch",
            sourceType: .online,
            category: .product,
            url: URL(string: "https://walmart.com/item"),
            location: nil,
            distance: nil,
            metadata: [:]
        )
        
        let results = [localResult, amazonResult, walmartResult]
        let filtered = aggregator.filter(results: results, denyList: filter)
        
        // Should only have local result
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "local-1")
    }
}
