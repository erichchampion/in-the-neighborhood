import SwiftUI
import MetasearchCore

/// Reusable product card for Amazon, Best Buy, and other product sources.
/// When urlToOpen is provided and non-nil, shows an Open button to open the product URL in the browser.
struct ProductCard: View {
    let result: SearchResult
    let onRefine: (() -> Void)?
    let urlToOpen: URL?
    
    init(result: SearchResult, onRefine: (() -> Void)? = nil, urlToOpen: URL? = nil) {
        self.result = result
        self.onRefine = onRefine
        self.urlToOpen = urlToOpen
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

                    // B2: Nutri-Score / Eco-Score / Nova badges for Open Facts results.
                    // The helper returns an empty array when none of the
                    // grades are present, so the HStack just doesn't render.
                    let healthBadges = ProductCard.healthBadges(for: result)
                    if !healthBadges.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(healthBadges, id: \.self) { badge in
                                Label(badge.text, systemImage: badge.systemImage)
                                    .font(.caption2)
                                    .foregroundColor(badge.tint.foreground)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(badge.tint.background)
                                    .clipShape(Capsule())
                            }
                        }
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
                    
                    // Price (for Best Buy, etc.)
                    if let price = result.price ?? result.metadata["price"] as? String {
                        Text(price)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
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

                    if let ethics = result.metadata["ethics"] as? EthicsEntry {
                        EthicsBadgeView(entry: ethics)
                    }
                }

                Spacer()
            }
            
            // Buttons: Refine and optionally Open
            HStack(spacing: 12) {
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
                
                if let url = urlToOpen {
                    Button(action: {
                        UIApplication.shared.open(url)
                    }) {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
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
            let resultUrlStr = result.url?.absoluteString ?? "nil"
            let urlToOpenStr = urlToOpen?.absoluteString ?? "nil"
            print("[DEBUG] ProductCard.swift - Rendering card with metadata - title: \(result.title), metadataKeys: \(Array(result.metadata.keys)), brand: \(brandStr), isbn: \(isbnStr), sku: \(skuStr), author: \(authorStr), artist: \(artistStr), source: \(result.source), result.url: \(resultUrlStr), urlToOpen: \(urlToOpenStr)")
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

// MARK: - B2: Nutri-Score / Eco-Score / Nova badges
//
// These helpers are `nonisolated` so XCTest methods can call them off
// the main actor — same pattern used for EthicsBadgeView.displayedItems
// and LibraryCard.mediaTypeLabel. They're pure projections of
// `result.metadata` and never touch UI state.

extension ProductCard {
    struct HealthBadge: Hashable {
        enum Tint: Hashable {
            case green   // A — best
            case lime    // B
            case yellow  // C
            case orange  // D
            case red     // E — worst
            case warning // Nova ultra-processed

            var foreground: Color {
                switch self {
                case .green, .lime, .yellow: return Color(.label)
                case .orange, .red, .warning: return .white
                }
            }
            var background: Color {
                switch self {
                case .green:   return Color.green.opacity(0.8)
                case .lime:    return Color.green.opacity(0.45)
                case .yellow:  return Color.yellow.opacity(0.8)
                case .orange:  return Color.orange.opacity(0.85)
                case .red:     return Color.red.opacity(0.85)
                case .warning: return Color.orange.opacity(0.85)
                }
            }
        }
        let text: String
        let systemImage: String
        let tint: Tint
    }

    /// Builds the ordered list of food/health badges from a result's
    /// metadata. Empty when none of the Open Facts grades are present.
    /// Order: Nutri-Score, Eco-Score, Nova warning (only if nova ≥ 3).
    nonisolated static func healthBadges(for result: SearchResult) -> [HealthBadge] {
        var badges: [HealthBadge] = []
        if let nutri = result.metadata["nutriscore_grade"] as? String,
           let badge = nutriBadge(grade: nutri) {
            badges.append(badge)
        }
        if let eco = result.metadata["ecoscore_grade"] as? String,
           let badge = ecoBadge(grade: eco) {
            badges.append(badge)
        }
        if let nova = result.metadata["nova_group"] as? Int, nova >= 3 {
            let label = nova == 4 ? "Ultra-processed" : "Processed"
            badges.append(HealthBadge(
                text: label,
                systemImage: "exclamationmark.triangle",
                tint: .warning
            ))
        }
        return badges
    }

    nonisolated static func nutriBadge(grade: String) -> HealthBadge? {
        guard let tint = gradeToTint(grade) else { return nil }
        return HealthBadge(text: "Nutri-Score \(grade.uppercased())", systemImage: "leaf", tint: tint)
    }

    nonisolated static func ecoBadge(grade: String) -> HealthBadge? {
        guard let tint = gradeToTint(grade) else { return nil }
        return HealthBadge(text: "Eco-Score \(grade.uppercased())", systemImage: "globe.americas", tint: tint)
    }

    /// Maps an Open Facts grade (case-insensitive A-E) to a tint.
    /// Returns nil for unknown grades (e.g. "unknown", "not-applicable")
    /// so the caller silently skips them.
    nonisolated static func gradeToTint(_ grade: String) -> HealthBadge.Tint? {
        switch grade.uppercased() {
        case "A": return .green
        case "B": return .lime
        case "C": return .yellow
        case "D": return .orange
        case "E": return .red
        default:  return nil
        }
    }
}

// Backward compatibility
typealias AmazonProductCard = ProductCard
