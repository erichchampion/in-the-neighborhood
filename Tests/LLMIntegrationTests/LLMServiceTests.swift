import XCTest
@testable import LLMIntegration
@testable import MetasearchCore

final class LLMServiceTests: XCTestCase {
    
    func test_LLMService_ErrorHandling() async {
        let service = MockLLMService()
        service.shouldThrow = true
        
        do {
            let _ = try await service.enhanceQuery("test query")
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is LLMServiceError)
        }
    }
    
    func test_LLMService_ProtocolConformance() {
        let service = MockLLMService()
        XCTAssertNotNil(service)
    }
}
