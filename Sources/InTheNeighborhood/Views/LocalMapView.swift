import SwiftUI
import MapKit
import CoreLocation
import MetasearchCore

/// C4: map presentation of the Local tab. Renders one annotation per
/// result with a `CLLocation`, plus a user-location dot. Tapping an
/// annotation surfaces the corresponding `LocalBusinessCard` in a
/// bottom sheet so the user can call, get directions, or save the
/// store without leaving the map.
struct LocalMapView: View {
    let results: [SearchResult]
    let userLocation: CLLocation?

    @State private var cameraPosition: MapCameraPosition
    @State private var selectedResult: SearchResult?

    init(results: [SearchResult], userLocation: CLLocation? = nil) {
        self.results = results
        self.userLocation = userLocation
        let initialRegion = Self.cameraRegion(for: results, userLocation: userLocation)
            ?? MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        _cameraPosition = State(initialValue: .region(initialRegion))
    }

    var body: some View {
        let pins = Self.annotations(for: results)
        if pins.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No nearby results to map")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Search to see local stores plotted on a map.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
        } else {
            Map(position: $cameraPosition, selection: $selectedResult) {
                UserAnnotation()
                ForEach(pins, id: \.id) { pin in
                    Marker(pin.title, coordinate: pin.coordinate)
                        .tint(.blue)
                        .tag(pin.result)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .sheet(item: $selectedResult) { result in
                LocalBusinessCard(result: result)
                    .padding()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Pure helpers (testable)

    /// One pin per result that has a CLLocation. Pins are pure value
    /// projections — `nonisolated` so XCTest methods can build them
    /// off the main actor.
    struct Annotation: Identifiable, Hashable {
        let id: String
        let title: String
        let coordinate: CLLocationCoordinate2D
        let distanceMeters: Double?
        let result: SearchResult

        static func == (lhs: Annotation, rhs: Annotation) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    nonisolated static func annotations(for results: [SearchResult]) -> [Annotation] {
        results.compactMap { result in
            guard let location = result.location else { return nil }
            return Annotation(
                id: result.id,
                title: result.title,
                coordinate: location.coordinate,
                distanceMeters: result.distance,
                result: result
            )
        }
    }

    /// Initial camera region for the map:
    ///  - Both `results` empty AND `userLocation` nil → nil (caller
    ///    falls back to a sensible default).
    ///  - `userLocation` provided → centered on the user, span scaled
    ///    to the furthest result + 30% padding (min 0.01° to avoid
    ///    over-zoom on a single nearby result).
    ///  - No user location → centered on the centroid of the result
    ///    coordinates with a span covering all results.
    nonisolated static func cameraRegion(for results: [SearchResult], userLocation: CLLocation?) -> MKCoordinateRegion? {
        let coords: [CLLocationCoordinate2D] = results.compactMap { $0.location?.coordinate }

        if let userLocation {
            let userCoord = userLocation.coordinate
            // Span based on max distance to any result.
            let maxMeters: Double = coords.map { coord in
                let resultLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                return resultLoc.distance(from: userLocation)
            }.max() ?? 0
            // 1 degree latitude ≈ 111,111 meters. Scale span to span
            // diagonally — multiply by 2 for full extent, by 1.3 for
            // padding.
            let latDelta = max(0.01, (maxMeters / 111_111.0) * 2 * 1.3)
            return MKCoordinateRegion(
                center: userCoord,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
            )
        }

        guard !coords.isEmpty else { return nil }

        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let latDelta = max(0.01, (maxLat - minLat) * 1.3)
        let lonDelta = max(0.01, (maxLon - minLon) * 1.3)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
