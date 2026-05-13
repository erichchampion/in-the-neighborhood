import Foundation
import CoreLocation
import MetasearchCore
import LocationServices

/// Searches OpenStreetMap data via the Overpass API for specialty local shops
/// using tag-based queries. Where Nominatim does free-text geocoding, Overpass
/// queries `shop=books`, `amenity=library`, etc., which surfaces stores that
/// MapKit's text matching can miss.
///
/// Endpoint: https://overpass-api.de/api/interpreter (POST, form-encoded body).
public final class OverpassSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = SourceIdentifier.overpass
    public let sourceType: SourceType = .local
    public let category: ResultCategory = .local

    private let locationService: LocationServiceProtocol
    private let urlSession: URLSessionProtocol
    private let searchRadius: CLLocationDistance
    private let userAgent: String
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    public init(
        locationService: LocationServiceProtocol,
        urlSession: URLSessionProtocol = URLSessionAdapter(),
        searchRadius: CLLocationDistance = 5000
    ) {
        self.locationService = locationService
        self.urlSession = urlSession
        self.searchRadius = searchRadius
        self.userAgent = "InTheNeighborhood/1.0 (com.in-the-neighborhood)"
    }

    // No `search()` override — the protocol's default extension wires the
    // streaming source to a properly-synchronized collector via a task group.
    // Earlier sources (e.g. Nominatim) re-implement `search()` with an
    // unstructured `Task { await collector.append(...) }` inside the
    // callback, which races with the outer `await collector.allResults`
    // and can return before the append lands.

    public func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        guard let location = await locationService.getLocationOrFallback() else {
            onResults([])
            return
        }

        let body = buildOverpassQL(query: query, location: location)
        guard let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            onResults([])
            return
        }
        let bodyString = "data=\(encodedBody)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                onResults([])
                return
            }

            let results = parseResponse(data: data, userLocation: location)
            onResults(results)
        } catch {
            onResults([])
            throw error
        }
    }

    /// Builds an Overpass QL query body that searches for nodes and ways
    /// matching the given query's categories within `searchRadius` meters of
    /// the user's location.
    func buildOverpassQL(query: EnhancedQuery, location: CLLocation) -> String {
        let tags = OverpassTagMap.tags(forCategories: query.categories)
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let radius = Int(searchRadius)

        var unionParts: [String] = []
        for spec in tags {
            let filter = overpassFilter(for: spec)
            unionParts.append("node\(filter)(around:\(radius),\(lat),\(lon));")
            unionParts.append("way\(filter)(around:\(radius),\(lat),\(lon));")
        }

        let union = unionParts.joined(separator: " ")
        return "[out:json][timeout:5];(\(union));out center tags 25;"
    }

    /// JSONSerialization bridges numbers as NSNumber, which casts cleanly to
    /// Double in most cases — but Swift 6's stricter conversion rules can
    /// reject `as? Double` for an NSNumber backed by a non-floating type.
    /// Normalize via NSNumber when the direct cast fails.
    private static func numericDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func numericInt(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    /// Converts a `"key=value"` or `"key=*"` tag spec into an Overpass filter.
    private func overpassFilter(for spec: String) -> String {
        let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
        guard let key = parts.first, !key.isEmpty else { return "" }
        if parts.count == 2, parts[1] != "*" {
            return "[\"\(key)\"=\"\(parts[1])\"]"
        }
        return "[\"\(key)\"]"
    }

    private func parseResponse(data: Data, userLocation: CLLocation) -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            return []
        }

        return elements.compactMap { element -> SearchResult? in
            let osmType = (element["type"] as? String) ?? "unknown"
            let osmId = Self.numericInt(element["id"]) ?? 0

            // JSONSerialization gives us a Foundation-bridged dictionary; cast
            // to `[String: Any]` then pull individual values as `String` to
            // avoid `as? [String: String]` runtime cast failures on bridged
            // NSDictionary types.
            let tags = element["tags"] as? [String: Any] ?? [:]
            guard let name = tags["name"] as? String, !name.isEmpty else { return nil }

            // Nodes carry lat/lon at top level. Ways/relations carry a `center`
            // (because of `out center` in the query body). JSON numbers may
            // arrive as Double, Int, or NSNumber depending on the value's
            // shape; `numericDouble` normalizes.
            let lat: Double?
            let lon: Double?
            if let nodeLat = Self.numericDouble(element["lat"]),
               let nodeLon = Self.numericDouble(element["lon"]) {
                lat = nodeLat
                lon = nodeLon
            } else if let center = element["center"] as? [String: Any],
                      let centerLat = Self.numericDouble(center["lat"]),
                      let centerLon = Self.numericDouble(center["lon"]) {
                lat = centerLat
                lon = centerLon
            } else {
                lat = nil
                lon = nil
            }
            guard let resolvedLat = lat, let resolvedLon = lon else { return nil }

            let resultLocation = CLLocation(latitude: resolvedLat, longitude: resolvedLon)
            let distance = resultLocation.distance(from: userLocation)

            let shop = tags["shop"] as? String
            let amenity = tags["amenity"] as? String
            let description = shop.map { "shop: \($0)" } ?? amenity.map { "amenity: \($0)" }

            // Serialize tags to JSON so the SearchResult metadata stays
            // `[String: AnyHashable]`-compatible (same approach as Nominatim).
            let tagsJSON = (try? JSONSerialization.data(withJSONObject: tags))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""

            let metadata: [String: AnyHashable] = [
                "osm_type": osmType,
                "osm_id": osmId,
                "tags_json": tagsJSON
            ]

            return SearchResult(
                id: "overpass-\(osmType)-\(osmId)",
                title: name,
                description: description,
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
