import XCTest
@testable import SearchSources
@testable import MetasearchCore

final class MarketplaceSearchSourceTests: XCTestCase {
    var source: MarketplaceSearchSource!
    
    override func setUp() {
        super.setUp()
        source = MarketplaceSearchSource()
    }
    
    func test_MarketplaceSource_HandlesAccessLimitations() async throws {
        // Marketplaces like Craigslist and Facebook have limited/no public APIs
        // This test verifies graceful degradation
        let query = EnhancedQuery(
            original: "used bicycle",
            productType: "bicycle",
            categories: [],
            priceMax: nil,
            condition: .used
        )
        
        // Should handle gracefully even if API unavailable
        let results = try await source.search(query: query)
        XCTAssertNotNil(results)
    }
    
    func test_MarketplaceSource_Structure() {
        XCTAssertEqual(source.identifier, "marketplace")
        XCTAssertEqual(source.sourceType, .online)
    }
}
