import XCTest
@testable import InTheNeighborhood
@testable import MetasearchCore

/// We don't render the SwiftUI view here — instead we assert against
/// `displayedItems`, which is the deterministic projection of an
/// `EthicsEntry` into the pills the body would draw.
final class EthicsBadgeViewTests: XCTestCase {

    // MARK: - Ownership badge mapping

    func test_indieOwnership_producesIndieBadge() {
        let entry = EthicsEntry(ownership: .indie)
        let items = EthicsBadgeView(entry: entry).displayedItems
        XCTAssertEqual(items.map(\.label), ["Indie"])
        XCTAssertEqual(items.first?.systemImage, "house")
        XCTAssertEqual(items.first?.tint, .positive)
    }

    func test_employeeOwnedOwnership_producesEmployeeOwnedBadge() {
        let items = EthicsBadgeView(entry: EthicsEntry(ownership: .employeeOwned)).displayedItems
        XCTAssertEqual(items.map(\.label), ["Employee-owned"])
        XCTAssertEqual(items.first?.systemImage, "person.3")
    }

    func test_coopOwnership_producesCoopBadge() {
        let items = EthicsBadgeView(entry: EthicsEntry(ownership: .coop)).displayedItems
        XCTAssertEqual(items.map(\.label), ["Co-op"])
    }

    func test_bCorpOwnership_producesBCorpBadge() {
        let items = EthicsBadgeView(entry: EthicsEntry(ownership: .bCorp)).displayedItems
        XCTAssertEqual(items.map(\.label), ["B-Corp"])
        XCTAssertEqual(items.first?.systemImage, "leaf")
    }

    func test_megaOwnership_producesWarningBadge() {
        let items = EthicsBadgeView(entry: EthicsEntry(ownership: .mega)).displayedItems
        XCTAssertEqual(items.map(\.label), ["Mega-owned"])
        XCTAssertEqual(items.first?.tint, .warning)
    }

    func test_unknownOwnership_producesEmptyItems() {
        let items = EthicsBadgeView(entry: EthicsEntry(ownership: .unknown)).displayedItems
        XCTAssertTrue(items.isEmpty, "Unknown ownership should render no pills")
    }

    // MARK: - Certification badges

    func test_certifications_addPills_capsAtTwo() {
        let entry = EthicsEntry(
            ownership: .indie,
            certifications: ["b-corp", "fair-trade", "1-percent-for-the-planet"]
        )
        let items = EthicsBadgeView(entry: entry).displayedItems
        // 1 ownership + 2 certifications = 3 pills max.
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.label), ["Indie", "B-Corp", "Fair Trade"])
    }

    func test_certifications_dedupedAgainstOwnership() {
        // employeeOwned ownership has label "Employee-owned"; the "esop" cert
        // also maps to "Employee-owned". The dup must be filtered out.
        let entry = EthicsEntry(
            ownership: .employeeOwned,
            certifications: ["esop", "b-corp"]
        )
        let items = EthicsBadgeView(entry: entry).displayedItems
        XCTAssertEqual(items.map(\.label), ["Employee-owned", "B-Corp"])
    }

    func test_unrecognizedCertificationsAreSkipped() {
        let entry = EthicsEntry(
            ownership: .indie,
            certifications: ["completely-made-up-cert", "b-corp"]
        )
        let items = EthicsBadgeView(entry: entry).displayedItems
        XCTAssertEqual(items.map(\.label), ["Indie", "B-Corp"])
    }

    func test_unionCertification() {
        let entry = EthicsEntry(ownership: .indie, certifications: ["unionized"])
        let items = EthicsBadgeView(entry: entry).displayedItems
        XCTAssertEqual(items.map(\.label), ["Indie", "Union"])
    }

    func test_unknownOwnershipWithCertifications_stillRendersCertPills() {
        // Even when ownership is unknown, recognized certs should surface.
        // (For example: a B-Corp not yet classified by ownership.)
        let entry = EthicsEntry(
            ownership: .unknown,
            certifications: ["b-corp", "fair-trade"]
        )
        let items = EthicsBadgeView(entry: entry).displayedItems
        XCTAssertEqual(items.map(\.label), ["B-Corp", "Fair Trade"])
    }
}
