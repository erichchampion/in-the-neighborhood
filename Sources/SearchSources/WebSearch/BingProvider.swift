import Foundation
import MetasearchCore

public final class BingProvider: WebSearchProvider, @unchecked Sendable {
    private let session: URLSession
    private let baseURL = "https://api.bing.microsoft.com/v7.0/search"
    private let apiKey: String?
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    
    // Helper struct for ad checking (needs to be accessible outside parseBingResponse)
    private struct WebPageInfo {
        let url: String?
        let displayUrl: String?
        let _type: String?
        let isSponsored: Bool?
        let isAd: Bool?
    }
    
    public init(apiKey: String? = nil, session: URLSession = .shared, maxRetries: Int = 3, retryDelay: TimeInterval = 1.0) {
        self.apiKey = apiKey
        self.session = session
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    public func search(query: String) async throws -> [SearchResult] {
        guard let apiKey = apiKey else {
            // Without API key, return empty results
            return []
        }
        
        // Enhance query for shopping if product intent is detected
        let enhancedQuery = enhanceQueryForShopping(query)
        
        return try await searchWithRetry(query: enhancedQuery, apiKey: apiKey, attempt: 0)
    }
    
    /// Enhances query to improve shopping/product search results
    private func enhanceQueryForShopping(_ query: String) -> String {
        let lowercasedQuery = query.lowercased()
        
        // Detect product intent indicators (for potential future query enhancement)
        let productIndicators = [
            "buy", "purchase", "price", "cost", "shop", "shopping",
            "product", "item", "for sale", "discount", "deal", "sale"
        ]
        
        _ = productIndicators.contains { indicator in
            lowercasedQuery.contains(indicator)
        }
        
        // If no explicit product intent, check for common product patterns
        // (e.g., brand names, model numbers, product categories)
        _ = detectProductPattern(query: lowercasedQuery)
        
        // If product intent is detected, the query is likely already optimized
        // Otherwise, we can optionally append shopping-related terms
        // For now, we'll return the original query as Bing's algorithm should handle it
        // But we'll mark it for shopping metadata extraction later
        return query
    }
    
    /// Detects if a query likely refers to a product (brand names, model numbers, etc.)
    private func detectProductPattern(query: String) -> Bool {
        // Check for model numbers (e.g., "iPhone 15", "MacBook Pro M3")
        let modelNumberPattern = #"\b[A-Z][a-z]+\s+\d+[A-Z]?\d*\b"#
        if let regex = try? NSRegularExpression(pattern: modelNumberPattern, options: []),
           regex.firstMatch(in: query, options: [], range: NSRange(location: 0, length: query.count)) != nil {
            return true
        }
        
        // Check for common product categories
        let productCategories = [
            "laptop", "phone", "tablet", "headphones", "speaker", "camera",
            "watch", "shoes", "clothing", "book", "game", "console",
            "tv", "monitor", "keyboard", "mouse", "printer", "router"
        ]
        
        return productCategories.contains { category in
            query.contains(category)
        }
    }
    
    private func searchWithRetry(query: String, apiKey: String, attempt: Int) async throws -> [SearchResult] {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "offset", value: "0")
        ]
        
        guard let url = components?.url else {
            throw WebSearchError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("InTheNeighborhood/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebSearchError.invalidResponse
            }
            
            // Handle rate limiting with retry
            if httpResponse.statusCode == 429 {
                if attempt < maxRetries {
                    // Exponential backoff: delay = retryDelay * 2^attempt
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
                }
                throw WebSearchError.rateLimitExceeded
            }
            
            // Handle other HTTP errors
            guard httpResponse.statusCode == 200 else {
                // For 401/403, don't retry (authentication issue)
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw WebSearchError.invalidResponse
                }
                
                // For 5xx errors, retry
                if httpResponse.statusCode >= 500 && attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
                }
                
