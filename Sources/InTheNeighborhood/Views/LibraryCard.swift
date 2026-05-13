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
                
                if let isbn = result.metadata["isbn"] as? String, let firstISBN = isbn.components(separatedBy: ",").first {
                    Text("ISBN: \(firstISBN.trimmingCharacters(in: .whitespaces))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
    
    private var extractAuthors: String? {
        // OpenLibrary: author_name is [String]
        if let authors = result.metadata["author_name"] as? [String], !authors.isEmpty {
            return authors.joined(separator: ", ")
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