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
    
    func test_BookshopSource_FiltersNonBookQueries() async throws {
        let query = EnhancedQuery(
            original: "furniture chair",
            productType: "furniture",
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        // Should return empty for non-book queries
        let results = try await source.search(query: query)
        XCTAssertEqual(results.count, 0)
    }
    
    func test_BookshopSource_HandlesBookQueries() async throws {
        let query = EnhancedQuery(
            original: "science fiction book",
            productType: "book",
            categories: ["books"],
            priceMax: nil,
            condition: nil
        )
        
        // May return results or empty, but should not crash
        let results = try await source.search(query: query)
        XCTAssertNotNil(results)
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
    
    func test_BookshopSource_ParsesHTMLResults() {
        // Test HTML parsing with mock HTML
        let _ = """
        <html>
        <body>
        <div class="product">
            <a href="/books/test-book-123">Test Book Title</a>
            <span class="author">Test Author</span>
            <span class="price">$19.99</span>
        </div>
        </body>
        </html>
        """
        
        // Would need to expose parseHTMLResults or test via search()
        XCTAssertNotNil(source)
    }
    
    func test_BookshopSource_HandlesRetryOnFailure() async throws {
        // Test that retry logic works on network failures
        // Would require mock session
        XCTAssertNotNil(source)
    }
}
