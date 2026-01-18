import Foundation
import MetasearchCore

public final class AmazonSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = "amazon"
    public let sourceType: SourceType = .online
    
    private let session: URLSession
    private let scraper: AmazonProductScraper
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    private let maxProductsToScrape: Int
    
    public init(
        session: URLSession = .shared,
        maxRetries: Int = 2,
        retryDelay: TimeInterval = 0.5,
        maxProductsToScrape: Int = 5
    ) {
        self.session = session
        self.scraper = AmazonProductScraper(session: session)
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.maxProductsToScrape = maxProductsToScrape
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        return try await searchWithRetry(query: query.original, attempt: 0)
    }
    
    private func searchWithRetry(query: String, attempt: Int) async throws -> [SearchResult] {
        // Amazon search URL
        var components = URLComponents(string: "https://www.amazon.com/s")
        components?.queryItems = [
            URLQueryItem(name: "k", value: query)
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
            
            let productUrls = parseSearchResults(html: html)
            
            // Scrape top products for detailed metadata
            return try await scrapeProducts(urls: productUrls.prefix(maxProductsToScrape))
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
    
    private func parseSearchResults(html: String) -> [URL] {
        var urls: [URL] = []
        let nsString = html as NSString
        
        // Amazon search results patterns - product links typically in data-asin attributes or hrefs
        let patterns = [
            // Pattern 1: Product link with data-asin
            #"<a[^>]*data-asin="([^"]+)"[^>]*href="([^"]+)"[^>]*>.*?<span[^>]*>([^<]+)</span>"#,
            // Pattern 2: Direct product link
            #"<a[^>]*href="(/dp/[^"]+)"[^>]*>.*?<span[^>]*>([^<]+)</span>"#,
            // Pattern 3: Product link in search result
            #"href="(/gp/product/[^"]+)"[^>]*>.*?<span[^>]*>([^<]+)</span>"#,
            // Pattern 4: Generic product link with title
            #"<h2[^>]*>.*?<a[^>]*href="([^"]*/(?:dp|gp/product)/[^"]+)"[^>]*>([^<]+)</a>"#
        ]
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                var urlString: String? = nil
                
                // Extract URL from different capture groups depending on pattern
                if match.numberOfRanges >= 3 {
                    // Some patterns have ASIN first, then URL
                    if match.range(at: 2).location != NSNotFound {
                        urlString = nsString.substring(with: match.range(at: 2))
                    } else if match.range(at: 1).location != NSNotFound {
                        urlString = nsString.substring(with: match.range(at: 1))
                    }
                }
                
                guard var urlString = urlString,
                      !urlString.isEmpty else {
                    continue
                }
                
                // Clean up URL
                urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Handle relative URLs
                if urlString.hasPrefix("/") {
                    urlString = "https://www.amazon.com\(urlString)"
                } else if !urlString.hasPrefix("http") {
                    continue
                }
                
                // Remove query parameters that might interfere
                if let urlObj = URL(string: urlString) {
                    var components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false)
                    // Keep only essential query parameters
                    let queryItems = components?.queryItems
                    components?.queryItems = queryItems?.filter { $0.name == "tag" || $0.name == "ref" }
                    
                    if let finalUrl = components?.url {
                        // Avoid duplicates
                        if !urls.contains(where: { $0.absoluteString == finalUrl.absoluteString }) {
                            urls.append(finalUrl)
                        }
                    }
                }
            }
            
            // If we found URLs with this pattern, use them
            if !urls.isEmpty {
                break
            }
        }
        
        return urls
    }
    
    private func scrapeProducts(urls: ArraySlice<URL>) async throws -> [SearchResult] {
        var results: [SearchResult] = []
        
        // Scrape products concurrently with timeout
        try await withThrowingTaskGroup(of: (URL, Result<AmazonProductMetadata, Error>).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let metadata = try await self.scraper.scrapeProduct(url: url)
                        return (url, .success(metadata))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            
            for try await (url, result) in group {
                switch result {
                case .success(let metadata):
                    // Use title from metadata or fallback
                    let title = metadata.title ?? extractTitleFromURL(url: url) ?? "Amazon Product"
                    
                    // Build description from metadata
                    var descriptionParts: [String] = []
                    if let brand = metadata.brand {
                        descriptionParts.append(brand)
                    }
                    if let price = metadata.price {
                        descriptionParts.append(price)
                    }
                    if let ratings = metadata.ratings {
                        descriptionParts.append("⭐ \(String(format: "%.1f", ratings))")
                    }
                    if let availability = metadata.availability {
                        descriptionParts.append(availability)
                    }
                    
                    let description = descriptionParts.isEmpty ? nil : descriptionParts.joined(separator: " • ")
                    
                    // Build metadata dictionary
                    var metadataDict: [String: AnyHashable] = [:]
                    if let price = metadata.price {
                        metadataDict["price"] = price
                    }
                    if let brand = metadata.brand {
                        metadataDict["brand"] = brand
                    }
                    if let ratings = metadata.ratings {
                        metadataDict["ratings"] = ratings
                    }
                    if let availability = metadata.availability {
                        metadataDict["availability"] = availability
                    }
                    if let asin = metadata.asin {
                        metadataDict["asin"] = asin
                    }
                    if let imageUrl = metadata.imageUrl {
                        metadataDict["imageUrl"] = imageUrl
                    }
                    
                    let result = SearchResult(
                        id: metadata.asin ?? UUID().uuidString,
                        title: title,
                        description: description,
                        source: identifier,
                        sourceType: sourceType,
                        url: url,
                        location: nil,
                        distance: nil,
                        metadata: metadataDict
                    )
                    
                    results.append(result)
                    
                case .failure:
                    // Skip failed products, continue with others
                    continue
                }
            }
        }
        
        return results
    }
    
    private func extractTitleFromURL(url: URL) -> String? {
        // Try to extract meaningful title from URL path
        let path = url.path
        if path.contains("/dp/") || path.contains("/gp/product/") {
            // URL structure: /dp/PRODUCT_NAME or /gp/product/PRODUCT_NAME
            let components = path.components(separatedBy: "/")
            if let productIndex = components.firstIndex(where: { $0 == "dp" || $0 == "gp" }),
               productIndex + 1 < components.count {
                let productId = components[productIndex + 1]
                // Clean up the product ID to make it more readable
                return productId.replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
            }
        }
        return nil
    }
}
