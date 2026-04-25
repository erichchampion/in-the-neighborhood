import Foundation
import MetasearchCore
import SwiftSoup

public final class AmazonSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = SourceIdentifier.amazon
    public let sourceType: SourceType = .online
    public let category: ResultCategory = .product
    
    
    private let session: URLSession
    private let scraper: AmazonProductScraper
    private let webExtractor: FoundationModelWebExtractor
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
        self.webExtractor = FoundationModelWebExtractor()
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.maxProductsToScrape = maxProductsToScrape
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        let collector = SearchResultsCollector()
        try await searchStreaming(query: query) { results in
            Task {
                await collector.append(results)
            }
        }
        return await collector.allResults
    }

    public func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        print("[AmazonSearchSource] Starting streaming search for: \(query.original)")
        do {
            try await searchWithRetry(query: query.original, attempt: 0, onResults: onResults)
            print("[AmazonSearchSource] Streaming search completed for: \(query.original)")
        } catch {
            print("[AmazonSearchSource] Streaming search failed with error: \(error)")
            throw error
        }
    }
    
    private func searchWithRetry(query: String, attempt: Int, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        // Amazon search URL
        var components = URLComponents(string: "https://www.amazon.com/s")
        components?.queryItems = [
            URLQueryItem(name: "k", value: query)
        ]
        
        guard let url = components?.url else {
            print("[AmazonSearchSource] Failed to create URL")
            return
        }
        
        print("[AmazonSearchSource] Searching Amazon with URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        
        // Set headers to mimic a real browser request (based on curl command)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,es-419;q=0.8,es;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("8", forHTTPHeaderField: "Device-Memory")
        request.setValue("10", forHTTPHeaderField: "Downlink")
        request.setValue("2", forHTTPHeaderField: "DPR")
        request.setValue("4g", forHTTPHeaderField: "ECT")
        request.setValue("u=0, i", forHTTPHeaderField: "Priority")
        request.setValue("50", forHTTPHeaderField: "RTT")
        request.setValue("8", forHTTPHeaderField: "Sec-CH-Device-Memory")
        request.setValue("2", forHTTPHeaderField: "Sec-CH-DPR")
        request.setValue("390", forHTTPHeaderField: "Sec-CH-Viewport-Width")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("390", forHTTPHeaderField: "Viewport-Width")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return
            }
            
            // Handle rate limiting
            if httpResponse.statusCode == 429 || httpResponse.statusCode == 403 {
                if attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    try await searchWithRetry(query: query, attempt: attempt + 1, onResults: onResults)
                    return
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode >= 500 && attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    try await searchWithRetry(query: query, attempt: attempt + 1, onResults: onResults)
                    return
                }
                return
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                print("[AmazonSearchSource] Failed to decode HTML")
                return
            }
            
            print("[AmazonSearchSource] HTML received, length: \(html.count)")
            let productInfos = parseSearchResults(html: html)
            print("[AmazonSearchSource] Found \(productInfos.count) product URLs")
            
            // Scrape top products for detailed metadata
            try await scrapeProducts(productInfos: Array(productInfos.prefix(maxProductsToScrape)), originalQuery: query, onResults: onResults)
            print("[AmazonSearchSource] Finished scraping products")
        } catch {
            // Retry on network errors
            if attempt < maxRetries {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                try await searchWithRetry(query: query, attempt: attempt + 1, onResults: onResults)
                return
            }
        }
    }
    
    private struct ProductInfo {
        let url: URL
        let imageUrl: String?
    }
    
    private func parseSearchResults(html: String) -> [ProductInfo] {
        var productInfos: [ProductInfo] = []
        print("[AmazonSearchSource] Parsing search results HTML...")
        
        do {
            // Parse HTML into a Document
            let doc = try SwiftSoup.parse(html)
            
            // Find all search result containers
            // Query for div elements with role="listitem" and data-component-type="s-search-result"
            // Try multiple selector patterns to handle different HTML structures
            var searchResults = try doc.select("div[role=listitem][data-component-type=s-search-result]")
            if searchResults.isEmpty() {
                // Fallback: try without role attribute
                searchResults = try doc.select("div[data-component-type=s-search-result]")
            }
            print("[AmazonSearchSource] Found \(searchResults.count) search result containers")
            
            var allFoundUrls: [(url: String, imageUrl: String?)] = []
            var dataAsinUrls: [(url: String, imageUrl: String?)] = [] // Prioritize URLs with data-asin attributes
            
            // Process each search result container
            for (index, result) in searchResults.enumerated() {
                var foundUrl: String? = nil
                var foundImageUrl: String? = nil
                var hasDataAsin = false
                
                // Strategy 1: Look for link in product image span (most reliable)
                // Try both direct child and descendant selectors
                if let imageSpan = try? result.select("span[data-component-type=s-product-image]").first() {
                    // Extract product image from img.s-image
                    if let img = try? imageSpan.select("img.s-image").first() {
                        // Try src first, then data-src
                        if let src = try? img.attr("src"), !src.isEmpty {
                            foundImageUrl = src
                        } else if let dataSrc = try? img.attr("data-src"), !dataSrc.isEmpty {
                            foundImageUrl = dataSrc
                        }
                    }
                    
                    // Look for link within the image span (try direct child first, then any descendant)
                    var imageLink: Element? = try? imageSpan.select("> a").first()
                    if imageLink == nil {
                        imageLink = try? imageSpan.select("a").first()
                    }
                    
                    if let link = imageLink,
                       let href = try? link.attr("href"),
                       !href.isEmpty {
                        if let url = processProductUrl(href) {
                            foundUrl = url.absoluteString
                            // Check for data-asin on the link or span
                            if let asin = try? link.attr("data-asin"), !asin.isEmpty {
                                hasDataAsin = true
                            } else if let asin = try? imageSpan.attr("data-asin"), !asin.isEmpty {
                                hasDataAsin = true
                            }
                        }
                    }
                }
                
                // Strategy 2: Look for link related to price-link span (as mentioned by user)
                if foundUrl == nil {
                    // Look for link with aria-describedby="price-link" (the span#price-link is just a marker)
                    if let priceLink = try? result.select("a[aria-describedby=price-link]").first(),
                       let href = try? priceLink.attr("href"),
                       !href.isEmpty {
                        if let url = processProductUrl(href) {
                            foundUrl = url.absoluteString
                            if let asin = try? priceLink.attr("data-asin"), !asin.isEmpty {
                                hasDataAsin = true
                            }
                        }
                    }
                }
                
                // Strategy 3: Look for any link with /dp/ or /gp/product/ in the result container
                if foundUrl == nil {
                    if let productLink = try? result.select("a[href*=/dp/], a[href*=/gp/product/]").first(),
                       let href = try? productLink.attr("href"),
                       !href.isEmpty {
                        if let url = processProductUrl(href) {
                            foundUrl = url.absoluteString
                            // Check if this element or parent has data-asin attribute
                            if let asin = try? productLink.attr("data-asin"), !asin.isEmpty {
                                hasDataAsin = true
                            } else {
                                // Check parent elements for data-asin
                                var parent = productLink.parent()
                                while parent != nil {
                                    if let asin = try? parent?.attr("data-asin"), !asin.isEmpty {
                                        hasDataAsin = true
                                        break
                                    }
                                    parent = parent?.parent()
                                }
                            }
                        }
                    }
                }
                
                // If we found a URL but no image yet, try to find image in the result container
                if foundUrl != nil && foundImageUrl == nil {
                    // Try to find image anywhere in the result container
                    if let img = try? result.select("img.s-image").first() {
                        if let src = try? img.attr("src"), !src.isEmpty {
                            foundImageUrl = src
                        } else if let dataSrc = try? img.attr("data-src"), !dataSrc.isEmpty {
                            foundImageUrl = dataSrc
                        }
                    }
                }
                
                // Add the found URL and image to the appropriate list
                if let urlString = foundUrl {
                    if hasDataAsin {
                        if !dataAsinUrls.contains(where: { $0.url == urlString }) {
                            dataAsinUrls.append((url: urlString, imageUrl: foundImageUrl))
                            print("[AmazonSearchSource] Found data-asin URL in result \(index): \(urlString.prefix(100)), image: \(foundImageUrl != nil ? "yes" : "no")")
                        }
                    } else if !allFoundUrls.contains(where: { $0.url == urlString }) && !dataAsinUrls.contains(where: { $0.url == urlString }) {
                        allFoundUrls.append((url: urlString, imageUrl: foundImageUrl))
                        print("[AmazonSearchSource] Found URL in result \(index): \(urlString.prefix(100)), image: \(foundImageUrl != nil ? "yes" : "no")")
                    }
                } else {
                    print("[AmazonSearchSource] No URL found in result container \(index)")
                }
            }
            
            // Use data-asin URLs first (most reliable), then fall back to others
            // Limit to top 10 URLs to avoid scraping too many
            let maxUrls = 10
            let prioritizedUrls = dataAsinUrls.isEmpty ? Array(allFoundUrls.prefix(maxUrls)) : Array(dataAsinUrls.prefix(maxUrls))
            print("[AmazonSearchSource] Found \(dataAsinUrls.count) data-asin URLs, \(allFoundUrls.count) other URLs, using \(prioritizedUrls.count) total")
            
            if prioritizedUrls.isEmpty {
                print("[AmazonSearchSource] WARNING: No URLs extracted! This may indicate Amazon's HTML structure has changed.")
            } else {
                print("[AmazonSearchSource] URLs to scrape: \(prioritizedUrls.prefix(5).map { $0.url }.joined(separator: ", "))")
            }
            
            // Convert to ProductInfo objects
            for (urlString, imageUrl) in prioritizedUrls {
                if let url = URL(string: urlString) {
                    productInfos.append(ProductInfo(url: url, imageUrl: imageUrl))
                }
            }
            
            print("[AmazonSearchSource] Total product infos found: \(productInfos.count)")
        } catch {
            print("[AmazonSearchSource] Failed to parse HTML with SwiftSoup: \(error)")
            return []
        }
        
        return productInfos
    }
    
    private func processProductUrl(_ urlString: String) -> URL? {
        var cleanedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanedUrl.isEmpty else {
            return nil
        }
        
        // Skip non-product URLs - must contain /dp/ or /gp/product/
        guard cleanedUrl.contains("/dp/") || cleanedUrl.contains("/gp/product/") else {
            return nil
        }
        
        // Skip tracking/redirect URLs (Amazon uses these for analytics)
        if cleanedUrl.contains("aax-us-east-retail-direct") || 
           cleanedUrl.contains("aax-us-west-retail-direct") ||
           cleanedUrl.contains("aax-eu-west-retail-direct") ||
           cleanedUrl.contains("/x/c/") {
            return nil
        }
        
        // Skip URLs that look like search result navigation or other non-product links
        if cleanedUrl.contains("/s?") || cleanedUrl.contains("/s/") || cleanedUrl.contains("/ref=sr_") {
            return nil
        }
        
        // Skip credit card/financial product URLs early
        let creditCardKeywords = ["credit-card", "creditcard", "secured-card", "business-card", "american-express", "amazon-card"]
        if creditCardKeywords.contains(where: { cleanedUrl.lowercased().contains($0) }) {
            print("[AmazonSearchSource] Skipping credit card URL pattern: \(cleanedUrl.prefix(100))")
            return nil
        }
        
        // Handle relative URLs
        if cleanedUrl.hasPrefix("/") {
            cleanedUrl = "https://www.amazon.com\(cleanedUrl)"
        } else if !cleanedUrl.hasPrefix("http") {
            return nil
        }
        
        // Remove query parameters that might interfere
        guard let urlObj = URL(string: cleanedUrl) else {
            return nil
        }
        
        var components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false)
        // Keep only essential query parameters
        let queryItems = components?.queryItems
        components?.queryItems = queryItems?.filter { $0.name == "tag" || $0.name == "ref" }
        
        guard let finalUrl = components?.url else {
            return nil
        }
        
        let finalUrlString = finalUrl.absoluteString
        
        // Skip credit card URLs early (before adding to list)
        let creditCardASINs = ["B084KP3NG6", "B07984JN3L", "B00DB3BNIG"]
        if creditCardASINs.contains(where: { finalUrlString.contains($0) }) {
            print("[AmazonSearchSource] Skipping known credit card URL: \(finalUrlString)")
            return nil
        }
        
        return finalUrl
    }
    
    private func scrapeProducts(productInfos: [ProductInfo], originalQuery: String = "", onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        print("[AmazonSearchSource] Scraping \(productInfos.count) product pages...")
        
        // Normalize search query for matching - extract meaningful words (skip common stop words)
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from", "as", "is", "was", "are", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did", "will", "would", "should", "could", "may", "might", "must", "can"])
        var characterSet = CharacterSet.whitespacesAndNewlines
        characterSet.formUnion(CharacterSet.punctuationCharacters)
        let queryWords = originalQuery.lowercased()
            .components(separatedBy: characterSet)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 1 }
        
        // Scrape products concurrently - process sequentially to avoid cancellation issues
        for productInfo in productInfos {
            // Try FoundationModels extraction first, fall back to SwiftSoup scraping
            let metadata = await extractMetadata(url: productInfo.url)
            
            // Use title from metadata or fallback
            let title = metadata.title ?? extractTitleFromURL(url: productInfo.url) ?? "Amazon Product"
            
            // Validate relevance: check if product matches the search query
            if !queryWords.isEmpty {
                let isRelevant = isProductRelevant(
                    title: title,
                    brand: metadata.brand,
                    metadata: metadata,
                    queryWords: queryWords
                )
                
                if !isRelevant {
                    print("[AmazonSearchSource] Filtering out irrelevant product - title: '\(title)', query: '\(originalQuery)'")
                    continue
                }
            }
            
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
            
            // Build ProductMetadata
            // Prefer image URL from search results, fall back to detail page image
            let finalImageUrl = productInfo.imageUrl ?? metadata.imageUrl
            
            let productMetadata = ProductMetadata(
                isbn: metadata.isbn,
                author: metadata.author,
                sku: metadata.sku,
                asin: metadata.asin,
                brand: metadata.brand,
                artist: metadata.artist,
                price: metadata.price,
                imageUrl: finalImageUrl,
                availability: metadata.availability,
                ratings: metadata.ratings
            )
            
            // Convert to dictionary for SearchResult (backward compatibility)
            var metadataDict = productMetadata.toDictionary()
            // Add ratings as Double if available (ProductMetadata stores it as Double)
            if let ratings = metadata.ratings {
                metadataDict["ratings"] = ratings
            }
            
            // #region agent log
            print("[DEBUG] AmazonSearchSource.swift:265 - Metadata stored in SearchResult - url: \(productInfo.url.absoluteString), title: \(title), metadataKeys: \(Array(metadataDict.keys)), metadataDict: \(metadataDict.mapValues { String(describing: $0) })")
            // #endregion
            
            let result = SearchResult(
                id: metadata.asin ?? UUID().uuidString,
                title: title,
                description: description,
                source: identifier,
                sourceType: sourceType,
                category: category,
                url: productInfo.url,
                location: nil,
                distance: nil,
                metadata: metadataDict
            )
            
            // Yield directly to the callback instead of waiting for the full array
            onResults([result])
        }
    }
    
    /// Validates if a product is relevant to the search query by checking if search terms appear in product metadata
    private func isProductRelevant(title: String, brand: String?, metadata: AmazonProductMetadata, queryWords: [String]) -> Bool {
        // Normalize text for comparison
        let titleLower = title.lowercased()
        let brandLower = brand?.lowercased() ?? ""
        
        // Combine all searchable text
        var searchableText = titleLower
        if !brandLower.isEmpty {
            searchableText += " \(brandLower)"
        }
        if let author = metadata.author {
            searchableText += " \(author.lowercased())"
        }
        if let sku = metadata.sku {
            searchableText += " \(sku.lowercased())"
        }
        
        // Check if at least one significant query word appears in the product metadata
        // We require at least one match to consider it relevant
        var matchCount = 0
        for queryWord in queryWords {
            // Check for exact word match or substring match (for compound words)
            if searchableText.contains(queryWord) {
                // Verify it's a word boundary match (not just a substring in the middle of another word)
                // Simple check: word appears as standalone or at word boundaries
                let wordPattern = "\\b\(NSRegularExpression.escapedPattern(for: queryWord))\\b"
                if let regex = try? NSRegularExpression(pattern: wordPattern, options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: searchableText.utf16.count)
                    if regex.firstMatch(in: searchableText, options: [], range: range) != nil {
                        matchCount += 1
                    }
                } else {
                    // Fallback to simple contains if regex fails
                    matchCount += 1
                }
            }
        }
        
        // Product is relevant if at least one query word matches
        // For very short queries (1-2 words), require at least 1 match
        // For longer queries (3+ words), require at least 1 match (we can be more lenient)
        let isRelevant = matchCount > 0
        
        if !isRelevant {
            print("[AmazonSearchSource] Relevance check failed - queryWords: \(queryWords), title: '\(title)', matches: \(matchCount)")
        }
        
        return isRelevant
    }
    
    /// Tries FoundationModels extraction first; falls back to SwiftSoup scraping.
    private func extractMetadata(url: URL) async -> AmazonProductMetadata {
        // Phase 1: Try FoundationModels-powered extraction
        if webExtractor.isAvailable {
            do {
                let html = try await fetchProductHTML(url: url)
                if let metadata = await webExtractor.extract(html: html, url: url) {
                    print("[AmazonSearchSource] FoundationModels extraction succeeded for \(url.absoluteString)")
                    return metadata
                }
            } catch {
                print("[AmazonSearchSource] HTML fetch for FoundationModels failed: \(error.localizedDescription)")
            }
        }

        // Fallback: Use existing SwiftSoup scraper
        do {
            print("[AmazonSearchSource] Falling back to SwiftSoup scraping for \(url.absoluteString)")
            return try await scraper.scrapeProduct(url: url)
        } catch {
            print("[AmazonSearchSource] SwiftSoup scraping also failed: \(error.localizedDescription)")
            return AmazonProductMetadata(
                title: nil, price: nil, brand: nil, ratings: nil,
                availability: nil, asin: nil, imageUrl: nil,
                isbn: nil, sku: nil, author: nil, artist: nil
            )
        }
    }

    /// Fetches raw HTML for a product page, reusing the same browser-like headers.
    private func fetchProductHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15.0

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AmazonScrapingError.invalidResponse
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw AmazonScrapingError.invalidResponse
        }
        return html
    }

    private func extractTitleFromURL(url: URL) -> String? {
        // Try to extract meaningful title from URL path
        let path = url.path
        if path.contains("/dp/") || path.contains("/gp/product/") {
            // URL structure: /dp/PRODUCT_NAME or /gp/product/PRODUCT_NAME
            let components = path.components(separatedBy: "/")
            if let productIndex = components.firstIndex(where: { $0 == "dp" || $0 == "gp" }),
               productIndex + 1 < components.count {
                var productId = components[productIndex + 1]
                
                // Skip "product" if it's part of the path structure
                if productId.lowercased() == "product" && productIndex + 2 < components.count {
                    productId = components[productIndex + 2]
                }
                
                // If productId looks like an ASIN (starts with B and has 10 chars), don't use it as title
                if productId.count == 10 && productId.hasPrefix("B") && productId.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    // This is an ASIN, not a readable title - return nil to use fallback
                    return nil
                }
                
                // Clean up the product ID to make it more readable
                return productId.replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
            }
        }
        return nil
    }
}
