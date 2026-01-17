import XCTest
@testable import LLMIntegration
@testable import MetasearchCore

final class QueryEnhancerTests: XCTestCase {
    var enhancer: QueryEnhancer!
    var mockLLMService: MockLLMService!
    
    override func setUp() {
        super.setUp()
        mockLLMService = MockLLMService()
        enhancer = QueryEnhancer(llmService: mockLLMService)
    }
    
    func test_QueryEnhancer_ExtractsProductType() async throws {
        let query = "ergonomic office chair"
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "office chair",
            categories: ["furniture store", "office supply"],
            priceMax: nil,
            condition: nil
        )
        
        let enhanced = try await enhancer.enhance(query: query)
        
        XCTAssertEqual(enhanced.original, query)
        XCTAssertEqual(enhanced.productType, "office chair")
        XCTAssertEqual(enhanced.categories.count, 2)
    }
    
    func test_QueryEnhancer_ExtractsPriceConstraint() async throws {
        let query = "office chair under $300"
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "office chair",
            categories: [],
            priceMax: 300.0,
            condition: nil
        )
        
        let enhanced = try await enhancer.enhance(query: query)
        
        XCTAssertEqual(enhanced.priceMax, 300.0)
    }
    
    func test_QueryEnhancer_ExtractsCategories() async throws {
        let query = "buy a bicycle near me"
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "bicycle",
            categories: ["sporting goods", "bike shop"],
            priceMax: nil,
            condition: nil
        )
        
        let enhanced = try await enhancer.enhance(query: query)
        
        XCTAssertTrue(enhanced.categories.contains("sporting goods"))
        XCTAssertTrue(enhanced.categories.contains("bike shop"))
    }
    
    func test_QueryEnhancer_ExtractsCondition() async throws {
        let query = "used bicycle for sale"
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "bicycle",
            categories: ["sporting goods"],
            priceMax: nil,
            condition: .used
        )
        
        let enhanced = try await enhancer.enhance(query: query)
        
        XCTAssertEqual(enhanced.condition, .used)
    }
    
    func test_QueryEnhancer_FallbackWhenLLMUnavailable() async throws {
        mockLLMService.shouldThrow = true
        
        let query = "test query"
        let enhanced = try await enhancer.enhance(query: query)
        
        // Should return a basic query without enhancement
        XCTAssertEqual(enhanced.original, query)
        XCTAssertNil(enhanced.productType)
        XCTAssertTrue(enhanced.categories.isEmpty)
        XCTAssertNil(enhanced.priceMax)
        XCTAssertNil(enhanced.condition)
    }
    
    func test_QueryEnhancer_CombinesAllFields() async throws {
        let query = "ergonomic office chair under $300"
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "office chair",
            categories: ["furniture store", "office supply"],
            priceMax: 300.0,
            condition: .new
        )
        
        let enhanced = try await enhancer.enhance(query: query)
        
        XCTAssertEqual(enhanced.original, query)
        XCTAssertEqual(enhanced.productType, "office chair")
        XCTAssertEqual(enhanced.categories.count, 2)
        XCTAssertEqual(enhanced.priceMax, 300.0)
        XCTAssertEqual(enhanced.condition, .new)
    }
}

// MARK: - Mock LLM Service

final class MockLLMService: LLMService, @unchecked Sendable {
    var mockResponse: EnhancedQuery?
    var shouldThrow = false
    
    func enhanceQuery(_ query: String) async throws -> EnhancedQuery {
        if shouldThrow {
            throw LLMServiceError.modelUnavailable
        }
        
        guard let response = mockResponse else {
            throw LLMServiceError.modelUnavailable
        }
        
        return response
    }
}
