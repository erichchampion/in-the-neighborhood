import XCTest
import Foundation
@testable import SearchSources
@testable import MetasearchCore

final class OpenFactsSearchSourceTests: XCTestCase {
    var mockSession: MockURLSession!  // reused from DPLASearchSourceTests

    override func setUp() {
        super.setUp()
        let emptyBody = #"{"products":[]}"#.data(using: .utf8)
        let ok = HTTPURLResponse(
            url: URL(string: "https://world.openfoodfacts.org/api/v2/search")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        mockSession = MockURLSession(data: emptyBody, response: ok)
    }

    override func tearDown() {
        mockSession = nil
        super.tearDown()
    }

    // MARK: - Protocol conformance per factory

    func test_food_factory_identifierAndCategory() {
        let sut = OpenFactsSearchSource.food(urlSession: mockSession)
        XCTAssertEqual(sut.identifier, SourceIdentifier.openfoodfacts)
        XCTAssertEqual(sut.sourceType, .online)
        XCTAssertEqual(sut.category, .product)
        XCTAssertTrue((sut as Any) is SearchSource)
    }

    func test_beauty_factory_identifier() {
        let sut = OpenFactsSearchSource.beauty(urlSession: mockSession)
        XCTAssertEqual(sut.identifier, SourceIdentifier.openbeautyfacts)
    }

    func test_products_factory_identifier() {
        let sut = OpenFactsSearchSource.products(urlSession: mockSession)
        XCTAssertEqual(sut.identifier, SourceIdentifier.openproductsfacts)
    }

    func test_petFood_factory_identifier() {
        let sut = OpenFactsSearchSource.petFood(urlSession: mockSession)
        XCTAssertEqual(sut.identifier, SourceIdentifier.openpetfoodfacts)
    }

    // MARK: - URL construction respects the host

    func test_buildURL_usesFoodHostForFoodFactory() {
        let url = OpenFactsSearchSource.buildURL(
            host: "world.openfoodfacts.org",
            query: "oat milk",
            maxResults: 20
        )
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("https://world.openfoodfacts.org/api/v2/search"),
                      "Got: \(s)")
    }

