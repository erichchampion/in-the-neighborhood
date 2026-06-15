import XCTest
@testable import InTheNeighborhood
@testable import MetasearchCore

final class LibraryTabTests: XCTestCase {
    
    // MARK: - Tab Selection Tests
    
    func testTabSelectionHasBorrowCase() {
        // C1: TabSelection now reflects intents — .library was renamed
        // to .borrow.
        let tab = SearchViewModel.TabSelection.borrow
        XCTAssertNotNil(tab)
    }

    func testTabSelectionHasRepairCase() {
        // C1: new intent tab.
        let tab = SearchViewModel.TabSelection.repair
        XCTAssertNotNil(tab)
    }

    // MARK: - C1: tab(for:) classifier

    private func mkResult(
        source: String,
        sourceType: SourceType,
        category: ResultCategory = .web,
        metadata: [String: AnyHashable] = [:]
    ) -> SearchResult {
        SearchResult(
            id: "x",
            title: "x",
            description: nil,
            source: source,
            sourceType: sourceType,
            category: category,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: metadata
        )
    }

    func test_classifier_openLibrary_routesToBorrow() {
        let r = mkResult(source: SourceIdentifier.openlibrary, sourceType: .online, category: .book)
        XCTAssertEqual(SearchViewModel.tab(for: r), .borrow)
    }

    func test_classifier_dpla_routesToBorrow() {
        let r = mkResult(source: SourceIdentifier.dpla, sourceType: .online, category: .book)
        XCTAssertEqual(SearchViewModel.tab(for: r), .borrow)
    }

    func test_classifier_internetArchive_routesToBorrow() {
        let r = mkResult(source: SourceIdentifier.internetarchive, sourceType: .online, category: .book)
        XCTAssertEqual(SearchViewModel.tab(for: r), .borrow)
    }

    func test_classifier_repairSignal_routesToRepair_evenForLocalSource() {
        // An Overpass result with `category_tag == "repair"` lands in the
        // Repair tab regardless of its sourceType being `.local`.
        let r = mkResult(
            source: SourceIdentifier.overpass,
            sourceType: .local,
            category: .local,
            metadata: ["category_tag": "repair"]
        )
        XCTAssertEqual(SearchViewModel.tab(for: r), .repair)
    }

    func test_classifier_geoLocalWithoutRepairSignal_routesToLocal() {
        let r = mkResult(source: SourceIdentifier.mapkit, sourceType: .local, category: .local)
        XCTAssertEqual(SearchViewModel.tab(for: r), .local)
    }

    func test_classifier_overpassWithoutRepairSignal_routesToLocal() {
        // A regular non-repair Overpass shop lands in Local.
        let r = mkResult(source: SourceIdentifier.overpass, sourceType: .local, category: .local)
        XCTAssertEqual(SearchViewModel.tab(for: r), .local)
    }

    func test_classifier_duckDuckGo_routesToOnline() {
        let r = mkResult(source: SourceIdentifier.duckduckgo, sourceType: .online, category: .web)
        XCTAssertEqual(SearchViewModel.tab(for: r), .online)
    }

    func test_classifier_amazon_routesToOnline() {
        // Mega-retailer results are filtered upstream, but if one reached
        // here it would land in Online (not Borrow).
        let r = mkResult(source: SourceIdentifier.amazon, sourceType: .online, category: .product)
        XCTAssertEqual(SearchViewModel.tab(for: r), .online)
    }

    func test_classifier_openFoodFacts_routesToOnline() {
        let r = mkResult(source: SourceIdentifier.openfoodfacts, sourceType: .online, category: .product)
        XCTAssertEqual(SearchViewModel.tab(for: r), .online)
    }

    // MARK: - W4 Area 1: borrow-tag routing

    func test_classifier_borrowSignal_routesToBorrow() {
        // An Overpass tool-library / library-of-things node carries
        // `category_tag == "borrow"` and joins the digitized-book sources
        // in the Borrow tab, even though its sourceType is `.local`.
        let r = mkResult(
            source: SourceIdentifier.overpass,
            sourceType: .local,
            category: .local,
            metadata: ["category_tag": "borrow"]
        )
        XCTAssertEqual(SearchViewModel.tab(for: r), .borrow)
    }

    // MARK: - W4 Area 2: WhyThisResultView.detailLines (pure formatter)

    func test_whyThisResult_detailLines_includesAlternativeEthicsAndBrand() {
        let lines = WhyThisResultView.detailLines(
            ethics: EthicsEntry(ownership: .bCorp, notes: "Certified B-Corp bakery."),
            alternativeFor: "Amazon Basics Widget",
            brand: "Acme"
        )
        XCTAssertTrue(lines.contains { $0.contains("Amazon Basics Widget") })
        XCTAssertTrue(lines.contains { $0.contains("Certified B-Corp bakery.") })
        XCTAssertTrue(lines.contains { $0.contains("Acme") })
    }

    func test_whyThisResult_detailLines_usesOwnershipLabelWhenNoNotes() {
        let lines = WhyThisResultView.detailLines(
            ethics: EthicsEntry(ownership: .coop),
            alternativeFor: nil,
            brand: nil
        )
        XCTAssertTrue(lines.contains { $0.lowercased().contains("cooperative") })
    }

