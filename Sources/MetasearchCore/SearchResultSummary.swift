import Foundation

/// Summarizes search results for the agent's context window (one line per result).
public enum SearchResultSummary {

    private static let snippetMaxLength = 80

    /// Returns a short text summary of results: one line per result (title, url, snippet), capped at maxItems.
    /// - Parameters:
    ///   - results: Search results to summarize.
    ///   - maxItems: Maximum number of result lines to include (default 8).
    /// - Returns: Newline-separated lines, e.g. "1. Title | url | snippet"
    public static func summarizeForAgent(results: [SearchResult], maxItems: Int = 8) -> String {
        let capped = Array(results.prefix(maxItems))
        return capped.enumerated().map { index, result in
            let num = index + 1
            let title = result.title
            let urlPart = result.url.map { $0.absoluteString } ?? ""
            let snippet: String = {
                if let desc = result.description, !desc.isEmpty {
                    let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count <= Self.snippetMaxLength { return trimmed }
                    return String(trimmed.prefix(Self.snippetMaxLength)) + "..."
                }
                return result.title
            }()
            var parts = ["\(num). \(title)"]
            if !urlPart.isEmpty { parts.append(urlPart) }
            parts.append(snippet)
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
    }
}
