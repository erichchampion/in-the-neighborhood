import SwiftUI
import MetasearchCore

/// Renders an `EthicsEntry` as a horizontal row of pill-shaped badges:
/// an ownership badge (omitted for `.unknown`) plus up to two
/// certification pills, deduped against the ownership label so we don't
/// show "Employee-owned" next to an "ESOP" pill.
///
/// The shape of the rendered content is exposed via `displayedItems` so
/// tests can assert which pills appear for a given entry without needing
/// a SwiftUI rendering harness.
struct EthicsBadgeView: View {
    let entry: EthicsEntry

    /// A single pill to display. Hashable so tests can compare arrays of
    /// items by value.
    struct BadgeItem: Hashable {
        enum Tint: Hashable { case positive, warning, neutral }
        let label: String
        let systemImage: String
        let tint: Tint
    }

    /// The pills that the body will render. Empty when the entry has no
    /// recognizable signal (unknown ownership, no recognized certs).
    ///
    /// `nonisolated` because the computation is a pure function of `entry`
    /// and the static lookup tables — it never touches main-actor state.
    /// Marking it explicitly nonisolated lets tests call it from XCTest
    /// methods (which run off the main actor by default).
    nonisolated var displayedItems: [BadgeItem] {
        var items: [BadgeItem] = []
        if let primary = Self.ownershipBadge(entry.ownership) {
            items.append(primary)
        }
        let ownershipLabel = items.first?.label.lowercased()
        for cert in entry.certifications {
            guard let badge = Self.certificationBadge(cert) else { continue }
            if badge.label.lowercased() == ownershipLabel { continue }
            items.append(badge)
            if items.count >= 3 { break } // ownership + at most 2 certs
        }
        return items
    }

    var body: some View {
        let items = displayedItems
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    pill(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func pill(for item: BadgeItem) -> some View {
        let palette = colors(for: item.tint)
        Label {
            Text(item.label)
        } icon: {
            Image(systemName: item.systemImage)
        }
        .font(.caption2)
        .foregroundColor(palette.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(palette.background)
        .clipShape(Capsule())
        .accessibilityLabel(item.label)
    }

    private func colors(for tint: BadgeItem.Tint) -> (foreground: Color, background: Color) {
        switch tint {
        case .positive: return (.green, Color.green.opacity(0.15))
        case .warning:  return (.orange, Color.orange.opacity(0.15))
        case .neutral:  return (.secondary, Color(.systemGray6))
        }
    }

    // MARK: - Lookup tables (static so they're also accessible in tests).
    // `nonisolated` because the lookup is a pure function of its argument;
    // marking it explicit lets `displayedItems` (also nonisolated) call them
    // without crossing the main-actor boundary that `View` would otherwise
    // impose.

    nonisolated static func ownershipBadge(_ ownership: EthicsEntry.Ownership) -> BadgeItem? {
        switch ownership {
        case .indie:
            return BadgeItem(label: "Indie", systemImage: "house", tint: .positive)
        case .employeeOwned:
            return BadgeItem(label: "Employee-owned", systemImage: "person.3", tint: .positive)
        case .coop:
            return BadgeItem(label: "Co-op", systemImage: "hands.sparkles", tint: .positive)
        case .bCorp:
            return BadgeItem(label: "B-Corp", systemImage: "leaf", tint: .positive)
        case .mega:
            return BadgeItem(label: "Mega-owned", systemImage: "exclamationmark.triangle", tint: .warning)
        case .unknown:
            return nil
        }
    }

    nonisolated static func certificationBadge(_ certification: String) -> BadgeItem? {
        switch certification.lowercased() {
        case "b-corp":
            return BadgeItem(label: "B-Corp", systemImage: "leaf", tint: .positive)
        case "esop":
            return BadgeItem(label: "Employee-owned", systemImage: "person.3", tint: .positive)
        case "coop":
            return BadgeItem(label: "Co-op", systemImage: "hands.sparkles", tint: .positive)
        case "union", "unionized":
            return BadgeItem(label: "Union", systemImage: "hand.raised", tint: .positive)
        case "fair-trade":
            return BadgeItem(label: "Fair Trade", systemImage: "checkmark.seal", tint: .positive)
        case "1-percent-for-the-planet":
            return BadgeItem(label: "1% for the Planet", systemImage: "globe", tint: .positive)
        default:
            return nil // unrecognized certifications are hidden
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        EthicsBadgeView(entry: EthicsEntry(ownership: .bCorp, certifications: ["b-corp", "1-percent-for-the-planet"]))
        EthicsBadgeView(entry: EthicsEntry(ownership: .coop, certifications: ["coop"]))
        EthicsBadgeView(entry: EthicsEntry(ownership: .employeeOwned, certifications: ["esop", "b-corp"]))
        EthicsBadgeView(entry: EthicsEntry(ownership: .indie, certifications: ["unionized"]))
        EthicsBadgeView(entry: EthicsEntry(ownership: .mega))
        EthicsBadgeView(entry: EthicsEntry(ownership: .unknown))
    }
    .padding()
}
