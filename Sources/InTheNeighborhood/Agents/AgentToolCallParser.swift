import Foundation

/// Parsed turn from the agent LLM: either a tool call or done.
/// Arguments are JSON-decoded; in practice only String and [String] values are used.
public enum AgentTurn: @unchecked Sendable {
    case callTool(tool: String, arguments: [String: Any])
    case done
}

/// Parses raw model output into an AgentTurn (tool call or done).
public enum AgentToolCallParser {

    public enum ParseError: Error, Sendable {
        case noJSONObject
        case invalidJSON(underlying: Error)
        case missingAction
        case unknownAction(String)
        case missingTool
        case missingArguments
    }

    /// Extracts the first `{ ... }` from `response` and parses it as JSON.
    /// - Parameter response: Raw string from the model (may contain leading/trailing text).
    /// - Returns: `.callTool(tool, arguments)` or `.done`.
    /// - Throws: `ParseError` when no valid JSON object or required fields are missing.
    public static func parse(_ response: String) throws -> AgentTurn {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{") else {
            throw ParseError.noJSONObject
        }
        var depth = 0
        var end: String.Index? = nil
        for i in trimmed.indices {
            if trimmed[i] == "{" { depth += 1 }
            else if trimmed[i] == "}" {
                depth -= 1
                if depth == 0 { end = i; break }
            }
        }
        guard let end = end else {
            throw ParseError.noJSONObject
        }
        let jsonString = String(trimmed[start...end])
        guard let data = jsonString.data(using: .utf8) else {
            throw ParseError.noJSONObject
        }
        let decoded: [String: Any]
        do {
            decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw ParseError.invalidJSON(underlying: error)
        }
        guard let action = decoded["action"] as? String else {
            throw ParseError.missingAction
        }
        if action == "done" {
            return .done
        }
        if action == "call_tool" {
            guard let tool = decoded["tool"] as? String else {
                throw ParseError.missingTool
            }
            guard let argsAny = decoded["arguments"] else {
                throw ParseError.missingArguments
            }
            let arguments: [String: Any] = (argsAny as? [String: Any]) ?? [:]
            return .callTool(tool: tool, arguments: arguments)
        }
        throw ParseError.unknownAction(action)
    }
}
