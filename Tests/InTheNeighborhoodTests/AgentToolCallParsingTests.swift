import XCTest
@testable import InTheNeighborhood

final class AgentToolCallParsingTests: XCTestCase {

    func test_validToolCall_parsesToCallToolWithNameAndArguments() throws {
        let json = """
        {"action": "call_tool", "tool": "search_web", "arguments": {"query": "books"}}
        """
        let turn = try AgentToolCallParser.parse(json)
        guard case .callTool(let name, let args) = turn else {
            XCTFail("Expected callTool, got \(turn)")
            return
        }
        XCTAssertEqual(name, "search_web")
        XCTAssertEqual(args["query"] as? String, "books")
    }

    func test_validDone_parsesToDone() throws {
        let json = """
        {"action": "done"}
        """
        let turn = try AgentToolCallParser.parse(json)
        guard case .done = turn else {
            XCTFail("Expected done, got \(turn)")
            return
        }
    }

    func test_textWithJunkAndOneJSONObject_extractsAndParsesObject() throws {
        let text = "Here is the response:\n{\"action\": \"call_tool\", \"tool\": \"search_products\", \"arguments\": {\"query\": \"laptop\"}}\nIgnore this."
        let turn = try AgentToolCallParser.parse(text)
        guard case .callTool(let name, let args) = turn else {
            XCTFail("Expected callTool, got \(turn)")
            return
        }
        XCTAssertEqual(name, "search_products")
        XCTAssertEqual(args["query"] as? String, "laptop")
    }

    func test_invalidJSON_throws() {
        let text = "not json at all"
        XCTAssertThrowsError(try AgentToolCallParser.parse(text))
    }

    func test_missingAction_throws() {
        let json = """
        {"tool": "search_web", "arguments": {}}
        """
        XCTAssertThrowsError(try AgentToolCallParser.parse(json))
    }
}
