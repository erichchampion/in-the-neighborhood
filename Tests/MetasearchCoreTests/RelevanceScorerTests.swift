import XCTest
@testable import MetasearchCore
import Foundation

// Mock FoundationModel for testing
final class MockLanguageModel: @unchecked Sendable {
    var mockResponse: String = "0.8"
    
    func respond(to prompt: String) async throws -> String {
        return mockResponse
    }
}

final class RelevanceScorerTests: XCTestCase {
    var sut: RelevanceScorer!
    
    override func setUp() {
        super.setUp()
        sut = RelevanceScorer()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func testScoreResultReturnsValidScore() async throws {
        // Given
        let result = SearchResult(
            id: "1",
            title: "Red Wool Sweater",
            description: "Warm red wool sweater, size M",
            source: "amazon",
            sourceType: .online,
            category: .product,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            metadata: [:]
        )
        let query = "red sweater"
        
        // When
        let score = try await sut.scoreResult(result, query: query)
        
        // Then
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }
    
    func testScoreResultReturnsZeroForIrrelevantQuery() async throws {
        // Given
        let result = SearchResult(
            id: "1",
            title: "Blue Jeans",
            description: "Denim blue jeans",
            source: "amazon",
            sourceType: .online,
            category: .product,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            metadata: [:]
        )
        let query = "red sweater"
        
        // When
        let score = try await sut.scoreResult(result, query: query)
        
        // Then
        XCTAssertLessThan(score, 0.5) // Should be low relevance
    }
}
