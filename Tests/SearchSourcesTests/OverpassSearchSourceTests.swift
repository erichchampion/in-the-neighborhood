import XCTest
import Foundation
import CoreLocation
@testable import SearchSources
@testable import MetasearchCore
@testable import LocationServices

/// Mock URLSession scoped to Overpass tests. Captures the outgoing request so
/// assertions can inspect method, body, and headers.
final class OverpassMockURLSession: URLSessionProtocol, @unchecked Sendable {
    let data: Data?
    let response: URLResponse?
    let error: Error?
    var lastRequest: URLRequest?

    init(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil) {
        self.data = data
        self.response = response
        self.error = error
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        if let error = error { throw error }
        return (data ?? Data(), response ?? URLResponse())
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error = error { throw error }
        return (data ?? Data(), response ?? URLResponse())
    }
}

final class OverpassSearchSourceTests: XCTestCase {
    var sut: OverpassSearchSource!
    var mockSession: OverpassMockURLSession!
    var testLocationService: TestLocationService!  // reused from NominatimSearchSourceTests

    override func setUp() {
        super.setUp()
        // Default mock returns an HTTP 200 with empty `elements`. Individual
        // tests override `mockSession.data` when they need a real fixture.
        let emptyBody = #"{"elements":[]}"#.data(using: .utf8)
        let ok = HTTPURLResponse(
            url: URL(string: "https://overpass-api.de/api/interpreter")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        mockSession = OverpassMockURLSession(data: emptyBody, response: ok)
        testLocationService = TestLocationService()
        sut = OverpassSearchSource(
            locationService: testLocationService,
            urlSession: mockSession,
            searchRadius: 5000
        )
    }

    override func tearDown() {
        sut = nil
        mockSession = nil
        testLocationService = nil
        super.tearDown()
    }

    // MARK: - Protocol Conformance

    func testConformsToSearchSource() {
        XCTAssertTrue((sut as Any) is SearchSource)
    }

    func testIdentifierIsOverpass() {
        XCTAssertEqual(sut.identifier, "overpass")
        XCTAssertEqual(sut.identifier, SourceIdentifier.overpass)
    }

    func testSourceTypeIsLocal() {
        XCTAssertEqual(sut.sourceType, .local)
    }

    func testCategoryIsLocal() {
        XCTAssertEqual(sut.category, .local)
    }

    // MARK: - Request shape

    func testSearchPostsToInterpreterEndpoint() async {
        let query = EnhancedQuery(original: "bookstore", productType: nil, categories: ["book"], priceMax: nil, condition: nil)
        _ = try? await sut.search(query: query)

        let request = mockSession.lastRequest
        XCTAssertEqual(request?.url?.absoluteString, "https://overpass-api.de/api/interpreter")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "User-Agent")?.contains("InTheNeighborhood"), true)
    }

    func testBookCategoryProducesShopBooksFilter() async {
        let query = EnhancedQuery(original: "moby dick", productType: nil, categories: ["book"], priceMax: nil, condition: nil)
        _ = try? await sut.search(query: query)

        guard let bodyData = mockSession.lastRequest?.httpBody,
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            XCTFail("No request body captured")
            return
        }
        // The body is `data=<percent-encoded Overpass QL>`. We decode and look
        // for the shop=books filter.
        XCTAssertTrue(bodyString.hasPrefix("data="), "Body must use form-encoded `data=` key. Got: \(bodyString)")
        let percentEncoded = String(bodyString.dropFirst("data=".count))
        let decoded = percentEncoded.removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains(#"["shop"="books"]"#), "Decoded body should contain shop=books filter. Got: \(decoded)")
        XCTAssertTrue(decoded.contains("around:5000,37.7749,-122.4194"), "Decoded body should include the around-radius around the user's location. Got: \(decoded)")
    }

    func testHardwareCategoryProducesMultipleShopFilters() async {
        let query = EnhancedQuery(original: "screwdriver", productType: nil, categories: ["hardware"], priceMax: nil, condition: nil)
        _ = try? await sut.search(query: query)

        guard let bodyData = mockSession.lastRequest?.httpBody,
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            XCTFail("No request body captured")
            return
        }
        let decoded = (String(bodyString.dropFirst("data=".count))).removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains(#"["shop"="hardware"]"#), "Decoded body should contain shop=hardware. Got: \(decoded)")
        XCTAssertTrue(decoded.contains(#"["shop"="doityourself"]"#), "Decoded body should contain shop=doityourself for hardware. Got: \(decoded)")
    }

    func testUnknownCategoryFallsBackToAnyShop() async {
        let query = EnhancedQuery(original: "stuff", productType: nil, categories: ["nonsense_category"], priceMax: nil, condition: nil)
        _ = try? await sut.search(query: query)

        guard let bodyData = mockSession.lastRequest?.httpBody,
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            XCTFail("No request body captured")
            return
        }
        let decoded = (String(bodyString.dropFirst("data=".count))).removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains(#"["shop"]"#), "Fallback should query any shop. Got: \(decoded)")
    }

    // MARK: - Response parsing

    func testParsesNodeAndWayElements() async throws {
        let fixture = """
        {
          "version": 0.6,
          "elements": [
            {
              "type": "node",
              "id": 111,
              "lat": 37.78,
              "lon": -122.41,
              "tags": { "name": "Indie Books", "shop": "books" }
            },
            {
              "type": "way",
              "id": 222,
              "center": { "lat": 37.79, "lon": -122.42 },
              "tags": { "name": "Big Box Books", "shop": "books" }
            }
          ]
        }
        """.data(using: .utf8)!

        let ok = HTTPURLResponse(
            url: URL(string: "https://overpass-api.de/api/interpreter")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        let session = OverpassMockURLSession(data: fixture, response: ok)
        let source = OverpassSearchSource(
            locationService: testLocationService,
            urlSession: session,
            searchRadius: 5000
        )

        let query = EnhancedQuery(original: "books", productType: nil, categories: ["book"], priceMax: nil, condition: nil)
        let results = try await source.search(query: query)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Indie Books")
        XCTAssertEqual(results[0].id, "overpass-node-111")
        XCTAssertEqual(results[0].location?.coordinate.latitude ?? 0, 37.78, accuracy: 0.0001)

        XCTAssertEqual(results[1].title, "Big Box Books")
        XCTAssertEqual(results[1].id, "overpass-way-222")
        XCTAssertEqual(results[1].location?.coordinate.latitude ?? 0, 37.79, accuracy: 0.0001)

        // All distances must be non-nil and computed from the user's location.
        XCTAssertNotNil(results[0].distance)
        XCTAssertNotNil(results[1].distance)
    }

    func testIgnoresElementsWithoutName() async throws {
        let fixture = """
        {
          "elements": [
            { "type": "node", "id": 1, "lat": 37.78, "lon": -122.41, "tags": { "shop": "books" } },
            { "type": "node", "id": 2, "lat": 37.79, "lon": -122.42, "tags": { "name": "Has Name", "shop": "books" } }
          ]
        }
        """.data(using: .utf8)!
        let ok = HTTPURLResponse(
            url: URL(string: "https://overpass-api.de/api/interpreter")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        let session = OverpassMockURLSession(data: fixture, response: ok)
        let source = OverpassSearchSource(locationService: testLocationService, urlSession: session)
        let query = EnhancedQuery(original: "books", productType: nil, categories: ["book"], priceMax: nil, condition: nil)
        let results = try await source.search(query: query)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Has Name")
    }

    func testEmptyElementsArrayReturnsEmptyResults() async throws {
        let query = EnhancedQuery(original: "anything", productType: nil, categories: ["book"], priceMax: nil, condition: nil)
        // setUp already configures an empty-elements response.
        let results = try await sut.search(query: query)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Failure modes

    func testNetworkErrorReturnsEmptyResults() async {
        let errorSession = OverpassMockURLSession(error: NSError(domain: "test", code: -1))
        let source = OverpassSearchSource(locationService: testLocationService, urlSession: errorSession)
        let query = EnhancedQuery(original: "anything", productType: nil, categories: ["book"], priceMax: nil, condition: nil)
        // search() collects via searchStreaming which yields [] then re-throws.
        // We just want to confirm the caller doesn't get a populated list.
        let collected: [SearchResult] = (try? await source.search(query: query)) ?? []
        XCTAssertTrue(collected.isEmpty)
    }

    func testNoLocationProducesEmptyResultsAndSkipsNetwork() async throws {
        let noLocation = TestLocationService(location: nil)
        let session = OverpassMockURLSession()
        let source = OverpassSearchSource(locationService: noLocation, urlSession: session)
        let query = EnhancedQuery(original: "books", productType: nil, categories: ["book"], priceMax: nil, condition: nil)
        let results = try await source.search(query: query)
        XCTAssertTrue(results.isEmpty)
        XCTAssertNil(session.lastRequest, "No network call should happen without a location")
    }

    // MARK: - OverpassTagMap

    func testTagMapResolvesKnownCategory() {
        XCTAssertEqual(OverpassTagMap.tags(forCategories: ["book"]), ["shop=books"])
    }

    func testTagMapIsCaseInsensitive() {
        XCTAssertEqual(OverpassTagMap.tags(forCategories: ["Hardware"]).sorted(), ["shop=doityourself", "shop=hardware"].sorted())
    }

    func testTagMapDedupesWhenMultipleCategoriesShareTags() {
        let tags = OverpassTagMap.tags(forCategories: ["book", "books", "bookstore"])
        XCTAssertEqual(tags, ["shop=books"], "Three book-synonym categories should collapse to one tag")
    }

    func testTagMapFallsBackForUnknownCategories() {
        XCTAssertEqual(OverpassTagMap.tags(forCategories: ["nonsense"]), OverpassTagMap.fallbackTags)
        XCTAssertEqual(OverpassTagMap.tags(forCategories: []), OverpassTagMap.fallbackTags)
    }

    // MARK: - C1: repair-tag classification

    func test_categoryTag_returnsRepairForShopRepair() {
        XCTAssertEqual(OverpassTagMap.categoryTag(for: ["shop": "repair"]), "repair")
    }

    func test_categoryTag_returnsRepairForMobilePhoneRepair() {
        XCTAssertEqual(OverpassTagMap.categoryTag(for: ["shop": "mobile_phone_repair"]), "repair")
    }

    func test_categoryTag_returnsRepairForComputerRepair() {
        XCTAssertEqual(OverpassTagMap.categoryTag(for: ["shop": "computer_repair"]), "repair")
    }

    func test_categoryTag_returnsRepairForBicycleRepairStation() {
        XCTAssertEqual(OverpassTagMap.categoryTag(for: ["amenity": "bicycle_repair_station"]),
                       "repair")
    }

    func test_categoryTag_returnsRepairForRepairCafe() {
        XCTAssertEqual(OverpassTagMap.categoryTag(for: ["amenity": "repair_cafe"]), "repair")
    }

    func test_categoryTag_returnsNilForNonRepairTags() {
        XCTAssertNil(OverpassTagMap.categoryTag(for: ["shop": "books"]))
        XCTAssertNil(OverpassTagMap.categoryTag(for: ["amenity": "library"]))
        XCTAssertNil(OverpassTagMap.categoryTag(for: [:]))
    }

    // MARK: - C1: parser surfaces metadata["category_tag"] for repair

    func test_parseResponse_attachesCategoryTagWhenRepairShop() async throws {
        // Two nodes: one is a repair shop (should get category_tag),
        // one is a bookstore (should not).
        let fixture = """
        {
          "elements": [
            {
              "type": "node",
              "id": 999,
              "lat": 37.78,
              "lon": -122.41,
              "tags": { "name": "Bike Repair Co", "shop": "repair" }
            },
            {
              "type": "node",
              "id": 888,
              "lat": 37.79,
              "lon": -122.42,
              "tags": { "name": "Indie Books", "shop": "books" }
            }
          ]
        }
        """.data(using: .utf8)!
        let ok = HTTPURLResponse(
            url: URL(string: "https://overpass-api.de/api/interpreter")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        let session = OverpassMockURLSession(data: fixture, response: ok)
        let source = OverpassSearchSource(locationService: testLocationService, urlSession: session)
        let query = EnhancedQuery(
            original: "anything",
            productType: nil,
            categories: ["book"],
            priceMax: nil,
            condition: nil
        )
        let results = try await source.search(query: query)
        XCTAssertEqual(results.count, 2)
        let repairResult = results.first(where: { $0.title == "Bike Repair Co" })
        let booksResult = results.first(where: { $0.title == "Indie Books" })
        XCTAssertEqual(repairResult?.metadata["category_tag"] as? String, "repair",
                       "Repair shop must carry the category_tag for ViewModel routing")
        XCTAssertNil(booksResult?.metadata["category_tag"],
                     "Non-repair shop must not carry the repair signal")
    }
}
