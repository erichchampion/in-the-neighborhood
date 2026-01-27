import Foundation
import MetasearchCore

final class DuckDuckGoProvider: WebSearchProvider, @unchecked Sendable {
    private let session: URLSession
    private let searchURL = "https://html.duckduckgo.com/html/"
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    
    init(session: URLSession = .shared, maxRetries: Int = 2, retryDelay: TimeInterval = 0.5) {
        self.session = session
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    func search(query: String) async throws -> [SearchResult] {
        return try await searchWithRetry(query: query, attempt: 0)
    }
    
    private func searchWithRetry(query: String, attempt: Int) async throws -> [SearchResult] {
        var components = URLComponents(string: searchURL)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        
        guard let url = components?.url else {
            throw WebSearchError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebSearchError.invalidResponse
            }
            
            // Handle rate limiting or blocking
            if httpResponse.statusCode == 429 || httpResponse.statusCode == 403 {
                if attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, attempt: attempt + 1)
                }
                throw WebSearchError.rateLimitExceeded
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode >= 500 && attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, attempt: attempt + 1)
                }
                throw WebSearchError.invalidResponse
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                throw WebSearchError.invalidResponse
            }
            
            return parseHTMLResults(html: html)
        } catch {
            if error is WebSearchError {
                throw error
            }
            
            // Retry on network errors
            if attempt < maxRetries {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await searchWithRetry(query: query, attempt: attempt + 1)
            }
            
            throw WebSearchError.networkError(error)
        }
    }
    
    private func parseHTMLResults(html: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        // DuckDuckGo HTML structure: results are in <div class="result"> elements
        // Try multiple patterns to handle different HTML structures
        
        // Pattern 1: Modern DuckDuckGo structure with result__a class
        let titleLinkPattern1 = #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([^<]+)</a>"#
        
        // Pattern 2: Alternative structure
        let titleLinkPattern2 = #"<a[^>]*href="([^"]+)"[^>]*class="[^"]*result[^"]*"[^>]*>([^<]+)</a>"#
        
        // Pattern 3: Generic result link
        let titleLinkPattern3 = #"<a[^>]*href="(/l/\?kh=[^"]+)"[^>]*>([^<]+)</a>"#
        
        let patterns = [titleLinkPattern1, titleLinkPattern2, titleLinkPattern3]
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            
            let nsString = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                
                let urlRange = match.range(at: 1)
                let titleRange = match.range(at: 2)
                
                guard urlRange.location != NSNotFound,
                      titleRange.location != NSNotFound else {
                    continue
                }
                
                // Check if this result is an ad by examining the HTML context
                // Look for ad indicators in the 200 chars before the match
                let contextStart = max(0, match.range.location - 200)
                let contextLength = match.range.location - contextStart + match.range.length
                let contextRange = NSRange(location: contextStart, length: contextLength)
                let contextBefore = nsString.substring(with: contextRange).lowercased()
                
                // Skip if this appears to be an ad/sponsored result
                if isAdResult(context: contextBefore) {
                    continue
                }
                
                var urlString = nsString.substring(with: urlRange)
                let title = nsString.substring(with: titleRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                
                // Skip if title is empty or too short
                guard !title.isEmpty, title.count > 3 else {
                    continue
                }
                
                // Handle DuckDuckGo redirect URLs (both relative /l/... and full URLs)
                if urlString.contains("uddg=") {
                    // Extract actual URL from redirect parameter
                    if let redirectRange = urlString.range(of: "uddg=") {
                        let encodedURL = String(urlString[redirectRange.upperBound...])
                        // Handle multiple parameters - take everything up to next &
                        let encodedPart: String
                        if let paramEnd = encodedURL.firstIndex(of: "&") {
                            encodedPart = String(encodedURL[..<paramEnd])
                        } else {
                            encodedPart = encodedURL
                        }
                        
                        if let decoded = encodedPart.removingPercentEncoding {
                            urlString = decoded
                        } else {
                            // If decoding fails, skip this result
                            continue
                        }
                    } else {
                        // Has "uddg=" in URL but can't find the parameter - skip
                        continue
                    }
                } else if urlString.hasPrefix("/l/") {
                    // Relative redirect URL without uddg parameter - skip (can't resolve)
                    continue
                }
                
                // Ensure URL has a protocol
                if urlString.hasPrefix("//") {
                    urlString = "https:" + urlString
                } else if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                    // If it's a relative URL, skip it (we need absolute URLs)
                    continue
                }
                
                guard let url = URL(string: urlString) else {
                    continue
                }
                
                // Extract snippet - try multiple patterns
                var snippet: String? = nil
                let snippetPatterns = [
                    #"<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([^<]+)</a>"#,
                    #"<span[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([^<]+)</span>"#,
                    #"<div[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([^<]+)</div>"#
                ]
                
                // Find snippet near this result (within 500 chars after the link)
                let searchStart = match.range.location + match.range.length
                let searchEnd = min(searchStart + 500, nsString.length)
                let searchRange = NSRange(location: searchStart, length: searchEnd - searchStart)
                let contextAfter = nsString.substring(with: searchRange)
                
                for snippetPattern in snippetPatterns {
                    if let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.caseInsensitive]),
                       let snippetMatch = snippetRegex.firstMatch(in: contextAfter, options: [], range: NSRange(location: 0, length: contextAfter.count)),
                       snippetMatch.range(at: 1).location != NSNotFound {
                        snippet = (contextAfter as NSString).substring(with: snippetMatch.range(at: 1))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "\t", with: " ")
                        break
                    }
                }
                
                // Avoid duplicates by checking URL
                if results.contains(where: { $0.url?.absoluteString == url.absoluteString }) {
                    continue
                }
                
                let result = SearchResult(
                    id: UUID().uuidString,
                    title: title,
                    description: snippet,
                    source: "duckduckgo",
                    sourceType: .online,
                    url: url,
                    location: nil,
                    distance: nil,
                    metadata: [:]
                )
                
                results.append(result)
            }
            
            // If we found results with this pattern, use them
            if !results.isEmpty {
                break
            }
        }
        
        return results
    }
    
    /// Checks if a result appears to be an ad based on HTML context
    private func isAdResult(context: String) -> Bool {
        let adIndicators = [
            "class=\"ad\"",
            "class='ad'",
            "class=\"ad-",
            "class='ad-",
            "class=\"sponsored\"",
            "class='sponsored'",
            "class=\"result--ad\"",
            "class='result--ad'",
            "class=\"result__ad\"",
            "class='result__ad'",
            "data-module=\"ad\"",
            "data-module='ad'",
            "sponsored link",
            "sponsored result",
            "advertisement",
            "ad result",
            "microsoft advertising",
            "ads by microsoft"
        ]
        
        let lowercasedContext = context.lowercased()
        return adIndicators.contains { indicator in
            lowercasedContext.contains(indicator)
        }
    }
}

enum WebSearchError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case rateLimitExceeded
}
