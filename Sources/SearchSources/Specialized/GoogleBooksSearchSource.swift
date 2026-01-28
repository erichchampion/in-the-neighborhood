import Foundation
import MetasearchCore

public final class GoogleBooksSearchSource: SearchSource, @unchecked Sendable {
    public let identifier: String = "googlebooks"
    public let sourceType: SourceType = .online
    
    private let session: URLSession
    private let apiKey: String?
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    private let baseURL = "https://www.googleapis.com/books/v1/volumes"
    
    public init(
        apiKey: String? = nil,
        session: URLSession = .shared,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0
    ) {
        self.apiKey = apiKey
        self.session = session
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        print("[GoogleBooksSearchSource] Starting search for: \(query.original)")
        
        // Log bundle ID for iOS app restriction debugging
        if let bundleId = Bundle.main.bundleIdentifier {
            print("[GoogleBooksSearchSource] Bundle ID: \(bundleId)")
        }
        
        // Google Books API works without an API key for public searches, but using one
        // allows higher rate limits. If no key is provided, we'll search without it.
        do {
            let results = try await searchWithRetry(query: query.original, apiKey: apiKey, attempt: 0)
            print("[GoogleBooksSearchSource] Found \(results.count) results")
            for result in results {
                print("[GoogleBooksSearchSource] Result: title=\(result.title), author=\(result.metadata["author"] as? String ?? "nil"), isbn=\(result.metadata["isbn"] as? String ?? "nil")")
            }
            return results
        } catch {
            print("[GoogleBooksSearchSource] Search failed with error: \(error)")
            throw error
        }
    }
    
