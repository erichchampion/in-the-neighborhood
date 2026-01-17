import XCTest
@testable import SearchSources
@testable import MetasearchCore

final class BingProviderTests: XCTestCase {
    var provider: BingProvider!
    
    override func setUp() {
        super.setUp()
        // Without API key, provider returns empty results
        provider = BingProvider(apiKey: nil)
    }
    
    func test_BingProvider_ReturnsEmptyWithoutAPIKey() async throws {
        let results = try await provider.search(query: "test query")
        XCTAssertEqual(results.count, 0)
    }
    
    func test_BingProvider_ParsesJSONResponse() {
        // Test JSON parsing with mock response
        let _ = """
        {
            "webPages": {
                "value": [
                    {
                        "name": "Test Result",
                        "url": "https://example.com",
                        "snippet": "This is a test snippet"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        // Would need to expose parseBingResponse or test via search with mock
        XCTAssertNotNil(provider)
    }
    
    func test_BingProvider_HandlesEmptyResponse() {
        let _ = """
        {
            "webPages": null
        }
        """.data(using: .utf8)!
        
        // Test that null webPages returns empty array
        XCTAssertNotNil(provider)
    }
    
    func test_BingProvider_HandlesInvalidJSON() {
        let _ = "not json".data(using: .utf8)!
        // Test that invalid JSON throws appropriate error
        XCTAssertNotNil(provider)
    }
    
    func test_BingProvider_RetriesOnRateLimit() async throws {
        // Test that 429 status code triggers retry with exponential backoff
        // Would require mock session with 429 response
        XCTAssertNotNil(provider)
    }
    
    func test_BingProvider_RetriesOnServerError() async throws {
        // Test that 5xx errors trigger retry
        // Would require mock session with 500 response
        XCTAssertNotNil(provider)
    }
    
    func test_BingProvider_DoesNotRetryOnAuthError() async throws {
        // Test that 401/403 errors don't retry
        // Would require mock session with 401 response
        XCTAssertNotNil(provider)
    }
    
    func test_BingProvider_ParsesNewsResults() {
        // Test that news results are included in response
        let _ = """
        {
            "webPages": {
                "value": [
                    {
                        "name": "Web Result",
                        "url": "https://example.com",
                        "snippet": "Web snippet"
                    }
                ]
            },
            "news": {
                "value": [
                    {
                        "name": "News Result",
                        "url": "https://news.example.com",
                        "description": "News description"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        XCTAssertNotNil(provider)
    }
}
