import Foundation

/// On-device query-result cache. Keyed by normalized query string, bounded
/// by both TTL (default 24h — repeat searches in a single day skip the
/// network entirely) and entry count (default 64 — older entries are
/// evicted oldest-first when full).
public actor ResultCache {
    private var cache: [String: CachedResult] = [:]
    private let ttl: TimeInterval
    private let maxEntries: Int

    /// Default TTL: 24 hours. Default capacity: 64 distinct queries.
    /// Both can be overridden for tests or larger deployments.
    public init(ttl: TimeInterval = 86_400, maxEntries: Int = 64) {
        self.ttl = ttl
        self.maxEntries = maxEntries
    }

    /// Lowercases + trims a raw query string so trivially-different inputs
    /// (extra whitespace, casing) share a cache slot. `static` so callers
    /// can normalize without crossing the actor boundary.
    public static func normalizedKey(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func get(key: String) -> [SearchResult]? {
        guard let cached = cache[key] else { return nil }
        if Date().timeIntervalSince(cached.timestamp) >= ttl {
            cache.removeValue(forKey: key)
            return nil
        }
        return cached.results
    }

    public func set(key: String, results: [SearchResult]) {
        // Evict the oldest entry when full to keep the cache bounded.
        if cache[key] == nil, cache.count >= maxEntries {
            if let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                cache.removeValue(forKey: oldestKey)
            }
        }
        cache[key] = CachedResult(results: results, timestamp: Date())
    }

    public func clear() {
        cache.removeAll()
    }

    public func clearExpired() {
        let now = Date()
        cache = cache.filter { _, value in
            now.timeIntervalSince(value.timestamp) < ttl
        }
    }

    /// Test/inspection helper: number of entries currently in the cache.
    public var count: Int { cache.count }

    private struct CachedResult {
        let results: [SearchResult]
        let timestamp: Date
    }
}
