import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Extracts structured product metadata from raw HTML using the on-device FoundationModel.
///
/// Internal to `SearchSources`; only `AmazonSearchSource` uses this directly.
/// When FoundationModels is unavailable the caller falls back to `AmazonProductScraper`.
final class FoundationModelWebExtractor: @unchecked Sendable {

    /// Maximum characters of cleaned HTML passed to the model.
    let maxHTMLLength: Int

    init(maxHTMLLength: Int = 6000) {
        self.maxHTMLLength = maxHTMLLength
    }

    // MARK: - API

    /// Whether FoundationModels is available on this OS.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Tries to extract product metadata using the on-device FoundationModel.
    /// Returns `nil` when FoundationModels is unavailable or extraction fails.
    func extract(html: String, url: URL) async -> AmazonProductMetadata? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await extractWithFoundationModels(html: html, url: url)
        }
        #endif
        print("[FoundationModelWebExtractor] FoundationModels not available on this OS version.")
        return nil
    }

    // MARK: - FoundationModels Extraction

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func extractWithFoundationModels(html: String, url: URL) async -> AmazonProductMetadata? {
        do {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                print("[FoundationModelWebExtractor] SystemLanguageModel not available (downloading or disabled).")
                return nil
            }

            let cleanedHTML = stripNonContentHTML(html)
            let truncated = String(cleanedHTML.prefix(maxHTMLLength))

            let prompt = """
            Extract product information from this product page HTML. \
            Return only the fields you can confidently identify. \
            The page URL is: \(url.absoluteString)

            HTML content:
            \(truncated)
            """

            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt, generating: ExtractedProductInfo.self)
            let info = response.content

            print("[FoundationModelWebExtractor] Extracted: title=\(info.title ?? "nil"), brand=\(info.brand ?? "nil"), price=\(info.price ?? "nil"), isbn=\(info.isbn ?? "nil")")

            return info.toAmazonProductMetadata()
        } catch {
            print("[FoundationModelWebExtractor] Extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    // MARK: - HTML Cleaning

    /// Strips `<script>`, `<style>`, `<noscript>`, `<svg>`, and HTML comments
    /// then collapses whitespace so fewer tokens are wasted on non-content.
    func stripNonContentHTML(_ html: String) -> String {
        var result = html

        let patterns: [String] = [
            #"<script[^>]*>[\s\S]*?</script>"#,
            #"<style[^>]*>[\s\S]*?</style>"#,
            #"<noscript[^>]*>[\s\S]*?</noscript>"#,
            #"<svg[^>]*>[\s\S]*?</svg>"#,
            #"<!--[\s\S]*?-->"#
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Collapse runs of whitespace
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
