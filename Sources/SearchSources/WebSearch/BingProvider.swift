import Foundation
import MetasearchCore

final class BingProvider: WebSearchProvider, @unchecked Sendable {
    private let session: URLSession
    private let baseURL = "https://api.bing.microsoft.com/v7.0/search"
    private let apiKey: String?
    
    init(apiKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }
    
    func search(query: String) async throws -> [SearchResult] {
        guard let apiKey = apiKey else {
            // Without API key, return empty results
            return []
        }
        
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "offset", value: "0")
        ]
        
        guard let url = components?.url else {
            throw WebSearchError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebSearchError.invalidResponse
            }
            
            if httpResponse.statusCode == 429 {
                throw WebSearchError.rateLimitExceeded
            }
            
            guard httpResponse.statusCode == 200 else {
                throw WebSearchError.invalidResponse
            }
            
            // Parse Bing API response
            // TODO: Implement proper JSON parsing for Bing API
            return try parseBingResponse(data: data)
        } catch {
            if error is WebSearchError {
                throw error
            }
            throw WebSearchError.networkError(error)
        }
    }
    
    private func parseBingResponse(data: Data) throws -> [SearchResult] {
        struct BingResponse: Codable {
            let webPages: WebPages?
            
            struct WebPages: Codable {
                let value: [WebPage]?
            }
            
            struct WebPage: Codable {
                let name: String?
                let url: String?
                let snippet: String?
            }
        }
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(BingResponse.self, from: data)
        
        guard let webPages = response.webPages?.value else {
            return []
        }
        
        return webPages.compactMap { page in
            guard let title = page.name,
                  let urlString = page.url,
                  let url = URL(string: urlString) else {
                return nil
            }
            
            return SearchResult(
                id: UUID().uuidString,
                title: title,
                description: page.snippet,
                source: "bing",
                sourceType: .online,
                url: url,
                location: nil,
                distance: nil,
                metadata: [:]
            )
        }
    }
}