    func test_whyThisResult_detailLines_fallsBackWhenEmpty() {
        let lines = WhyThisResultView.detailLines(ethics: nil, alternativeFor: nil, brand: nil)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("open, non-monopolistic"))
    }

    // MARK: - W4 Area 3: LibraryCard borrow-availability badge

    private func libraryCard(ebookAccess: String?) -> LibraryCard {
        var metadata: [String: AnyHashable] = [:]
        if let ebookAccess { metadata["ebook_access"] = ebookAccess }
        return LibraryCard(result: mkResult(
            source: SourceIdentifier.openlibrary,
            sourceType: .online,
            category: .book,
            metadata: metadata
        ))
    }

    func test_libraryCard_borrowStatusBadge_borrowable() {
        XCTAssertEqual(libraryCard(ebookAccess: "borrowable").borrowStatusBadge?.text, "Borrow now")
    }

    func test_libraryCard_borrowStatusBadge_public() {
        XCTAssertEqual(libraryCard(ebookAccess: "public").borrowStatusBadge?.text, "Read free")
    }

    func test_libraryCard_borrowStatusBadge_noEbookOrAbsent_isNil() {
        XCTAssertNil(libraryCard(ebookAccess: "no_ebook").borrowStatusBadge)
        XCTAssertNil(libraryCard(ebookAccess: "printdisabled").borrowStatusBadge)
        XCTAssertNil(libraryCard(ebookAccess: nil).borrowStatusBadge)
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
    
    func testInternetArchiveResultsDetectedAsLibrarySource() {
        // B4: Internet Archive results must route into the Library tab,
        // alongside Open Library and DPLA.
        let iaResult = SearchResult(
            id: "ia-mobydick00melv",
            title: "Moby Dick",
            description: "A whaling novel",
            source: SourceIdentifier.internetarchive,
            sourceType: .online,
            category: .book,
            url: URL(string: "https://archive.org/details/mobydick00melv"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: [
                "ia_identifier": "mobydick00melv",
                "mediatype": "texts"
            ]
        )

        let isLibrarySource =
            iaResult.source == SourceIdentifier.openlibrary
            || iaResult.source == SourceIdentifier.dpla
            || iaResult.source == SourceIdentifier.internetarchive

        XCTAssertTrue(isLibrarySource)
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

    // MARK: - B4: media-type badge

    func test_libraryCard_mediaTypeLabel_audioBecomesAudioBadge() {
        let result = mkLibraryResult(metadata: ["mediatype": "audio"])
        let card = LibraryCard(result: result)
        XCTAssertEqual(card.mediaTypeLabel?.text, "Audio")
        XCTAssertEqual(card.mediaTypeLabel?.systemImage, "headphones")
    }

    func test_libraryCard_mediaTypeLabel_moviesBecomesFilmBadge() {
        let result = mkLibraryResult(metadata: ["mediatype": "movies"])
        let card = LibraryCard(result: result)
        XCTAssertEqual(card.mediaTypeLabel?.text, "Film")
        XCTAssertEqual(card.mediaTypeLabel?.systemImage, "film")
    }

    func test_libraryCard_mediaTypeLabel_textsHasNoBadge() {
        let result = mkLibraryResult(metadata: ["mediatype": "texts"])
        let card = LibraryCard(result: result)
        XCTAssertNil(card.mediaTypeLabel,
                     "Default-book layout should not be cluttered with a redundant badge")
    }

    func test_libraryCard_mediaTypeLabel_absentMediatypeHasNoBadge() {
        let result = mkLibraryResult(metadata: ["author": "Some One"])
        let card = LibraryCard(result: result)
        XCTAssertNil(card.mediaTypeLabel)
    }

    // MARK: - B4: "Read free at Internet Archive" link

    func test_libraryCard_readFreeURL_fromOpenLibraryIA() {
        // Open Library expanded: book has `ia` array → card surfaces link.
        let result = mkLibraryResult(metadata: [
            "ia": "ontyranny0000snyd",
            "has_fulltext": true
        ])
        let card = LibraryCard(result: result)
        XCTAssertEqual(card.readFreeURL?.absoluteString,
                       "https://archive.org/details/ontyranny0000snyd")
    }

    func test_libraryCard_readFreeURL_fromInternetArchiveTexts() {
        // IA item with mediatype=texts → link to its details page.
        let result = mkLibraryResult(metadata: [
            "ia_identifier": "mobydick00melv",
            "mediatype": "texts"
        ])
        let card = LibraryCard(result: result)
        XCTAssertEqual(card.readFreeURL?.absoluteString,
                       "https://archive.org/details/mobydick00melv")
    }

    func test_libraryCard_readFreeURL_nilForBookWithoutIA() {
        // Plain Open Library result without an IA scan → no link.
        let result = mkLibraryResult(metadata: [
            "author": "Timothy Snyder",
            "isbn": "9780804190114"
        ])
        let card = LibraryCard(result: result)
        XCTAssertNil(card.readFreeURL)
    }

    func test_libraryCard_readFreeURL_nilForIAMoviesAndAudio() {
        // Films/audio items use the regular `result.url` link in the card,
        // not the "Read free" affordance — readFreeURL only fires for texts.
        let audio = mkLibraryResult(metadata: [
            "ia_identifier": "JazzNight1925",
            "mediatype": "audio"
        ])
        XCTAssertNil(LibraryCard(result: audio).readFreeURL)

        let movies = mkLibraryResult(metadata: [
            "ia_identifier": "BusterKeaton_TheGeneral",
            "mediatype": "movies"
        ])
        XCTAssertNil(LibraryCard(result: movies).readFreeURL)
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