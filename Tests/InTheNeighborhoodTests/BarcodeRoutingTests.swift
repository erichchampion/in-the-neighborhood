import XCTest
@testable import InTheNeighborhood

final class BarcodeRoutingTests: XCTestCase {

    // MARK: - ISBN classification

    func test_isbn13_with978Prefix_isRoutedToISBN() {
        // The ISBN-13 for "On Tyranny" by Timothy Snyder.
        XCTAssertEqual(BarcodeRouter.route("9780804190114"), "isbn:9780804190114")
    }

    func test_isbn13_with979Prefix_isRoutedToISBN() {
        // ISBN-13 with 979 prefix (newer Bookland range).
        XCTAssertEqual(BarcodeRouter.route("9791234567890"), "isbn:9791234567890")
    }

    func test_isbn10_isRoutedToISBN() {
        // Legacy ISBN-10.
        XCTAssertEqual(BarcodeRouter.route("0804190119"), "isbn:0804190119")
    }

    // MARK: - Non-book barcodes pass through

    func test_ean13_withoutBookPrefix_isPassthrough() {
        // An arbitrary EAN-13 (not 978/979) is a regular product code.
        XCTAssertEqual(BarcodeRouter.route("4006381333931"), "4006381333931")
    }

    func test_upcA_12Digits_isPassthrough() {
        // UPC-A (12 digits) — typical grocery item.
        XCTAssertEqual(BarcodeRouter.route("012345678905"), "012345678905")
    }

    func test_arbitraryString_isPassthrough() {
        // QR codes can hold arbitrary URLs or text.
        XCTAssertEqual(BarcodeRouter.route("https://example.com/item/42"),
                       "https://example.com/item/42")
    }

    // MARK: - Whitespace handling

    func test_whitespaceIsTrimmed() {
        XCTAssertEqual(BarcodeRouter.route("  9780804190114  "), "isbn:9780804190114")
        XCTAssertEqual(BarcodeRouter.route("\n  abc\t"), "abc")
    }

    // MARK: - Edge cases

    func test_emptyStringIsPassthrough() {
        XCTAssertEqual(BarcodeRouter.route(""), "")
        XCTAssertEqual(BarcodeRouter.route("   "), "")
    }

    func test_isbnWithHyphens_isRoutedToISBN_usingDigitsOnly() {
        // Some barcodes/printed ISBNs include hyphens; the digit count after
        // stripping non-digits is what determines ISBN classification.
        XCTAssertEqual(BarcodeRouter.route("978-0-8041-9011-4"), "isbn:9780804190114")
    }
}
