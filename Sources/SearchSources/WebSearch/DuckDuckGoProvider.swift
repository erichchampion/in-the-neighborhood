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
                var title = nsString.substring(with: titleRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                
                // Decode HTML entities in title
                title = decodeHTMLEntities(title)
                
                // Skip if title is empty or too short
                guard !title.isEmpty, title.count > 3 else {
                    continue
                }
                
                // Filter out DuckDuckGo ad URLs (y.js?ad_domain= pattern)
                let urlStringLower = urlString.lowercased()
                if urlStringLower.contains("duckduckgo.com/y.js") && urlStringLower.contains("ad_domain=") {
                    // This is a DuckDuckGo ad redirect URL - skip it
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
                            
                            // Check if the decoded URL is a DuckDuckGo ad URL
                            let decodedLower = urlString.lowercased()
                            if decodedLower.contains("duckduckgo.com/y.js") && decodedLower.contains("ad_domain=") {
                                // This is a DuckDuckGo ad redirect URL - skip it
                                continue
                            }
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
                
                // Final check for ad URLs after all processing
                let finalUrlLower = urlString.lowercased()
                if finalUrlLower.contains("duckduckgo.com/y.js") && finalUrlLower.contains("ad_domain=") {
                    // This is a DuckDuckGo ad redirect URL - skip it
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
                        let extractedSnippet = (contextAfter as NSString).substring(with: snippetMatch.range(at: 1))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "\t", with: " ")
                        // Decode HTML entities in snippet
                        snippet = decodeHTMLEntities(extractedSnippet)
                        break
                    }
                }
                
                // Avoid duplicates by checking URL
                if results.contains(where: { $0.url?.absoluteString == url.absoluteString }) {
                    continue
                }
                
                // Extract shopping metadata from snippet and URL
                let shoppingMetadata = extractShoppingMetadata(snippet: snippet, url: urlString)
                
                let result = SearchResult(
                    id: UUID().uuidString,
                    title: title,
                    description: snippet,
                    source: "duckduckgo",
                    sourceType: .online,
                    url: url,
                    location: nil,
                    distance: nil,
                    metadata: shoppingMetadata
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
    
    /// Decodes HTML entities in a string
    /// Handles named entities (e.g., &amp;), decimal numeric entities (e.g., &#39;), and hexadecimal entities (e.g., &#x27;)
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        
        // First, decode common named entities
        let namedEntities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…"
        ]
        
        for (entity, replacement) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        
        // Decode decimal numeric entities (e.g., &#39;)
        if let decimalRegex = try? NSRegularExpression(pattern: #"&#(\d+);"#, options: []) {
            let nsString = result as NSString
            let matches = decimalRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Process matches in reverse order to preserve indices
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let codeRange = Range(match.range(at: 1), in: result),
                      let code = Int(result[codeRange]),
                      code >= 0 && code <= 0x10FFFF,
                      let scalar = Unicode.Scalar(code) else {
                    continue
                }
                
                let replacement = String(Character(scalar))
                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        
        // Decode hexadecimal numeric entities (e.g., &#x27; or &#X27;)
        if let hexRegex = try? NSRegularExpression(pattern: #"&#x([0-9a-fA-F]+);"#, options: [.caseInsensitive]) {
            let nsString = result as NSString
            let matches = hexRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Process matches in reverse order to preserve indices
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let codeRange = Range(match.range(at: 1), in: result),
                      let code = Int(result[codeRange], radix: 16),
                      code >= 0 && code <= 0x10FFFF,
                      let scalar = Unicode.Scalar(code) else {
                    continue
                }
                
                let replacement = String(Character(scalar))
                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        
        return result
    }
    
    /// Extracts shopping-related metadata from search results
    private func extractShoppingMetadata(snippet: String?, url: String) -> [String: AnyHashable] {
        var metadata: [String: AnyHashable] = [:]
        
        // Extract price information from snippet
        if let snippet = snippet {
            if let price = extractPrice(from: snippet) {
                metadata["price"] = price
            }
        }
        
        // Identify shopping domains
        let shoppingDomains: [String: String] = [
            "amazon.com": "amazon",
            "amazon.co.uk": "amazon",
            "walmart.com": "walmart",
            "target.com": "target",
            "bestbuy.com": "bestbuy",
            "homedepot.com": "homedepot",
            "lowes.com": "lowes",
            "costco.com": "costco",
            "ebay.com": "ebay",
            "etsy.com": "etsy",
            "shopify.com": "shopify",
            "zappos.com": "zappos",
            "overstock.com": "overstock",
            "wayfair.com": "wayfair",
            "macys.com": "macys",
            "nordstrom.com": "nordstrom"
        ]
        
        let urlLower = url.lowercased()
        for (domain, shoppingDomain) in shoppingDomains {
            if urlLower.contains(domain) {
                metadata["shoppingDomain"] = shoppingDomain
                metadata["isShoppingResult"] = true
                break
            }
        }
        
        // If we found a price but no shopping domain, still mark as potential shopping result
        if metadata["price"] != nil && metadata["isShoppingResult"] == nil {
            metadata["isShoppingResult"] = true
        }
        
        return metadata
    }
    
    /// Extracts price information from text using regex patterns
    private func extractPrice(from text: String) -> String? {
        // Pattern 1: $XX.XX or $X,XXX.XX
        let pricePattern1 = #"\$[\d,]+\.?\d*"#
        // Pattern 2: Price: $XX.XX
        let pricePattern2 = #"(?i)price[:\s]+\$?[\d,]+\.?\d*"#
        // Pattern 3: $XX.XX - $YY.YY (price range)
        let pricePattern3 = #"\$[\d,]+\.?\d*\s*-\s*\$[\d,]+\.?\d*"#
        
        let patterns = [pricePattern1, pricePattern2, pricePattern3]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.count)) {
                let matchedString = (text as NSString).substring(with: match.range)
                // Clean up the price string
                let cleaned = matchedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        
        return nil
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
