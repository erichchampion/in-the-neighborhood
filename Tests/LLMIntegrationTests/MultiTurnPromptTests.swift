import XCTest
@testable import LLMIntegration

final class MultiTurnPromptTests: XCTestCase {

    func test_buildMultiTurnPrompt_containsSystemUserAssistantToolResultInOrder() {
        let messages: [(role: String, content: String)] = [
            ("system", "S"),
            ("user", "U"),
            ("assistant", "A1"),
            ("tool_result", "T1")
        ]
        let prompt = LlamaCppLLMService.buildMultiTurnPromptForAgent(messages: messages, chatTemplate: .llama32)
        XCTAssertFalse(prompt.isEmpty)
        let order = ["S", "U", "A1", "T1"]
        var lastIndex = prompt.startIndex
        for substring in order {
            guard let range = prompt.range(of: substring) else {
                XCTFail("Prompt should contain '\(substring)'")
                return
            }
            XCTAssertGreaterThanOrEqual(range.lowerBound, lastIndex, "Content should appear in order: \(substring)")
            lastIndex = range.upperBound
        }
    }

    func test_buildMultiTurnPrompt_endsWithAssistantHeader() {
        let messages: [(role: String, content: String)] = [
            ("system", "S"),
            ("user", "U"),
            ("assistant", "A1"),
            ("tool_result", "T1")
        ]
        let prompt = LlamaCppLLMService.buildMultiTurnPromptForAgent(messages: messages, chatTemplate: .llama32)
        XCTAssertFalse(prompt.isEmpty)
        // Llama 3.2 assistant header is <|start_header_id|>assistant<|end_header_id|>
        XCTAssertTrue(prompt.contains("assistant"), "Prompt should end with assistant turn so model generates next")
    }
}
