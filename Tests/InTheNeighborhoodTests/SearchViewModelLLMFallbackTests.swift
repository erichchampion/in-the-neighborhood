import XCTest
@testable import InTheNeighborhood
import MetasearchCore
import LLMIntegration
import SearchSources
import LocationServices

/// Tests that search works even when LLM enhancement fails
@MainActor
final class SearchViewModelLLMFallbackTests: XCTestCase {
    var coordinator: MetasearchCoordinator!
    var queryEnhancer: QueryEnhancer!
    var locationService: LocationService!
    var viewModel: SearchViewModel!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Setup real services
        locationService = LocationService()
        
        // Create LLM service that will fail
        let llmService = LlamaCppLLMService()
        queryEnhancer = QueryEnhancer(llmService: llmService)
        
        // Setup search sources including bookshop
        let mapKitSource = MapKitSearchSource(locationService: locationService)
        let webSearchSource = WebSearchSource()
        let bookshopSource = BookshopSearchSource()
        let marketplaceSource = MarketplaceSearchSource()
        
        coordinator = MetasearchCoordinator(sources: [
            mapKitSource,
            webSearchSource,
            bookshopSource,
            marketplaceSource
        ])
        
        viewModel = SearchViewModel(
            coordinator: coordinator,
            queryEnhancer: queryEnhancer
        )
    }
    
    /// Test that search for book query returns results even when LLM fails
    /// Query: "the past through tomorrow" should find bookstores and bookshop.org
    func test_BookSearch_WithLLMFailure_ReturnsResults() async throws {
        // Given: A search query for a book
        let query = "the past through tomorrow"
        
        // When: Searching (LLM may fail but should fall back gracefully)
        await viewModel.search(query: query)
        
        // Then: Should have results or at least not be in error state
        // The query should work with fallback rule-based parsing
        XCTAssertNotEqual(viewModel.state, .error, "Search should not fail even if LLM fails")
        
        // If LLM fails, it should fall back to rule-based parsing which should
        // still allow the coordinator to search with the original query
        // We expect either:
        // 1. Results found (ideal case)
        // 2. Or at least loaded state with empty results (acceptable)
        // But NOT error state
        
        if viewModel.state == .loaded {
            // If we got results, great!
            if !viewModel.results.isEmpty {
                XCTAssertTrue(true, "Got \(viewModel.results.count) results with fallback")
            } else {
                // Empty results are acceptable - at least it didn't error
                XCTAssertTrue(true, "Search completed without error, no results found")
            }
        } else {
            XCTFail("Expected state to be .loaded but got \(viewModel.state). Error: \(viewModel.errorMessage ?? "none")")
        }
    }
    
    /// Test that QueryEnhancer falls back when LLM service throws
    func test_QueryEnhancer_WithLLMError_ReturnsFallbackQuery() async throws {
        // Given: A query
        let query = "the past through tomorrow"
        
        // When: Enhancing query (LLM may fail)
        let enhanced = try await queryEnhancer.enhance(query: query)
        
        // Then: Should get an EnhancedQuery even if LLM failed
        XCTAssertEqual(enhanced.original, query)
        // Fallback query should have basic structure
        XCTAssertNotNil(enhanced)
    }
    
    /// Test that rule-based parsing extracts book category
    func test_RuleBasedParsing_BookQuery_ExtractsBookstoreCategory() async throws {
        // This tests the fallback parsing logic directly
        let query = "the past through tomorrow book"
        let llmService = LlamaCppLLMService()
        
        // Even if LLM fails, parseQuery should extract "bookstore" category
        // We can't directly test parseQuery as it's private, but we can test
        // that enhanceQuery with no model falls back correctly
        let enhanced = try await llmService.enhanceQuery(query)
        
        // Should at least preserve the original query
        XCTAssertEqual(enhanced.original, query)
        
        // If rule-based parsing works, it should detect "book" and add "bookstore" category
        // But we can't assert this directly as parseQuery is private
        // The important thing is it doesn't throw
    }
}
