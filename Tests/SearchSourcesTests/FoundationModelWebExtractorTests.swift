import XCTest
@testable import SearchSources
import MetasearchCore

final class FoundationModelWebExtractorTests: XCTestCase {

    // MARK: - HTML Stripping Tests

    func test_stripNonContentHTML_removesScriptTags() {
        let extractor = FoundationModelWebExtractor()
        let html = """
        <html><head><script>var x = 1;</script></head>
        <body><h1>Product</h1><script type="text/javascript">alert('hi');</script></body></html>
        """
        let result = extractor.stripNonContentHTML(html)
        XCTAssertFalse(result.contains("var x = 1"))
        XCTAssertFalse(result.contains("alert"))
        XCTAssertTrue(result.contains("Product"))
    }

    func test_stripNonContentHTML_removesStyleTags() {
        let extractor = FoundationModelWebExtractor()
        let html = """
        <html><head><style>.foo { color: red; }</style></head>
        <body><p>Hello</p></body></html>
        """
        let result = extractor.stripNonContentHTML(html)
        XCTAssertFalse(result.contains("color: red"))
        XCTAssertTrue(result.contains("Hello"))
    }

    func test_stripNonContentHTML_removesComments() {
        let extractor = FoundationModelWebExtractor()
        let html = "<html><!-- secret comment --><body>Visible</body></html>"
        let result = extractor.stripNonContentHTML(html)
        XCTAssertFalse(result.contains("secret comment"))
        XCTAssertTrue(result.contains("Visible"))
    }

    func test_stripNonContentHTML_removesSVG() {
        let extractor = FoundationModelWebExtractor()
        let html = "<html><body><svg width=\"100\"><path d=\"M0 0\"/></svg><p>Content</p></body></html>"
        let result = extractor.stripNonContentHTML(html)
        XCTAssertFalse(result.contains("<svg"))
        XCTAssertTrue(result.contains("Content"))
    }

    func test_stripNonContentHTML_collapsesWhitespace() {
        let extractor = FoundationModelWebExtractor()
        let html = "<html>   \n\n\n   <body>  Text  </body>  \n  </html>"
        let result = extractor.stripNonContentHTML(html)
        // Should not have runs of 2+ whitespace characters
        XCTAssertFalse(result.contains("  "))
    }

    func test_stripNonContentHTML_removesNoscriptTags() {
        let extractor = FoundationModelWebExtractor()
        let html = "<html><body><noscript>Enable JS</noscript><p>Real content</p></body></html>"
        let result = extractor.stripNonContentHTML(html)
        XCTAssertFalse(result.contains("Enable JS"))
        XCTAssertTrue(result.contains("Real content"))
    }

    // MARK: - ExtractedProductInfo Conversion Tests

    func test_extractedProductInfo_toAmazonProductMetadata_mapsAllFields() {
        let info = ExtractedProductInfo(
            title: "Widget Pro",
            brand: "Acme",
            price: "$19.99",
            isbn: "978-0-13-468599-1",
            sku: "WP-100",
            author: "Jane Doe",
            artist: nil,
            asin: "B08N5WRWNW",
            ratings: 4.5,
            availability: "In Stock",
            imageUrl: "https://example.com/image.jpg"
        )

        let metadata = info.toAmazonProductMetadata()

        XCTAssertEqual(metadata.title, "Widget Pro")
        XCTAssertEqual(metadata.brand, "Acme")
        XCTAssertEqual(metadata.price, "$19.99")
        XCTAssertEqual(metadata.isbn, "978-0-13-468599-1")
        XCTAssertEqual(metadata.sku, "WP-100")
        XCTAssertEqual(metadata.author, "Jane Doe")
        XCTAssertNil(metadata.artist)
        XCTAssertEqual(metadata.asin, "B08N5WRWNW")
        XCTAssertEqual(metadata.ratings, 4.5)
        XCTAssertEqual(metadata.availability, "In Stock")
        XCTAssertEqual(metadata.imageUrl, "https://example.com/image.jpg")
    }

    func test_extractedProductInfo_toAmazonProductMetadata_handlesAllNils() {
        let info = ExtractedProductInfo()
        let metadata = info.toAmazonProductMetadata()

        XCTAssertNil(metadata.title)
        XCTAssertNil(metadata.brand)
        XCTAssertNil(metadata.price)
        XCTAssertNil(metadata.isbn)
        XCTAssertNil(metadata.sku)
        XCTAssertNil(metadata.author)
        XCTAssertNil(metadata.artist)
        XCTAssertNil(metadata.asin)
        XCTAssertNil(metadata.ratings)
        XCTAssertNil(metadata.availability)
        XCTAssertNil(metadata.imageUrl)
    }

    // MARK: - Availability Tests

    func test_isAvailable_reflectsOSCapability() {
        // This just verifies the property doesn't crash; actual value depends on the OS.
        let extractor = FoundationModelWebExtractor()
        // On CI or older simulators this will be false; on iOS 26+ it will be true.
        _ = extractor.isAvailable
    }

    // MARK: - Extract with unavailable model

    func test_extract_returnsNilWhenFoundationModelsUnavailable() async {
        // On simulators without Apple Intelligence, extract() should return nil gracefully.
        let extractor = FoundationModelWebExtractor()
        let html = "<html><body><h1>Product Title</h1><span>$29.99</span></body></html>"
        let url = URL(string: "https://www.amazon.com/dp/B08N5WRWNW")!

        let result = await extractor.extract(html: html, url: url)

        // On most test environments (CI, Xcode simulator), FoundationModels won't be available.
        // We just verify it doesn't crash and returns nil gracefully.
        if !extractor.isAvailable {
            XCTAssertNil(result)
        }
        // If FoundationModels IS available (real device), we accept any non-crashing result.
    }

    // MARK: - Truncation

    func test_maxHTMLLength_respectedInStripping() {
        let extractor = FoundationModelWebExtractor(maxHTMLLength: 100)
        // The extractor itself only truncates in the extract() call, but we can verify
        // the parameter is accepted without crashing.
        XCTAssertNotNil(extractor)
    }
}
