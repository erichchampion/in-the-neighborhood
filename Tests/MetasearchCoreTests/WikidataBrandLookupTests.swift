import XCTest
@testable import MetasearchCore

final class WikidataBrandLookupTests: XCTestCase {

    // MARK: - URL builders + static parsers (no network)

    func test_searchEntitiesURL_includesExpectedParams() {
        let url = WikidataBrandLookup.searchEntitiesURL(query: "Method")
        let s = url.absoluteString
        XCTAssertTrue(s.hasPrefix("https://www.wikidata.org/w/api.php"))
        for expected in [
            "action=wbsearchentities",
            "search=Method",
            "language=en",
            "format=json",
            "type=item",
            "limit=5"
        ] {
            XCTAssertTrue(s.contains(expected), "Missing \(expected) in \(s)")
        }
    }

    func test_sparqlURL_targetsQueryEndpointAndIncludesQID() {
        let url = WikidataBrandLookup.sparqlURL(qid: "Q19842")
        let s = url.absoluteString
        XCTAssertTrue(s.hasPrefix("https://query.wikidata.org/sparql"))
        let decoded = s.removingPercentEncoding ?? ""
        // The QID must appear inline in the SPARQL `wd:Q…` clauses.
        XCTAssertTrue(decoded.contains("wd:Q19842"), "QID must be substituted into the SPARQL body. Got: \(decoded)")
        // The three Wikidata property paths we care about must appear.
        XCTAssertTrue(decoded.contains("wdt:P127"), "owned-by predicate must be queried")
        XCTAssertTrue(decoded.contains("wdt:P749"), "parent-organization predicate must be queried")
        XCTAssertTrue(decoded.contains("wdt:P1027"), "certification predicate must be queried")
    }

    func test_normalizedKey_lowercasesAndTrims() {
        XCTAssertEqual(WikidataBrandLookup.normalizedKey("  Method  "), "method")
        XCTAssertEqual(WikidataBrandLookup.normalizedKey("BRAND"), "brand")
    }

    // MARK: - firstBrandQID

    func test_firstBrandQID_picksFirstCandidateWithBrandDescription() {
        let fixture = """
        {
          "search": [
            { "id": "Q11111", "label": "Method", "description": "rock band from California" },
            { "id": "Q19842", "label": "Method", "description": "American cleaning products company" },
            { "id": "Q22222", "label": "Method", "description": "a TV show" }
          ]
        }
        """.data(using: .utf8)!
        XCTAssertEqual(WikidataBrandLookup.firstBrandQID(from: fixture), "Q19842",
                       "Should skip rock-band entry and land on the cleaning-products company")
    }

    func test_firstBrandQID_returnsNilWhenNoCandidateLooksBrandy() {
        let fixture = """
        {
          "search": [
            { "id": "Q11111", "label": "Method", "description": "rock band from California" },
            { "id": "Q22222", "label": "Method", "description": "a method in programming" }
          ]
        }
        """.data(using: .utf8)!
        // Better to return nil than to confidently report a wrong QID.
        XCTAssertNil(WikidataBrandLookup.firstBrandQID(from: fixture))
    }

    func test_firstBrandQID_acceptsManufacturerCorporationProducts() {
        // The token list also accepts manufacturer / corporation / products.
        let fixtures: [(String, String)] = [
            ("X1", "American manufacturer of soap"),
            ("X2", "Multinational corporation"),
            ("X3", "American consumer products group")
        ]
        for (qid, desc) in fixtures {
            let data = """
            { "search": [ { "id": "\(qid)", "label": "Test", "description": "\(desc)" } ] }
            """.data(using: .utf8)!
            XCTAssertEqual(WikidataBrandLookup.firstBrandQID(from: data), qid,
                           "Description '\(desc)' should be classified brand-like")
        }
    }

    func test_firstBrandQID_returnsNilForMalformedJSON() {
        XCTAssertNil(WikidataBrandLookup.firstBrandQID(from: "garbage".data(using: .utf8)!))
        XCTAssertNil(WikidataBrandLookup.firstBrandQID(from: "{}".data(using: .utf8)!))
    }

