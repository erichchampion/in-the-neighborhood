import SwiftUI
import MetasearchCore

struct AmazonProductCard: View {
    let result: SearchResult
    let onRefine: (() -> Void)?
    
    init(result: SearchResult, onRefine: (() -> Void)? = nil) {
        self.result = result
        self.onRefine = onRefine
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Product Image Thumbnail
                if let imageUrlString = result.metadata["imageUrl"] as? String,
                   let imageUrl = URL(string: imageUrlString) {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 80, height: 80)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                                .frame(width: 80, height: 80)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                    .background(Color(.systemGray6))
                } else {
                    // Placeholder image
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                        .frame(width: 80, height: 80)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                
                // Product Metadata
                VStack(alignment: .leading, spacing: 6) {
                    // Title
                    Text(result.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    // Manufacturer/Brand
                    if let brand = result.metadata["brand"] as? String {
                        Text(brand)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Author (for books)
                    if let author = result.metadata["author"] as? String {
                        Text("by \(author)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Artist (for media)
                    if let artist = result.metadata["artist"] as? String {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // ISBN or SKU (generally applicable identifiers)
                    if let isbn = result.metadata["isbn"] as? String {
                        Text("ISBN: \(isbn)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let sku = result.metadata["sku"] as? String {
                        Text("SKU: \(sku)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Refine button
            if let onRefine = onRefine {
                Button(action: {
                    onRefine()
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Refine")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .accessibilityLabel("Refine search with \(result.title)")
                .accessibilityHint("Uses this product's metadata to refine the search on other websites")
            }
        }
        .padding()
        .background(Color.clear)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(buildAccessibilityLabel())
        .onAppear {
            // #region agent log
            let brandStr = (result.metadata["brand"] as? String) ?? "nil"
            let isbnStr = (result.metadata["isbn"] as? String) ?? "nil"
            let skuStr = (result.metadata["sku"] as? String) ?? "nil"
            let authorStr = (result.metadata["author"] as? String) ?? "nil"
            let artistStr = (result.metadata["artist"] as? String) ?? "nil"
            print("[DEBUG] AmazonProductCard.swift:115 - Rendering card with metadata - title: \(result.title), metadataKeys: \(Array(result.metadata.keys)), brand: \(brandStr), isbn: \(isbnStr), sku: \(skuStr), author: \(authorStr), artist: \(artistStr)")
            // #endregion
        }
    }
    
    private func buildAccessibilityLabel() -> String {
        var components: [String] = [result.title]
        
        if let brand = result.metadata["brand"] as? String {
            components.append("Manufacturer: \(brand)")
        }
        if let author = result.metadata["author"] as? String {
            components.append("Author: \(author)")
        }
        if let artist = result.metadata["artist"] as? String {
            components.append("Artist: \(artist)")
        }
        if let isbn = result.metadata["isbn"] as? String {
            components.append("ISBN: \(isbn)")
        }
        if let sku = result.metadata["sku"] as? String {
            components.append("SKU: \(sku)")
        }
        
        return components.joined(separator: ", ")
    }
}
