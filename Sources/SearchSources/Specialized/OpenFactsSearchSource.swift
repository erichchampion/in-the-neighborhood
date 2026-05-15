import Foundation
import MetasearchCore

/// Searches one of the Open Facts hosts — `world.openfoodfacts.org`,
/// `world.openbeautyfacts.org`, `world.openproductsfacts.org`, or
/// `world.openpetfoodfacts.org`. All four share the same JSON v2 search
/// API, field set, and policy requirements; this single class is
/// host-parameterized so the four siblings can be wired up as
/// independent instances without duplicating code.
///
/// No API key required on any host. The Open Facts policy requires a
/// distinctive User-Agent.
///
/// Endpoint: `https://<host>/api/v2/search`
public final class OpenFactsSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String
    public let sourceType: SourceType = .online
    public let category: ResultCategory = .product

    private let host: String
    private let urlSession: URLSessionProtocol
    private let maxResults: Int
    private let userAgent = "InTheNeighborhood/1.0 (com.in-the-neighborhood)"

    public init(
        host: String,
        identifier: String,
        urlSession: URLSessionProtocol = URLSessionAdapter(),
        maxResults: Int = 20
    ) {
        self.host = host
        self.identifier = identifier
        self.urlSession = urlSession
        self.maxResults = maxResults
    }

    // Inherit the protocol-default `search()` — no `Task { await
    // collector.append(...) }` race pattern that bit the older sources.

    public func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        guard let url = Self.buildURL(host: host, query: query.original, maxResults: maxResults) else {
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

            let results = Self.parseResponse(data: data, host: host, sourceId: identifier)
            onResults(results)
        } catch {
            onResults([])
            throw error
        }
    }

    /// Builds the Open Facts v2 search URL. Exposed as `static internal`
    /// so tests can verify the URL shape without hitting the network.
    static func buildURL(host: String, query: String, maxResults: Int) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v2/search"
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(
                name: "fields",
                value: "code,product_name,brands,image_url,nutriscore_grade,ecoscore_grade,nova_group,labels_tags"
            ),
            URLQueryItem(name: "page_size", value: "\(maxResults)"),
            URLQueryItem(name: "json", value: "true")
        ]
        return components.url
    }

    static func parseResponse(data: Data, host: String, sourceId: String) -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else {
            return []
        }

        return products.compactMap { product -> SearchResult? in
            // `product_name` may be a String or null; skip if missing/empty.
            guard let title = (product["product_name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }

            // `code` is the GTIN/EAN/UPC. Open Facts always returns it
            // as a String even when it looks like a number.
            let code = (product["code"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // brands is a comma-separated String like "Method, Ecover".
            // Take the first brand.
            let brand: String? = {
                guard let brands = product["brands"] as? String, !brands.isEmpty else { return nil }
                let first = brands
                    .split(separator: ",", maxSplits: 1)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return first?.isEmpty == false ? first : nil
            }()

            let imageUrl = (product["image_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }

            // Nutri-Score / Eco-Score arrive as lowercased single chars
            // ("a"…"e"). Normalize to uppercase for display.
            let nutriscoreGrade: String? = (product["nutriscore_grade"] as? String)
                .flatMap { $0.isEmpty ? nil : $0.uppercased() }
            let ecoscoreGrade: String? = (product["ecoscore_grade"] as? String)
                .flatMap { $0.isEmpty ? nil : $0.uppercased() }

            // nova_group may be Int or, surprisingly, String — handle both.
            let novaGroup: Int? = {
                if let i = product["nova_group"] as? Int { return i }
                if let s = product["nova_group"] as? String { return Int(s) }
                return nil
            }()

            var metadata: [String: AnyHashable] = [
                "open_facts_source": host
            ]
            if !code.isEmpty {
                metadata["barcode"] = code
            }
            if let brand { metadata["brand"] = brand }
            if let imageUrl { metadata["imageUrl"] = imageUrl }
            if let nutriscoreGrade { metadata["nutriscore_grade"] = nutriscoreGrade }
            if let ecoscoreGrade { metadata["ecoscore_grade"] = ecoscoreGrade }
            if let novaGroup { metadata["nova_group"] = novaGroup }

            let productURL = code.isEmpty
                ? URL(string: "https://\(host)/")
                : URL(string: "https://\(host)/product/\(code)")

            let resultId = code.isEmpty
                ? "\(sourceId)-\(UUID().uuidString)"
                : "\(sourceId)-\(code)"

            return SearchResult(
                id: resultId,
                title: title,
                description: brand.map { "Brand: \($0)" },
                source: sourceId,
                sourceType: .online,
                category: .product,
                url: productURL,
                location: nil,
                distance: nil,
                metadata: metadata
            )
        }
    }
}

// MARK: - Convenience factories for the four sibling hosts

public extension OpenFactsSearchSource {
    /// Food products. Carries Nutri-Score, Eco-Score, and Nova metadata.
    static func food(urlSession: URLSessionProtocol = URLSessionAdapter()) -> OpenFactsSearchSource {
        OpenFactsSearchSource(
            host: "world.openfoodfacts.org",
            identifier: SourceIdentifier.openfoodfacts,
            urlSession: urlSession
        )
    }

    /// Personal-care and cosmetic products (Open Beauty Facts).
    /// Nutri-Score / Nova rarely populated; Eco-Score sometimes.
    static func beauty(urlSession: URLSessionProtocol = URLSessionAdapter()) -> OpenFactsSearchSource {
        OpenFactsSearchSource(
            host: "world.openbeautyfacts.org",
            identifier: SourceIdentifier.openbeautyfacts,
            urlSession: urlSession
        )
    }

    /// General non-food products (Open Products Facts).
    static func products(urlSession: URLSessionProtocol = URLSessionAdapter()) -> OpenFactsSearchSource {
        OpenFactsSearchSource(
            host: "world.openproductsfacts.org",
            identifier: SourceIdentifier.openproductsfacts,
            urlSession: urlSession
        )
    }

    /// Pet food (Open Pet Food Facts). May carry Nova-style processing scores.
    static func petFood(urlSession: URLSessionProtocol = URLSessionAdapter()) -> OpenFactsSearchSource {
        OpenFactsSearchSource(
            host: "world.openpetfoodfacts.org",
            identifier: SourceIdentifier.openpetfoodfacts,
            urlSession: urlSession
        )
    }
}