                throw WebSearchError.invalidResponse
            }
            
            // Parse Bing API response
            // First check raw JSON for ad indicators, then parse
            return try parseBingResponse(data: data)
        } catch {
            // Retry on network errors
            if error is URLError && attempt < maxRetries {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
            }
            
            if error is WebSearchError {
                throw error
            }
            throw WebSearchError.networkError(error)
        }
    }
    
    private func parseBingResponse(data: Data) throws -> [SearchResult] {
        // Define response structures
        struct BingResponse: Codable {
            let webPages: WebPages?
            let news: News?
            let images: Images?
            
            struct WebPages: Codable {
                let value: [WebPage]?
            }
            
            struct WebPage: Codable {
                let name: String?
                let url: String?
                let snippet: String?
                let displayUrl: String?
                let dateLastCrawled: String?
                let _type: String?
                let isSponsored: Bool?
                let isAd: Bool?
                let id: String?
                
                // Additional fields that might indicate ads
                private enum CodingKeys: String, CodingKey {
                    case name, url, snippet, displayUrl, dateLastCrawled
                    case _type = "_type"
                    case isSponsored, isAd, id
                }
            }
            
            struct News: Codable {
                let value: [NewsItem]?
            }
            
            struct NewsItem: Codable {
                let name: String?
                let url: String?
                let description: String?
            }
            
            struct Images: Codable {
                let value: [ImageItem]?
            }
            
            struct ImageItem: Codable {
                let name: String?
                let contentUrl: String?
                let thumbnailUrl: String?
            }
        }
        
        // First, check raw JSON for ad indicators
        var adUrlSet: Set<String> = []
        if let rawJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let webPages = rawJson["webPages"] as? [String: Any],
           let webPagesValue = webPages["value"] as? [[String: Any]] {
            // Look for ads array or sponsored results
            if let ads = rawJson["ads"] as? [[String: Any]] {
                for ad in ads {
                    if let adUrl = ad["url"] as? String {
                        adUrlSet.insert(adUrl.lowercased())
                    }
                }
            }
            
            // Check each web page for ad indicators in raw JSON
            for pageJson in webPagesValue {
                if let pageUrl = pageJson["url"] as? String {
                    // Check for various ad indicators
                    if let isSponsored = pageJson["isSponsored"] as? Bool, isSponsored {
                        adUrlSet.insert(pageUrl.lowercased())
                    }
                    if let isAd = pageJson["isAd"] as? Bool, isAd {
                        adUrlSet.insert(pageUrl.lowercased())
                    }
                    if let type = pageJson["_type"] as? String,
                       (type.lowercased().contains("ad") || type.lowercased().contains("sponsored")) {
                        adUrlSet.insert(pageUrl.lowercased())
                    }
                }
            }
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let response: BingResponse
        do {
            response = try decoder.decode(BingResponse.self, from: data)
        } catch {
            // If JSON parsing fails, try to extract error information
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let _ = error["message"] as? String {
                throw WebSearchError.invalidResponse
            }
            throw WebSearchError.invalidResponse
        }
        
        var results: [SearchResult] = []
        
        // Create a map of image URLs by domain/page for shopping results
        var imageUrlMap: [String: String] = [:]
        if let images = response.images?.value {
            for image in images {
                if let contentUrl = image.contentUrl,
                   let thumbnailUrl = image.thumbnailUrl {
                    // Try to match images to web pages by domain
                    if let url = URL(string: contentUrl),
                       let domain = url.host {
                        imageUrlMap[domain] = thumbnailUrl
                    }
                }
            }
        }
        
        // Parse web pages (primary results)
        if let webPages = response.webPages?.value {
            results.append(contentsOf: webPages.compactMap { (page: BingResponse.WebPage) -> SearchResult? in
                guard let title = page.name,
                      let urlString = page.url,
                      let url = URL(string: urlString) else {
                    return nil
                }
                
                // Skip if this is identified as an ad
                let pageInfo = WebPageInfo(
                    url: page.url,
                    displayUrl: page.displayUrl,
                    _type: page._type,
                    isSponsored: page.isSponsored,
                    isAd: page.isAd
                )
                if isAdResult(pageInfo: pageInfo, adUrlSet: adUrlSet) {
                    return nil
                }
                
                // Extract shopping metadata
                let shoppingMetadata = extractShoppingMetadata(
                    snippet: page.snippet,
                    url: urlString,
                    imageUrlMap: imageUrlMap
                )
                
                // Build ProductMetadata
                let productMetadata = ProductMetadata(
                    price: shoppingMetadata["price"] as? String,
                    imageUrl: shoppingMetadata["imageUrl"] as? String,
                    displayUrl: page.displayUrl,
                    dateLastCrawled: page.dateLastCrawled,
                    shoppingDomain: shoppingMetadata["shoppingDomain"] as? String,
                    isShoppingResult: shoppingMetadata["isShoppingResult"] as? Bool
                )
                
                // Convert to dictionary for SearchResult (backward compatibility)
                var metadata = productMetadata.toDictionary()
                // Merge any additional shopping metadata that might not be in ProductMetadata
                for (key, value) in shoppingMetadata {
                    if metadata[key] == nil {
                        metadata[key] = value
                    }
                }
                
                return SearchResult(
                    id: UUID().uuidString,
                    title: title,
                    description: page.snippet,
                    source: SourceIdentifier.bing,
                    sourceType: .online,
                    category: .web,
                    url: url,
                    location: nil,
                    distance: nil,
                    metadata: metadata
                )
            })
        }
        
        // Parse news results (if available)
        if let newsItems = response.news?.value {
            results.append(contentsOf: newsItems.compactMap { item in
                guard let title = item.name,
                      let urlString = item.url,
                      let url = URL(string: urlString) else {
                    return nil
                }
                
                return SearchResult(
                    id: UUID().uuidString,
                    title: title,
                    description: item.description,
                    source: SourceIdentifier.bing,
                    sourceType: .online,
                    category: .web,
                    url: url,
                    location: nil,
                    distance: nil,
                    metadata: ["type": "news"]
                )
            })
        }
        
        return results
    }
    
    /// Checks if a Bing result appears to be an ad based on response fields and ad URL set
    private func isAdResult(pageInfo: WebPageInfo, adUrlSet: Set<String>) -> Bool {
        // First check if URL is in the known ad URL set from raw JSON
        if let url = pageInfo.url?.lowercased(), adUrlSet.contains(url) {
            return true
        }
        
        // Check explicit ad indicators in decoded response
        if let isSponsored = pageInfo.isSponsored, isSponsored {
            return true
        }
        if let isAd = pageInfo.isAd, isAd {
            return true
        }
        
        // Check _type field for ad indicators
        if let type = pageInfo._type?.lowercased() {
            if type.contains("ad") || type.contains("sponsored") || type.contains("advertisement") {
                return true
            }
        }
        
        // Check URL patterns that might indicate ads
        if let url = pageInfo.url?.lowercased() {
            let adUrlPatterns = [
                "/ads/",
                "/advertisement",
                "/sponsored",
                "bing.com/aclk",
                "bing.com/clk",
                "adclick",
                "adclick.net"
            ]
            if adUrlPatterns.contains(where: { url.contains($0) }) {
                return true
            }
        }
        
        // Check display URL for ad indicators
        if let displayUrl = pageInfo.displayUrl?.lowercased() {
            if displayUrl.contains("ad") || displayUrl.contains("sponsored") {
                // Be more careful here - only flag if it's clearly an ad domain
                let adDomains = [
                    "adclick",
                    "advertising",
                    "ads.",
                    "sponsored."
                ]
                if adDomains.contains(where: { displayUrl.contains($0) }) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Extracts shopping-related metadata from search results
    private func extractShoppingMetadata(snippet: String?, url: String, imageUrlMap: [String: String]) -> [String: AnyHashable] {
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
                
                // Try to find matching image URL
                if let imageUrl = imageUrlMap[domain] {
                    metadata["imageUrl"] = imageUrl
                }
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
}
