import Foundation
@preconcurrency import CoreLocation

/// Collapses local results that describe the same physical business across
/// different sources (e.g. MapKit + Overpass both returning the same shop).
///
/// Two results merge when they share a normalized title (one contains the
/// other as a substring after lowercase/punctuation/suffix stripping) AND
/// they are within `proximityMeters` of each other. Proximity alone false-
/// positives in dense retail; title alone false-positives across chain
/// locations — both signals are required.
///
/// The primary record is chosen by source priority (MapKit > Overpass >
/// Nominatim > others), with longest description as tie-breaker. Discarded
/// records' metadata is merged into the primary with the primary winning
/// on key conflicts, so Overpass-only signals like `category_tag` are
/// preserved on the MapKit primary.
public enum NearDuplicateMerger {
    public static let proximityMeters: CLLocationDistance = 75

    public static func merge(_ results: [SearchResult]) -> [SearchResult] {
        guard !results.isEmpty else { return [] }

        var locals: [(index: Int, result: SearchResult)] = []
        var nonLocalsByIndex: [Int: SearchResult] = [:]
        for (index, result) in results.enumerated() {
            if result.sourceType == .local, result.location != nil {
                locals.append((index, result))
            } else {
                nonLocalsByIndex[index] = result
            }
        }

        var groupOf: [Int: Int] = [:] // local-array-index -> group leader local-array-index
        for i in 0..<locals.count {
            if groupOf[i] != nil { continue }
            groupOf[i] = i
            for j in (i + 1)..<locals.count {
                if groupOf[j] != nil { continue }
                if isSameBusiness(locals[i].result, locals[j].result) {
                    groupOf[j] = i
                }
            }
        }

        var groupMembers: [Int: [Int]] = [:]
        for (member, leader) in groupOf {
            groupMembers[leader, default: []].append(member)
        }

        var mergedByOriginalIndex: [Int: SearchResult] = nonLocalsByIndex
        for (_, members) in groupMembers {
            let memberResults = members.map { locals[$0].result }
            let primary = pickPrimary(memberResults)
            let merged = mergeMetadata(primary: primary, others: memberResults.filter { $0.id != primary.id })
            let originalIndex = locals[members.first { locals[$0].result.id == primary.id } ?? members[0]].index
            mergedByOriginalIndex[originalIndex] = merged
        }

        return mergedByOriginalIndex
            .sorted { $0.key < $1.key }
            .map { $0.value }
    }

    // MARK: - Predicates

    static func isSameBusiness(_ a: SearchResult, _ b: SearchResult) -> Bool {
        guard let locA = a.location, let locB = b.location else { return false }
        guard locA.distance(from: locB) <= proximityMeters else { return false }
        return titlesMatch(a.title, b.title)
    }

    /// Returns true when every token of the shorter normalized title set
    /// appears in the longer one. Both contiguous-substring matching
    /// ("Joe's Bike Shop" vs "Joe's Bikes" — different final token) and
    /// raw set equality fall apart on storefront naming variations; this
    /// rule lets a strict subset name match a longer variant while still
    /// rejecting same-length names that differ on a distinguishing token
    /// (e.g. "Trek Bicycle Bellevue" vs "Trek Bicycle Seattle").
    static func titlesMatch(_ a: String, _ b: String) -> Bool {
        let ta = normalizedTokens(a)
        let tb = normalizedTokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        let (shorter, longer) = ta.count <= tb.count ? (ta, tb) : (tb, ta)
        let longerSet = Set(longer)
        return shorter.allSatisfy { longerSet.contains($0) }
    }

    static func normalizedTitle(_ title: String) -> String {
        return normalizedTokens(title).joined(separator: " ")
    }

    /// Lowercased token list with punctuation dropped (not substituted —
    /// "Joe's" becomes "joes", not "joe s"), short suffix words removed,
    /// and a tiny stem applied (trailing "s" stripped on tokens longer
    /// than 3 chars so "bikes" matches "bike" but "us" stays "us").
    static func normalizedTokens(_ title: String) -> [String] {
        let lowered = title.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789 ")
        let stripped = String(lowered.filter { allowed.contains($0) })
        let raw = stripped.split(whereSeparator: { $0 == " " }).map(String.init)
        let suffixes: Set<String> = ["the", "inc", "llc", "ltd", "co", "company", "corp"]
        return raw
            .filter { !$0.isEmpty && !suffixes.contains($0) }
            .map(stem(_:))
    }

    private static func stem(_ token: String) -> String {
        if token.count > 3, token.hasSuffix("s") {
            return String(token.dropLast())
        }
        return token
    }

    static func sourcePriority(_ source: String) -> Int {
        switch source {
        case SourceIdentifier.mapkit:   return 0
        case SourceIdentifier.overpass: return 1
        case "nominatim":               return 2
        default:                        return 3
        }
    }

    // MARK: - Merge

    private static func pickPrimary(_ results: [SearchResult]) -> SearchResult {
        return results.min { lhs, rhs in
            let lp = sourcePriority(lhs.source)
            let rp = sourcePriority(rhs.source)
            if lp != rp { return lp < rp }
            return (lhs.description?.count ?? 0) > (rhs.description?.count ?? 0)
        } ?? results[0]
    }

    private static func mergeMetadata(primary: SearchResult, others: [SearchResult]) -> SearchResult {
        guard !others.isEmpty else { return primary }
        var carried: [String: AnyHashable] = [:]
        for other in others {
            for (key, value) in other.metadata where carried[key] == nil {
                carried[key] = value
            }
        }
        for key in primary.metadata.keys { carried.removeValue(forKey: key) }
        let allSources = ([primary] + others).map { $0.source }
        let uniqueSources = Array(NSOrderedSet(array: allSources)) as? [String] ?? allSources
        carried["merged_sources"] = uniqueSources
        return primary.withMetadata(carried)
    }
}
