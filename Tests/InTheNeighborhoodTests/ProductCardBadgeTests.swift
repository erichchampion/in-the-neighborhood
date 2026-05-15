import XCTest
@testable import InTheNeighborhood
@testable import MetasearchCore

/// Pins the Nutri-Score / Eco-Score / Nova badge derivation. The helpers
/// are pure projections of `result.metadata`, marked `nonisolated` so
/// XCTest methods (off the main actor) can call them directly without a
/// SwiftUI rendering harness.
final class ProductCardBadgeTests: XCTestCase {

    private func mkProduct(metadata: [String: AnyHashable]) -> SearchResult {
        SearchResult(
            id: "p",
            title: "Test Product",
            description: nil,
            source: SourceIdentifier.openfoodfacts,
            sourceType: .online,
            category: .product,
            url: nil,
            location: nil,
            distance: nil,
            relevanceScore: nil,
            price: nil,
            metadata: metadata
        )
    }

    // MARK: - Nutri-Score

    func test_nutriScoreA_isGreen() {
        let r = mkProduct(metadata: ["nutriscore_grade": "A"])
        let badges = ProductCard.healthBadges(for: r)
        XCTAssertEqual(badges.first?.text, "Nutri-Score A")
        XCTAssertEqual(badges.first?.systemImage, "leaf")
        XCTAssertEqual(badges.first?.tint, .green)
    }

    func test_nutriScoreE_isRed() {
        let r = mkProduct(metadata: ["nutriscore_grade": "E"])
        let badges = ProductCard.healthBadges(for: r)
        XCTAssertEqual(badges.first?.text, "Nutri-Score E")
        XCTAssertEqual(badges.first?.tint, .red)
    }

    func test_nutriScoreLowercase_isAccepted() {
        // Source normalizes to uppercase before storing; helper should
        // still handle a stray lowercase entry defensively.
        let r = mkProduct(metadata: ["nutriscore_grade": "c"])
        let badges = ProductCard.healthBadges(for: r)
        XCTAssertEqual(badges.first?.text, "Nutri-Score C")
        XCTAssertEqual(badges.first?.tint, .yellow)
    }

    func test_nutriScoreUnknownGrade_isSkipped() {
        let r = mkProduct(metadata: ["nutriscore_grade": "unknown"])
        XCTAssertTrue(ProductCard.healthBadges(for: r).isEmpty)
    }

    // MARK: - Eco-Score

    func test_ecoScoreA_isGreenLeafGlobe() {
        let r = mkProduct(metadata: ["ecoscore_grade": "A"])
        let badges = ProductCard.healthBadges(for: r)
        XCTAssertEqual(badges.first?.text, "Eco-Score A")
        XCTAssertEqual(badges.first?.systemImage, "globe.americas")
        XCTAssertEqual(badges.first?.tint, .green)
    }

    // MARK: - Nova

    func test_novaGroup4_emitsUltraProcessedWarning() {
        let r = mkProduct(metadata: ["nova_group": 4])
        let badges = ProductCard.healthBadges(for: r)
        XCTAssertEqual(badges.first?.text, "Ultra-processed")
        XCTAssertEqual(badges.first?.tint, .warning)
        XCTAssertEqual(badges.first?.systemImage, "exclamationmark.triangle")
    }

    func test_novaGroup3_emitsProcessedWarning() {
        let r = mkProduct(metadata: ["nova_group": 3])
        let badges = ProductCard.healthBadges(for: r)
        XCTAssertEqual(badges.first?.text, "Processed")
        XCTAssertEqual(badges.first?.tint, .warning)
    }

    func test_novaGroup1And2_areNotSurfaced() {
        // Unprocessed (1) and minimally processed (2) get no warning —
        // we only flag concerning processing levels.
        XCTAssertTrue(ProductCard.healthBadges(for: mkProduct(metadata: ["nova_group": 1])).isEmpty)
        XCTAssertTrue(ProductCard.healthBadges(for: mkProduct(metadata: ["nova_group": 2])).isEmpty)
    }

    // MARK: - Combinations

    func test_allThreePresent_returnsThreeBadgesInOrder() {
        let r = mkProduct(metadata: [
            "nutriscore_grade": "C",
            "ecoscore_grade": "A",
            "nova_group": 4
        ])
        let badges = ProductCard.healthBadges(for: r)
        XCTAssertEqual(badges.count, 3)
        XCTAssertEqual(badges[0].text, "Nutri-Score C")
        XCTAssertEqual(badges[1].text, "Eco-Score A")
        XCTAssertEqual(badges[2].text, "Ultra-processed")
    }

    func test_noOpenFactsMetadata_returnsEmpty() {
        // A regular Amazon/BestBuy result with no Open Facts fields
        // produces no badges — the row simply doesn't render.
        let r = mkProduct(metadata: [
            "brand": "Some Brand",
            "sku": "1234"
        ])
        XCTAssertTrue(ProductCard.healthBadges(for: r).isEmpty)
    }
}