    private func searchWithRetry(query: String, apiKey: String?, attempt: Int) async throws -> [SearchResult] {
        var components = URLComponents(string: baseURL)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "projection", value: "lite")
            // Note: "lite" projection should still include industryIdentifiers (ISBNs)
        ]
        
        // Add API key only if provided (optional for public searches)
        if let apiKey = apiKey, !apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
            print("[GoogleBooksSearchSource] Using API key (length: \(apiKey.count))")
        } else {
            print("[GoogleBooksSearchSource] No API key provided, searching without authentication")
        }
        
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw GoogleBooksError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("InTheNeighborhood/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleBooksError.invalidResponse
            }
            
            // Handle rate limiting with retry
            if httpResponse.statusCode == 429 {
                if attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
                }
                throw GoogleBooksError.rateLimitExceeded
            }
            
            // Handle other HTTP errors
            guard httpResponse.statusCode == 200 else {
                // Log error response body for debugging
                if let errorData = String(data: data, encoding: .utf8) {
                    print("[GoogleBooksSearchSource] Error response (\(httpResponse.statusCode)): \(errorData)")
                }
                
                // For 400/403, try without API key if one was provided
                if httpResponse.statusCode == 400 || httpResponse.statusCode == 403 {
                    print("[GoogleBooksSearchSource] Bad request or invalid API key: \(httpResponse.statusCode)")
                    if let errorData = String(data: data, encoding: .utf8) {
                        print("[GoogleBooksSearchSource] Error details: \(errorData)")
                    }
                    
                    // Log bundle ID for iOS app restriction debugging
                    if let bundleId = Bundle.main.bundleIdentifier {
                        print("[GoogleBooksSearchSource] Current bundle ID: \(bundleId)")
                        print("[GoogleBooksSearchSource] NOTE: If your API key has iOS app restrictions, ensure the bundle ID in Google Cloud Console matches exactly: \(bundleId)")
                    }
                    
                    // If we had an API key and got 403, try again without it
                    if let apiKey = apiKey, !apiKey.isEmpty, attempt == 0 {
                        print("[GoogleBooksSearchSource] Retrying without API key...")
                        return try await searchWithRetry(query: query, apiKey: nil, attempt: attempt + 1)
                    }
                    
                    return []
                }
                
                // For 5xx errors, retry
                if httpResponse.statusCode >= 500 && attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
                }
                
                throw GoogleBooksError.invalidResponse
            }
            
            // Parse Google Books API response
            return try parseGoogleBooksResponse(data: data)
        } catch {
            // Retry on network errors
            if error is URLError && attempt < maxRetries {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await searchWithRetry(query: query, apiKey: apiKey, attempt: attempt + 1)
            }
            
            if error is GoogleBooksError {
                throw error
            }
            throw GoogleBooksError.networkError(error)
        }
    }
    
    private func parseGoogleBooksResponse(data: Data) throws -> [SearchResult] {
        // Define response structures
        struct GoogleBooksResponse: Codable {
            let items: [Volume]?
            let totalItems: Int?
        }
        
        struct Volume: Codable {
            let id: String
            let volumeInfo: VolumeInfo
            let saleInfo: SaleInfo?
        }
        
        struct VolumeInfo: Codable {
            let title: String?
            let subtitle: String?
            let authors: [String]?
            let publisher: String?
            let publishedDate: String?
            let description: String?
            let industryIdentifiers: [IndustryIdentifier]?
            let pageCount: Int?
            let categories: [String]?
            let averageRating: Double?
            let ratingsCount: Int?
            let imageLinks: ImageLinks?
            let previewLink: String?
            let infoLink: String?
        }
        
        struct IndustryIdentifier: Codable {
            let type: String
            let identifier: String
        }
        
        struct ImageLinks: Codable {
            let thumbnail: String?
            let small: String?
            let medium: String?
            let large: String?
            let extraLarge: String?
        }
        
        struct SaleInfo: Codable {
            let listPrice: Price?
            let retailPrice: Price?
            let buyLink: String?
        }
        
        struct Price: Codable {
            let amount: Double?
            let currencyCode: String?
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let response: GoogleBooksResponse
        do {
            response = try decoder.decode(GoogleBooksResponse.self, from: data)
        } catch {
            print("[GoogleBooksSearchSource] Failed to parse JSON: \(error)")
            // Log a sample of the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                let preview = String(responseString.prefix(500))
                print("[GoogleBooksSearchSource] Response preview: \(preview)...")
            }
            throw GoogleBooksError.invalidResponse
        }
        
        guard let items = response.items else {
            print("[GoogleBooksSearchSource] No items in response (totalItems: \(response.totalItems ?? 0))")
            return []
        }
        
        print("[GoogleBooksSearchSource] Parsed \(items.count) items from response")
        
        var results: [SearchResult] = []
        
        for volume in items {
            let volumeInfo = volume.volumeInfo
            guard let title = volumeInfo.title else {
                continue
            }
            
            // Build full title with subtitle if available
            var fullTitle = title
            if let subtitle = volumeInfo.subtitle {
                fullTitle = "\(title): \(subtitle)"
            }
            
            // Extract authors
            let authors = volumeInfo.authors ?? []
            let authorString = authors.joined(separator: ", ")
            
            // Extract ISBN (prefer ISBN-13, fallback to ISBN-10)
            var isbn: String? = nil
            if let identifiers = volumeInfo.industryIdentifiers {
                if let isbn13 = identifiers.first(where: { $0.type == "ISBN_13" || $0.type.uppercased() == "ISBN_13" }) {
                    isbn = isbn13.identifier
                } else if let isbn10 = identifiers.first(where: { $0.type == "ISBN_10" || $0.type.uppercased() == "ISBN_10" }) {
                    isbn = isbn10.identifier
                }
            }
            
            // Debug: Log if identifiers exist but ISBN wasn't found
            if let identifiers = volumeInfo.industryIdentifiers, isbn == nil, !identifiers.isEmpty {
                print("[GoogleBooksSearchSource] Found \(identifiers.count) industry identifiers but no ISBN: \(identifiers.map { "\($0.type): \($0.identifier)" }.joined(separator: ", "))")
            }
            
            // Extract image URL (prefer thumbnail, fallback to small)
            // Convert HTTP URLs to HTTPS to comply with App Transport Security
            var imageUrl: String? = nil
            if let imageLinks = volumeInfo.imageLinks {
                if let thumbnail = imageLinks.thumbnail {
                    imageUrl = thumbnail.replacingOccurrences(of: "http://", with: "https://")
                } else if let small = imageLinks.small {
                    imageUrl = small.replacingOccurrences(of: "http://", with: "https://")
                }
            }
            
            // Extract price
            var price: String? = nil
            if let saleInfo = volume.saleInfo {
                if let listPrice = saleInfo.listPrice,
                   let amount = listPrice.amount {
                    let currencyCode = listPrice.currencyCode ?? "USD"
                    if currencyCode == "USD" {
                        price = String(format: "$%.2f", amount)
                    } else {
                        price = String(format: "%.2f %@", amount, currencyCode)
                    }
                } else if let retailPrice = saleInfo.retailPrice,
                          let amount = retailPrice.amount {
                    let currencyCode = retailPrice.currencyCode ?? "USD"
                    if currencyCode == "USD" {
                        price = String(format: "$%.2f", amount)
                    } else {
                        price = String(format: "%.2f %@", amount, currencyCode)
                    }
                }
            }
            
            // Build description from available fields
            var descriptionParts: [String] = []
            if !authorString.isEmpty {
                descriptionParts.append("by \(authorString)")
            }
            if let publisher = volumeInfo.publisher {
                descriptionParts.append(publisher)
            }
            if let publishedDate = volumeInfo.publishedDate {
                descriptionParts.append(publishedDate)
            }
            if let pageCount = volumeInfo.pageCount {
                descriptionParts.append("\(pageCount) pages")
            }
            if let averageRating = volumeInfo.averageRating {
                let ratingString = String(format: "⭐ %.1f", averageRating)
                if let ratingsCount = volumeInfo.ratingsCount, ratingsCount > 0 {
                    descriptionParts.append("\(ratingString) (\(ratingsCount))")
                } else {
                    descriptionParts.append(ratingString)
                }
            }
            if let price = price {
                descriptionParts.append(price)
            }
            
            let description = descriptionParts.isEmpty ? volumeInfo.description : descriptionParts.joined(separator: " • ")
            
            // Determine URL (prefer infoLink, fallback to previewLink)
            let urlString = volumeInfo.infoLink ?? volumeInfo.previewLink
            let url = urlString.flatMap { URL(string: $0) }
            
            // Build ProductMetadata
            let productMetadata = ProductMetadata(
                isbn: isbn,
                author: authorString.isEmpty ? nil : authorString,
                price: price,
                imageUrl: imageUrl,
                publisher: volumeInfo.publisher,
                publishedDate: volumeInfo.publishedDate,
                pageCount: volumeInfo.pageCount.map { String($0) },
                averageRating: volumeInfo.averageRating,
                ratingsCount: volumeInfo.ratingsCount,
                buyLink: volume.saleInfo?.buyLink,
                source: "Google Books"
            )
            
            // Convert to dictionary for SearchResult (backward compatibility)
            let metadata = productMetadata.toDictionary()
            
            let result = SearchResult(
                id: volume.id,
                title: fullTitle,
                description: description,
                source: identifier,
                sourceType: sourceType,
                url: url,
                location: nil,
                distance: nil,
                metadata: metadata
            )
            
            results.append(result)
        }
        
        return results
    }
}

enum GoogleBooksError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case rateLimitExceeded
}
