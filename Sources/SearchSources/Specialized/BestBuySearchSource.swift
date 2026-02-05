import Foundation
import MetasearchCore

/// Best Buy Products API search source.
/// Requires an API key from https://developer.bestbuy.com/
public final class BestBuySearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = "bestbuy"
    public let sourceType: SourceType = .online
    
    private let session: URLSession
    private let apiKey: String?
    private let baseURL = "https://api.bestbuy.com/v1"
    private let showAttributes = "sku,name,salePrice,url,image,thumbnailImage,regularPrice,manufacturer,customerReviewAverage"
    private let pageSize = 10
    
    public init(
        apiKey: String?,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.session = session
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            print("[BestBuySearchSource] No API key configured, skipping search")
            return []
        }
        
        print("[BestBuySearchSource] Starting search for: \(query.original)")
        
        do {
            let results = try await performSearch(query: query.original, apiKey: apiKey)
            print("[BestBuySearchSource] Found \(results.count) results")
            return results
        } catch {
            print("[BestBuySearchSource] Search failed with error: \(error)")
            throw error
        }
    }
    
    private func performSearch(query: String, apiKey: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        
        // Build search terms: "wireless mouse" -> search=wireless&search=mouse
        let words = trimmed
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let searchClause: String
        if words.isEmpty {
            searchClause = "search=\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)"
        } else {
            let encodedTerms = words.map { "search=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" }
            searchClause = encodedTerms.joined(separator: "&")
        }
        
        let path = "\(baseURL)/products(\(searchClause))"
        var components = URLComponents(string: path)
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "show", value: showAttributes),
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        
        guard let url = components?.url else {
            print("[BestBuySearchSource] Failed to build URL")
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("InTheNeighborhood/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BestBuyError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 403 {
                print("[BestBuySearchSource] API key invalid or rate limit exceeded (403)")
            }
            return []
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(BestBuyProductsResponse.self, from: data)
        
        return apiResponse.products?.compactMap { product -> SearchResult? in
            mapProductToSearchResult(product)
        } ?? []
    }
    
    private func mapProductToSearchResult(_ product: BestBuyProduct) -> SearchResult? {
        let sku = product.sku
        let id = "bestbuy-\(sku)"
        
        let priceStr: String?
        if let salePrice = product.salePrice {
            priceStr = String(format: "$%.2f", salePrice)
        } else {
            priceStr = nil
        }
        
        var metadata: [String: AnyHashable] = [:]
        if let manufacturer = product.manufacturer {
            metadata["brand"] = manufacturer
        }
        metadata["sku"] = String(sku)
        if let salePrice = product.salePrice {
            metadata["price"] = String(format: "$%.2f", salePrice)
        }
        if let imageUrl = product.image ?? product.thumbnailImage {
            metadata["imageUrl"] = imageUrl
        }
        if let reviewAvg = product.customerReviewAverage {
            metadata["customerReviewAverage"] = String(format: "%.1f", reviewAvg)
        }
        
        let productURL: URL?
        if let urlString = product.url, let url = URL(string: urlString) {
            productURL = url
        } else {
            // Fallback: build product URL from SKU when API omits url
            productURL = URL(string: "https://www.bestbuy.com/site/-/\(sku).p?skuId=\(sku)")
        }
        
        return SearchResult(
            id: id,
            title: product.name ?? "Best Buy Product",
            description: priceStr,
            source: identifier,
            sourceType: sourceType,
            url: productURL,
            location: nil,
            distance: nil,
            metadata: metadata
        )
    }
}

// MARK: - API Response Models

private struct BestBuyProductsResponse: Decodable {
    let products: [BestBuyProduct]?
}

private struct BestBuyProduct: Decodable {
    let sku: Int
    let name: String?
    let salePrice: Double?
    let regularPrice: Double?
    let url: String?
    let image: String?
    let thumbnailImage: String?
    let manufacturer: String?
    let customerReviewAverage: Double?
}

// MARK: - Errors

private enum BestBuyError: Error {
    case invalidResponse
}
