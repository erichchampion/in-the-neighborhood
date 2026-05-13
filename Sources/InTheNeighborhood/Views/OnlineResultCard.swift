import SwiftUI
import MetasearchCore

struct OnlineResultCard: View {
    let result: SearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Product Image Thumbnail (if available)
                if hasShoppingMetadata, let imageUrlString = result.metadata["imageUrl"] as? String,
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
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.headline)
                    
                    // Show price if available
                    if let price = result.metadata["price"] as? String {
                        Text(price)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    
                    if let description = result.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    if let ethics = result.metadata["ethics"] as? EthicsEntry {
                        EthicsBadgeView(entry: ethics)
                    }

                    // Show URL as link for online results, otherwise show source label
                    if result.sourceType == .online, let url = result.url {
                        Link(destination: url) {
                            Text(truncatedURL(url))
                                .font(.caption)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                    } else {
                        Text(sourceLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let url = result.url {
                    Button(action: {
                        UIApplication.shared.open(url)
                    }) {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("Open \(result.title)")
                    .accessibilityHint("Opens this result in your browser")
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.title)
        .accessibilityValue(buildAccessibilityValue())
    }
    
    /// Checks if this result has shopping metadata
    private var hasShoppingMetadata: Bool {
        result.metadata["isShoppingResult"] as? Bool == true ||
        result.metadata["price"] != nil ||
        result.metadata["imageUrl"] != nil
    }
    
    private func buildAccessibilityValue() -> String {
        var components: [String] = []
        if let description = result.description {
            components.append(description)
        }
        // Add price if available
        if let price = result.metadata["price"] as? String {
            components.append("Price: \(price)")
        }
        // For online results, use URL instead of "Online Option"
        if result.sourceType == .online, let url = result.url {
            components.append(url.absoluteString)
        } else {
            components.append(sourceLabel)
        }
        return components.joined(separator: ", ")
    }
    
    private var sourceLabel: String {
        switch result.sourceType {
        case .local:
            return "Local"
        case .regional:
            return "Regional / Ethical Online"
        case .online:
            return "Online Option"
        }
    }
    
    /// Truncates a URL to a maximum length, adding ellipsis if needed
    /// - Parameter url: URL to truncate
    /// - Returns: Truncated URL string
    private func truncatedURL(_ url: URL) -> String {
        let urlString = url.absoluteString
        let maxLength = 50 // Maximum characters before truncation
        
        if urlString.count <= maxLength {
            return urlString
        }
        
        // Truncate and add ellipsis
        let truncated = String(urlString.prefix(maxLength - 3))
        return truncated + "..."
    }
}
