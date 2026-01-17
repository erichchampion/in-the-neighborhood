import Foundation

public struct ResultAggregator {
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
        results.filter { result in
            guard let url = result.url else {
                // Results without URLs (e.g., local businesses) are allowed
                return true
            }
            
            return !denyList.shouldFilter(url: url)
        }
    }
}
