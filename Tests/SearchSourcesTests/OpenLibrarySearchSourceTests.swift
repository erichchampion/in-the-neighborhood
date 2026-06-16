import XCTest
@testable import SearchSources
@testable import MetasearchCore

final class OpenLibrarySearchSourceTests: XCTestCase {

    private let sut = OpenLibrarySearchSource()

    // MARK: - C3: declared categoryAffinity

    /// Before Phase C3 this source self-gated via a `looksLikeBookQuery`
    /// exclusion list. C3 moved gating to the coordinator: OpenLibrary
    /// now declares `[.book]` affinity and the coordinator skips it for
    /// other classified categories. The lowercase-book-title bug
    /// (`"on tyranny"` being rejected) is also gone because
    /// classification returns nil for ambiguous queries and nil ->
    /// "run every source".
    func test_categoryAffinity_isBookOnly() {
        XCTAssertEqual(sut.categoryAffinity, [.book])
    }

    // MARK: - B4: expanded fields in the search URL

    func test_buildURL_requestsExpandedFields_hasFulltextIaSubject() {
        // The "Read free at Internet Archive" link in LibraryCard depends on
        // Open Library returning `has_fulltext` and `ia`. The subject field
        // gates optional category display. All three must be in the
        // `fields=` parameter or the metadata pipeline silently loses them.
        let url = OpenLibrarySearchSource.buildURL(query: "on tyranny", maxResults: 10)
        XCTAssertNotNil(url)
        let decoded = url!.absoluteString.removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains("has_fulltext"),
                      "URL must request has_fulltext. Got: \(decoded)")
        XCTAssertTrue(decoded.contains("ia"),
                      "URL must request ia. Got: \(decoded)")
        XCTAssertTrue(decoded.contains("subject"),
                      "URL must request subject. Got: \(decoded)")
        // Make sure we didn't lose the originally-requested fields either.
        XCTAssertTrue(decoded.contains("author_name"))
        XCTAssertTrue(decoded.contains("cover_i"))
    }

    // MARK: - W3: exact ISBN lookup

    func test_buildURL_withValidISBN_usesExactIsbnQuery() {
        let url = OpenLibrarySearchSource.buildURL(query: "the dispossessed", isbn: "978-0-06-105488-4", maxResults: 10)
        XCTAssertNotNil(url)
        let decoded = url!.absoluteString.removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains("q=isbn:9780061054884"),
                      "A valid ISBN must produce an exact isbn: query with hyphens stripped. Got: \(decoded)")
        XCTAssertFalse(decoded.contains("q=the dispossessed"),
                       "Free-text query must be replaced by the exact ISBN lookup")
    }

    func test_buildURL_withInvalidISBN_fallsBackToFreeText() {
        let url = OpenLibrarySearchSource.buildURL(query: "the dispossessed", isbn: "12345", maxResults: 10)
        XCTAssertNotNil(url)
        let decoded = url!.absoluteString.removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains("q=the dispossessed"),
                      "A malformed ISBN must be ignored and the free-text query used. Got: \(decoded)")
        XCTAssertFalse(decoded.contains("isbn:"))
    }

    func test_normalizedISBN_validatesAndStrips() {
        XCTAssertEqual(OpenLibrarySearchSource.normalizedISBN("978-0-06-105488-4"), "9780061054884")
        XCTAssertEqual(OpenLibrarySearchSource.normalizedISBN("030788748x"), "030788748X")
        XCTAssertNil(OpenLibrarySearchSource.normalizedISBN("12345"))
        XCTAssertNil(OpenLibrarySearchSource.normalizedISBN(""))
    }

    // MARK: - W4 Area 3: borrow-availability field

    func test_buildURL_requestsEbookAccessField() {
        // The "Borrow now"/"Read free" badge depends on Open Library returning
        // `ebook_access`; it must be in the `fields=` parameter.
        let url = OpenLibrarySearchSource.buildURL(query: "on tyranny", maxResults: 10)
        XCTAssertNotNil(url)
        let decoded = url!.absoluteString.removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains("ebook_access"),
                      "URL must request ebook_access. Got: \(decoded)")
    }
}
