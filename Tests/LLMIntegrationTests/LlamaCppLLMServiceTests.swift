import XCTest
@testable import LLMIntegration
@testable import MetasearchCore

/// Test suite for LlamaCppLLMService following TDD approach
final class LlamaCppLLMServiceTests: XCTestCase {
    var service: LlamaCppLLMService!
    
    override func setUp() async throws {
        try await super.setUp()
        service = LlamaCppLLMService()
    }
    
    override func tearDown() async throws {
        service = nil
        try await super.tearDown()
    }
    
    // MARK: - Model Loading Tests
    
    func test_ServiceInitializesWithoutModel() async {
        // Service should initialize even if model is not available
        let newService = LlamaCppLLMService()
        XCTAssertNotNil(newService)
    }
    
    func test_ServiceUsesFallbackWhenModelNotAvailable() async throws {
        // When model is not available, should fall back to rule-based parsing
        let query = "office chair under $300"
        let enhanced = try await service.enhanceQuery(query)
        
        // Should extract basic information via rule-based parsing
        XCTAssertEqual(enhanced.original, query)
        // Rule-based parser should extract price
        XCTAssertNotNil(enhanced.priceMax)
    }
    
    // MARK: - Query Enhancement Tests (with actual llama.cpp - requires model)
    
    func test_EnhanceQuery_ExtractsProductType_WithLLM() async throws {
        // Skip if model not available
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        let query = "ergonomic office chair"
        let enhanced = try await service.enhanceQuery(query)
        
        XCTAssertEqual(enhanced.original, query)
        // LLM should extract product type better than rule-based
        XCTAssertNotNil(enhanced.productType)
        XCTAssertTrue(enhanced.productType?.contains("chair") == true || enhanced.productType?.contains("office") == true)
    }
    
    func test_EnhanceQuery_ExtractsPrice_WithLLM() async throws {
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        let query = "bicycle under $500"
        let enhanced = try await service.enhanceQuery(query)
        
        XCTAssertEqual(enhanced.original, query)
        XCTAssertNotNil(enhanced.priceMax)
        if let priceMax = enhanced.priceMax {
            XCTAssertEqual(priceMax, 500.0, accuracy: 1.0)
        } else {
            XCTFail("Expected priceMax to be extracted")
        }
    }
    
    func test_EnhanceQuery_ExtractsCategories_WithLLM() async throws {
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        let query = "buy a bicycle near me"
        let enhanced = try await service.enhanceQuery(query)
        
        XCTAssertEqual(enhanced.original, query)
        // Should extract relevant categories
        XCTAssertFalse(enhanced.categories.isEmpty)
    }
    
    func test_EnhanceQuery_ExtractsCondition_WithLLM() async throws {
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        let query = "used bicycle for sale"
        let enhanced = try await service.enhanceQuery(query)
        
        XCTAssertEqual(enhanced.original, query)
        XCTAssertEqual(enhanced.condition, .used)
    }
    
    func test_EnhanceQuery_ParsesJSONResponse_WithLLM() async throws {
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        // Complex query with multiple constraints
        let query = "ergonomic office chair under $300 new condition"
        let enhanced = try await service.enhanceQuery(query)
        
        XCTAssertEqual(enhanced.original, query)
        XCTAssertNotNil(enhanced.productType)
        XCTAssertNotNil(enhanced.priceMax)
        XCTAssertEqual(enhanced.condition, .new)
        XCTAssertFalse(enhanced.categories.isEmpty)
    }
    
    // MARK: - Error Handling Tests
    
