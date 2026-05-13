import Foundation

/// Maps query categories to OpenStreetMap tag selectors for Overpass queries.
/// Tag specs use the form `"key=value"` or `"key=*"` (any value). The Overpass
/// source converts these to Overpass QL filter syntax: `["key"="value"]` or
/// `["key"]`.
public enum OverpassTagMap {
    /// Category strings → OSM tag specs. Categories are lowercased before lookup.
    /// Each value is a list because some categories map to multiple shop tags
    /// (a hardware store may be tagged `shop=hardware` OR `shop=doityourself`).
    public static let categoryToTags: [String: [String]] = [
        "book":         ["shop=books"],
        "books":        ["shop=books"],
        "bookstore":    ["shop=books"],
        "hardware":     ["shop=hardware", "shop=doityourself"],
        "grocery":      ["shop=greengrocer", "shop=organic", "shop=farm"],
        "bike":         ["shop=bicycle"],
        "bicycle":      ["shop=bicycle"],
        "music":        ["shop=music", "shop=musical_instrument"],
        "clothing":     ["shop=clothes", "shop=second_hand"],
        "repair":       ["shop=repair"],
        "library":      ["amenity=library"],
        "tool_library": ["amenity=library"]
    ]

    /// Used when no category matches — any shop at all in range.
    public static let fallbackTags: [String] = ["shop=*"]

    /// Resolves a list of category strings to a deduplicated list of OSM tag
    /// specs. Returns `fallbackTags` if nothing matched.
    public static func tags(forCategories categories: [String]) -> [String] {
        var collected: [String] = []
        for cat in categories {
            if let mapped = categoryToTags[cat.lowercased()] {
                collected.append(contentsOf: mapped)
            }
        }
        if collected.isEmpty {
            return fallbackTags
        }
        var seen = Set<String>()
        return collected.filter { seen.insert($0).inserted }
    }
}
