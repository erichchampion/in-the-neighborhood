import Foundation
import MetasearchCore

/// Searches the Internet Archive's advanced search API for digitized
/// texts, audio, and films. Internet Archive is free and key-less; the
/// results surface in the Library tab alongside Open Library and DPLA
/// because the user can read/listen/watch them right now (the project's
/// "borrow instead of buy" angle).
///
/// Endpoint: https://archive.org/advancedsearch.php
public final class InternetArchiveSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = SourceIdentifier.internetarchive
    public let sourceType: SourceType = .online
    public let category: ResultCategory = .book

    private let urlSession: URLSessionProtocol
    private let userAgent = "InTheNeighborhood/1.0 (com.in-the-neighborhood)"
    private let maxResults: Int

    public init(urlSession: URLSessionProtocol = URLSessionAdapter(), maxResults: Int = 20) {
        self.urlSession = urlSession
        self.maxResults = maxResults
    }

    // No `search()` override — protocol default uses a properly-synchronized
    // task group, avoiding the race the older sources had.

    public func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        guard let url = Self.buildURL(query: query.original, maxResults: maxResults) else {
            onResults([])
            return
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                onResults([])
                return
            }

            let results = Self.parseResponse(data: data)
            onResults(results)
        } catch {
            onResults([])
            throw error
        }
    }

    /// Builds the Internet Archive advancedsearch URL. Exposed as `static`
    /// `internal` so tests can verify the URL shape without standing up a
    /// mock URLSession.
    static func buildURL(query: String, maxResults: Int) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Restrict to media types that fit the Library tab — texts, audio,
        // movies. Excludes software/data/web crawls which would clutter the
        // results with irrelevant collections.
        let filteredQuery = "(\(trimmed)) AND mediatype:(texts OR audio OR movies)"

        var components = URLComponents(string: "https://archive.org/advancedsearch.php")
        components?.queryItems = [
            URLQueryItem(name: "q", value: filteredQuery),
            // Multiple `fl[]` items request specific fields. URLComponents
            // URL-encodes the brackets correctly.
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "fl[]", value: "mediatype"),
            URLQueryItem(name: "fl[]", value: "date"),
            URLQueryItem(name: "fl[]", value: "description"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "rows", value: "\(maxResults)")
        ]
        return components?.url
    }

    static func parseResponse(data: Data) -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else {
            return []
        }

        return docs.compactMap { doc -> SearchResult? in
            guard let identifier = doc["identifier"] as? String, !identifier.isEmpty else { return nil }
            // `title` in Internet Archive's payload can be either a String
            // or an array of Strings (some old items have multi-valued
            // titles). Accept both shapes; bail if neither produces a
            // non-empty title.
            let title: String
            if let single = doc["title"] as? String, !single.isEmpty {
                title = single
            } else if let multi = doc["title"] as? [String], let first = multi.first, !first.isEmpty {
                title = first
            } else {
                return nil
            }

            // `creator` and `description` follow the same single-or-array
            // pattern.
            let creator: String? = {
                if let single = doc["creator"] as? String, !single.isEmpty { return single }
                if let multi = doc["creator"] as? [String], !multi.isEmpty {
                    return multi.joined(separator: ", ")
                }
                return nil
            }()

            let description: String? = {
                if let single = doc["description"] as? String, !single.isEmpty { return single }
                if let multi = doc["description"] as? [String], let first = multi.first, !first.isEmpty {
                    return first
                }
                return nil
            }()

            let mediatype = (doc["mediatype"] as? String) ?? "texts"

            // Date field can be a full ISO date ("1920-05-15"), a year, or
            // an array. Extract a 4-digit year for the card to display.
            let yearString: String? = {
                if let single = doc["date"] as? String { return single }
                if let multi = doc["date"] as? [String], let first = multi.first { return first }
                return nil
            }()
            let firstPublishYear = yearString.flatMap { Int($0.prefix(4)) }

            var metadata: [String: AnyHashable] = [
                "ia_identifier": identifier,
                "mediatype": mediatype,
                "imageUrl": "https://archive.org/services/img/\(identifier)"
            ]
            if let creator { metadata["author"] = creator }
            if let firstPublishYear { metadata["first_publish_year"] = firstPublishYear }

            let itemURL = URL(string: "https://archive.org/details/\(identifier)")

            return SearchResult(
                id: "ia-\(identifier)",
                title: title,
                description: description,
                source: SourceIdentifier.internetarchive,
                sourceType: .online,
                category: .book,
                url: itemURL,
                location: nil,
                distance: nil,
                metadata: metadata
            )
        }
    }
}
