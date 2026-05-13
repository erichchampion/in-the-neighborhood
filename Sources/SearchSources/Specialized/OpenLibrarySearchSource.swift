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
        // Allow search if:
        // 1. Query explicitly indicates book intent (isBook)
        // 2. Query has ISBN-like pattern (10+ digit number)
        // 3. Query has author-like pattern (capitalized words that could be names)
        let allowSearch = query.isBook || looksLikeBookQuery(query.original)
        
        guard allowSearch else {
            print("[OpenLibrarySearchSource] Skipping non-book query: \(query.original)")
            return
        }
        
        print("[OpenLibrarySearchSource] Searching for: \(query.original)")
        try await searchBooks(query: query.original, onResults: onResults)
    }
    
    private func looksLikeBookQuery(_ query: String) -> Bool {
        // Check for ISBN-like patterns (10+ digit numbers)
        let digitsOnly = query.filter { $0.isNumber }
        if digitsOnly.count >= 10 {
            return true
        }
        // Check for author-like patterns (2+ capitalized words that could be names)
        let words = query.components(separatedBy: .whitespaces)
        let capitalizedWords = words.filter { $0.first?.isUppercase == true && $0.count > 1 }
        if capitalizedWords.count >= 2 {
            return true
        }
        return false
    }

    // MARK: - Private

    /// Only run for book / reading queries to avoid cluttering non-book results.
    private func isBookQuery(_ query: EnhancedQuery) -> Bool {
        let bookCategories: Set<String> = [
            "bookstore", "books", "book shop", "library", "reading", "novel",
            "author", "fiction", "nonfiction", "non-fiction", "biography",
            "textbook", "comic", "graphic novel"
        ]
        let lowerOriginal = query.original.lowercased()
        if query.categories.contains(where: { bookCategories.contains($0.lowercased()) }) {
            return true
        }
        if bookCategories.contains(where: { lowerOriginal.contains($0) }) {
            return true
        }
        // Check productType if available
        if let type = query.productType?.lowercased(),
           type.contains("book") || type.contains("novel") || type.contains("reading") {
            return true
        }
        return false
    }

    private func searchBooks(query: String, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(maxResults)"),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,isbn,cover_i,publisher,number_of_pages_median")
        ]

        guard let url = components?.url else {
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
            metadata: productMetadata.toDictionary()
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

    enum CodingKeys: String, CodingKey {
        case key, title, isbn, publisher
        case authorName = "author_name"
        case firstPublishYear = "first_publish_year"
        case coverI = "cover_i"
        case numberOfPagesMedian = "number_of_pages_median"
    }
}
