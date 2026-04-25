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
        
        return finalResults
    }
    
    public func filter(results: [SearchResult], denyList: DenyListFilter) -> [SearchResult] {
        // Create ad domain filter (returns empty set if list not downloaded yet - graceful degradation)
        let adFilter = AdDomainFilter()
        
        return results.filter { result in
            // Allow results from AmazonSearchSource even if URL is amazon.com
            // The deny list is meant to filter Amazon results from OTHER sources
            if result.source.lowercased() == SourceIdentifier.amazon {
                return true
            }
            
            guard let url = result.url else {
                // Results without URLs (e.g., local businesses) are allowed
                return true
            }
            
            // Resolve redirect URLs before filtering
            let resolvedURL = resolveRedirectURL(url)
            
            // Check for search provider ad URLs
            let resolvedURLString = resolvedURL.absoluteString.lowercased()
            let originalURLString = url.absoluteString.lowercased()
            
            // DuckDuckGo ad URLs (y.js?ad_domain= pattern)
            if (resolvedURLString.contains("duckduckgo.com/y.js") && resolvedURLString.contains("ad_domain=")) ||
               (originalURLString.contains("duckduckgo.com/y.js") && originalURLString.contains("ad_domain=")) {
                return false
            }
            
            // Bing ad URLs (aclk, clk patterns)
            if resolvedURLString.contains("bing.com/aclk") || resolvedURLString.contains("bing.com/clk") ||
               originalURLString.contains("bing.com/aclk") || originalURLString.contains("bing.com/clk") {
                return false
            }
            
            // Check deny list first
            if denyList.shouldFilter(url: resolvedURL) {
                return false
            }
            
            // Check ad domain filter (may have empty set if list not downloaded yet)
            if adFilter.shouldFilter(url: resolvedURL) {
                return false
            }
            
            return true
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
