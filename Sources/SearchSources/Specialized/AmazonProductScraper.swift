import Foundation
import SwiftSoup

struct AmazonProductMetadata {
    let title: String?
    let price: String?
    let brand: String?
    let ratings: Double?
    let availability: String?
    let asin: String?
    let imageUrl: String?
    let isbn: String?
    let sku: String?
    let author: String?
    let artist: String?
}

final class AmazonProductScraper: @unchecked Sendable {
    private let session: URLSession
    private let timeout: TimeInterval
    
    init(session: URLSession = .shared, timeout: TimeInterval = 15.0) {
        self.session = session
        self.timeout = timeout
    }
    
    func scrapeProduct(url: URL) async throws -> AmazonProductMetadata {
        var request = URLRequest(url: url)
        
        // Set headers to mimic a real browser request (based on curl command)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,es-419;q=0.8,es;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("8", forHTTPHeaderField: "Device-Memory")
        request.setValue("10", forHTTPHeaderField: "Downlink")
        request.setValue("2", forHTTPHeaderField: "DPR")
        request.setValue("4g", forHTTPHeaderField: "ECT")
        request.setValue("u=0, i", forHTTPHeaderField: "Priority")
        request.setValue("50", forHTTPHeaderField: "RTT")
        request.setValue("8", forHTTPHeaderField: "Sec-CH-Device-Memory")
        request.setValue("2", forHTTPHeaderField: "Sec-CH-DPR")
        request.setValue("390", forHTTPHeaderField: "Sec-CH-Viewport-Width")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("390", forHTTPHeaderField: "Viewport-Width")
        request.timeoutInterval = timeout
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AmazonScrapingError.invalidResponse
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw AmazonScrapingError.invalidResponse
        }
        
        // Validate this is actually a product page (not a credit card page, search page, etc.)
        let isProductPage = html.contains("productTitle") || 
                           html.contains("id=\"title\"") || 
                           html.contains("data-asin=") ||
                           (html.contains("/dp/") && html.contains("product"))
        
        if !isProductPage {
            print("[AmazonProductScraper] WARNING: URL \(url.absoluteString) does not appear to be a product page")
            // Still try to parse, but log the issue
        }
        
        // Check if this is a series page and extract individual product if needed
        let isSeries = isSeriesPage(url: url, html: html)
        print("[AmazonProductScraper] URL: \(url.absoluteString), isSeriesPage: \(isSeries)")
        
        if isSeries {
            let productLinks = extractIndividualProductLinks(html: html)
            print("[AmazonProductScraper] Found \(productLinks.count) individual product links")
            if let individualProductUrl = productLinks.first {
                // Recursively scrape the individual product page
                print("[AmazonProductScraper] Detected series page, following to individual product: \(individualProductUrl.absoluteString)")
                let individualMetadata = try await scrapeProduct(url: individualProductUrl)
                // Merge metadata: keep series page title/author if individual page lacks it
                let seriesMetadata = parseProductDetails(html: html, url: url)
                return mergeMetadata(series: seriesMetadata, individual: individualMetadata)
            } else {
                print("[AmazonProductScraper] Series page detected but no individual product links found")
            }
        }
        
