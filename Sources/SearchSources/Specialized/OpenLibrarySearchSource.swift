import Foundation
import MetasearchCore

/// Searches the Open Library API (https://openlibrary.org) for book results.
/// No API key required — completely free with no rate limits for reasonable use.
///
/// Complements `GoogleBooksSearchSource` and provides an ethical alternative
/// to book results from locked-down or paid APIs.
public final class OpenLibrarySearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = SourceIdentifier.openlibrary
    public let sourceType: SourceType = .online
    public let category: ResultCategory = .book
    public let categoryAffinity: Set<QueryCategory> = [.book]

    private let session: URLSession
    private let maxResults: Int

    public init(session: URLSession = .shared, maxResults: Int = 10) {
        self.session = session
        self.maxResults = maxResults
    }

    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        let collector = SearchResultsCollector()
        try await searchStreaming(query: query) { results in
            Task {
                await collector.append(results)
            }
        }
        return await collector.allResults
    }

    public func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        // Source-side filtering is gone — the coordinator's
        // categoryAffinity gate (Phase C3) now decides whether
        // OpenLibrary runs based on the classifier output. If we got
        // here, this query is book-related.
        print("[OpenLibrarySearchSource] Searching for: \(query.original)")
        try await searchBooks(query: query.original, onResults: onResults)
    }

    private func searchBooks(query: String, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        guard let url = Self.buildURL(query: query, maxResults: maxResults) else {
            print("[OpenLibrarySearchSource] Failed to build URL")
            return
        }

        print("[OpenLibrarySearchSource] Fetching: \(url.absoluteString)")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("[OpenLibrarySearchSource] Unexpected HTTP response")
            return
        }

        guard let json = try? JSONDecoder().decode(OpenLibraryResponse.self, from: data) else {
            print("[OpenLibrarySearchSource] Failed to decode Open Library response")
            return
        }

        print("[OpenLibrarySearchSource] Received \(json.docs.count) docs")
        let results = json.docs.prefix(maxResults).compactMap { mapDocToSearchResult($0) }
        if !results.isEmpty {
            onResults(Array(results))
        }
    }

    /// Builds the Open Library search URL with the full field set, including
    /// the B4 additions (`has_fulltext`, `ia`, `subject`) that let the
    /// LibraryCard surface "Read free at Internet Archive" when a scan
    /// exists. Exposed as `internal static` so tests can pin the URL shape.
    static func buildURL(query: String, maxResults: Int) -> URL? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(maxResults)"),
            URLQueryItem(
                name: "fields",
                value: "key,title,author_name,first_publish_year,isbn,cover_i,publisher,number_of_pages_median,subject,has_fulltext,ia"
            )
        ]
        return components?.url
    }

    private func mapDocToSearchResult(_ doc: OpenLibraryDoc) -> SearchResult? {
        guard let title = doc.title, !title.isEmpty else { return nil }

        let authors = doc.authorName?.joined(separator: ", ")
        let isbn = doc.isbn?.first
        let coverID = doc.coverI.map { "\($0)" }
        let coverURL = coverID.map { "https://covers.openlibrary.org/b/id/\($0)-M.jpg" }
        let workURL = doc.key.map { URL(string: "https://openlibrary.org\($0)") } ?? nil

        var descriptionParts: [String] = []
        if let authors { descriptionParts.append("By \(authors)") }
        if let year = doc.firstPublishYear { descriptionParts.append(String(year)) }
        if let pages = doc.numberOfPagesMedian { descriptionParts.append("\(pages) pages") }
        if let publisher = doc.publisher?.first { descriptionParts.append(publisher) }

        let productMetadata = ProductMetadata(
            isbn: isbn,
            author: authors,
            imageUrl: coverURL
        )

        // Start from ProductMetadata's dictionary (isbn/author/imageUrl) and
        // layer in the B4 expansions. When `has_fulltext == true` and the
        // `ia` array is non-empty, the book has a free scan on
        // archive.org — LibraryCard turns this into a "Read free" link.
        var metadata = productMetadata.toDictionary()
        if let hasFulltext = doc.hasFulltext {
            metadata["has_fulltext"] = hasFulltext
        }
        if let iaIds = doc.ia, !iaIds.isEmpty, doc.hasFulltext == true {
            metadata["ia"] = iaIds.first
        }
        if let subjects = doc.subject, !subjects.isEmpty {
            // Cap at 3 to avoid blowing up the metadata payload — the card
            // only shows a handful at most.
            metadata["subject"] = Array(subjects.prefix(3))
        }

        return SearchResult(
            id: doc.key ?? UUID().uuidString,
            title: title,
            description: descriptionParts.isEmpty ? nil : descriptionParts.joined(separator: " • "),
            source: identifier,
            sourceType: sourceType,
            category: category,
            url: workURL,
            location: nil,
            distance: nil,
            metadata: metadata
        )
    }
}

// MARK: - Response Models

private struct OpenLibraryResponse: Decodable {
    let docs: [OpenLibraryDoc]
}

private struct OpenLibraryDoc: Decodable {
    let key: String?
    let title: String?
    let authorName: [String]?
    let firstPublishYear: Int?
    let isbn: [String]?
    let coverI: Int?
    let publisher: [String]?
    let numberOfPagesMedian: Int?
    // B4: expanded fields. `hasFulltext` + `ia` together unlock the
    // "Read free at Internet Archive" link in LibraryCard.
    let subject: [String]?
    let hasFulltext: Bool?
    let ia: [String]?

    enum CodingKeys: String, CodingKey {
        case key, title, isbn, publisher, subject, ia
        case authorName = "author_name"
        case firstPublishYear = "first_publish_year"
        case coverI = "cover_i"
        case numberOfPagesMedian = "number_of_pages_median"
        case hasFulltext = "has_fulltext"
    }
}
