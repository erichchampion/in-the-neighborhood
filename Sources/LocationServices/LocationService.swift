import Foundation
@preconcurrency import CoreLocation
import MapKit

public protocol LocationServiceProtocol: Sendable {
    func getCurrentLocation() async -> CLLocation?
    func getLocationOrFallback() async -> CLLocation?
}

public actor LocationService: LocationServiceProtocol {
    nonisolated private let locationManager: CLLocationManager
    private var lastKnownLocation: CLLocation?
    private var zipCodeLocation: CLLocation?
    
    public init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.locationManager.distanceFilter = 100 // meters
    }
    
    public func requestPermissionIfNeeded() async {
        let status = await MainActor.run { locationManager.authorizationStatus }
        switch status {
        case .notDetermined:
            await MainActor.run {
                self.locationManager.requestWhenInUseAuthorization()
            }
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }
    
    public func getCurrentLocation() async -> CLLocation? {
        await requestPermissionIfNeeded()
        
        let status = await MainActor.run { locationManager.authorizationStatus }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if let location = await (MainActor.run { locationManager.location }) {
                lastKnownLocation = location
                return location
            }
            // Wait for location update (simplified - would need proper delegation in production)
            return nil
        case .denied, .restricted, .notDetermined:
            return nil
        @unknown default:
            return nil
        }
    }
    
    public func getLocationOrFallback() async -> CLLocation? {
        // Try to get current location
        if let location = await getCurrentLocation() {
            return location
        }
        
        // Use cached location if available
        if let cached = lastKnownLocation {
            return cached
        }
        
        // Use zip code location if set
        if let zipLocation = zipCodeLocation {
            return zipLocation
        }
        
        // Return nil - caller should handle this (e.g., prompt for zip code)
        return nil
    }
    
    public func setZipCode(_ zipCode: String) async throws {
        // Geocode zip code to location using MapKit (CLGeocoder deprecated in iOS 26)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = zipCode
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        
        guard let item = response.mapItems.first else {
            throw LocationServiceError.geocodingFailed
        }
        let location = item.location
        
        zipCodeLocation = location
    }
    
    nonisolated public func calculateDistance(from: CLLocation, to: CLLocation) -> Double {
        return from.distance(from: to) // Returns distance in meters
    }
    
    public func clearCache() {
        lastKnownLocation = nil
        zipCodeLocation = nil
    }
}

public enum LocationServiceError: Error {
    case geocodingFailed
    case permissionDenied
    case locationUnavailable
}
