import XCTest
@testable import MetasearchCore

final class EthicsScorerTests: XCTestCase {
    private func makeScorer() -> EthicsScorer {
        let ledger = EthicsLedger(version: "test", entries: [
            "amazon.com":           EthicsEntry(ownership: .mega, region: "global"),
            "bookshop.org":         EthicsEntry(ownership: .bCorp, region: "national", certifications: ["b-corp"]),
            "powells.com":          EthicsEntry(ownership: .indie, region: "regional"),
            "rei.com":              EthicsEntry(ownership: .coop, region: "national", certifications: ["coop"]),
            "kingarthurbaking.com": EthicsEntry(ownership: .employeeOwned, region: "national", certifications: ["esop", "b-corp"])
        ])
        return EthicsScorer(ledger: ledger)
    }

    // MARK: - entry(forHost:)

    func test_entry_exactMatch() {
        let scorer = makeScorer()
        XCTAssertEqual(scorer.entry(forHost: "amazon.com")?.ownership, .mega)
        XCTAssertEqual(scorer.entry(forHost: "bookshop.org")?.ownership, .bCorp)
    }

    func test_entry_isCaseInsensitive() {
        let scorer = makeScorer()
        XCTAssertEqual(scorer.entry(forHost: "AMAZON.COM")?.ownership, .mega)
        XCTAssertEqual(scorer.entry(forHost: "Bookshop.ORG")?.ownership, .bCorp)
    }

    func test_entry_matchesSubdomainViaBaseDomain() {
        let scorer = makeScorer()
        // The ledger keys by `amazon.com`. A request for `www.amazon.com` or
        // `m.amazon.com` should still resolve via base-domain fallback.
        XCTAssertEqual(scorer.entry(forHost: "www.amazon.com")?.ownership, .mega)
        XCTAssertEqual(scorer.entry(forHost: "m.amazon.com")?.ownership, .mega)
    }

    func test_entry_unknownHostReturnsNil() {
        let scorer = makeScorer()
        XCTAssertNil(scorer.entry(forHost: "example.com"))
        XCTAssertNil(scorer.entry(forHost: ""))
    }

    // MARK: - isBlocked(host:)

    func test_isBlocked_trueForMega() {
        let scorer = makeScorer()
        XCTAssertTrue(scorer.isBlocked(host: "amazon.com"))
        XCTAssertTrue(scorer.isBlocked(host: "www.amazon.com"))
    }

    func test_isBlocked_falseForNonMega() {
        let scorer = makeScorer()
        XCTAssertFalse(scorer.isBlocked(host: "bookshop.org"))
        XCTAssertFalse(scorer.isBlocked(host: "powells.com"))
        XCTAssertFalse(scorer.isBlocked(host: "rei.com"))
        XCTAssertFalse(scorer.isBlocked(host: "kingarthurbaking.com"))
    }

    func test_isBlocked_falseForUnknown() {
        let scorer = makeScorer()
        XCTAssertFalse(scorer.isBlocked(host: "example.com"))
    }

    // MARK: - score(forHost:) monotonicity

    func test_score_orderingMatchesEthicsHierarchy() {
        let scorer = makeScorer()
        let mega = scorer.score(forHost: "amazon.com")
        let unknown = scorer.score(forHost: "example.com")
        let indie = scorer.score(forHost: "powells.com")
        let bCorp = scorer.score(forHost: "bookshop.org")
        let coop = scorer.score(forHost: "rei.com")
        let employeeOwned = scorer.score(forHost: "kingarthurbaking.com")

        XCTAssertLessThan(mega, unknown,    "mega should rank below unknown")
        XCTAssertLessThan(unknown, indie,   "unknown should rank below indie")
        XCTAssertLessThan(indie, bCorp,     "indie should rank below b-corp")
        XCTAssertEqual(coop, bCorp,         "co-op and b-corp should be peers at the top")
        XCTAssertEqual(employeeOwned, bCorp,"employee-owned and b-corp should be peers at the top")
    }

    // MARK: - empty ledger graceful behavior

    func test_emptyLedger_unknownEverywhere() {
        let scorer = EthicsScorer(ledger: EthicsLedger(version: "empty", entries: [:]))
        XCTAssertNil(scorer.entry(forHost: "amazon.com"))
        XCTAssertFalse(scorer.isBlocked(host: "amazon.com"))
        XCTAssertEqual(scorer.score(forHost: "amazon.com"), 1, "Empty ledger → all hosts unknown → score 1")
    }
}
