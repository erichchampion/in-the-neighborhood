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
    
    // MARK: - Metadata-Aware Tests
    
    func test_QueryEnhancer_PassesMetadataToLLM() async throws {
        let query = "The color purple"
        let metadata = ProductMetadata(
            isbn: "9780143135692",
            author: "Alice Walker"
        )
        
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "book",
            categories: ["bookstore"],
            priceMax: nil,
            condition: nil
        )
        
        let enhanced = try await enhancer.enhance(query: query, metadata: metadata)
        
        // Verify metadata was passed to LLM service
        XCTAssertNotNil(mockLLMService.receivedMetadata)
        XCTAssertEqual(mockLLMService.receivedMetadata?.isbn, "9780143135692")
        XCTAssertEqual(mockLLMService.receivedMetadata?.author, "Alice Walker")
        
        // Verify enhanced query reflects book categorization
        XCTAssertEqual(enhanced.productType, "book")
        XCTAssertTrue(enhanced.categories.contains("bookstore"))
    }
    
    func test_QueryEnhancer_HandlesISBNMetadata() async throws {
        let query = "The color purple"
        let metadata = ProductMetadata(isbn: "9780143135692")
        
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "book",
            categories: ["bookstore"],
            priceMax: nil,
            condition: nil
        )
        
        let enhanced = try await enhancer.enhance(query: query, metadata: metadata)
        
        XCTAssertEqual(mockLLMService.receivedMetadata?.isbn, "9780143135692")
        XCTAssertEqual(enhanced.productType, "book")
    }
    
    func test_QueryEnhancer_HandlesSKUMetadata() async throws {
        let query = "office chair"
        let metadata = ProductMetadata(sku: "OC-12345")
        
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "office chair",
            categories: ["furniture store", "office supply"],
            priceMax: nil,
            condition: nil
        )
        
        let enhanced = try await enhancer.enhance(query: query, metadata: metadata)
        
        XCTAssertEqual(mockLLMService.receivedMetadata?.sku, "OC-12345")
        XCTAssertEqual(enhanced.productType, "office chair")
    }
    
    func test_QueryEnhancer_HandlesAuthorMetadata() async throws {
        let query = "The color purple"
        let metadata = ProductMetadata(author: "Alice Walker")
        
        mockLLMService.mockResponse = EnhancedQuery(
            original: query,
            productType: "book",
            categories: ["bookstore"],
            priceMax: nil,
            condition: nil
        )
        
        let enhanced = try await enhancer.enhance(query: query, metadata: metadata)
        
        XCTAssertEqual(mockLLMService.receivedMetadata?.author, "Alice Walker")
        XCTAssertEqual(enhanced.productType, "book")
        XCTAssertTrue(enhanced.categories.contains("bookstore"))
    }
}

// MARK: - Mock LLM Service

final class MockLLMService: LLMService, @unchecked Sendable {
    var mockResponse: EnhancedQuery?
    var shouldThrow = false
    var receivedMetadata: ProductMetadata?
    
    func enhanceQuery(_ query: String, metadata: ProductMetadata?) async throws -> EnhancedQuery {
        receivedMetadata = metadata
        
        if shouldThrow {
            throw LLMServiceError.modelUnavailable
        }
        
        guard let response = mockResponse else {
            throw LLMServiceError.modelUnavailable
        }
        
        return response
    }
}
