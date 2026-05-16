import Foundation
import MetasearchCore

public final class DPLASearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = "dpla"
    public let sourceType: SourceType = .online
    public let category: ResultCategory = .book
    public let categoryAffinity: Set<QueryCategory> = [.book, .media]

    private let apiKey: String
    private let urlSession: URLSessionProtocol
    
    public init(apiKey: String, urlSession: URLSessionProtocol = URLSessionAdapter()) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }
    
    // No `search()` override — the protocol's default extension wires the
    // streaming source into a properly-synchronized collector via a task
    // group. The hand-rolled override that used to live here scheduled an
    // unstructured `Task { await collector.append(results) }` inside the
    // callback, which races with the outer `await collector.allResults`
    // and can return before the append lands.

    public func searchStreaming(query: EnhancedQuery, onResults: @escaping @Sendable ([SearchResult]) -> Void) async throws {
        // DPLA requires an API key. Without one, the v2 API rejects every
        // request with a 401 — silently swallowed by the coordinator's
        // catch but a waste of network and log noise. Short-circuit instead,
        // matching BestBuySearchSource's pattern.
        guard !apiKey.isEmpty else {
            print("[DPLASearchSource] No API key configured, skipping search")
            onResults([])
            return
        }

        guard let url = buildURL(query: query) else {
            onResults([])
            return
        }
        
        do {
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw SearchError.invalidResponse
            }
            
            let results = parseResponse(data: data)
            onResults(results)
        } catch {
            throw error
        }
    }
    
    private func buildURL(query: EnhancedQuery) -> URL? {
        var components = URLComponents(string: "https://api.dp.la/v2/items")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query.original),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        return components?.url
    }
    
    private func parseResponse(data: Data) -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]] else {
            return []
        }
        
        return docs.compactMap { doc in
            guard let id = doc["id"] as? String,
                  let title = doc["title"] as? String else {
                return nil
            }
            
            let description = doc["description"] as? String
            let urlString = doc["isShownAt"] as? String
            let url = urlString.flatMap { URL(string: $0) }
            
            let providers = (doc["provider"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let metadata: [String: AnyHashable] = [
                "dpla_id": id,
                "providers": providers as [String]
            ]
            
            return SearchResult(
                id: id,
                title: title,
                description: description,
                source: identifier,
                sourceType: sourceType,
                category: category,
                url: url,
                location: nil,
                distance: nil,
                metadata: metadata
            )
        }
    }
}

public enum SearchError: Error {
    case invalidResponse
}
