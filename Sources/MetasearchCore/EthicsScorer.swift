import Foundation

/// Looks up ethics-ledger entries by hostname and converts them into a
/// numeric score used for within-tier ranking. The ledger is hostname-keyed
/// because the search pipeline only sees URLs; local results without URLs
/// (e.g. MapKit places) have no entry and fall through with `.unknown`.
public struct EthicsScorer: Sendable {
    private let ledger: EthicsLedger

    public init(ledger: EthicsLedger = .loadBundled()) {
        self.ledger = ledger
    }

    /// Returns the ledger entry for the given host, or `nil` if neither the
    /// full host nor its base domain are in the ledger. Tries an exact match
    /// first, then a base-domain fallback so subdomains and per-region TLDs
    /// (`www.amazon.ca`, `m.amazon.com`) resolve to the same entry.
    public func entry(forHost host: String) -> EthicsEntry? {
        let lowered = host.lowercased()
        if let entry = ledger.entries[lowered] { return entry }
        let base = DenyListFilter.extractBaseDomain(from: lowered)
        if !base.isEmpty {
            // Try matching base-only ("amazon" → "amazon.com" preferred, then
            // any other registered amazon.* variant).
            for (key, entry) in ledger.entries
            where DenyListFilter.extractBaseDomain(from: key) == base {
                return entry
            }
        }
        return nil
    }

    /// `true` if the host is classified as a mega-retailer and should be
    /// dropped from results entirely.
    public func isBlocked(host: String) -> Bool {
        entry(forHost: host)?.ownership == .mega
    }

    /// Within-tier ranking score. Higher is better. Used by ResultPrioritizer
    /// to break ties between two results in the same source-type tier with
    /// the same relevance score.
    public func score(forHost host: String) -> Int {
        switch entry(forHost: host)?.ownership {
        case .coop, .bCorp, .employeeOwned: return 3
        case .indie:                         return 2
        case .unknown, .none:                return 1
        case .mega:                          return 0
        }
    }
}
