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
}
