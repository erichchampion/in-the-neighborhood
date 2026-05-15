import Foundation

/// Information Wikidata has on file for a brand: a parent company (if
/// any) and a list of certifications (B-Corp, Fair Trade, etc.).
public struct BrandInfo: Codable, Hashable, Sendable {
    public let brand: String
    public let qid: String?
    public let parentCompany: String?
    public let certifications: [String]

    public init(
        brand: String,
        qid: String? = nil,
        parentCompany: String? = nil,
        certifications: [String] = []
    ) {
        self.brand = brand
        self.qid = qid
        self.parentCompany = parentCompany
        self.certifications = certifications
    }
}

/// Two-step Wikidata lookup for brand metadata. Hits
/// `www.wikidata.org/w/api.php?action=wbsearchentities` to find the
/// Wikidata QID for a brand name, then runs a SPARQL query at
/// `query.wikidata.org/sparql` to extract the parent company (P127 or
/// P749) and any certifications (P1027).
///
/// **Important:** this is a *tool*, not a live filter. Wikidata's SPARQL
/// endpoint commonly takes 3-5 seconds per query, and we already have a
/// 4-second per-source budget in the coordinator. Wiring this into the
/// inline search path would tank latency. Use it from background
/// enrichment tasks, a future C7 "Why this result?" drawer, or to seed
/// `EthicsLedger.json` during development.
///
/// Results are cached in-memory for `cacheTTL` (default 7 days — brand
/// ownership changes rarely). A persistent cache backing is a follow-up.
public actor WikidataBrandLookup {
    private let urlSession: URLSessionProtocol
    private let cacheTTL: TimeInterval
    private var cache: [String: CachedBrandInfo] = [:]
    private let userAgent = "InTheNeighborhood/1.0 (com.in-the-neighborhood)"

    public init(
        urlSession: URLSessionProtocol = URLSessionAdapter(),
        cacheTTL: TimeInterval = 604_800 // 7 days
    ) {
        self.urlSession = urlSession
        self.cacheTTL = cacheTTL
    }

    /// Looks up brand info via Wikidata. Returns a `BrandInfo` whose
    /// `qid`, `parentCompany`, and `certifications` may all be nil/empty
    /// if Wikidata has no entry that looks like a brand for the given
    /// name — callers should treat that as "no info" rather than an
    /// error.
    public func lookup(brand: String) async throws -> BrandInfo {
        let key = Self.normalizedKey(brand)

        if let entry = cache[key],
           Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            return entry.info
        }

        // Step 1: find the Wikidata QID via wbsearchentities.
        guard let qid = try await findQID(forBrand: brand) else {
            let info = BrandInfo(brand: brand)
            cache[key] = CachedBrandInfo(info: info, timestamp: Date())
            return info
        }

        // Step 2: SPARQL for parent/certifications.
        let (parent, certs) = try await fetchEntityInfo(qid: qid)
        let info = BrandInfo(
            brand: brand,
            qid: qid,
            parentCompany: parent,
            certifications: certs
        )
        cache[key] = CachedBrandInfo(info: info, timestamp: Date())
        return info
    }

    public func clearCache() {
        cache.removeAll()
    }

    /// Test/inspection helper: how many entries are currently cached.
    public var cachedEntryCount: Int { cache.count }

    // MARK: - Private steps

    private func findQID(forBrand brand: String) async throws -> String? {
        let url = Self.searchEntitiesURL(query: brand)
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await urlSession.data(for: request)
        return Self.firstBrandQID(from: data)
    }

    private func fetchEntityInfo(qid: String) async throws -> (parent: String?, certs: [String]) {
        let url = Self.sparqlURL(qid: qid)
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await urlSession.data(for: request)
        return Self.parseSPARQL(data: data)
    }

    // MARK: - Static helpers (exposed for tests)

    static func normalizedKey(_ brand: String) -> String {
        brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func searchEntitiesURL(query: String) -> URL {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbsearchentities"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "type", value: "item"),
            URLQueryItem(name: "limit", value: "5")
        ]
        return components.url!
    }

    static func sparqlURL(qid: String) -> URL {
        let sparql = """
        SELECT ?parent ?parentLabel ?certification ?certificationLabel WHERE {
          OPTIONAL { wd:\(qid) wdt:P127 ?parent. }
          OPTIONAL { wd:\(qid) wdt:P749 ?parent. }
          OPTIONAL { wd:\(qid) wdt:P1027 ?certification. }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        LIMIT 50
        """
        var components = URLComponents(string: "https://query.wikidata.org/sparql")!
        components.queryItems = [
            URLQueryItem(name: "query", value: sparql),
            URLQueryItem(name: "format", value: "json")
        ]
        return components.url!
    }

    /// Picks the first wbsearchentities candidate whose description hints
    /// at "brand", "company", "corporation", or "manufacturer". Returns
    /// `nil` if no candidate looks brand-like — better to return nil
    /// than to confidently report (e.g.) a rock band's QID for a brand
    /// query.
    static func firstBrandQID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let search = json["search"] as? [[String: Any]] else {
            return nil
        }
        let brandTokens = ["brand", "company", "corporation", "manufacturer", "products"]
        for item in search {
            guard let id = item["id"] as? String, !id.isEmpty else { continue }
            let description = (item["description"] as? String)?.lowercased() ?? ""
            if !description.isEmpty,
               brandTokens.contains(where: { description.contains($0) }) {
                return id
            }
        }
        return nil
    }

    /// Parses a SPARQL JSON result. Picks the first non-empty
    /// `parentLabel` value and collects unique `certificationLabel`
    /// values across all bindings (since `OPTIONAL` branches produce
    /// one row per match).
    static func parseSPARQL(data: Data) -> (parent: String?, certs: [String]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let bindings = results["bindings"] as? [[String: Any]] else {
            return (nil, [])
        }
        var parent: String?
        var certs: [String] = []
        var seenCerts = Set<String>()
        for binding in bindings {
            if parent == nil,
               let parentLabel = (binding["parentLabel"] as? [String: Any])?["value"] as? String,
               !parentLabel.isEmpty {
                parent = parentLabel
            }
            if let certLabel = (binding["certificationLabel"] as? [String: Any])?["value"] as? String,
               !certLabel.isEmpty,
               seenCerts.insert(certLabel).inserted {
                certs.append(certLabel)
            }
        }
        return (parent, certs)
    }

    // MARK: - Cache entry

    private struct CachedBrandInfo {
        let info: BrandInfo
        let timestamp: Date
    }
}
