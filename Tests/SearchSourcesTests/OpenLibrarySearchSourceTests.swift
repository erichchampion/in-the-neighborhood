import XCTest
@testable import SearchSources
@testable import MetasearchCore

/// These tests exercise the `looksLikeBookQuery` trigger decision rather than
/// hitting the live Open Library API — that's intentional. The bug fixed by
/// Phase 1 was that the trigger rejected lowercase book titles entirely, so
/// asserting on the trigger directly is what catches the regression.
final class OpenLibrarySearchSourceTests: XCTestCase {

    private let sut = OpenLibrarySearchSource()

    // MARK: - Default-true behavior (the Phase 1 bug fix)

    func test_lowercaseBookTitle_isAllowed() {
        // The user-reported regression: typing "on tyranny" used to be rejected
        // because the old rule needed 2+ capitalized words.
        XCTAssertTrue(sut.looksLikeBookQuery("on tyranny"))
    }

    func test_singleCapitalizedWord_isAllowed() {
        XCTAssertTrue(sut.looksLikeBookQuery("Tyranny"))
    }

    func test_titleWithAuthor_isAllowed() {
        XCTAssertTrue(sut.looksLikeBookQuery("On Tyranny by Timothy Snyder"))
    }

    func test_isbn_isAllowed() {
        XCTAssertTrue(sut.looksLikeBookQuery("9780804190114"))
    }

    func test_isbnWithPrefix_isAllowed() {
        XCTAssertTrue(sut.looksLikeBookQuery("isbn:9780804190114"))
    }

    // MARK: - Exclusion list (obviously non-book queries)

    func test_hardwareStoreQuery_isRejected() {
        XCTAssertFalse(sut.looksLikeBookQuery("hardware store near me"))
    }

    func test_nearMeQuery_isRejected() {
        XCTAssertFalse(sut.looksLikeBookQuery("coffee shop near me"))
    }

    func test_groceryQuery_isRejected() {
        XCTAssertFalse(sut.looksLikeBookQuery("grocery store"))
    }

    // MARK: - Edge cases

    func test_emptyQuery_isRejected() {
        XCTAssertFalse(sut.looksLikeBookQuery(""))
    }

    func test_whitespaceQuery_isRejected() {
        XCTAssertFalse(sut.looksLikeBookQuery("   \n  "))
    }

    func test_singleCharacterQuery_isRejected() {
        XCTAssertFalse(sut.looksLikeBookQuery("a"))
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
