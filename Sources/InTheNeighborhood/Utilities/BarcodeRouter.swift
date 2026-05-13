import Foundation

/// Translates a raw barcode payload (UPC, EAN-13, ISBN-10/13) into a
/// search-text string the existing search pipeline can use.
///
/// Pulled out of `SearchViewModel.handleScannedBarcode` so the routing
/// logic can be unit-tested without spinning up the full view model.
enum BarcodeRouter {
    /// Returns the search text that should be entered for a given scanned
    /// code. Books (ISBN-10 or ISBN-13 with 978/979 prefix) are prefixed
    /// with `isbn:` so book-aware sources can target them. Any other code
    /// is returned verbatim — the existing full-text search handles
    /// arbitrary UPCs/EANs as plain queries.
    static func route(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)

        if digits.count == 10 {
            return "isbn:\(digits)"
        }
        if digits.count == 13, digits.hasPrefix("978") || digits.hasPrefix("979") {
            return "isbn:\(digits)"
        }
        return trimmed
    }
}
