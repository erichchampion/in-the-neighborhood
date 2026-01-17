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
}
