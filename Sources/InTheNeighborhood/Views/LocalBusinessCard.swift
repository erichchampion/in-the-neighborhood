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
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m away", meters)
        } else {
            let km = meters / 1000
            return String(format: "%.1f km away", km)
        }
    }
    
    private func openDirections(to location: CLLocation) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        mapItem.name = result.title
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
