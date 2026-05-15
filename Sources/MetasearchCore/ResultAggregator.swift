import Foundation

public struct ResultAggregator: Sendable {
    public init() {}
    
    public func aggregate(results: [SearchResult]) -> [SearchResult] {
        // Deduplicate by ID
        var seenIDs: Set<String> = []
        var uniqueResults: [SearchResult] = []
        
        for result in results {
            if !seenIDs.contains(result.id) {
                seenIDs.insert(result.id)
                uniqueResults.append(result)
            }
        }
        
        // Also deduplicate by URL if IDs differ but URLs are the same
        var seenURLs: Set<String> = []
        var finalResults: [SearchResult] = []
        
        for result in uniqueResults {
            if let url = result.url?.absoluteString {
                if !seenURLs.contains(url) {
                    seenURLs.insert(url)
                    finalResults.append(result)
                }
            } else {
                finalResults.append(result)
            }
        }

        return NearDuplicateMerger.merge(finalResults)
    }
    
    public func filter(
        results: [SearchResult],
        denyList: DenyListFilter,
        scorer: EthicsScorer? = nil
    ) -> [SearchResult] {
        // Create ad domain filter (returns empty set if list not downloaded yet - graceful degradation)
        let adFilter = AdDomainFilter()

        return results.compactMap { result -> SearchResult? in
            // Allow AmazonSearchSource results ONLY for product category (for metadata extraction)
            // Web category Amazon results should be filtered (no direct shopping links)
            // Product results are scraped for brand/author/ISBN to improve local search refinement
            if result.source.lowercased() == SourceIdentifier.amazon && result.category == .product {
                return result
            }

            guard let url = result.url else {
                // Results without URLs (e.g., local businesses) are allowed
                return result
            }

            // Resolve redirect URLs before filtering
            let resolvedURL = resolveRedirectURL(url)

            // Check for search provider ad URLs
            let resolvedURLString = resolvedURL.absoluteString.lowercased()
            let originalURLString = url.absoluteString.lowercased()

            // DuckDuckGo ad URLs (y.js?ad_domain= pattern)
            if (resolvedURLString.contains("duckduckgo.com/y.js") && resolvedURLString.contains("ad_domain=")) ||
               (originalURLString.contains("duckduckgo.com/y.js") && originalURLString.contains("ad_domain=")) {
                return nil
            }

            // Bing ad URLs (aclk, clk patterns)
            if resolvedURLString.contains("bing.com/aclk") || resolvedURLString.contains("bing.com/clk") ||
               originalURLString.contains("bing.com/aclk") || originalURLString.contains("bing.com/clk") {
                return nil
            }

            // Check deny list (delegates mega-retailer blocking to the scorer
            // when one is provided; otherwise falls back to the hard-coded list).
            if denyList.shouldFilter(url: resolvedURL, scorer: scorer) {
                return nil
            }

            // Check ad domain filter (may have empty set if list not downloaded yet)
            if adFilter.shouldFilter(url: resolvedURL) {
                return nil
            }

            // Attach the ethics-ledger entry (if any) so downstream
            // ranking and UI badges can read it from result.metadata["ethics"].
            if let scorer,
               let host = resolvedURL.host?.lowercased(),
               let entry = scorer.entry(forHost: host) {
                return result.withMetadata(["ethics": entry])
            }
            return result
        }
    }
    
    /// Resolves DuckDuckGo and other redirect URLs to their actual destination
    private func resolveRedirectURL(_ url: URL) -> URL {
        let urlString = url.absoluteString
        
        // Check if this is a DuckDuckGo redirect URL
        if url.host?.lowercased() == "duckduckgo.com" || urlString.contains("uddg=") {
            // Extract the actual destination URL from the redirect
            if let uddgRange = urlString.range(of: "uddg=") {
                let encodedURL = String(urlString[uddgRange.upperBound...])
                // Handle multiple parameters - take everything up to next &
                let encodedPart: String
                if let paramEnd = encodedURL.firstIndex(of: "&") {
                    encodedPart = String(encodedURL[..<paramEnd])
                } else {
                    encodedPart = encodedURL
                }
                
                if let decoded = encodedPart.removingPercentEncoding,
                   let resolved = URL(string: decoded) {
                    return resolved
                }
            }
        }
        
        // Return original URL if not a redirect or if resolution failed
        return url
    }
}
