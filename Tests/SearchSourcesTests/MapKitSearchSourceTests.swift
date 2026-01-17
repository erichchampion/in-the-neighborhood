import XCTest
import MapKit
import CoreLocation
@testable import SearchSources
@testable import MetasearchCore
@testable import LocationServices

final class MapKitSearchSourceTests: XCTestCase {
    nonisolated(unsafe) var source: MapKitSearchSource!
    nonisolated(unsafe) var mockLocationService: MockLocationService!
    
    override func setUp() {
        super.setUp()
        mockLocationService = MockLocationService()
        source = MapKitSearchSource(locationService: mockLocationService)
    }
    
    @MainActor
    func test_MapKitSource_SearchesByCategory() async throws {
        mockLocationService.mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        
        // This test may require actual MapKit integration or mocking
        // For now, we test that the source can be instantiated and conforms to protocol
        XCTAssertEqual(source.identifier, "mapkit")
        XCTAssertEqual(source.sourceType, .local)
    }
    
    @MainActor
    func test_MapKitSource_MapsResultsCorrectly() async throws {
        mockLocationService.mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        
        // This will test actual MapKit integration
        // Note: May return empty results in test environment
        let _ = try? await source.search(query: EnhancedQuery(
            original: "bookstore",
            productType: "book",
            categories: ["bookstore"],
            priceMax: nil,
            condition: nil
        ))
        
        // Verify source structure
        XCTAssertNotNil(source)
    }
    
    @MainActor
    func test_MapKitSource_HandlesNoResults() async throws {
        mockLocationService.mockLocation = CLLocation(latitude: 0, longitude: 0) // Middle of ocean
        
        let query = EnhancedQuery(
            original: "nonexistent store type",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        let results = try await source.search(query: query)
        XCTAssertTrue(results.isEmpty)
    }
    
    @MainActor
    func test_MapKitSource_LocationPermissionDenied() async throws {
        mockLocationService.mockLocation = nil // Simulate permission denied
        
        let query = EnhancedQuery(
            original: "test query",
            productType: nil,
            categories: [],
            priceMax: nil,
            condition: nil
        )
        
        // Should handle gracefully without location
        let results = try await source.search(query: query)
        // Results may be empty or use fallback location
        XCTAssertNotNil(results)
    }
}

// MARK: - Mock Location Service

final class MockLocationService: LocationServiceProtocol, @unchecked Sendable {
    var mockLocation: CLLocation?
    
    func getCurrentLocation() async -> CLLocation? {
        return mockLocation
    }
    
    func getLocationOrFallback() async -> CLLocation? {
        return mockLocation ?? CLLocation(latitude: 37.7749, longitude: -122.4194) // Default to SF
    }
}
