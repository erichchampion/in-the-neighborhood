import Foundation

public actor ResultCache {
    private var cache: [String: CachedResult] = [:]
    private let ttl: TimeInterval // 5 minutes default
    
    public init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }
    
    public func get(key: String) -> [SearchResult]? {
        guard let cached = cache[key],
              Date().timeIntervalSince(cached.timestamp) < ttl else {
            // Expired or not found
            cache.removeValue(forKey: key)
            return nil
        }
        
        return cached.results
    }
    
    public func set(key: String, results: [SearchResult]) {
        cache[key] = CachedResult(
            results: results,
            timestamp: Date()
        )
    }
    
    public func clear() {
        cache.removeAll()
    }
    
    public func clearExpired() {
        let now = Date()
        cache = cache.filter { key, value in
            now.timeIntervalSince(value.timestamp) < ttl
        }
    }
    
    private struct CachedResult {
        let results: [SearchResult]
        let timestamp: Date
    }
}
