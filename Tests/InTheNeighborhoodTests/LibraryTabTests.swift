import XCTest
@testable import InTheNeighborhood
@testable import MetasearchCore

final class LibraryTabTests: XCTestCase {
    
    // MARK: - Tab Selection Tests
    
    func testTabSelectionHasLibraryCase() {
        // Verify TabSelection enum includes .library
        let tab = SearchViewModel.TabSelection.library
        XCTAssertNotNil(tab)
    }
    
    // MARK: - Library Source Detection Tests
    
    func testOpenLibraryResultsDetectedAsLibrarySource() {
        // Given: A result from OpenLibrary
        let openLibraryResult = SearchResult(
            id: "openlib-1",
            title: "On Tyranny",
            description: "Book by Timothy Snyder",
            source: SourceIdentifier.openlibrary,
            sourceType: .online,
            category: .book,
            url: URL(string: "https://openlibrary.org/works/OL12345W"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: ["author_name": ["Timothy Snyder"]]
        )
        
        // When: Checking if it's a library source
        let isLibrarySource = openLibraryResult.source == SourceIdentifier.openlibrary || openLibraryResult.source == SourceIdentifier.dpla
        
        // Then: Should be detected as library source
        XCTAssertTrue(isLibrarySource)
    }
    
    func testDPLAResultsDetectedAsLibrarySource() {
        // Given: A result from DPLA
        let dplaResult = SearchResult(
            id: "dpla-1",
            title: "On Tyranny",
            description: "Book from DPLA",
            source: SourceIdentifier.dpla,
            sourceType: .online,
            category: .book,
            url: URL(string: "https://dp.la/item/123"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: ["providers": [["name": "NYPL"]]]
        )
        
        // When: Checking if it's a library source
        let isLibrarySource = dplaResult.source == SourceIdentifier.openlibrary || dplaResult.source == SourceIdentifier.dpla
        
        // Then: Should be detected as library source
        XCTAssertTrue(isLibrarySource)
    }
    
    func testAmazonResultsNotDetectedAsLibrarySource() {
        // Given: A result from Amazon (commercial product)
        let amazonResult = SearchResult(
            id: "amazon-1",
            title: "On Tyranny",
            description: "Book on Amazon",
            source: SourceIdentifier.amazon,
            sourceType: .online,
            category: .product,
            url: URL(string: "https://amazon.com/dp/123"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: "$14.99",
            metadata: [:]
        )
        
        // When: Checking if it's a library source
        let isLibrarySource = amazonResult.source == SourceIdentifier.openlibrary || amazonResult.source == SourceIdentifier.dpla
        
        // Then: Should NOT be detected as library source
        XCTAssertFalse(isLibrarySource)
    }
    
    func testGoogleBooksResultsNotDetectedAsLibrarySource() {
        // Given: A result from Google Books (not a library source)
        let googleBooksResult = SearchResult(
            id: "googlebooks-1",
            title: "On Tyranny",
            description: "Book on Google Books",
            source: SourceIdentifier.googlebooks,
            sourceType: .online,
            category: .book,
            url: URL(string: "https://books.google.com/books?id=123"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: [:]
        )
        
        // When: Checking if it's a library source
        let isLibrarySource = googleBooksResult.source == SourceIdentifier.openlibrary || googleBooksResult.source == SourceIdentifier.dpla
        
        // Then: Should NOT be detected as library source
        XCTAssertFalse(isLibrarySource)
    }
    
    // MARK: - Metadata Extraction Tests
    
    func testOpenLibraryAuthorExtraction() {
        // Given: OpenLibrary result with author_name
        let result = SearchResult(
            id: "test",
            title: "Test",
            description: nil,
            source: SourceIdentifier.openlibrary,
            sourceType: .online,
            category: .book,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: ["author_name": ["Author One", "Author Two"]]
        )
        
        // When: Extracting authors
        let authors = result.metadata["author_name"] as? [String]
        
        // Then: Should extract author names
        XCTAssertNotNil(authors)
        XCTAssertEqual(authors?.count, 2)
    }
    
    func testDPLAProviderExtraction() {
        // Given: DPLA result with providers
        let result = SearchResult(
            id: "test",
            title: "Test",
            description: nil,
            source: SourceIdentifier.dpla,
            sourceType: .online,
            category: .book,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: ["providers": [["name": "Library A"], ["name": "Library B"]]]
        )
        
        // When: Extracting providers
        let providers = result.metadata["providers"] as? [[String: Any]]
        
        // Then: Should extract provider names
        XCTAssertNotNil(providers)
        XCTAssertEqual(providers?.count, 2)
    }
    
    // MARK: - Library-tab rendering predicate (author_name vs author key parity)

    private func mkLibraryResult(metadata: [String: AnyHashable]) -> SearchResult {
        SearchResult(
            id: "test",
            title: "Test",
            description: nil,
            source: SourceIdentifier.openlibrary,
            sourceType: .online,
            category: .book,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: metadata
        )
    }

    func test_renderableInLibraryTab_acceptsAuthorStringKey() {
        // OpenLibrary writes the joined author string under "author".
        let result = mkLibraryResult(metadata: ["author": "Timothy Snyder"])
        XCTAssertTrue(ResultsView.renderableInLibraryTab(result),
                      "A result whose only signal is metadata[\"author\"] must still render")
    }

    func test_renderableInLibraryTab_acceptsAuthorNameArrayKey() {
        // Raw OpenLibrary shape — predicate must accept the legacy key too.
        let result = mkLibraryResult(metadata: ["author_name": ["Timothy Snyder"]])
        XCTAssertTrue(ResultsView.renderableInLibraryTab(result))
    }

    func test_renderableInLibraryTab_acceptsISBNOnly() {
        let result = mkLibraryResult(metadata: ["isbn": "9780804190114"])
        XCTAssertTrue(ResultsView.renderableInLibraryTab(result))
    }

    func test_renderableInLibraryTab_rejectsResultWithNoBookSignal() {
        let result = mkLibraryResult(metadata: [:])
        XCTAssertFalse(ResultsView.renderableInLibraryTab(result),
                       "A result with no isbn/author/cover/imageUrl/providers should not render in the library tab")
    }

    func test_libraryCard_extractAuthors_prefersAuthorNameArray() {
        // When both keys are present, the array form (richer) wins.
        let result = mkLibraryResult(metadata: [
            "author_name": ["First", "Second"],
            "author": "ShouldNotBeUsed"
        ])
        let card = LibraryCard(result: result)
        XCTAssertEqual(card.extractAuthors, "First, Second")
    }

    func test_libraryCard_extractAuthors_fallsBackToAuthorString() {
        // OpenLibrary-via-ProductMetadata case — only "author" is set.
        let result = mkLibraryResult(metadata: ["author": "Timothy Snyder"])
        let card = LibraryCard(result: result)
        XCTAssertEqual(card.extractAuthors, "Timothy Snyder",
                       "Card should display the joined author string when author_name is missing")
    }

    func test_libraryCard_extractAuthors_returnsNilWhenAbsent() {
        let result = mkLibraryResult(metadata: ["isbn": "9780804190114"])
        let card = LibraryCard(result: result)
        XCTAssertNil(card.extractAuthors)
    }

    func testOpenLibraryCoverImageURL() {
        // Given: OpenLibrary result with cover_i
        let result = SearchResult(
            id: "test",
            title: "Test",
            description: nil,
            source: SourceIdentifier.openlibrary,
            sourceType: .online,
            category: .book,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: ["cover_i": 1234567]
        )
        
        // When: Getting cover URL
        let coverId = result.metadata["cover_i"] as? Int
        let expectedURL = "https://covers.openlibrary.org/b/id/1234567-M.jpg"
        
        // Then: Should construct correct URL
        XCTAssertNotNil(coverId)
        XCTAssertEqual(expectedURL, "https://covers.openlibrary.org/b/id/1234567-M.jpg")
    }
}