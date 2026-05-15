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
        // TTL is measured against `insertedAt`, not `lastAccessedAt`,
        // so popular entries still expire at the configured TTL rather
        // than refreshing forever just because they're being read.
        if Date().timeIntervalSince(cached.insertedAt) >= ttl {
            cache.removeValue(forKey: key)
            return nil
        }
        // Bump access time so the LRU eviction policy can recognize
        // this entry as recently used.
        cache[key] = CachedResult(
            results: cached.results,
            insertedAt: cached.insertedAt,
            lastAccessedAt: Date()
        )
        return cached.results
    }

    public func set(key: String, results: [SearchResult]) {
        // Evict the least-recently-ACCESSED entry when full. Insertion
        // time is the wrong signal — a frequently-read entry inserted
        // long ago is more valuable than a never-read entry inserted
        // recently.
        if cache[key] == nil, cache.count >= maxEntries {
            if let lruKey = cache.min(by: { $0.value.lastAccessedAt < $1.value.lastAccessedAt })?.key {
                cache.removeValue(forKey: lruKey)
            }
        }
        let now = Date()
        cache[key] = CachedResult(results: results, insertedAt: now, lastAccessedAt: now)
    }

    public func clear() {
        cache.removeAll()
    }

    public func clearExpired() {
        let now = Date()
        cache = cache.filter { _, value in
            now.timeIntervalSince(value.insertedAt) < ttl
        }
    }

    /// Test/inspection helper: number of entries currently in the cache.
    public var count: Int { cache.count }

    private struct CachedResult {
        let results: [SearchResult]
        /// When the entry was first written. Used for TTL expiry.
        let insertedAt: Date
        /// When the entry was most recently read (or written). Used for
        /// LRU eviction when the cache is at capacity.
        let lastAccessedAt: Date
    }
}
