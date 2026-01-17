import Foundation
import MetasearchCore

final class BingProvider: WebSearchProvider, @unchecked Sendable {
    private let session: URLSession
    private let baseURL = "https://api.bing.microsoft.com/v7.0/search"
    private let apiKey: String?
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    
    init(apiKey: String? = nil, session: URLSession = .shared, maxRetries: Int = 3, retryDelay: TimeInterval = 1.0) {
        self.apiKey = apiKey
        self.session = session
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    func search(query: String) async throws -> [SearchResult] {
        guard let apiKey = apiKey else {
            // Without API key, return empty results
            return []
        }
        
        return try await searchWithRetry(query: query, apiKey: apiKey, attempt: 0)
    }
    
    private func searchWithRetry(query: String, apiKey: String, attempt: Int) async throws -> [SearchResult] {
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
        request.setValue("InTheNeighborhood/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebSearchError.invalidResponse
            }
            
            // Handle rate limiting with retry
            if httpResponse.statusCode == 429 {
                if attempt < maxRetries {
                    // Exponential backoff: delay = retryDelay * 2^attempt
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
                }
                throw WebSearchError.rateLimitExceeded
            }
            
            // Handle other HTTP errors
            guard httpResponse.statusCode == 200 else {
                // For 401/403, don't retry (authentication issue)
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw WebSearchError.invalidResponse
                }
                
                // For 5xx errors, retry
                if httpResponse.statusCode >= 500 && attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
                }
                
                throw WebSearchError.invalidResponse
            }
            
            // Parse Bing API response
            return try parseBingResponse(data: data)
        } catch {
            // Retry on network errors
            if error is URLError && attempt < maxRetries {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
            }
            
            if error is WebSearchError {
                throw error
            }
            throw WebSearchError.networkError(error)
        }
    }
    
    private func parseBingResponse(data: Data) throws -> [SearchResult] {
        struct BingResponse: Codable {
            let webPages: WebPages?
            let news: News?
            let images: Images?
            
            struct WebPages: Codable {
                let value: [WebPage]?
            }
            
            struct WebPage: Codable {
                let name: String?
                let url: String?
                let snippet: String?
                let displayUrl: String?
                let dateLastCrawled: String?
            }
            
            struct News: Codable {
                let value: [NewsItem]?
            }
            
            struct NewsItem: Codable {
                let name: String?
                let url: String?
                let description: String?
            }
            
            struct Images: Codable {
                let value: [ImageItem]?
            }
            
            struct ImageItem: Codable {
                let name: String?
                let contentUrl: String?
                let thumbnailUrl: String?
            }
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let response: BingResponse
        do {
            response = try decoder.decode(BingResponse.self, from: data)
        } catch {
            // If JSON parsing fails, try to extract error information
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let _ = error["message"] as? String {
                throw WebSearchError.invalidResponse
            }
            throw WebSearchError.invalidResponse
        }
        
        var results: [SearchResult] = []
        
        // Parse web pages (primary results)
        if let webPages = response.webPages?.value {
            results.append(contentsOf: webPages.compactMap { page in
                guard let title = page.name,
                      let urlString = page.url,
                      let url = URL(string: urlString) else {
                    return nil
                }
                
                var metadata: [String: AnyHashable] = [:]
                if let displayUrl = page.displayUrl {
                    metadata["displayUrl"] = displayUrl
                }
                if let dateLastCrawled = page.dateLastCrawled {
                    metadata["dateLastCrawled"] = dateLastCrawled
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
                    metadata: metadata
                )
            })
        }
        
        // Parse news results (if available)
        if let newsItems = response.news?.value {
            results.append(contentsOf: newsItems.compactMap { item in
                guard let title = item.name,
                      let urlString = item.url,
                      let url = URL(string: urlString) else {
                    return nil
                }
                
                return SearchResult(
                    id: UUID().uuidString,
                    title: title,
                    description: item.description,
                    source: "bing",
                    sourceType: .online,
                    url: url,
                    location: nil,
                    distance: nil,
                    metadata: ["type": "news"]
                )
            })
        }
        
        return results
    }
}
