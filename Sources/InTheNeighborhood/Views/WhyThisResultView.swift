import SwiftUI
import MetasearchCore

/// On-demand "Why this result?" sheet. Explains why a result is surfaced —
/// the ethics-ledger note, its relation as an ethical alternative to a
/// deny-listed product, and (loaded lazily from Wikidata when the sheet
/// opens) the brand's parent company and certifications.
///
/// Wikidata's SPARQL endpoint is slow (3–5s), so the lookup runs ONLY here,
/// from the sheet's `.task` when the user taps to open it — never on the
/// inline search path. This keeps search latency untouched.
struct WhyThisResultView: View {
    let result: SearchResult
    /// Injectable so tests/previews can substitute a stub. Defaults to a
    /// real Wikidata-backed lookup.
    var lookup: WikidataBrandLookup = WikidataBrandLookup()

    @Environment(\.dismiss) private var dismiss
    @State private var brandInfo: BrandInfo?
    @State private var isLoading = false

    private var brand: String? {
        (result.metadata["brand"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Why this result") {
                    let lines = Self.detailLines(
                        ethics: result.metadata["ethics"] as? EthicsEntry,
                        alternativeFor: result.metadata["ethicalAlternativeFor"] as? String,
                        brand: brand
                    )
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }

                if brand != nil {
                    Section("Brand ownership (via Wikidata)") {
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Looking up…").foregroundColor(.secondary)
                            }
                        } else if let info = brandInfo,
                                  info.parentCompany != nil || !info.certifications.isEmpty {
                            if let parent = info.parentCompany {
                                LabeledContent("Parent company", value: parent)
                            }
                            if !info.certifications.isEmpty {
                                LabeledContent("Certifications", value: info.certifications.joined(separator: ", "))
                            }
                        } else {
                            Text("No additional ownership data found.")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Why this result?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Only hit Wikidata when there's a brand and we haven't already.
                guard let brand, brandInfo == nil else { return }
                isLoading = true
                brandInfo = try? await lookup.lookup(brand: brand)
                isLoading = false
            }
        }
    }

    /// Pure formatter for the non-network explanation lines. `nonisolated`
    /// and `static` so it's unit-testable without a rendering harness or
    /// network — mirrors the `LibraryCard` pure-helper pattern.
    nonisolated static func detailLines(
        ethics: EthicsEntry?,
        alternativeFor: String?,
        brand: String?
    ) -> [String] {
        var lines: [String] = []
        if let alternativeFor, !alternativeFor.isEmpty {
            lines.append("Surfaced as an ethical alternative to “\(alternativeFor)”, found using product metadata gathered behind the scenes from a deny-listed retailer.")
        }
        if let ethics {
            if let notes = ethics.notes, !notes.isEmpty {
                lines.append(notes)
            } else {
                lines.append("Ownership: \(Self.ownershipLabel(ethics.ownership)).")
            }
        }
        if let brand, !brand.isEmpty {
            lines.append("Brand: \(brand).")
        }
        if lines.isEmpty {
            lines.append("This result comes from an open, non-monopolistic source.")
        }
        return lines
    }

    nonisolated static func ownershipLabel(_ ownership: EthicsEntry.Ownership) -> String {
        switch ownership {
        case .indie:         return "independent"
        case .employeeOwned: return "employee-owned"
        case .coop:          return "cooperative"
        case .bCorp:         return "certified B-Corp"
        case .discouraged:   return "large chain"
        case .mega:          return "mega-retailer"
        case .unknown:       return "unknown"
        }
    }
}
