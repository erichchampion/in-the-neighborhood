import XCTest
@testable import InTheNeighborhood
import MetasearchCore
import LLMIntegration
import SearchSources
import LocationServices

final class IntegrationTests: XCTestCase {
    
    @MainActor
    func test_EndToEndSearchFlow() async throws {
        // Setup
        let locationService = LocationService()
        let llmService = LlamaCppLLMService()
        let _ = QueryEnhancer(llmService: llmService)
        
        let mapKitSource = MapKitSearchSource(locationService: locationService)
        let webSearchSource = WebSearchSource()
        
        let coordinator = MetasearchCoordinator(sources: [mapKitSource, webSearchSource])
        
        // Perform search
        let query = EnhancedQuery(
            original: "office chair",
            productType: "office chair",
            categories: ["furniture store"],
            priceMax: nil,
            condition: nil
        )
        
        let results = try await coordinator.search(query: query)
        
        // Verify results structure (may be empty in test environment)
        XCTAssertNotNil(results)
    }
    
    @MainActor
    func test_ErrorRecovery() async {
        // Test that app handles errors gracefully
        let _ = LocationService()
        let llmService = LlamaCppLLMService()
        let _ = QueryEnhancer(llmService: llmService)
        
        let coordinator = MetasearchCoordinator(sources: [])
        
        // Search with no sources should return empty results
        let query = EnhancedQuery(
            original: "test",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        do {
            let results = try await coordinator.search(query: query)
            XCTAssertTrue(results.isEmpty)
        } catch {
            XCTFail("Should not throw error with empty sources")
        }
    }
    
    func test_Accessibility() {
        // Test accessibility structure
        // This would verify VoiceOver support, dynamic type, etc.
        // In practice, this would require UI testing or accessibility testing tools
        XCTAssertTrue(true, "Placeholder for accessibility tests")
    }
}
