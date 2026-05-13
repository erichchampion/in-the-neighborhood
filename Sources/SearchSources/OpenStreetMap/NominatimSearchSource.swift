import Foundation
import CoreLocation
import MapKit
import MetasearchCore
import LocationServices

public final class NominatimSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = "nominatim"
    public let sourceType: SourceType = .local
    public let category: ResultCategory = .local
    
    private let locationService: LocationServiceProtocol
    private let urlSession: URLSessionProtocol
    private let searchRadius: CLLocationDistance
    private let userAgent: String
    
    public init(
        locationService: LocationServiceProtocol,
        urlSession: URLSessionProtocol = URLSessionAdapter(),
        searchRadius: CLLocationDistance = 50000
    ) {
        self.locationService = locationService
        self.urlSession = urlSession
        self.searchRadius = searchRadius
        self.userAgent = "InTheNeighborhood/1.0 (com.in-the-neighborhood)"
    }
    
    // No `search()` override — the protocol's default extension wires the
    // streaming source into a properly-synchronized collector via a task
    // group. The hand-rolled override that used to live here scheduled an
    // unstructured `Task { await collector.append(results) }` inside the
    // callback, which races with the outer `await collector.allResults`
    // and can return before the append lands.

    public func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        guard let location = await locationService.getLocationOrFallback() else {
            onResults([])
            return
        }
        
        guard let url = buildURL(query: query, location: location) else {
            onResults([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                onResults([])
                return
            }
            
            let results = parseResponse(data: data, location: location)
            onResults(results)
        } catch {
            onResults([])
            throw error
        }
    }
    
    private func buildURL(query: EnhancedQuery, location: CLLocation) -> URL? {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        
        var queryItems = [
            URLQueryItem(name: "q", value: query.original),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "lat", value: "\(location.coordinate.latitude)"),
            URLQueryItem(name: "lon", value: "\(location.coordinate.longitude)"),
            URLQueryItem(name: "radius", value: "\(Int(searchRadius))"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "extratags", value: "1")
        ]
        
        // Add category-based search terms if available
        if !query.categories.isEmpty {
            let categoryQuery = query.categories.joined(separator: " OR ")
            queryItems.append(URLQueryItem(name: "q", value: "\(query.original) \(categoryQuery)"))
        }
        
        components?.queryItems = queryItems
        return components?.url
    }
    
    private func parseResponse(data: Data, location: CLLocation) -> [SearchResult] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return jsonArray.compactMap { item in
            guard let placeId = item["place_id"] as? String,
                  let displayName = item["display_name"] as? String,
                  let latString = item["lat"] as? String,
                  let lonString = item["lon"] as? String,
                  let lat = Double(latString),
                  let lon = Double(lonString) else {
                return nil
            }
            
            let resultLocation = CLLocation(latitude: lat, longitude: lon)
            let distance = resultLocation.distance(from: location)
            
            let type = item["type"] as? String
            let addressJSON = (try? JSONSerialization.data(withJSONObject: item["address"] ?? [:]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let metadata: [String: AnyHashable] = [
                "place_id": placeId,
                "type": type ?? "unknown",
                "address_json": addressJSON
            ]
            
            return SearchResult(
                id: placeId,
                title: displayName,
                description: type,
                source: identifier,
                sourceType: sourceType,
                category: category,
                url: nil,
                location: resultLocation,
                distance: distance,
                metadata: metadata
            )
        }
    }
}