    func test_buildURL_usesBeautyHostForBeautyFactory() {
        let url = OpenFactsSearchSource.buildURL(
            host: "world.openbeautyfacts.org",
            query: "shampoo",
            maxResults: 20
        )
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.hasPrefix("https://world.openbeautyfacts.org/api/v2/search"))
    }

    func test_buildURL_usesProductsHostForProductsFactory() {
        let url = OpenFactsSearchSource.buildURL(
            host: "world.openproductsfacts.org",
            query: "toothbrush",
            maxResults: 20
        )
        XCTAssertTrue(url!.absoluteString.hasPrefix("https://world.openproductsfacts.org/api/v2/search"))
    }

    func test_buildURL_usesPetFoodHostForPetFoodFactory() {
        let url = OpenFactsSearchSource.buildURL(
            host: "world.openpetfoodfacts.org",
            query: "dog food",
            maxResults: 20
        )
        XCTAssertTrue(url!.absoluteString.hasPrefix("https://world.openpetfoodfacts.org/api/v2/search"))
    }

    func test_buildURL_includesAllRequestedFields() {
        let url = OpenFactsSearchSource.buildURL(
            host: "world.openfoodfacts.org",
            query: "x",
            maxResults: 20
        )!
        let decoded = url.absoluteString.removingPercentEncoding ?? ""
        for field in [
            "code", "product_name", "brands", "image_url",
            "nutriscore_grade", "ecoscore_grade", "nova_group", "labels_tags"
        ] {
            XCTAssertTrue(decoded.contains(field),
                          "URL must request \(field). Got: \(decoded)")
        }
        XCTAssertTrue(decoded.contains("page_size=20"))
        XCTAssertTrue(decoded.contains("json=true"))
    }

    func test_buildURL_rejectsEmptyQuery() {
        XCTAssertNil(OpenFactsSearchSource.buildURL(host: "world.openfoodfacts.org", query: "", maxResults: 20))
        XCTAssertNil(OpenFactsSearchSource.buildURL(host: "world.openfoodfacts.org", query: "  \n", maxResults: 20))
    }

    func test_searchSetsUserAgentHeader() async throws {
        let sut = OpenFactsSearchSource.food(urlSession: mockSession)
        _ = try? await sut.search(query: EnhancedQuery(
            original: "test", productType: nil, categories: [], priceMax: nil, condition: nil
        ))
        let ua = mockSession.lastRequest?.value(forHTTPHeaderField: "User-Agent")
        XCTAssertNotNil(ua)
        XCTAssertEqual(ua?.contains("InTheNeighborhood"), true)
    }

    // MARK: - Response parsing

    func test_parseResponse_mapsFoodProductWithAllFields() {
        let fixture = """
        {
          "products": [
            {
              "code": "5410228197867",
              "product_name": "Alpro Oat Original",
              "brands": "Alpro, Danone",
              "image_url": "https://example.org/img.jpg",
              "nutriscore_grade": "b",
              "ecoscore_grade": "a",
              "nova_group": 4
            }
          ]
        }
        """.data(using: .utf8)!
        let results = OpenFactsSearchSource.parseResponse(
            data: fixture,
            host: "world.openfoodfacts.org",
            sourceId: SourceIdentifier.openfoodfacts
        )
        XCTAssertEqual(results.count, 1)
        let r = results[0]
        XCTAssertEqual(r.id, "openfoodfacts-5410228197867")
        XCTAssertEqual(r.title, "Alpro Oat Original")
        XCTAssertEqual(r.url?.absoluteString, "https://world.openfoodfacts.org/product/5410228197867")
        XCTAssertEqual(r.metadata["brand"] as? String, "Alpro",
                       "Only first comma-separated brand should be kept")
        XCTAssertEqual(r.metadata["imageUrl"] as? String, "https://example.org/img.jpg")
        XCTAssertEqual(r.metadata["nutriscore_grade"] as? String, "B")
        XCTAssertEqual(r.metadata["ecoscore_grade"] as? String, "A")
        XCTAssertEqual(r.metadata["nova_group"] as? Int, 4)
        XCTAssertEqual(r.metadata["barcode"] as? String, "5410228197867")
        XCTAssertEqual(r.metadata["open_facts_source"] as? String, "world.openfoodfacts.org")
        XCTAssertEqual(r.source, SourceIdentifier.openfoodfacts)
        XCTAssertEqual(r.category, .product)
    }

    func test_parseResponse_skipsFoodSpecificFieldsWhenAbsent() {
        // Non-food hosts often omit nutriscore_grade / nova_group entirely.
        // Result must still parse, just without those metadata keys.
        let fixture = """
        {
          "products": [
            {
              "code": "0123456789012",
              "product_name": "Bamboo Toothbrush",
              "brands": "Brush With Bamboo",
              "image_url": "https://example.org/brush.jpg",
              "ecoscore_grade": "a"
            }
          ]
        }
        """.data(using: .utf8)!
        let results = OpenFactsSearchSource.parseResponse(
            data: fixture,
            host: "world.openproductsfacts.org",
            sourceId: SourceIdentifier.openproductsfacts
        )
        XCTAssertEqual(results.count, 1)
        let r = results[0]
        XCTAssertEqual(r.title, "Bamboo Toothbrush")
        XCTAssertEqual(r.metadata["ecoscore_grade"] as? String, "A")
        XCTAssertNil(r.metadata["nutriscore_grade"], "Absent food-grade should not produce a metadata entry")
        XCTAssertNil(r.metadata["nova_group"])
    }

    func test_parseResponse_skipsProductsWithoutProductName() {
        let fixture = """
        {
          "products": [
            { "code": "111", "brands": "NoName" },
            { "code": "222", "product_name": "", "brands": "Empty" },
            { "code": "333", "product_name": "Real Product" }
          ]
        }
        """.data(using: .utf8)!
        let results = OpenFactsSearchSource.parseResponse(
            data: fixture,
            host: "world.openfoodfacts.org",
            sourceId: SourceIdentifier.openfoodfacts
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Real Product")
    }

    func test_parseResponse_emptyProducts_returnsEmpty() {
        let fixture = #"{"products":[]}"#.data(using: .utf8)!
        let results = OpenFactsSearchSource.parseResponse(
            data: fixture,
            host: "world.openfoodfacts.org",
            sourceId: SourceIdentifier.openfoodfacts
        )
        XCTAssertEqual(results.count, 0)
    }

    func test_parseResponse_malformedJSON_returnsEmpty() {
        let fixture = "garbage".data(using: .utf8)!
        XCTAssertEqual(
            OpenFactsSearchSource.parseResponse(
                data: fixture,
                host: "world.openfoodfacts.org",
                sourceId: SourceIdentifier.openfoodfacts
            ).count,
            0
        )
    }

    func test_parseResponse_handlesNovaGroupAsString() {
        // Some Open Facts responses ship nova_group as a stringified int.
        let fixture = """
        { "products": [{ "code": "1", "product_name": "X", "nova_group": "3" }] }
        """.data(using: .utf8)!
        let results = OpenFactsSearchSource.parseResponse(
            data: fixture,
            host: "world.openfoodfacts.org",
            sourceId: SourceIdentifier.openfoodfacts
        )
        XCTAssertEqual(results.first?.metadata["nova_group"] as? Int, 3)
    }

    // MARK: - Failure modes

    func test_nonHTTPResponse_returnsEmpty() async throws {
        let session = MockURLSession(
            data: "x".data(using: .utf8),
            response: URLResponse()
        )
        let sut = OpenFactsSearchSource.food(urlSession: session)
        let results = try await sut.search(query: EnhancedQuery(
            original: "test", productType: nil, categories: [], priceMax: nil, condition: nil
        ))
        XCTAssertTrue(results.isEmpty)
    }

    func test_networkError_returnsEmpty() async {
        let session = MockURLSession(error: NSError(domain: "test", code: -1))
        let sut = OpenFactsSearchSource.food(urlSession: session)
        let query = EnhancedQuery(
            original: "test", productType: nil, categories: [], priceMax: nil, condition: nil
        )
        let collected: [SearchResult] = (try? await sut.search(query: query)) ?? []
        XCTAssertTrue(collected.isEmpty)
    }
}