    // MARK: - parseSPARQL

    func test_parseSPARQL_extractsParentAndCertifications() {
        let fixture = """
        {
          "head": { "vars": ["parent", "parentLabel", "certification", "certificationLabel"] },
          "results": {
            "bindings": [
              {
                "parent":      { "type": "uri", "value": "http://www.wikidata.org/entity/Q467691" },
                "parentLabel": { "type": "literal", "value": "S. C. Johnson & Son" }
              },
              {
                "certification":      { "type": "uri", "value": "http://www.wikidata.org/entity/Q4827881" },
                "certificationLabel": { "type": "literal", "value": "B Corporation" }
              },
              {
                "certification":      { "type": "uri", "value": "http://www.wikidata.org/entity/Q9999" },
                "certificationLabel": { "type": "literal", "value": "Fair Trade Certified" }
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let (parent, certs) = WikidataBrandLookup.parseSPARQL(data: fixture)
        XCTAssertEqual(parent, "S. C. Johnson & Son")
        XCTAssertEqual(certs, ["B Corporation", "Fair Trade Certified"])
    }

    func test_parseSPARQL_dedupesCertifications() {
        let fixture = """
        {
          "results": {
            "bindings": [
              { "certificationLabel": { "value": "B Corporation" } },
              { "certificationLabel": { "value": "B Corporation" } },
              { "certificationLabel": { "value": "B Corporation" } }
            ]
          }
        }
        """.data(using: .utf8)!
        let (_, certs) = WikidataBrandLookup.parseSPARQL(data: fixture)
        XCTAssertEqual(certs, ["B Corporation"])
    }

    func test_parseSPARQL_emptyBindings_returnsNilAndEmpty() {
        let fixture = #"{"results":{"bindings":[]}}"#.data(using: .utf8)!
        let (parent, certs) = WikidataBrandLookup.parseSPARQL(data: fixture)
        XCTAssertNil(parent)
        XCTAssertTrue(certs.isEmpty)
    }

    func test_parseSPARQL_malformedJSON_returnsNilAndEmpty() {
        let (parent, certs) = WikidataBrandLookup.parseSPARQL(data: "junk".data(using: .utf8)!)
        XCTAssertNil(parent)
        XCTAssertTrue(certs.isEmpty)
    }

    // MARK: - lookup() end-to-end with a branching mock

    func test_lookup_happyPath_returnsBrandInfoWithParentAndCert() async throws {
        let session = BranchingMockURLSession(routes: [
            "www.wikidata.org": (
                #"""
                { "search": [
                    { "id": "Q19842", "label": "Method", "description": "American cleaning products company" }
                ]}
                """#.data(using: .utf8)!,
                200
            ),
            "query.wikidata.org": (
                #"""
                { "results": { "bindings": [
                    { "parentLabel":        { "value": "S. C. Johnson & Son" } },
                    { "certificationLabel": { "value": "B Corporation" } }
                ]}}
                """#.data(using: .utf8)!,
                200
            )
        ])
        let sut = WikidataBrandLookup(urlSession: session)
        let info = try await sut.lookup(brand: "Method")
        XCTAssertEqual(info.brand, "Method")
        XCTAssertEqual(info.qid, "Q19842")
        XCTAssertEqual(info.parentCompany, "S. C. Johnson & Son")
        XCTAssertEqual(info.certifications, ["B Corporation"])
    }

    func test_lookup_brandNotFound_returnsEmptyBrandInfo() async throws {
        let session = BranchingMockURLSession(routes: [
            "www.wikidata.org": (
                #"""
                { "search": [
                    { "id": "Q11111", "label": "Method", "description": "rock band" }
                ]}
                """#.data(using: .utf8)!,
                200
            )
        ])
        let sut = WikidataBrandLookup(urlSession: session)
        let info = try await sut.lookup(brand: "Method")
        XCTAssertEqual(info.brand, "Method")
        XCTAssertNil(info.qid, "No brand-like candidate → no QID and no SPARQL call")
        XCTAssertNil(info.parentCompany)
        XCTAssertTrue(info.certifications.isEmpty)
        let sparqlCount = await session.requestsToHost("query.wikidata.org")
        XCTAssertEqual(sparqlCount, 0,
                       "SPARQL endpoint must not be queried when no QID was resolved")
    }

    func test_lookup_cacheHit_skipsBothNetworkCalls() async throws {
        let session = BranchingMockURLSession(routes: [
            "www.wikidata.org": (
                #"""
                { "search": [{ "id": "Q19842", "description": "company" }]}
                """#.data(using: .utf8)!,
                200
            ),
            "query.wikidata.org": (
                #"""
                { "results": { "bindings": [
                    { "parentLabel": { "value": "Parent Co" } }
                ]}}
                """#.data(using: .utf8)!,
                200
            )
        ])
        let sut = WikidataBrandLookup(urlSession: session)

        _ = try await sut.lookup(brand: "Method")
        _ = try await sut.lookup(brand: "method")  // case-insensitive cache hit
        _ = try await sut.lookup(brand: "  Method  ")  // whitespace-trim cache hit

        let searchCount = await session.requestsToHost("www.wikidata.org")
        let sparqlCount = await session.requestsToHost("query.wikidata.org")
        XCTAssertEqual(searchCount, 1, "wbsearchentities must be called exactly once")
        XCTAssertEqual(sparqlCount, 1, "SPARQL must be called exactly once")
    }

    func test_lookup_clearCache_forcesRefetch() async throws {
        let session = BranchingMockURLSession(routes: [
            "www.wikidata.org": (
                #"""
                { "search": [{ "id": "Q1", "description": "brand" }]}
                """#.data(using: .utf8)!,
                200
            ),
            "query.wikidata.org": (
                #"""
                { "results": { "bindings": [] }}
                """#.data(using: .utf8)!,
                200
            )
        ])
        let sut = WikidataBrandLookup(urlSession: session)

        _ = try await sut.lookup(brand: "Brand")
        await sut.clearCache()
        _ = try await sut.lookup(brand: "Brand")

        let searchCount = await session.requestsToHost("www.wikidata.org")
        XCTAssertEqual(searchCount, 2,
                       "After clearCache, the next lookup must re-hit the network")
    }

    func test_lookup_networkError_throws_andDoesNotPoisonCache() async {
        let session = BranchingMockURLSession(error: NSError(domain: "test", code: -1))
        let sut = WikidataBrandLookup(urlSession: session)
        do {
            _ = try await sut.lookup(brand: "Anything")
            XCTFail("Expected the lookup to throw")
        } catch {
            // expected
        }
        let count = await sut.cachedEntryCount
        XCTAssertEqual(count, 0, "Failed lookups must not leave partial cache entries")
    }
}

// MARK: - Branching mock URLSession

/// A URLSessionProtocol mock that routes responses based on the
/// request's host. Lets a single test exercise both Wikidata endpoints
/// (wbsearchentities on www.wikidata.org and SPARQL on
/// query.wikidata.org).
///
/// The request counter lives in a small actor — Swift 6 makes
/// `NSLock.lock()/unlock()` unavailable from async contexts, and the
/// protocol's `data(for:)` is async.
private final class BranchingMockURLSession: URLSessionProtocol, @unchecked Sendable {
    struct Response {
        let data: Data
        let statusCode: Int
    }

    private let routes: [String: Response]
    private let error: Error?
    private let counter = HostRequestCounter()

    init(routes: [String: (Data, Int)] = [:], error: Error? = nil) {
        self.routes = routes.mapValues { Response(data: $0.0, statusCode: $0.1) }
        self.error = error
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await data(for: request)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let host = request.url?.host {
            await counter.increment(host)
        }
        if let error { throw error }
        guard let host = request.url?.host,
              let route = routes[host] else {
            return (Data(), HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.org")!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: route.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (route.data, response)
    }

    func requestsToHost(_ host: String) async -> Int {
        await counter.count(for: host)
    }
}

private actor HostRequestCounter {
    private var counts: [String: Int] = [:]
    func increment(_ host: String) {
        counts[host, default: 0] += 1
    }
    func count(for host: String) -> Int {
        counts[host] ?? 0
    }
}