    func test_EnhanceQuery_HandlesInvalidQuery() async throws {
        // Empty queries should throw an error
        let query = ""
        do {
            _ = try await service.enhanceQuery(query)
            XCTFail("Expected invalidInput error for empty query")
        } catch LLMServiceError.invalidInput {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func test_EnhanceQuery_HandlesWhitespaceOnlyQuery() async throws {
        // Whitespace-only queries should throw an error
        let query = "   \n\t  "
        do {
            _ = try await service.enhanceQuery(query)
            XCTFail("Expected invalidInput error for whitespace-only query")
        } catch LLMServiceError.invalidInput {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func test_EnhanceQuery_FallbackOnModelLoadFailure() async throws {
        // Service should gracefully fall back if model fails to load
        // This test verifies fallback behavior works
        let query = "test query"
        let enhanced = try await service.enhanceQuery(query)
        
        // Should always return a valid EnhancedQuery, even if model fails
        XCTAssertEqual(enhanced.original, query)
    }
    
    // MARK: - Performance Tests
    
    func test_EnhanceQuery_CompletesWithinTimeout() async throws {
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        let query = "office chair"
        let startTime = Date()
        let enhanced = try await service.enhanceQuery(query)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete within reasonable time (< 5 seconds for inference)
        XCTAssertLessThan(duration, 5.0, "Query enhancement should complete quickly")
        XCTAssertEqual(enhanced.original, query)
    }
    
    // MARK: - Metadata-Aware Tests
    
    func test_EnhanceQuery_WithISBNMetadata_CategorizesAsBook() async throws {
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        let query = "The color purple"
        let metadata = ProductMetadata(isbn: "9780143135692")
        
        let enhanced = try await service.enhanceQuery(query, metadata: metadata)
        
        XCTAssertEqual(enhanced.original, query)
        // Should recognize ISBN and categorize as book
        XCTAssertTrue(
            enhanced.productType?.lowercased().contains("book") == true ||
            enhanced.categories.contains("bookstore") ||
            enhanced.categories.contains { $0.lowercased().contains("book") }
        )
    }
    
    func test_EnhanceQuery_WithAuthorMetadata_CategorizesAsBook() async throws {
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        let query = "The color purple"
        let metadata = ProductMetadata(author: "Alice Walker")
        
        let enhanced = try await service.enhanceQuery(query, metadata: metadata)
        
        XCTAssertEqual(enhanced.original, query)
        // Should recognize author and categorize as book
        XCTAssertTrue(
            enhanced.productType?.lowercased().contains("book") == true ||
            enhanced.categories.contains("bookstore") ||
            enhanced.categories.contains { $0.lowercased().contains("book") }
        )
    }
    
    func test_EnhanceQuery_WithSKUMetadata_ExtractsProductType() async throws {
        guard await modelIsAvailable() else {
            throw XCTSkip("LLM model not available for testing")
        }
        
        let query = "office chair"
        let metadata = ProductMetadata(sku: "OC-12345")
        
        let enhanced = try await service.enhanceQuery(query, metadata: metadata)
        
        XCTAssertEqual(enhanced.original, query)
        XCTAssertNotNil(enhanced.productType)
        // Should extract product type from query
        XCTAssertTrue(enhanced.productType?.lowercased().contains("chair") == true || 
                     enhanced.productType?.lowercased().contains("office") == true)
    }
    
    func test_EnhanceQuery_FallbackParser_UsesISBNMetadata() async throws {
        // Test fallback parser with metadata (when LLM unavailable)
        let query = "The color purple"
        let metadata = ProductMetadata(isbn: "9780143135692")
        
        let enhanced = try await service.enhanceQuery(query, metadata: metadata)
        
        XCTAssertEqual(enhanced.original, query)
        // Fallback parser should recognize ISBN and categorize as book
        XCTAssertTrue(enhanced.categories.contains("bookstore"))
    }
    
    func test_EnhanceQuery_FallbackParser_UsesAuthorMetadata() async throws {
        // Test fallback parser with metadata (when LLM unavailable)
        let query = "The color purple"
        let metadata = ProductMetadata(author: "Alice Walker")
        
        let enhanced = try await service.enhanceQuery(query, metadata: metadata)
        
        XCTAssertEqual(enhanced.original, query)
        // Fallback parser should recognize author and categorize as book
        XCTAssertTrue(enhanced.categories.contains("bookstore"))
    }
    
    // MARK: - Helper Methods
    
    private func modelIsAvailable() async -> Bool {
        return LLMModelDownloadManager.shared.isModelAvailable()
    }
}
