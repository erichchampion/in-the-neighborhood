import Foundation
import MetasearchCore

/// Result of an agent-driven search: results by bucket plus local store categories.
public struct AgentSearchResult: Sendable {
    public let webResults: [SearchResult]
    public let amazonResults: [SearchResult]
    public let localResults: [SearchResult]
    public let localStoreCategories: [String]

    public init(
        webResults: [SearchResult],
        amazonResults: [SearchResult],
        localResults: [SearchResult],
        localStoreCategories: [String]
    ) {
        self.webResults = webResults
        self.amazonResults = amazonResults
        self.localResults = localResults
        self.localStoreCategories = localStoreCategories
    }
}

/// Agent that runs a tool loop: prompt LLM, parse tool call or done, execute tools, accumulate results, fallback on failure.
public final class SearchAgent: Sendable {

    private let generateFromMessages: @Sendable ([(role: String, content: String)]) async throws -> String
    private let toolExecutor: SearchToolExecutor
    private let classicFallback: @Sendable () async throws -> AgentSearchResult

    private static let maxIterations = 5
    private static let maxParseFailuresBeforeFallback = 2

    private static let systemPrompt: String = """
        You help the user find products via web, product, and local store searches.
        You have three tools:
        - search_web: arguments {"query": "string"} — general web search
        - search_products: arguments {"query": "string"} — product/book search
        - search_local_stores: arguments {"query": "string", "categories": ["string"]} (categories optional) — local stores
        Respond with ONLY a JSON object. Either {"action": "call_tool", "tool": "...", "arguments": {...}} or {"action": "done"}. No other text.
        """

    public init(
        generateFromMessages: @escaping @Sendable ([(role: String, content: String)]) async throws -> String,
        toolExecutor: SearchToolExecutor,
        classicFallback: @escaping @Sendable () async throws -> AgentSearchResult
    ) {
        self.generateFromMessages = generateFromMessages
        self.toolExecutor = toolExecutor
        self.classicFallback = classicFallback
    }

    /// Runs the agent loop; returns accumulated results or fallback result on parse failure / max iterations.
    /// - Parameter runTimeClassicFallback: When provided, called with the current query when fallback is needed; when nil, uses init's fallback.
    /// - Parameter onToolResult: Optional callback invoked when each tool completes; enables incremental UI display before agent loop finishes.
    public func run(
        userQuery: String,
        metadata: MetasearchCore.ProductMetadata?,
        classicFallback runTimeClassicFallback: (@Sendable (String) async throws -> AgentSearchResult)? = nil,
        onToolResult: (@Sendable (String, [SearchResult]) -> Void)? = nil
    ) async throws -> AgentSearchResult {
        let performFallback: () async throws -> AgentSearchResult = {
            if let runTimeFallback = runTimeClassicFallback {
                return try await runTimeFallback(userQuery)
            }
            return try await self.classicFallback()
        }
        var messages: [(role: String, content: String)] = [
            ("system", Self.systemPrompt),
            ("user", userMessage(from: userQuery, metadata: metadata))
        ]
        var webResults: [SearchResult] = []
        var amazonResults: [SearchResult] = []
        var localResults: [SearchResult] = []
        var localStoreCategories: [String] = []
        var consecutiveParseFailures = 0

        for _ in 0..<Self.maxIterations {
            let response: String
            do {
                response = try await generateFromMessages(messages)
            } catch {
                return try await performFallback()
            }

            let turn: AgentTurn
            do {
                turn = try AgentToolCallParser.parse(response)
                consecutiveParseFailures = 0
            } catch {
                consecutiveParseFailures += 1
                if consecutiveParseFailures >= Self.maxParseFailuresBeforeFallback {
                    return try await performFallback()
                }
                continue
            }

            switch turn {
            case .done:
                return AgentSearchResult(
                    webResults: webResults,
                    amazonResults: amazonResults,
                    localResults: localResults,
                    localStoreCategories: localStoreCategories
                )
            case .callTool(let tool, let arguments):
                let results: [SearchResult]
                do {
                    results = try await toolExecutor.execute(toolName: tool, arguments: arguments)
                } catch {
                    consecutiveParseFailures += 1
                    if consecutiveParseFailures >= Self.maxParseFailuresBeforeFallback {
                        return try await performFallback()
                    }
                    continue
                }
                let summary = SearchResultSummary.summarizeForAgent(results: results, maxItems: 8)
                messages.append(("assistant", response))
                messages.append(("tool_result", summary))
                switch tool {
                case "search_web":
                    webResults = results
                    onToolResult?(tool, results)
                case "search_products":
                    amazonResults = results
                    onToolResult?(tool, results)
                case "search_local_stores":
                    localResults = results
                    if let cats = arguments["categories"] as? [String] {
                        localStoreCategories = cats
                    }
                    onToolResult?(tool, results)
                default:
                    break
                }
            }
        }

        return try await performFallback()
    }

    private func userMessage(from query: String, metadata: MetasearchCore.ProductMetadata?) -> String {
        var parts = [query]
        if let m = metadata, !m.isEmpty {
            var ctx: [String] = []
            if let isbn = m.isbn { ctx.append("ISBN \(isbn)") }
            if let author = m.author { ctx.append("Author: \(author)") }
            if let brand = m.brand { ctx.append("Brand: \(brand)") }
            if !ctx.isEmpty {
                parts.append("Context: " + ctx.joined(separator: " "))
            }
        }
        return parts.joined(separator: "\n")
    }
}
