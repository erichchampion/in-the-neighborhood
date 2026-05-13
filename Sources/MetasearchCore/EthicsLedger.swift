import Foundation

/// One curated entry in the ethics ledger: who owns this hostname and what
/// certifications/region apply. Used both for filtering (mega-retailers get
/// blocked) and for ranking (B-Corp / co-op / employee-owned outrank
/// uncategorized peers in the same source-type tier).
public struct EthicsEntry: Codable, Hashable, Sendable {
    public enum Ownership: String, Codable, Hashable, Sendable {
        case indie
        case employeeOwned = "employee-owned"
        case coop
        case bCorp = "b-corp"
        case mega
        case unknown
    }

    public let ownership: Ownership
    /// Optional region tag — "local", "regional", "national", "global".
    public let region: String?
    /// Free-form certifications: "b-corp", "fair-trade", "union", etc.
    public let certifications: [String]
    /// Optional human-readable note for surfacing in a "why this result?" UI.
    public let notes: String?

    public init(
        ownership: Ownership,
        region: String? = nil,
        certifications: [String] = [],
        notes: String? = nil
    ) {
        self.ownership = ownership
        self.region = region
        self.certifications = certifications
        self.notes = notes
    }
}

/// The full hostname-keyed ledger, loaded from a bundled JSON file at app
/// startup. Hostnames in the JSON are normalized to the same shape as
/// `URL.host?.lowercased()` — bare domains like `"amazon.com"` (no leading
/// `www.`).
public struct EthicsLedger: Codable, Sendable {
    public let version: String
    public let entries: [String: EthicsEntry]

    public init(version: String, entries: [String: EthicsEntry]) {
        self.version = version
        self.entries = entries
    }

    /// Loads the ledger from the given bundle. Returns an empty ledger if the
    /// resource is missing or the JSON is malformed — the search pipeline
    /// degrades gracefully (no ethics signal, but search still works).
    public static func loadBundled(bundle: Bundle = .main) -> EthicsLedger {
        guard let url = bundle.url(forResource: "EthicsLedger", withExtension: "json") else {
            return EthicsLedger(version: "missing", entries: [:])
        }
        guard let data = try? Data(contentsOf: url),
              let ledger = try? JSONDecoder().decode(EthicsLedger.self, from: data) else {
            return EthicsLedger(version: "malformed", entries: [:])
        }
        return ledger
    }
}
