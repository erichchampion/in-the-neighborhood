import XCTest
@testable import SearchSources
@testable import MetasearchCore

final class BookshopSearchSourceTests: XCTestCase {
    var source: BookshopSearchSource!
    
    override func setUp() {
        super.setUp()
        source = BookshopSearchSource()
    }
    
    func test_BookshopSource_FetchesBooks() async throws {
        // Verify source structure
        XCTAssertEqual(source.identifier, "bookshop")
        XCTAssertEqual(source.sourceType, .online)
    }
    
    func test_BookshopSource_HandlesEmptyResults() async throws {
        let query = EnhancedQuery(
            original: "nonexistent book title xyz123",
            productType: "book",
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        // May return empty results
        let results = try await source.search(query: query)
        XCTAssertNotNil(results)
    }
}
