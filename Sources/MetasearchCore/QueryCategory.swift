import Foundation

/// High-level product categorization of a user query. Used by
/// `MetasearchCoordinator` to filter which sources to invoke for a given
/// search — e.g. a `.book` query should not hit `OpenFoodFacts`, an
/// `.electronics` query should not hit `OpenLibrary`.
///
/// Populated by `QueryClassifier`. Optional everywhere — `nil` means
/// "no confident classification, run every source" (today's default
/// behavior, safe under uncertainty).
public enum QueryCategory: String, Hashable, Sendable, CaseIterable {
    case book
    case grocery
    case hardware
    case electronics
    case clothing
    case media
    case personalCare
    case petFood
}
