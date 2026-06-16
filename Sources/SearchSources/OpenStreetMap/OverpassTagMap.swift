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
        // Bike categories include `amenity=bicycle_repair_station` so a
        // query about bikes also surfaces repair options. The parser's
        // `categoryTag(for:)` will classify those station nodes into the
        // Repair intent tab automatically.
        "bike":         ["shop=bicycle", "amenity=bicycle_repair_station"],
        "bicycle":      ["shop=bicycle", "amenity=bicycle_repair_station"],
        "music":        ["shop=music", "shop=musical_instrument"],
        "clothing":     ["shop=clothes", "shop=second_hand"],
        "repair":       repairTags,
        "library":      ["amenity=library", "amenity=public_bookcase"],
        "tool_library": ["amenity=library", "amenity=tool_library", "amenity=public_bookcase"]
    ]

    /// Soft synonyms for categories the query enhancer might produce
    /// that don't have a direct entry in `categoryToTags`. Each value
    /// is the canonical key that the synonym should resolve to.
    /// Lookup is case-insensitive (callers normalize).
    public static let synonyms: [String: String] = [
        "cycling":  "bicycle",
        "cyclist":  "bicycle",
        "biking":   "bicycle",
        "ebike":    "bicycle",
        "e-bike":   "bicycle",
        // Borrow-intent synonyms resolve to the library tag set so a
        // "tool library" / "library of things" query actually fetches the
        // OSM nodes that `categoryTag` will then classify as "borrow".
        "tool library":     "tool_library",
        "library of things": "tool_library",
        "borrow":           "library"
    ]

    /// Tag specs that identify a "repair" intent — used both to drive
    /// Overpass queries when the user explicitly asks about repair, and to
    /// classify incoming results into the Repair intent tab (C1) regardless
    /// of how the query was constructed.
    public static let repairTags: [String] = [
        "shop=repair",
        "shop=mobile_phone_repair",
        "shop=computer_repair",
        "amenity=bicycle_repair_station",
        "amenity=repair_cafe"
    ]

    /// Tag specs that identify a "borrow" intent (borrow-instead-of-buy) —
    /// tool libraries, libraries of things, little free libraries, and
    /// public libraries. Used by `categoryTag(for:)` to route these OSM
    /// nodes into the Borrow intent tab. Mission-aligned: surfaces places
    /// where the user can borrow rather than purchase.
    public static let borrowTags: [String] = [
        "amenity=tool_library",
        "amenity=public_bookcase",
        "amenity=library",
        "library:type=tool_library",
        "library:type=lending",
        "library:type=things"
    ]

    /// Used when no category matches — any shop at all in range.
    public static let fallbackTags: [String] = ["shop=*"]

    /// Resolves a list of category strings to a deduplicated list of OSM tag
    /// specs. Returns `fallbackTags` if nothing matched.
    ///
    /// Lookup is tolerant of:
    ///   - case (`"Bicycles"` matches),
    ///   - trailing whitespace,
    ///   - simple pluralization — if `"bikes"` isn't a direct key, falls
    ///     back to looking up `"bike"`,
    ///   - synonyms (`"cycling"` → `"bicycle"` etc.).
    public static func tags(forCategories categories: [String]) -> [String] {
        var collected: [String] = []
        for cat in categories {
            if let mapped = resolve(cat) {
                collected.append(contentsOf: mapped)
            }
        }
        if collected.isEmpty {
            return fallbackTags
        }
        var seen = Set<String>()
        return collected.filter { seen.insert($0).inserted }
    }

    /// Resolves a single category string to its tag list, applying the
    /// case/plural/synonym tolerance. Returns `nil` if nothing matches —
    /// callers in `tags(forCategories:)` then either find another match
    /// or use `fallbackTags`.
    static func resolve(_ category: String) -> [String]? {
        let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if let direct = categoryToTags[normalized] {
            return direct
        }
        // Synonym table — must run before plural stripping so explicit
        // synonyms win over accidental plural matches.
        if let canonical = synonyms[normalized],
           let mapped = categoryToTags[canonical] {
            return mapped
        }
        // Simple plural fallback: `bikes` → `bike`, `bicycles` → `bicycle`.
        if normalized.hasSuffix("s"),
           let direct = categoryToTags[String(normalized.dropLast())] {
            return direct
        }
        return nil
    }

    /// Inspects an Overpass element's `tags` dictionary and returns a
    /// category tag (`"repair"` or `"borrow"`) when the tags match a known
    /// intent. Used by `OverpassSearchSource.parseResponse` to set
    /// `metadata["category_tag"]` so `SearchViewModel` can route results
    /// to the right intent tab (C1). Repair takes precedence over borrow
    /// when a node somehow matches both (e.g. a repair café inside a
    /// library), since "get it fixed" is the more specific intent.
    public static func categoryTag(for tags: [String: String]) -> String? {
        if matches(tags, anyOf: repairTags) { return "repair" }
        if matches(tags, anyOf: borrowTags) { return "borrow" }
        return nil
    }

    /// `true` if `tags` satisfies any spec in `specs`. A spec `"key=value"`
    /// matches when `tags[key] == value`; a spec `"key=*"` (or bare `"key"`)
    /// matches any value for that key.
    static func matches(_ tags: [String: String], anyOf specs: [String]) -> Bool {
        for spec in specs {
            let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first else { continue }
            let value: String? = parts.count == 2 && parts[1] != "*" ? parts[1] : nil
            if let actual = tags[key] {
                if let value {
                    if actual == value { return true }
                } else {
                    return true  // wildcard match — any value for this key
                }
            }
        }
        return false
    }
}
