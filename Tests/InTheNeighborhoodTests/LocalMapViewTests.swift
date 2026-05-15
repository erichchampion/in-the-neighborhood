import XCTest
import CoreLocation
import MapKit
@testable import InTheNeighborhood
@testable import MetasearchCore

/// C4: pins on the Local map. The map itself can't be unit-rendered
/// without a device, so these tests pin the pure helpers
/// `LocalMapView.annotations(for:)` and
/// `LocalMapView.cameraRegion(for:userLocation:)` — same pattern as
/// `ProductCard.healthBadges` and `EthicsBadgeView.displayedItems`.
final class LocalMapViewTests: XCTestCase {

    private func mkResult(
        id: String,
        title: String,
        lat: Double?,
        lon: Double?,
        distance: Double? = nil
    ) -> SearchResult {
        let location = lat.flatMap { l in lon.map { CLLocation(latitude: l, longitude: $0) } }
        return SearchResult(
            id: id,
            title: title,
            description: nil,
            source: SourceIdentifier.mapkit,
            sourceType: .local,
            category: .local,
            url: nil,
            location: location,
            distance: distance,
            relevanceScore: nil,
            price: nil,
            metadata: [:]
        )
    }

    // MARK: - annotations(for:)

    func test_annotations_skipsResultsWithoutLocation() {
        let results = [
            mkResult(id: "a", title: "Has location", lat: 37.78, lon: -122.41),
            mkResult(id: "b", title: "No location", lat: nil, lon: nil),
            mkResult(id: "c", title: "Has location 2", lat: 37.79, lon: -122.42)
        ]
        let pins = LocalMapView.annotations(for: results)
        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(pins.map(\.title).sorted(),
                       ["Has location", "Has location 2"])
    }

    func test_annotations_preservesIdsAndCoordinates() {
        let results = [
            mkResult(id: "powells", title: "Powell's Books", lat: 45.5232, lon: -122.6814, distance: 250)
        ]
        let pin = LocalMapView.annotations(for: results).first!
        XCTAssertEqual(pin.id, "powells")
        XCTAssertEqual(pin.title, "Powell's Books")
        XCTAssertEqual(pin.coordinate.latitude, 45.5232, accuracy: 0.0001)
        XCTAssertEqual(pin.coordinate.longitude, -122.6814, accuracy: 0.0001)
        XCTAssertEqual(pin.distanceMeters, 250)
    }

    func test_annotations_emptyForEmptyResults() {
        XCTAssertTrue(LocalMapView.annotations(for: []).isEmpty)
    }

    // MARK: - cameraRegion(for:userLocation:)

    func test_cameraRegion_returnsNilWhenNoResultsAndNoUserLocation() {
        XCTAssertNil(LocalMapView.cameraRegion(for: [], userLocation: nil))
    }

    func test_cameraRegion_centersOnUserLocationWhenProvided() {
        let user = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let nearby = mkResult(id: "x", title: "Nearby", lat: 37.78, lon: -122.42)
        let region = LocalMapView.cameraRegion(for: [nearby], userLocation: user)
        XCTAssertNotNil(region)
        XCTAssertEqual(region?.center.latitude ?? 0, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(region?.center.longitude ?? 0, -122.4194, accuracy: 0.0001)
        // Even a tiny distance should produce a usable span (≥ 0.01°).
        XCTAssertGreaterThanOrEqual(region?.span.latitudeDelta ?? 0, 0.01)
    }

    func test_cameraRegion_spanScalesWithFurthestResult() {
        let user = CLLocation(latitude: 37.7749, longitude: -122.4194)
        // Roughly 5 km north.
        let close = mkResult(id: "close", title: "Close", lat: 37.82, lon: -122.4194)
        // Roughly 50 km north.
        let far = mkResult(id: "far", title: "Far", lat: 38.225, lon: -122.4194)

        let closeOnlyRegion = LocalMapView.cameraRegion(for: [close], userLocation: user)!
        let farRegion = LocalMapView.cameraRegion(for: [close, far], userLocation: user)!

        XCTAssertGreaterThan(farRegion.span.latitudeDelta, closeOnlyRegion.span.latitudeDelta,
                             "A farther result should grow the camera span")
    }

    func test_cameraRegion_centersOnCentroidWhenNoUserLocation() {
        let north = mkResult(id: "n", title: "North", lat: 38.0, lon: -122.4)
        let south = mkResult(id: "s", title: "South", lat: 37.0, lon: -122.4)
        let region = LocalMapView.cameraRegion(for: [north, south], userLocation: nil)!
        XCTAssertEqual(region.center.latitude, 37.5, accuracy: 0.001,
                       "Center should be the midpoint of the result latitudes")
        XCTAssertEqual(region.center.longitude, -122.4, accuracy: 0.001)
        XCTAssertGreaterThan(region.span.latitudeDelta, 1.0,
                             "Two points 1° apart should give >1° span (with padding)")
    }

    func test_cameraRegion_singleResultGetsMinimumSpan() {
        // With one point and no user location, the bbox span is zero —
        // we should clamp to at least 0.01° so the map doesn't infinitely
        // zoom into a single coordinate.
        let one = mkResult(id: "one", title: "One", lat: 37.78, lon: -122.41)
        let region = LocalMapView.cameraRegion(for: [one], userLocation: nil)!
        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, 0.01)
        XCTAssertGreaterThanOrEqual(region.span.longitudeDelta, 0.01)
    }
}
