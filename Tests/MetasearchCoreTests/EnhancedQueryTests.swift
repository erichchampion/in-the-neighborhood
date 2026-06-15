import XCTest
@testable import MetasearchCore

final class EnhancedQueryTests: XCTestCase {
    
    func test_EnhancedQuery_Initialization() {
        let query = EnhancedQuery(
            original: "ergonomic office chair under $300",
            productType: "office chair",
            categories: ["furniture store", "office supply"],
            priceMax: 300.0,
            condition: .new
        )
        
        XCTAssertEqual(query.original, "ergonomic office chair under $300")
        XCTAssertEqual(query.productType, "office chair")
        XCTAssertEqual(query.categories.count, 2)
        XCTAssertEqual(query.priceMax, 300.0)
        XCTAssertEqual(query.condition, .new)
    }
    
    func test_EnhancedQuery_WithNilValues() {
        let query = EnhancedQuery(
            original: "book",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        XCTAssertEqual(query.original, "book")
        XCTAssertNil(query.productType)
        XCTAssertTrue(query.categories.isEmpty)
        XCTAssertNil(query.priceMax)
        XCTAssertNil(query.condition)
    }
    
    func test_EnhancedQuery_Parsing() {
        let query = EnhancedQuery(
            original: "used bicycle",
            productType: "bicycle",
            categories: ["sporting goods"],
            priceMax: nil,
            condition: .used
        )

        XCTAssertEqual(query.productType, "bicycle")
        XCTAssertEqual(query.condition, .used)
    }

    // MARK: - W3: structured identifiers

    func test_withIdentifiers_attachesIdentifiersAndPreservesOtherFields() {
        let base = EnhancedQuery(
            original: "the dispossessed",
            productType: "novel",
            categories: ["bookstore"],
            priceMax: 20.0,
            condition: .new,
            queryCategory: .book
        )
        let refined = base.withIdentifiers(isbn: "9780061054884", upcEan: nil, model: "X1")

        XCTAssertEqual(refined.isbn, "9780061054884")
        XCTAssertEqual(refined.model, "X1")
        XCTAssertNil(refined.upcEan)
        // Everything else carries over untouched.
        XCTAssertEqual(refined.original, base.original)
        XCTAssertEqual(refined.productType, base.productType)
        XCTAssertEqual(refined.categories, base.categories)
        XCTAssertEqual(refined.priceMax, base.priceMax)
        XCTAssertEqual(refined.condition, base.condition)
        XCTAssertEqual(refined.queryCategory, .book)
        // Original is unmutated.
        XCTAssertNil(base.isbn)
    }

    func test_withIdentifiers_onlyReplacesNonNilArguments() {
        let base = EnhancedQuery(
            original: " q", productType: nil, categories: [], priceMax: nil, condition: nil,
            isbn: "111", upcEan: "222", model: "333"
        )
        // Passing only a new model must leave isbn/upcEan intact.
        let refined = base.withIdentifiers(model: "999")
        XCTAssertEqual(refined.isbn, "111")
        XCTAssertEqual(refined.upcEan, "222")
        XCTAssertEqual(refined.model, "999")
    }

    func test_withQueryCategory_preservesIdentifiers() {
        let base = EnhancedQuery(
            original: "q", productType: nil, categories: [], priceMax: nil, condition: nil,
            isbn: "111", upcEan: "222", model: "333"
        )
        let categorized = base.withQueryCategory(.grocery)
        XCTAssertEqual(categorized.queryCategory, .grocery)
        XCTAssertEqual(categorized.isbn, "111")
        XCTAssertEqual(categorized.upcEan, "222")
        XCTAssertEqual(categorized.model, "333")
    }
}
