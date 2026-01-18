import SwiftUI
import MetasearchCore

struct AmazonProductCard: View {
    let result: SearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Product Image
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
                
                // Product Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    // Brand
                    if let brand = result.metadata["brand"] as? String {
                        Text(brand)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Price
                    if let price = result.metadata["price"] as? String {
                        Text(price)
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    // Ratings
                    if let ratings = result.metadata["ratings"] as? Double {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text(String(format: "%.1f", ratings))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Availability
                    if let availability = result.metadata["availability"] as? String {
                        Text(availability)
                            .font(.caption)
                            .foregroundColor(availability.lowercased().contains("stock") && !availability.lowercased().contains("out") ? .green : .orange)
                    }
                }
                
                Spacer()
            }
            
            // View on Amazon button
            if let url = result.url {
                Button(action: {
                    UIApplication.shared.open(url)
                }) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("View on Amazon")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .accessibilityLabel("View \(result.title) on Amazon")
                .accessibilityHint("Opens this product page on Amazon")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(buildAccessibilityLabel())
    }
    
    private func buildAccessibilityLabel() -> String {
        var components: [String] = [result.title]
        
        if let brand = result.metadata["brand"] as? String {
            components.append("Brand: \(brand)")
        }
        if let price = result.metadata["price"] as? String {
            components.append("Price: \(price)")
        }
        if let ratings = result.metadata["ratings"] as? Double {
            components.append("Rating: \(String(format: "%.1f", ratings)) stars")
        }
        if let availability = result.metadata["availability"] as? String {
            components.append("Availability: \(availability)")
        }
        
        return components.joined(separator: ", ")
    }
}