        return parseProductDetails(html: html, url: url)
    }
    
    private func isSeriesPage(url: URL, html: String) -> Bool {
        // Check URL path for "series"
        if url.path.lowercased().contains("series") {
            return true
        }
        
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Check canonical URL meta tag (most reliable indicator)
            if let canonicalLink = try? doc.select("link[rel=canonical]").first(),
               let canonicalUrl = try? canonicalLink.attr("href"),
               canonicalUrl.lowercased().contains("series") {
                return true
            }
            
            // Check for series-specific HTML indicators
            // formatTwisterList indicates format switcher (series pages have this)
            if html.contains("formatTwisterList") && html.contains("product details for:") {
                return true
            }
            
            // Check for SeriesMainPageRequestId script tag
            if html.contains("SeriesMainPageRequestId") {
                return true
            }
        } catch {
            // If parsing fails, fall back to string checks
        }
        
        return false
    }
    
    private func extractIndividualProductLinks(html: String) -> [URL] {
        var productUrls: [URL] = []
        
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Look for /gp/product/ links in the format switcher
            // These are typically in formatTwisterList or similar structures
            let links = try doc.select("a[href*=/gp/product/]")
            
            for link in links {
                guard let href = try? link.attr("href"),
                      !href.isEmpty else {
                    continue
                }
                
                // Skip if it's a navigation link that won't redirect to product page
                if href.contains("notRedirectToSDP=1") {
                    continue
                }
                
                // Handle relative URLs
                var urlString = href
                if urlString.hasPrefix("/") {
                    urlString = "https://www.amazon.com\(urlString)"
                }
                
                // Remove query parameters to normalize URLs
                if let url = URL(string: urlString) {
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    components?.queryItems = nil
                    if let cleanUrl = components?.url,
                       !productUrls.contains(where: { 
                           var otherComponents = URLComponents(url: $0, resolvingAgainstBaseURL: false)
                           otherComponents?.queryItems = nil
                           return otherComponents?.url?.absoluteString == cleanUrl.absoluteString
                       }) {
                        productUrls.append(cleanUrl)
                    }
                }
            }
            
            // Prefer physical book versions (Paperback/Hardcover) over digital (Kindle/Audiobook)
            // Check the link text context to determine format type
            let physicalBookUrls = productUrls.filter { url in
                // Extract the product ID from URL
                let productId = url.lastPathComponent
                // Look for context around this product ID in HTML to determine format
                // Escape the productId for use in regex
                let escapedProductId = NSRegularExpression.escapedPattern(for: productId)
                let productIdPattern = "href=\"[^\"]*\(escapedProductId)[^\"]*\"[^>]*>([^<]+)</a>"
                if let regex = try? NSRegularExpression(pattern: productIdPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                   let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: (html as NSString).length)),
                   match.range(at: 1).location != NSNotFound {
                    let linkText = (html as NSString).substring(with: match.range(at: 1)).lowercased()
                    // Prefer Paperback, Hardcover, Mass Market Paperback over Kindle, Audiobook
                    return linkText.contains("paperback") || linkText.contains("hardcover") || linkText.contains("mass market")
                }
                return false
            }
            
            // If we found physical book links, use those; otherwise use all links
            if !physicalBookUrls.isEmpty {
                return physicalBookUrls
            }
            
            // Fallback: prefer non-Kindle/Audiobook links by URL pattern
            let preferredUrls = productUrls.filter { url in
                let urlString = url.absoluteString.lowercased()
                return !urlString.contains("kindle") && !urlString.contains("audiobook") && !urlString.contains("audible")
            }
            
            return preferredUrls.isEmpty ? productUrls : preferredUrls
        } catch {
            print("[AmazonProductScraper] Failed to parse HTML for product links: \(error)")
            return []
        }
    }
    
    private func mergeMetadata(series: AmazonProductMetadata, individual: AmazonProductMetadata) -> AmazonProductMetadata {
        // Merge metadata: prefer individual page data, but keep series page data if individual lacks it
        return AmazonProductMetadata(
            title: individual.title ?? series.title,
            price: individual.price ?? series.price,
            brand: individual.brand ?? series.brand,
            ratings: individual.ratings ?? series.ratings,
            availability: individual.availability ?? series.availability,
            asin: individual.asin ?? series.asin,
            imageUrl: individual.imageUrl ?? series.imageUrl,
            isbn: individual.isbn ?? series.isbn,
            sku: individual.sku ?? series.sku,
            author: individual.author ?? series.author,
            artist: individual.artist ?? series.artist
        )
    }
    
    private func parseProductDetails(html: String, url: URL) -> AmazonProductMetadata {
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Extract product title - prioritize title tag from product detail page
            var title: String? = nil
            
            // Try title tag first (most reliable for product detail pages)
            if let titleElement = try? doc.select("title").first() {
                var extracted = try titleElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Clean up title tag results (remove "Amazon.com:" prefix, etc.)
                extracted = extracted.replacingOccurrences(of: #"^Amazon\.com[:\s]*"#, with: "", options: .regularExpression)
                extracted = extracted.replacingOccurrences(of: #"\s*:\s*Amazon\.com.*$"#, with: "", options: .regularExpression)
                extracted = extracted.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
                
                if !extracted.isEmpty && extracted.count > 3 {
                    title = extracted
                    print("[DEBUG] AmazonProductScraper - Title extracted using selector: title, title: \(title ?? "nil")")
                }
            }
            
            // Fallback to other selectors if title tag didn't work
            if title == nil {
                let titleSelectors = [
                    "span#productTitle",
                    "h1#title span",
                    "span.a-size-large.product-title-word-break",
                    "h1[data-automation-id=title]",
                    "meta[property=og:title]"
                ]
                
                for selector in titleSelectors {
                    if let element = try? doc.select(selector).first() {
                        let extracted = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !extracted.isEmpty && extracted.count > 3 {
                            title = extracted
                            print("[DEBUG] AmazonProductScraper - Title extracted using selector: \(selector), title: \(title ?? "nil")")
                            break
                        }
                    }
                }
            }
            
            if title == nil {
                print("[DEBUG] AmazonProductScraper - WARNING: No title extracted from URL: \(url.absoluteString)")
            }
            
            // Extract ASIN from URL or page
            var asin: String? = nil
            // Handle /dp/ASIN and /gp/product/ASIN formats
            if let dpMatch = url.absoluteString.range(of: "/dp/") {
                let afterDp = url.absoluteString[dpMatch.upperBound...]
                if let slashIndex = afterDp.firstIndex(of: "/") {
                    let extracted = String(afterDp[..<slashIndex])
                    if extracted.lowercased() != "product" {
                        asin = extracted
                    } else if let nextSlash = afterDp[afterDp.index(after: slashIndex)...].firstIndex(of: "/") {
                        asin = String(afterDp[afterDp.index(after: slashIndex)..<nextSlash])
                    }
                } else if let questionIndex = afterDp.firstIndex(of: "?") {
                    let extracted = String(afterDp[..<questionIndex])
                    if extracted.lowercased() != "product" {
                        asin = extracted
                    }
                } else {
                    let extracted = String(afterDp)
                    if extracted.lowercased() != "product" {
                        asin = extracted
                    }
                }
            } else if let gpMatch = url.absoluteString.range(of: "/gp/product/") {
                let afterGp = url.absoluteString[gpMatch.upperBound...]
                if let slashIndex = afterGp.firstIndex(of: "/") {
                    asin = String(afterGp[..<slashIndex])
                } else if let questionIndex = afterGp.firstIndex(of: "?") {
                    asin = String(afterGp[..<questionIndex])
                } else {
                    asin = String(afterGp)
                }
            }
            
            // Fallback: Try to extract from page if not found in URL
            if asin == nil || asin?.lowercased() == "product" {
                // Strategy 1: Try prodDetTable
                if let prodDetTable = try? doc.select("table.prodDetTable").first() {
                    let rows = try? prodDetTable.select("tr")
                    if let rows = rows {
                        for row in rows {
                            if let th = try? row.select("th.prodDetSectionEntry").first(),
                               let thText = try? th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                               thText.contains("ASIN"),
                               let td = try? row.select("td.prodDetAttrValue").first() {
                                let extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                if !extracted.isEmpty && extracted.lowercased() != "product" {
                                    asin = extracted
                                    break
                                }
                            }
                        }
                    }
                }
                
                // Strategy 2: Try detail-bullet-list (unordered list structure)
                if asin == nil || asin?.lowercased() == "product" {
                    if let bulletList = try? doc.select("ul.detail-bullet-list, ul.a-unordered-list.detail-bullet-list").first() {
                        let listItems = try? bulletList.select("li")
                        if let listItems = listItems {
                            for item in listItems {
                                if let listItemSpan = try? item.select("span.a-list-item").first(),
                                   let labelSpan = try? listItemSpan.select("span.a-text-bold").first(),
                                   let labelText = try? labelSpan.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                                   labelText.contains("ASIN") {
                                    // Get all spans in the list item, find the one that's not bold
                                    let allSpans = try? listItemSpan.select("span")
                                    if let allSpans = allSpans {
                                        for span in allSpans {
                                            let spanClass = try? span.attr("class")
                                            if spanClass?.contains("a-text-bold") != true {
                                                let extracted = try span.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                                if !extracted.isEmpty && extracted.lowercased() != "product" {
                                                    asin = extracted
                                                    break
                                                }
                                            }
                                        }
                                    }
                                    if asin != nil { break }
                                }
                            }
                        }
                    }
                }
                
                // Strategy 3: Fallback to data-asin attribute
                if asin == nil || asin?.lowercased() == "product" {
                    if let element = try? doc.select("[data-asin]").first(),
                       let extracted = try? element.attr("data-asin"),
                       !extracted.isEmpty && extracted.lowercased() != "product" {
                        asin = extracted
                    }
                }
            }
            
            // Extract price - multiple selectors for different price displays
            var price: String? = nil
            let priceSelectors = [
                "span.a-price-whole",
                "span#priceblock_dealprice",
                "span#priceblock_ourprice",
                "span#priceblock_saleprice",
                "span.a-price"
            ]
            
            for selector in priceSelectors {
                if let element = try? doc.select(selector).first() {
                    let priceText = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleaned = priceText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
                    if !cleaned.isEmpty {
                        price = "$\(cleaned)"
                        break
                    }
                }
            }
            
            // Extract brand/manufacturer from Product Details and Technical Details sections
            var brand: String? = nil
            let brandLabels = ["Brand", "Brand Name", "Manufacturer", "Publisher", "Imprint"]
            
            // Strategy 1: Try prodDetTable (most reliable)
            if let prodDetTable = try? doc.select("table.prodDetTable").first() {
                let rows = try? prodDetTable.select("tr")
                if let rows = rows {
                    for row in rows {
                        if let th = try? row.select("th.prodDetSectionEntry").first(),
                           let thText = try? th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                           brandLabels.contains(where: { thText.contains($0) }),
                           let td = try? row.select("td.prodDetAttrValue").first() {
                            let extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            if !extracted.isEmpty && extracted.count > 1 && extracted.lowercased() != "amazon" {
                                brand = extracted
                                print("[DEBUG] AmazonProductScraper - Brand extracted from prodDetTable: \(brand ?? "nil")")
                                break
                            }
                        }
                    }
                }
            }
            
            // Strategy 2: Try detail-bullet-list (unordered list structure)
            if brand == nil {
                if let bulletList = try? doc.select("ul.detail-bullet-list, ul.a-unordered-list.detail-bullet-list").first() {
                    let listItems = try? bulletList.select("li")
                    if let listItems = listItems {
                        for item in listItems {
                            if let listItemSpan = try? item.select("span.a-list-item").first(),
                               let labelSpan = try? listItemSpan.select("span.a-text-bold").first(),
                               let labelText = try? labelSpan.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                               brandLabels.contains(where: { labelText.contains($0) }) {
                                // Get all spans in the list item, find the one that's not bold
                                let allSpans = try? listItemSpan.select("span")
                                if let allSpans = allSpans {
                                    for span in allSpans {
                                        let spanClass = try? span.attr("class")
                                        if spanClass?.contains("a-text-bold") != true {
                                            let extracted = try span.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                            if !extracted.isEmpty && extracted.count > 1 && extracted.lowercased() != "amazon" {
                                                brand = extracted
                                                print("[DEBUG] AmazonProductScraper - Brand extracted from detail-bullet-list: \(brand ?? "nil")")
                                                break
                                            }
                                        }
                                    }
                                }
                                if brand != nil { break }
                            }
                        }
                    }
                }
            }
            
            // Strategy 3: Fallback - Try all table rows
            if brand == nil {
                let brandRows = try? doc.select("tr")
                if let brandRows = brandRows {
                    for row in brandRows {
                        if let th = try? row.select("th").first() {
                            let thText = try th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            if brandLabels.contains(where: { thText.contains($0) }) {
                                if let td = try? row.select("td").first() {
                                    let extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                    if !extracted.isEmpty && extracted.count > 1 && extracted.lowercased() != "amazon" {
                                        brand = extracted
                                        print("[DEBUG] AmazonProductScraper - Brand extracted: \(brand ?? "nil")")
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Try span-based patterns
            if brand == nil {
                for label in brandLabels {
                    let spans = try? doc.select("span.a-text-bold")
                    if let spans = spans {
                        for span in spans {
                            let spanText = try? span.text()
                            if spanText?.contains(label) == true {
                                if let parent = span.parent(),
                                   let valueSpan = try? parent.select("span").last() {
                                    let extracted = try valueSpan.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                    if !extracted.isEmpty && extracted.count > 1 && extracted.lowercased() != "amazon" {
                                        brand = extracted
                                        break
                                    }
                                }
                            }
                        }
                    }
                    if brand != nil { break }
                }
            }
            
            // Try data attribute
            if brand == nil {
                if let element = try? doc.select("[data-brand]").first(),
                   let extracted = try? element.attr("data-brand"),
                   !extracted.isEmpty && extracted.lowercased() != "amazon" {
                    brand = extracted
                }
            }
            
            // Extract ratings (star rating)
            var ratings: Double? = nil
            
            // Strategy 1: Try prodDetTable for "Customer Reviews"
            if let prodDetTable = try? doc.select("table.prodDetTable").first() {
                let rows = try? prodDetTable.select("tr")
                if let rows = rows {
                    for row in rows {
                        if let th = try? row.select("th.prodDetSectionEntry").first(),
                           let thText = try? th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                           thText.contains("Customer Reviews"),
                           let td = try? row.select("td").first() {
                            let reviewText = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            // Extract number from "X.X out of 5 stars" pattern
                            if let regex = try? NSRegularExpression(pattern: #"([\d.]+)\s+out of 5"#, options: []),
                               let match = regex.firstMatch(in: reviewText, options: [], range: NSRange(location: 0, length: (reviewText as NSString).length)),
                               match.range(at: 1).location != NSNotFound {
                                let ratingString = (reviewText as NSString).substring(with: match.range(at: 1))
                                if let ratingValue = Double(ratingString), ratingValue >= 0 && ratingValue <= 5 {
                                    ratings = ratingValue
                                }
                            }
                        }
                    }
                }
            }
            
            // Strategy 2: Try detail-bullet-list for "Customer Reviews"
            if ratings == nil {
                if let bulletList = try? doc.select("ul.detail-bullet-list, ul.a-unordered-list.detail-bullet-list").first() {
                    let listItems = try? bulletList.select("li")
                    if let listItems = listItems {
                        for item in listItems {
                            if let labelSpan = try? item.select("span.a-text-bold").first(),
                               let labelText = try? labelSpan.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                               labelText.contains("Customer Reviews") {
                                // Look for rating in the item - could be in a span with aria-label or in text
                                let itemText = try item.text()
                                // Also check for aria-label in star icons
                                if let starIcon = try? item.select("span.a-icon-alt").first(),
                                   let ariaLabel = try? starIcon.attr("aria-label"),
                                   let regex = try? NSRegularExpression(pattern: #"([\d.]+)\s+out of 5"#, options: []),
                                   let match = regex.firstMatch(in: ariaLabel, options: [], range: NSRange(location: 0, length: (ariaLabel as NSString).length)),
                                   match.range(at: 1).location != NSNotFound {
                                    let ratingString = (ariaLabel as NSString).substring(with: match.range(at: 1))
                                    if let ratingValue = Double(ratingString), ratingValue >= 0 && ratingValue <= 5 {
                                        ratings = ratingValue
                                        break
                                    }
                                } else {
                                    // Try extracting from item text
                                    if let regex = try? NSRegularExpression(pattern: #"([\d.]+)\s+out of 5"#, options: []),
                                       let match = regex.firstMatch(in: itemText, options: [], range: NSRange(location: 0, length: (itemText as NSString).length)),
                                       match.range(at: 1).location != NSNotFound {
                                        let ratingString = (itemText as NSString).substring(with: match.range(at: 1))
                                        if let ratingValue = Double(ratingString), ratingValue >= 0 && ratingValue <= 5 {
                                            ratings = ratingValue
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Fallback: try span.a-icon-alt
            if ratings == nil {
                if let ratingElement = try? doc.select("span.a-icon-alt").first() {
                    let ratingText = try ratingElement.text()
                    // Extract number from "X.X out of 5" pattern
                    if let regex = try? NSRegularExpression(pattern: #"([\d.]+)\s+out of 5"#, options: []),
                       let match = regex.firstMatch(in: ratingText, options: [], range: NSRange(location: 0, length: (ratingText as NSString).length)),
                       match.range(at: 1).location != NSNotFound {
                        let ratingString = (ratingText as NSString).substring(with: match.range(at: 1))
                        if let ratingValue = Double(ratingString), ratingValue >= 0 && ratingValue <= 5 {
                            ratings = ratingValue
                        }
                    }
                }
            }
            
            // Fallback: try aria-label
            if ratings == nil {
                if let ratingElement = try? doc.select("span[aria-label*='out of 5']").first(),
                   let ariaLabel = try? ratingElement.attr("aria-label"),
                   let regex = try? NSRegularExpression(pattern: #"([\d.]+)\s+out of 5"#, options: []),
                   let match = regex.firstMatch(in: ariaLabel, options: [], range: NSRange(location: 0, length: (ariaLabel as NSString).length)),
                   match.range(at: 1).location != NSNotFound {
                    let ratingString = (ariaLabel as NSString).substring(with: match.range(at: 1))
                    if let ratingValue = Double(ratingString), ratingValue >= 0 && ratingValue <= 5 {
                        ratings = ratingValue
                    }
                }
            }
            
            // Extract availability
            var availability: String? = nil
            if let availabilityElement = try? doc.select("span#availability, div#availability").first() {
                if let span = try? availabilityElement.select("span").first() {
                    availability = try span.text().trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    let text = try availabilityElement.text()
                    if text.lowercased().contains("in stock") {
                        availability = "In Stock"
                    } else if text.lowercased().contains("out of stock") || text.lowercased().contains("unavailable") {
                        availability = "Out of Stock"
                    }
                }
            }
            
            // Extract product image URL
            var imageUrl: String? = nil
            
            // Strategy 1: Look for img tag under span with data-action="main-image-click"
            if let imageSpan = try? doc.select("span[data-action=main-image-click]").first() {
                if let img = try? imageSpan.select("img").first() {
                    // Try src first, then data-src, then data-old-src
                    if let src = try? img.attr("src"), !src.isEmpty {
                        imageUrl = src
                    } else if let dataSrc = try? img.attr("data-src"), !dataSrc.isEmpty {
                        imageUrl = dataSrc
                    } else if let dataOldSrc = try? img.attr("data-old-src"), !dataOldSrc.isEmpty {
                        imageUrl = dataOldSrc
                    }
                }
            }
            
            // Strategy 2: Fallback to img#landingImage
            if imageUrl == nil {
                if let img = try? doc.select("img#landingImage").first() {
                    // Try src first, then data-src
                    if let src = try? img.attr("src"), !src.isEmpty {
                        imageUrl = src
                    } else if let dataSrc = try? img.attr("data-src"), !dataSrc.isEmpty {
                        imageUrl = dataSrc
                    }
                }
            }
            
            // Strategy 3: Fallback to any img with class containing "a-dynamic-image"
            if imageUrl == nil {
                if let img = try? doc.select("img.a-dynamic-image").first() {
                    if let src = try? img.attr("src"), !src.isEmpty {
                        imageUrl = src
                    } else if let dataSrc = try? img.attr("data-src"), !dataSrc.isEmpty {
                        imageUrl = dataSrc
                    }
                }
            }
            
            // Extract ISBN from Product Details and Technical Details
            var isbn: String? = nil
            let isbnLabels = ["ISBN-13", "ISBN-10", "ISBN"]
            
            // Strategy 1: Try prodDetTable (most reliable)
            if let prodDetTable = try? doc.select("table.prodDetTable").first() {
                let rows = try? prodDetTable.select("tr")
                if let rows = rows {
                    for row in rows {
                        if let th = try? row.select("th.prodDetSectionEntry").first(),
                           let thText = try? th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                           isbnLabels.contains(where: { thText.contains($0) }),
                           let td = try? row.select("td.prodDetAttrValue").first() {
                            var extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            extracted = extracted.replacingOccurrences(of: " ", with: "")
                            
                            // Validate: ISBN should be 10 or 13 digits (with optional hyphens)
                            let cleaned = extracted.replacingOccurrences(of: "-", with: "")
                            if cleaned.count == 10 || cleaned.count == 13 {
                                isbn = extracted
                                print("[DEBUG] AmazonProductScraper - ISBN extracted from prodDetTable: \(isbn ?? "nil")")
                                break
                            }
                        }
                    }
                }
            }
            
            // Strategy 2: Try detail-bullet-list (unordered list structure)
            if isbn == nil {
                if let bulletList = try? doc.select("ul.detail-bullet-list, ul.a-unordered-list.detail-bullet-list").first() {
                    let listItems = try? bulletList.select("li")
                    if let listItems = listItems {
                        for item in listItems {
                            if let listItemSpan = try? item.select("span.a-list-item").first(),
                               let labelSpan = try? listItemSpan.select("span.a-text-bold").first(),
                               let labelText = try? labelSpan.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                               isbnLabels.contains(where: { labelText.contains($0) }) {
                                // Get all spans in the list item, find the one that's not bold
                                let allSpans = try? listItemSpan.select("span")
                                if let allSpans = allSpans {
                                    for span in allSpans {
                                        let spanClass = try? span.attr("class")
                                        if spanClass?.contains("a-text-bold") != true {
                                            var extracted = try span.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                            extracted = extracted.replacingOccurrences(of: " ", with: "")
                                            
                                            // Validate: ISBN should be 10 or 13 digits (with optional hyphens)
                                            let cleaned = extracted.replacingOccurrences(of: "-", with: "")
                                            if cleaned.count == 10 || cleaned.count == 13 {
                                                isbn = extracted
                                                print("[DEBUG] AmazonProductScraper - ISBN extracted from detail-bullet-list: \(isbn ?? "nil")")
                                                break
                                            }
                                        }
                                    }
                                }
                                if isbn != nil { break }
                            }
                        }
                    }
                }
            }
            
            // Strategy 3: Fallback - Try all table rows
            if isbn == nil {
                let isbnRows = try? doc.select("tr")
                if let isbnRows = isbnRows {
                    for row in isbnRows {
                        if let th = try? row.select("th").first() {
                            let thText = try th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            if isbnLabels.contains(where: { thText.contains($0) }) {
                                if let td = try? row.select("td").first() {
                                    var extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                    extracted = extracted.replacingOccurrences(of: " ", with: "")
                                    
                                    // Validate: ISBN should be 10 or 13 digits (with optional hyphens)
                                    let cleaned = extracted.replacingOccurrences(of: "-", with: "")
                                    if cleaned.count == 10 || cleaned.count == 13 {
                                        isbn = extracted
                                        print("[DEBUG] AmazonProductScraper - ISBN extracted: \(isbn ?? "nil")")
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Fallback: Extract ISBN from keywords meta tag
            if isbn == nil {
                if let keywordsMeta = try? doc.select("meta[name=keywords]").first(),
                   let keywords = try? keywordsMeta.attr("content") {
                    let isbnKeywordPatterns = [
                        #"isbn-13[:\s]+([0-9\-X]{10,17})"#,
                        #"isbn-10[:\s]+([0-9\-X]{10,13})"#,
                        #"isbn[:\s]+([0-9\-X]{10,17})"#
                    ]
                    
                    for pattern in isbnKeywordPatterns {
                        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                           let match = regex.firstMatch(in: keywords, options: [], range: NSRange(location: 0, length: (keywords as NSString).length)),
                           match.range(at: 1).location != NSNotFound {
                            let extracted = (keywords as NSString).substring(with: match.range(at: 1))
                            let cleaned = extracted.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
                            if cleaned.count == 10 || cleaned.count == 13 {
                                isbn = extracted
                                break
                            }
                        }
                    }
                }
            }
            
            // Extract SKU/Model Number/Manufacturer Part Number
            var sku: String? = nil
            let skuLabels = ["Item model number", "Part Number", "Manufacturer Part Number", "MPN", "SKU", "Model", "Model Number", "Item Type Name"]
            
            // Strategy 1: Try prodDetTable (most reliable)
            if let prodDetTable = try? doc.select("table.prodDetTable").first() {
                let rows = try? prodDetTable.select("tr")
                if let rows = rows {
                    for row in rows {
                        if let th = try? row.select("th.prodDetSectionEntry").first(),
                           let thText = try? th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                           skuLabels.contains(where: { thText.contains($0) }),
                           let td = try? row.select("td.prodDetAttrValue").first() {
                            let extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            
                            // Validate: must be meaningful text, not generic values
                            let invalidValues = ["n/a", "na", "not applicable", "see description", "varies", "unknown"]
                            if !extracted.isEmpty && extracted.count > 1 && !invalidValues.contains(extracted.lowercased()) {
                                sku = extracted
                                print("[DEBUG] AmazonProductScraper - SKU extracted from prodDetTable: \(sku ?? "nil")")
                                break
                            }
                        }
                    }
                }
            }
            
            // Strategy 2: Try detail-bullet-list (unordered list structure)
            if sku == nil {
                if let bulletList = try? doc.select("ul.detail-bullet-list, ul.a-unordered-list.detail-bullet-list").first() {
                    let listItems = try? bulletList.select("li")
                    if let listItems = listItems {
                        for item in listItems {
                            if let listItemSpan = try? item.select("span.a-list-item").first(),
                               let labelSpan = try? listItemSpan.select("span.a-text-bold").first(),
                               let labelText = try? labelSpan.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                               skuLabels.contains(where: { labelText.contains($0) }) {
                                // Get all spans in the list item, find the one that's not bold
                                let allSpans = try? listItemSpan.select("span")
                                if let allSpans = allSpans {
                                    for span in allSpans {
                                        let spanClass = try? span.attr("class")
                                        if spanClass?.contains("a-text-bold") != true {
                                            let extracted = try span.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                            
                                            // Validate: must be meaningful text, not generic values
                                            let invalidValues = ["n/a", "na", "not applicable", "see description", "varies", "unknown"]
                                            if !extracted.isEmpty && extracted.count > 1 && !invalidValues.contains(extracted.lowercased()) {
                                                sku = extracted
                                                print("[DEBUG] AmazonProductScraper - SKU extracted from detail-bullet-list: \(sku ?? "nil")")
                                                break
                                            }
                                        }
                                    }
                                }
                                if sku != nil { break }
                            }
                        }
                    }
                }
            }
            
            // Strategy 3: Fallback - Try all table rows
            if sku == nil {
                let skuRows = try? doc.select("tr")
                if let skuRows = skuRows {
                    for row in skuRows {
                        if let th = try? row.select("th").first() {
                            let thText = try th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            if skuLabels.contains(where: { thText.contains($0) }) {
                                if let td = try? row.select("td").first() {
                                    let extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                    
                                    // Validate: must be meaningful text, not generic values
                                    let invalidValues = ["n/a", "na", "not applicable", "see description", "varies", "unknown"]
                                    if !extracted.isEmpty && extracted.count > 1 && !invalidValues.contains(extracted.lowercased()) {
                                        sku = extracted
                                        print("[DEBUG] AmazonProductScraper - SKU extracted: \(sku ?? "nil")")
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Extract Author from Product Details
            var author: String? = nil
            let invalidAuthorValues = ["follow", "see all", "see more", "view all", "more", "less", "show", "hide", 
                                     "illustrated", "annotated", "edition", "illustrated annotated edition",
                                     "paperback", "hardcover", "kindle", "ebook", "audiobook", "audio book"]
            
            // Strategy 1: Try prodDetTable (most reliable)
            if let prodDetTable = try? doc.select("table.prodDetTable").first() {
                let rows = try? prodDetTable.select("tr")
                if let rows = rows {
                    for row in rows {
                        if let th = try? row.select("th.prodDetSectionEntry").first(),
                           let thText = try? th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                           thText.contains("Author"),
                           let td = try? row.select("td.prodDetAttrValue").first() {
                            let extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            if !extracted.isEmpty && extracted.count > 2 && !invalidAuthorValues.contains(extracted.lowercased()) {
                                author = extracted
                                break
                            }
                        }
                    }
                }
            }
            
            // Strategy 2: Try detail-bullet-list (unordered list structure)
            if author == nil {
                if let bulletList = try? doc.select("ul.detail-bullet-list, ul.a-unordered-list.detail-bullet-list").first() {
                    let listItems = try? bulletList.select("li")
                    if let listItems = listItems {
                        for item in listItems {
                            if let listItemSpan = try? item.select("span.a-list-item").first(),
                               let labelSpan = try? listItemSpan.select("span.a-text-bold").first(),
                               let labelText = try? labelSpan.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                               labelText.contains("Author") {
                                // Get all spans in the list item, find the one that's not bold
                                let allSpans = try? listItemSpan.select("span")
                                if let allSpans = allSpans {
                                    for span in allSpans {
                                        let spanClass = try? span.attr("class")
                                        if spanClass?.contains("a-text-bold") != true {
                                            let extracted = try span.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                            if !extracted.isEmpty && extracted.count > 2 && !invalidAuthorValues.contains(extracted.lowercased()) {
                                                author = extracted
                                                break
                                            }
                                        }
                                    }
                                }
                                if author != nil { break }
                            }
                        }
                    }
                }
            }
            
            // Strategy 3: Fallback - Try all table rows
            if author == nil {
                let authorRows = try? doc.select("tr")
                if let authorRows = authorRows {
                    for row in authorRows {
                        if let th = try? row.select("th").first() {
                            let thText = try th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            if thText.contains("Author") {
                                if let td = try? row.select("td").first() {
                                    let extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                    if !extracted.isEmpty && extracted.count > 2 && !invalidAuthorValues.contains(extracted.lowercased()) {
                                        author = extracted
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Try author link in contributor section
            if author == nil {
                if let authorLink = try? doc.select("a.contributorNameID").first() {
                    let extracted = try authorLink.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extracted.isEmpty && extracted.count > 2 && !invalidAuthorValues.contains(extracted.lowercased()) {
                        author = extracted
                    }
                }
            }
            
            // Try meta tag
            if author == nil {
                if let authorMeta = try? doc.select("meta[name=author]").first(),
                   let extracted = try? authorMeta.attr("content"),
                   !extracted.isEmpty && extracted.count > 2 && !invalidAuthorValues.contains(extracted.lowercased()) {
                    author = extracted
                }
            }
            
            // Extract Artist from Product Details (for music/media)
            var artist: String? = nil
            let artistLabels = ["Artist", "Director"]
            
            let artistRows = try? doc.select("tr")
            if let artistRows = artistRows {
                for row in artistRows {
                    if let th = try? row.select("th").first() {
                        let thText = try th.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        if artistLabels.contains(where: { thText.contains($0) }) {
                            if let td = try? row.select("td").first() {
                                let extracted = try td.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                if !extracted.isEmpty && extracted.count > 1 {
                                    artist = extracted
                                    break
                                }
                            }
                        }
                    }
                }
            }
            
            print("[DEBUG] AmazonProductScraper - Metadata extracted - url: \(url.absoluteString), title: \(title ?? "nil"), brand: \(brand ?? "nil"), isbn: \(isbn ?? "nil"), sku: \(sku ?? "nil"), author: \(author ?? "nil"), artist: \(artist ?? "nil"), asin: \(asin ?? "nil"), imageUrl: \(imageUrl ?? "nil")")
            
            return AmazonProductMetadata(
                title: title,
                price: price,
                brand: brand,
                ratings: ratings,
                availability: availability,
                asin: asin,
                imageUrl: imageUrl,
                isbn: isbn,
                sku: sku,
                author: author,
                artist: artist
            )
        } catch {
            print("[AmazonProductScraper] Failed to parse HTML with SwiftSoup: \(error)")
            // Return empty metadata on parse failure
            return AmazonProductMetadata(
                title: nil,
                price: nil,
                brand: nil,
                ratings: nil,
                availability: nil,
                asin: nil,
                imageUrl: nil,
                isbn: nil,
                sku: nil,
                author: nil,
                artist: nil
            )
        }
    }
}

enum AmazonScrapingError: Error {
    case invalidResponse
    case networkError(Error)
    case timeout
}
