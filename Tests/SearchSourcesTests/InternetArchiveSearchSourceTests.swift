import XCTest
import Foundation
@testable import SearchSources
@testable import MetasearchCore

final class InternetArchiveSearchSourceTests: XCTestCase {
    var mockSession: MockURLSession!  // reused from DPLASearchSourceTests
    var sut: InternetArchiveSearchSource!

    override func setUp() {
        super.setUp()
        let emptyResponse = #"{"response":{"numFound":0,"start":0,"docs":[]}}"#.data(using: .utf8)
        let ok = HTTPURLResponse(
            url: URL(string: "https://archive.org/advancedsearch.php")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        mockSession = MockURLSession(data: emptyResponse, response: ok)
        sut = InternetArchiveSearchSource(urlSession: mockSession)
    }

    override func tearDown() {
        sut = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - Protocol conformance

    func testConformsToSearchSource() {
        XCTAssertTrue((sut as Any) is SearchSource)
    }

    func testIdentifierIsInternetArchive() {
        XCTAssertEqual(sut.identifier, "internetarchive")
        XCTAssertEqual(sut.identifier, SourceIdentifier.internetarchive)
    }

    func testSourceTypeIsOnline() {
        XCTAssertEqual(sut.sourceType, .online)
    }

    func testCategoryIsBook() {
        XCTAssertEqual(sut.category, .book)
    }

    // MARK: - URL construction

    func testBuildURL_includesAdvancedSearchEndpoint() {
        let url = InternetArchiveSearchSource.buildURL(query: "moby dick", maxResults: 20)
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("https://archive.org/advancedsearch.php"), "URL must hit the advancedsearch endpoint. Got: \(s)")
    }

    func testBuildURL_appliesMediatypeFilter() {
        let url = InternetArchiveSearchSource.buildURL(query: "jazz", maxResults: 20)
        let decoded = url!.absoluteString.removingPercentEncoding ?? ""
        // The filter is appended via `AND mediatype:(texts OR audio OR movies)` inside the q= value.
        XCTAssertTrue(decoded.contains("mediatype:(texts OR audio OR movies)"),
                      "URL must restrict the search to texts/audio/movies. Got: \(decoded)")
        XCTAssertTrue(decoded.contains("jazz"), "User query must survive into the q= parameter")
    }

    func testBuildURL_requestsJSONOutputAndCorrectRowCount() {
        let url = InternetArchiveSearchSource.buildURL(query: "anything", maxResults: 15)!
        let s = url.absoluteString
        XCTAssertTrue(s.contains("output=json"))
        XCTAssertTrue(s.contains("rows=15"))
    }

    func testBuildURL_requestsExpectedFields() {
        let url = InternetArchiveSearchSource.buildURL(query: "x", maxResults: 1)!
        let s = url.absoluteString
        // URLComponents encodes `[` as `%5B`. Decode for readability.
        let decoded = s.removingPercentEncoding ?? ""
        for field in ["identifier", "title", "creator", "mediatype", "date", "description"] {
            XCTAssertTrue(decoded.contains("fl[]=\(field)"),
                          "URL must request the \(field) field. Got: \(decoded)")
        }
    }

    func testBuildURL_rejectsEmptyQuery() {
        XCTAssertNil(InternetArchiveSearchSource.buildURL(query: "", maxResults: 20))
        XCTAssertNil(InternetArchiveSearchSource.buildURL(query: "  \n", maxResults: 20))
    }

    func testSearchSetsUserAgentHeader() async throws {
        _ = try? await sut.search(query: EnhancedQuery(
            original: "test",
            productType: nil,
            categories: ["books"],
            priceMax: nil,
            condition: nil
        ))
        let request = mockSession.lastRequest
        XCTAssertNotNil(request)
        let ua = request?.value(forHTTPHeaderField: "User-Agent")
        XCTAssertNotNil(ua)
        XCTAssertEqual(ua?.contains("InTheNeighborhood"), true)
    }

    // MARK: - Response parsing

    func testParse_textsAudioAndMovies_mapToCorrectMetadata() {
        let fixture = """
        {
          "response": {
            "numFound": 3,
            "docs": [
              {
                "identifier": "mobydick00melv",
                "title": "Moby Dick",
                "creator": "Herman Melville",
                "mediatype": "texts",
                "date": "1851-01-01",
                "description": "A whaling novel"
              },
              {
                "identifier": "JazzNight1925",
                "title": ["Jazz Night 1925"],
                "creator": ["Various Artists"],
                "mediatype": "audio",
                "date": "1925"
              },
              {
                "identifier": "BusterKeaton_TheGeneral",
                "title": "The General",
                "creator": "Buster Keaton",
                "mediatype": "movies",
                "date": "1926-12-31"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let results = InternetArchiveSearchSource.parseResponse(data: fixture)
        XCTAssertEqual(results.count, 3)

        let texts = results[0]
        XCTAssertEqual(texts.title, "Moby Dick")
        XCTAssertEqual(texts.id, "ia-mobydick00melv")
        XCTAssertEqual(texts.url?.absoluteString, "https://archive.org/details/mobydick00melv")
        XCTAssertEqual(texts.metadata["mediatype"] as? String, "texts")
        XCTAssertEqual(texts.metadata["ia_identifier"] as? String, "mobydick00melv")
        XCTAssertEqual(texts.metadata["author"] as? String, "Herman Melville")
        XCTAssertEqual(texts.metadata["first_publish_year"] as? Int, 1851)
        XCTAssertEqual(texts.metadata["imageUrl"] as? String, "https://archive.org/services/img/mobydick00melv")

        let audio = results[1]
        XCTAssertEqual(audio.title, "Jazz Night 1925", "Array-valued title must use the first element")
        XCTAssertEqual(audio.metadata["mediatype"] as? String, "audio")
        XCTAssertEqual(audio.metadata["author"] as? String, "Various Artists")
        XCTAssertEqual(audio.metadata["first_publish_year"] as? Int, 1925)

        let movies = results[2]
        XCTAssertEqual(movies.title, "The General")
        XCTAssertEqual(movies.metadata["mediatype"] as? String, "movies")
        XCTAssertEqual(movies.metadata["first_publish_year"] as? Int, 1926)
    }

    func testParse_emptyDocsArray_returnsEmpty() {
        let fixture = #"{"response":{"docs":[]}}"#.data(using: .utf8)!
        XCTAssertEqual(InternetArchiveSearchSource.parseResponse(data: fixture).count, 0)
    }

    func testParse_malformedJSON_returnsEmpty() {
        let fixture = "not json at all".data(using: .utf8)!
        XCTAssertEqual(InternetArchiveSearchSource.parseResponse(data: fixture).count, 0)
    }

    func testParse_docWithoutTitleOrIdentifier_isSkipped() {
        let fixture = """
        {
          "response": {
            "docs": [
              { "identifier": "no-title" },
              { "title": "no-id" },
              { "identifier": "ok", "title": "OK" }
            ]
          }
        }
        """.data(using: .utf8)!
        let results = InternetArchiveSearchSource.parseResponse(data: fixture)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "OK")
    }

    // MARK: - Failure modes

    func testNonHTTPResponse_returnsEmpty() async throws {
        let session = MockURLSession(
            data: "anything".data(using: .utf8),
            response: URLResponse() // not an HTTPURLResponse
        )
        let source = InternetArchiveSearchSource(urlSession: session)
        let results = try await source.search(query: EnhancedQuery(
            original: "test", productType: nil, categories: ["books"], priceMax: nil, condition: nil
        ))
        XCTAssertTrue(results.isEmpty)
    }

    func testNetworkError_returnsEmpty() async {
        let session = MockURLSession(error: NSError(domain: "test", code: -1))
        let source = InternetArchiveSearchSource(urlSession: session)
        let query = EnhancedQuery(original: "test", productType: nil, categories: ["books"], priceMax: nil, condition: nil)
        let collected: [SearchResult] = (try? await source.search(query: query)) ?? []
        XCTAssertTrue(collected.isEmpty)
    }
}
