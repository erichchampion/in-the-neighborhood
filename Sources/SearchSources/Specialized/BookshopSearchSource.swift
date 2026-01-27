import Foundation
import MetasearchCore

public final class BookshopSearchSource: SearchSource {
    public let identifier: String = "bookshop"
    public let sourceType: SourceType = .online
    
    private let baseURL = "https://bookshop.org"
    private let session: URLSession
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    
    public init(session: URLSession = .shared, maxRetries: Int = 2, retryDelay: TimeInterval = 0.5) {
        self.session = session
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        // Filter to only book-related queries
        guard query.productType?.lowercased().contains("book") == true ||
              query.categories.contains(where: { $0.lowercased().contains("book") }) ||
              query.original.lowercased().contains("book") else {
            return []
        }
        
        return try await searchWithRetry(query: query.original, attempt: 0)
    }
    
    private func searchWithRetry(query: String, attempt: Int) async throws -> [SearchResult] {
        // Bookshop.org search URL format
        var components = URLComponents(string: "\(baseURL)/books")
        components?.queryItems = [
            URLQueryItem(name: "keywords", value: query)
        ]
        
        guard let url = components?.url else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return []
            }
            
            // Handle rate limiting
            if httpResponse.statusCode == 429 || httpResponse.statusCode == 403 {
                if attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, attempt: attempt + 1)
                }
                return []
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode >= 500 && attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, attempt: attempt + 1)
                }
                return []
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                return []
            }
            
            return parseHTMLResults(html: html)
        } catch {
            // Retry on network errors
            if attempt < maxRetries {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await searchWithRetry(query: query, attempt: attempt + 1)
            }
            return []
        }
    }
    
    private func parseHTMLResults(html: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        // Bookshop.org structure: books are typically in product cards or list items
        // Look for common patterns: product cards, book listings, etc.
        
        // Pattern 1: Product card with link to book
        let productPattern = #"<a[^>]*href="(/books/[^"]+)"[^>]*>.*?<[^>]*>([^<]+)</[^>]*>.*?</a>"#
        
        // Pattern 2: Book title in h2/h3 with link
        let titlePattern = #"<h[23][^>]*>.*?<a[^>]*href="(/books/[^"]+)"[^>]*>([^<]+)</a>.*?</h[23]>"#
        
        // Pattern 3: Generic book link
        let bookLinkPattern = #"href="(/books/[^"]+)"[^>]*>.*?([^<]*book[^<]*)</a>"#
        
        let patterns = [productPattern, titlePattern, bookLinkPattern]
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
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
                
                var urlPath = nsString.substring(with: urlRange)
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
                
                // Construct full URL
                if !urlPath.hasPrefix("http") {
                    urlPath = "\(baseURL)\(urlPath)"
                }
                
                guard let url = URL(string: urlPath) else {
                    continue
                }
                
                // Extract author and price from context around the match
                var author: String? = nil
                var price: String? = nil
                
                // Look for author in nearby context (within 300 chars)
                let searchStart = max(0, match.range.location - 150)
                let searchEnd = min(match.range.location + match.range.length + 300, nsString.length)
                let contextRange = NSRange(location: searchStart, length: searchEnd - searchStart)
                let context = nsString.substring(with: contextRange)
                
                // Try to find author (common patterns: "by Author Name", "Author Name", etc.)
                let authorPatterns = [
                    #"by\s+([A-Z][a-zA-Z\s]+?)(?:\s|,|</)"#,
                    #"<span[^>]*class="[^"]*author[^"]*"[^>]*>([^<]+)</span>"#,
                    #"<div[^>]*class="[^"]*author[^"]*"[^>]*>([^<]+)</div>"#
                ]
                
                for authorPattern in authorPatterns {
                    if let authorRegex = try? NSRegularExpression(pattern: authorPattern, options: [.caseInsensitive]),
                       let authorMatch = authorRegex.firstMatch(in: context, options: [], range: NSRange(location: 0, length: context.count)),
                       authorMatch.range(at: 1).location != NSNotFound {
                        author = (context as NSString).substring(with: authorMatch.range(at: 1))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
                
                // Try to find price
                let pricePatterns = [
                    #"\$(\d+\.?\d*)"#,
                    #"<span[^>]*class="[^"]*price[^"]*"[^>]*>\$?(\d+\.?\d*)</span>"#
                ]
                
                for pricePattern in pricePatterns {
                    if let priceRegex = try? NSRegularExpression(pattern: pricePattern, options: [.caseInsensitive]),
                       let priceMatch = priceRegex.firstMatch(in: context, options: [], range: NSRange(location: 0, length: context.count)),
                       priceMatch.range(at: 1).location != NSNotFound {
                        price = "$" + (context as NSString).substring(with: priceMatch.range(at: 1))
                    }
                }
                
                // Build description with author and price
                var description: String? = nil
                if let author = author {
                    description = "by \(author)"
                    if let price = price {
                        description = "\(description!) • \(price)"
                    }
                } else if let price = price {
                    description = price
                }
                
                // Build metadata
                var metadata: [String: AnyHashable] = [:]
                if let author = author {
                    metadata["author"] = author
                }
                if let price = price {
                    metadata["price"] = price
                }
                metadata["attribution"] = "Bookshop.org"
                
                // Avoid duplicates
                if results.contains(where: { $0.url?.absoluteString == url.absoluteString }) {
                    continue
                }
                
                let result = SearchResult(
                    id: UUID().uuidString,
                    title: title,
                    description: description,
                    source: identifier,
                    sourceType: sourceType,
                    url: url,
                    location: nil,
                    distance: nil,
                    metadata: metadata
                )
                
                results.append(result)
            }
            
            // If we found results, use them
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
}
