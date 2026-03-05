import SwiftUI
import MapKit
import MetasearchCore

struct LocalBusinessCard: View {
    let result: SearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.headline)
                    
                    if let description = result.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Show website URL as clickable link if available
                    if let url = result.url {
                        Link(destination: url) {
                            Text(truncatedURL(url))
                                .font(.caption)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                    }
                    
                    if let distance = result.distance {
                        Text(formatDistance(distance))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    if let phone = result.metadata["phone"] as? String {
                        Button(action: {
                            if let url = URL(string: "tel:\(phone)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Label("Call", systemImage: "phone.fill")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .accessibilityLabel("Call \(result.title)")
                        .accessibilityHint("Opens phone dialer to call this business")
                    }
                    
                    if let location = result.location {
                        Button(action: {
                            openDirections(to: location)
                        }) {
                            Label("Directions", systemImage: "map.fill")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .accessibilityLabel("Get directions to \(result.title)")
                        .accessibilityHint("Opens Maps app with directions to this business")
                    }
                }
            }
            
            Text("Note: Call to check availability")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.title)
        .accessibilityValue(buildAccessibilityValue())
    }
    
    private func formatDistance(_ meters: Double) -> String {
        // Convert meters to miles (1 mile = 1609.34 meters)
        let miles = meters / 1609.34
        
        if miles < 0.1 {
            // For very short distances, show in feet
            let feet = meters * 3.28084
            return String(format: "%.0f ft away", feet)
        } else if miles < 1.0 {
            // For distances less than 1 mile, show with 2 decimal places
            return String(format: "%.2f miles away", miles)
        } else {
            // For distances 1 mile or more, show with 1 decimal place
            return String(format: "%.1f miles away", miles)
        }
    }
    
    private func openDirections(to location: CLLocation) {
        let mapItem = MKMapItem(location: location, address: nil)
        mapItem.name = result.title
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
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
    
    private func buildAccessibilityValue() -> String {
        var components: [String] = []
        if let description = result.description {
            components.append(description)
        }
        if let url = result.url {
            components.append(url.absoluteString)
        }
        if let distance = result.distance {
            components.append(formatDistance(distance))
        }
        return components.joined(separator: ", ")
    }
}
