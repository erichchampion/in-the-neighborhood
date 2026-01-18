import Foundation

struct AmazonProductMetadata {
    let title: String?
    let price: String?
    let brand: String?
    let ratings: Double?
    let availability: String?
    let asin: String?
    let imageUrl: String?
}

final class AmazonProductScraper: @unchecked Sendable {
    private let session: URLSession
    private let timeout: TimeInterval
    
    init(session: URLSession = .shared, timeout: TimeInterval = 5.0) {
        self.session = session
        self.timeout = timeout
    }
    
    func scrapeProduct(url: URL) async throws -> AmazonProductMetadata {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = timeout
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AmazonScrapingError.invalidResponse
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw AmazonScrapingError.invalidResponse
        }
        
        return parseProductDetails(html: html, url: url)
    }
    
    private func parseProductDetails(html: String, url: URL) -> AmazonProductMetadata {
        let nsString = html as NSString
        
        // Extract product title
        var title: String? = nil
        let titlePatterns = [
            #"<span[^>]*id="productTitle"[^>]*>([^<]+)</span>"#,
            #"<h1[^>]*id="title"[^>]*>.*?<span[^>]*>([^<]+)</span>"#,
            #"<h1[^>]*class="[^"]*a-size-large[^"]*"[^>]*>([^<]+)</h1>"#,
            #"<meta[^>]*property="og:title"[^>]*content="([^"]+)""#
        ]
        
        for pattern in titlePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)),
               match.range(at: 1).location != NSNotFound {
                title = nsString.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                
                if !title!.isEmpty {
                    break
                }
            }
        }
        
        // Extract ASIN from URL or page
        var asin: String? = nil
        if let asinMatch = url.absoluteString.range(of: "/dp/") {
            let afterDp = url.absoluteString[asinMatch.upperBound...]
            if let slashIndex = afterDp.firstIndex(of: "/") {
                asin = String(afterDp[..<slashIndex])
            } else if let questionIndex = afterDp.firstIndex(of: "?") {
                asin = String(afterDp[..<questionIndex])
            } else {
                asin = String(afterDp)
            }
        } else {
            // Try to extract from page
            let asinPattern = #"data-asin="([^"]+)""#
            if let regex = try? NSRegularExpression(pattern: asinPattern, options: []),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)),
               match.range(at: 1).location != NSNotFound {
                asin = nsString.substring(with: match.range(at: 1))
            }
        }
        
        // Extract price - multiple patterns for different price displays
        var price: String? = nil
        let pricePatterns = [
            #"<span[^>]*class="[^"]*a-price-whole[^"]*"[^>]*>([^<]+)</span>"#,
            #"<span[^>]*id="priceblock_[^"]*"[^>]*>\s*\$?\s*([\d,]+\.?\d*)"#,
            #"<span[^>]*class="[^"]*a-price[^"]*"[^>]*>\s*\$?\s*([\d,]+\.?\d*)"#,
            #"price\s*[:\-]\s*\$?\s*([\d,]+\.?\d*)"#
        ]
        
        for pattern in pricePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)),
               match.range(at: 1).location != NSNotFound {
                let priceValue = nsString.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: "")
                
                if !priceValue.isEmpty {
                    price = "$\(priceValue)"
                    break
                }
            }
        }
        
        // Extract brand from Product Details section
        var brand: String? = nil
        let brandPatterns = [
            #"<tr[^>]*>\s*<th[^>]*>Brand</th>\s*<td[^>]*>([^<]+)</td>\s*</tr>"#,
            #"<span[^>]*>Brand</span>\s*<span[^>]*>([^<]+)</span>"#,
            #"data-brand="([^"]+)""#,
            #"<a[^>]*class="[^"]*a-link-normal[^"]*"[^>]*>([^<]+)</a>\s*<span[^>]*>Brand</span>"#
        ]
        
        for pattern in brandPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)),
               match.range(at: 1).location != NSNotFound {
                brand = nsString.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                
                if !brand!.isEmpty && brand!.count > 1 {
                    break
                }
            }
        }
        
        // Extract ratings (star rating)
        var ratings: Double? = nil
        let ratingPatterns = [
            #"<span[^>]*class="[^"]*a-icon-alt[^"]*"[^>]*>([\d.]+)\s+out of 5"#,
            #"<span[^>]*aria-label="([\d.]+)\s+out of 5"#,
            #"rating[^>]*>([\d.]+)\s*out of 5"#,
            #"data-hook="rating-star-text"[^>]*>([\d.]+)"#
        ]
        
        for pattern in ratingPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)),
               match.range(at: 1).location != NSNotFound {
                let ratingString = nsString.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let ratingValue = Double(ratingString), ratingValue >= 0 && ratingValue <= 5 {
                    ratings = ratingValue
                    break
                }
            }
        }
        
        // Extract availability
        var availability: String? = nil
        let availabilityPatterns = [
            #"<span[^>]*id="availability"[^>]*>.*?<span[^>]*>([^<]+)</span>"#,
            #"<div[^>]*id="availability"[^>]*>.*?<span[^>]*>([^<]+)</span>"#,
            #"availability[^>]*>([^<]+)</"#,
            #"In Stock"#,
            #"Out of Stock"#,
            #"Currently unavailable"#
        ]
        
        for pattern in availabilityPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) {
                
                if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                    availability = nsString.substring(with: match.range(at: 1))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    // For patterns without capture groups, check what matched
                    let matchedText = nsString.substring(with: match.range)
                    if matchedText.lowercased().contains("in stock") {
                        availability = "In Stock"
                    } else if matchedText.lowercased().contains("out of stock") || matchedText.lowercased().contains("unavailable") {
                        availability = "Out of Stock"
                    }
                }
                
                if availability != nil {
                    break
                }
            }
        }
        
        // Extract product image URL
        var imageUrl: String? = nil
        let imagePatterns = [
            #"<img[^>]*id="landingImage"[^>]*src="([^"]+)""#,
            #"<img[^>]*data-src="([^"]+)"[^>]*id="landingImage""#,
            #"<img[^>]*class="[^"]*a-dynamic-image[^"]*"[^>]*src="([^"]+)""#
        ]
        
        for pattern in imagePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)),
               match.range(at: 1).location != NSNotFound {
                imageUrl = nsString.substring(with: match.range(at: 1))
                if imageUrl != nil && !imageUrl!.isEmpty {
                    break
                }
            }
        }
        
        return AmazonProductMetadata(
            title: title,
            price: price,
            brand: brand,
            ratings: ratings,
            availability: availability,
            asin: asin,
            imageUrl: imageUrl
        )
    }
}

enum AmazonScrapingError: Error {
    case invalidResponse
    case networkError(Error)
    case timeout
}
