import SwiftUI
import MetasearchCore

struct LibraryCard: View {
    let result: SearchResult
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover image
            if let coverURL = libraryImageURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 80, height: 100)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 100)
                            .cornerRadius(6)
                    case .failure:
                        placeholderImage
                    @unknown default:
                        placeholderImage
                    }
                }
            } else {
                placeholderImage
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)

                if let mediaLabel = mediaTypeLabel {
                    Label(mediaLabel.text, systemImage: mediaLabel.systemImage)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                if let authors = extractAuthors {
                    Text("By \(authors)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let publisher = result.metadata["publisher"] as? String {
                    Text(publisher)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let year = result.metadata["first_publish_year"] as? Int {
                    Text(String(year))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let ethics = result.metadata["ethics"] as? EthicsEntry {
                    EthicsBadgeView(entry: ethics)
                }

                if let isbn = result.metadata["isbn"] as? String, let firstISBN = isbn.components(separatedBy: ",").first {
                    Text("ISBN: \(firstISBN.trimmingCharacters(in: .whitespaces))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // B4: when the result has a free Internet Archive scan
                // (either an Internet Archive item itself, or an Open
                // Library book whose `has_fulltext`+`ia` say so), surface a
                // "Read free" link.
                if let url = readFreeURL {
                    Link(destination: url) {
                        Label("Read free at Internet Archive", systemImage: "book.pages")
                            .font(.caption)
                    }
                }
            }
            
            Spacer()
            
            if let url = result.url {
                Link(destination: url) {
                    Image(systemName: "book.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var placeholderImage: some View {
        Image(systemName: "book.closed")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 80, height: 100)
            .foregroundColor(.secondary)
            .background(Color(.systemGray6))
            .cornerRadius(6)
    }
    
    private var libraryImageURL: URL? {
        // OpenLibrary: cover_i → covers.openlibrary.org
        if let coverId = result.metadata["cover_i"] as? Int {
            return URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-M.jpg")
        }
        // DPLA or other: imageUrl
        if let imageUrlString = result.metadata["imageUrl"] as? String {
            return URL(string: imageUrlString)
        }
        return nil
    }
    
    // MARK: - B4 helpers (internal so tests can pin behavior).
    // All three are `nonisolated` because they're pure functions of
    // `result.metadata` — they never touch main-actor UI state. Marking
    // them explicitly lets XCTest methods (which run off the main actor)
    // call them without crossing the `View`-imposed isolation boundary.

    /// Returns a media-type label for non-text Internet Archive results.
    /// `nil` means "no badge" (the default book layout is what the user
    /// expects for plain texts).
    struct MediaTypeLabel: Equatable {
        let text: String
        let systemImage: String
    }
    nonisolated var mediaTypeLabel: MediaTypeLabel? {
        guard let mediatype = result.metadata["mediatype"] as? String else { return nil }
        switch mediatype.lowercased() {
        case "audio":  return MediaTypeLabel(text: "Audio", systemImage: "headphones")
        case "movies": return MediaTypeLabel(text: "Film",  systemImage: "film")
        default:       return nil   // "texts" or anything else → no badge
        }
    }

    /// Returns the Internet Archive details URL when the result carries
    /// a free scan reference. Two paths:
    ///   - Open Library expanded: `metadata["ia"]` holds the IA identifier
    ///     when the book has a full-text scan.
    ///   - Internet Archive items themselves: `metadata["ia_identifier"]`
    ///     plus `mediatype == "texts"`.
    nonisolated var readFreeURL: URL? {
        if let iaId = result.metadata["ia"] as? String, !iaId.isEmpty {
            return URL(string: "https://archive.org/details/\(iaId)")
        }
        if let mediatype = result.metadata["mediatype"] as? String,
           mediatype.lowercased() == "texts",
           let iaId = result.metadata["ia_identifier"] as? String, !iaId.isEmpty {
            return URL(string: "https://archive.org/details/\(iaId)")
        }
        return nil
    }

    nonisolated var extractAuthors: String? {
        // OpenLibrary (raw): author_name is [String]
        if let authors = result.metadata["author_name"] as? [String], !authors.isEmpty {
            return authors.joined(separator: ", ")
        }
        // OpenLibrary (via ProductMetadata.toDictionary): "author" is a
        // pre-joined String. Falling back to this is what makes Open Library
        // results actually display author names — without it the card just
        // shows the title.
        if let author = result.metadata["author"] as? String, !author.isEmpty {
            return author
        }
        // DPLA: providers is [[String: Any]]
        if let providers = result.metadata["providers"] as? [[String: Any]] {
            let names = providers.compactMap { $0["name"] as? String }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        return nil
    }
}

#Preview {
    LibraryCard(
        result: SearchResult(
            id: "test-1",
            title: "On Tyranny: Twenty Lessons from the Twentieth Century",
            description: "A book by Timothy Snyder",
            source: "openlibrary",
            sourceType: .online,
            category: .book,
            url: URL(string: "https://openlibrary.org/works/OL12345W"),
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: [
                "author_name": ["Timothy Snyder"],
                "publisher": "Times Books",
                "first_publish_year": 2017,
                "cover_i": 1234567,
                "isbn": "9780804190114"
            ]
        )
    )
    .padding()
}