# Implementation Plan: A2 → A1 → B1 → A4+C5 → C2

## Context

This plan implements the top five recommendations from `docs/improvement_plan.md` in dependency order. The goals: cut perceived search latency (A2, A1), expand local-shop coverage (B1), surface the project's ethical values in the ranking and UI (A4, C5), and add the highest-leverage on-device-only feature (C2 barcode scan).

Each milestone is **one PR / one commit batch**. Run the test suite after each.

**Architectural anchors** (don't break these):
- `SearchSource` protocol at `Sources/MetasearchCore/SearchSource.swift:3-12` — every new source conforms.
- `URLSessionProtocol` at `Sources/SearchSources/URLSessionProtocol.swift` — every networking source takes it for testability.
- `MetasearchCoordinator.searchStreaming()` at `Sources/MetasearchCore/MetasearchCoordinator.swift:105-237` — the orchestration layer; do not rewrite, only adapt.
- Existing test pattern: `Tests/SearchSourcesTests/NominatimSearchSourceTests.swift` and `DPLASearchSourceTests.swift` — copy this shape for new sources.

---

## Milestone A2 — Tiered per-source timeouts

**Goal:** Drop the uniform 60s timeout. Slow sources can't drag down the UI.

### Files to modify
- `Sources/MetasearchCore/SearchSource.swift` — add `timeoutBudget` to protocol.
- `Sources/MetasearchCore/MetasearchCoordinator.swift` — replace `self.timeout` with `source.timeoutBudget` in both `search()` (line ~47) and `searchStreaming()` (lines ~157 and ~221) at every `withTimeout(seconds:)` call site. Keep the constructor `timeout` parameter as a *hard ceiling* fallback (`min(source.timeoutBudget, self.timeout)`).
- Per-source overrides where the default doesn't fit (initially: Amazon/BestBuy/Bookshop scrapers — set 6s).

### Key changes

In `SearchSource.swift`, add:
```swift
public protocol SearchSource: Sendable {
    // ...existing requirements...
    var timeoutBudget: TimeInterval { get }
}

public extension SearchSource {
    var timeoutBudget: TimeInterval {
        switch sourceType {
        case .local:    return 2.5    // MapKit, Nominatim, Overpass
        case .regional: return 4.0
        case .online:   return 4.0    // most JSON APIs
        }
    }
}
```

Then in `AmazonSearchSource.swift`, `BestBuySearchSource.swift`, `BookshopSearchSource.swift` (the HTML scrapers), override to `6.0`.

In `MetasearchCoordinator.swift`, every `try await self.withTimeout(seconds: timeoutValue)` becomes `try await self.withTimeout(seconds: min(source.timeoutBudget, self.timeout))`.

### Tests
- `Tests/MetasearchCoreTests/MetasearchCoordinatorTests.swift` (or a new `TimeoutBudgetTests.swift`): build a stub `SearchSource` with `timeoutBudget = 0.2` and an artificial 2s delay; assert it's dropped while a fast peer's results are returned.

### Verification
- `xcodebuild test -scheme InTheNeighborhood` — existing tests still pass.
- Run app, observe that overall search completes in ≤ 8s even when one source hangs.

---

## Milestone A1 — Decouple local search from intelligence extraction

**Goal:** Local results appear first instead of last. Currently `phase2Sources` (local) only runs after `await group.waitForAll()` on Phase 1 (`MetasearchCoordinator.swift:187`). Fix: fire local sources in parallel with Phase 1 using the raw query; re-fire with enriched query when intelligence becomes available.

### Files to modify
- `Sources/MetasearchCore/MetasearchCoordinator.swift` — restructure `searchStreaming()` (lines 105-237).

### Key changes
Restructure `searchStreaming()` to three concurrent stages:

```swift
await withTaskGroup(of: Void.self) { group in
    // Stage 1a: Phase 1 sources (web/product) — unchanged, fills intelligenceState
    for source in phase1Sources { group.addTask { ... } }

    // Stage 1b: Initial local pass with RAW query, in parallel with Phase 1
    let seenLocalIds = LocalSeenIDs()  // new actor, tracks emitted SearchResult.id
    for source in phase2Sources {
        group.addTask {
            try? await self.withTimeout(seconds: min(source.timeoutBudget, self.timeout)) {
                try await source.searchStreaming(query: query) { rawResults in
                    let fresh = await seenLocalIds.filterAndTrack(rawResults)
                    if !fresh.isEmpty { onResults(source.identifier, fresh) }
                }
            }
        }
    }
}

// Stage 2: Refined local pass only if intelligence enriched the query
let finalBrand = await intelligenceState.extractedBrand
let finalAuthor = await intelligenceState.extractedAuthor
if finalBrand != nil || finalAuthor != nil {
    let refinedQuery = buildEnrichedQuery(...)  // existing logic, lines 195-203
    await withTaskGroup(of: Void.self) { group in
        for source in phase2Sources {
            group.addTask {
                try? await self.withTimeout(seconds: min(source.timeoutBudget, self.timeout)) {
                    try await source.searchStreaming(query: refinedQuery) { rawResults in
                        let fresh = await seenLocalIds.filterAndTrack(rawResults)
                        if !fresh.isEmpty { onResults(source.identifier, fresh) }
                    }
                }
            }
        }
    }
}
```

New helper actor in the same file:
```swift
private actor LocalSeenIDs {
    private var ids: Set<String> = []
    func filterAndTrack(_ results: [SearchResult]) -> [SearchResult] {
        let fresh = results.filter { !ids.contains($0.id) }
        fresh.forEach { ids.insert($0.id) }
        return fresh
    }
}
```

### Tests
- `Tests/MetasearchCoreTests/MetasearchCoordinatorTests.swift`: stub a fast local source (returns in 50ms) and a slow web source (returns in 1s). Assert the local source's `onResults` callback fires **before** the web source's.
- Stub a local source that returns the same `place_id` for both raw and refined queries; assert no duplicate emission.

### Verification
- Run app, search "wireless headphones," observe local results appear within ~1s while web/product cards stream in over the next few seconds.

---

## Milestone B1 — OverpassSearchSource

**Goal:** Tag-based local discovery via OpenStreetMap Overpass — finds specialty shops that MapKit's free-text matches miss.

### Files to create
- `Sources/SearchSources/OpenStreetMap/OverpassSearchSource.swift`
- `Sources/SearchSources/OpenStreetMap/OverpassTagMap.swift` — static category→OSM-tag dictionary.
- `Tests/SearchSourcesTests/OverpassSearchSourceTests.swift`

### Files to modify
- `Sources/MetasearchCore/SourceIdentifier.swift` — add `public static let overpass = "overpass"`.
- Wherever sources are constructed (search for `NominatimSearchSource(` to find the wiring site, likely `Sources/InTheNeighborhood/App.swift` or a factory) — register `OverpassSearchSource` alongside Nominatim.

### Key changes

`OverpassTagMap.swift` — minimum viable category map:
```swift
enum OverpassTagMap {
    static let categoryToTags: [String: [String]] = [
        "book":      ["shop=books"],
        "hardware":  ["shop=hardware", "shop=doityourself"],
        "grocery":   ["shop=greengrocer", "shop=organic", "shop=farm"],
        "bike":      ["shop=bicycle"],
        "music":     ["shop=music", "shop=musical_instrument"],
        "clothing":  ["shop=clothes", "shop=second_hand"],
        "repair":    ["shop=repair", "service:repair=*"],
        "library":   ["amenity=library"],
        "tool_library": ["amenity=library", "library:type=tool_library"]
    ]
    static let fallbackTags = ["shop"]  // any shop tag at all
}
```

`OverpassSearchSource.swift` — model exactly on `NominatimSearchSource.swift:1-150`:
- Same init (`locationService`, `urlSession: URLSessionProtocol = URLSessionAdapter()`, `searchRadius: CLLocationDistance = 5000`).
- `identifier = "overpass"`, `sourceType = .local`, `category = .local`.
- `searchStreaming()`: resolve location via `locationService.getLocationOrFallback()`, build Overpass QL from `query.categories` (or heuristic match on `query.original`), POST to `https://overpass-api.de/api/interpreter` with `data=...` body, parse `elements` array.
- User-Agent header `InTheNeighborhood/1.0 (com.in-the-neighborhood)` — Overpass requires this like Nominatim.
- Parse each `element` with `tags["name"]` as title, `tags["shop"]` or `tags["amenity"]` as description, `lat`/`lon` → `CLLocation`, compute distance.

Sample Overpass query body (5km radius around lat/lon):
```
[out:json][timeout:5];
( node["shop"="books"](around:5000,LAT,LON);
  way["shop"="books"](around:5000,LAT,LON); );
out center tags 25;
```

### Tests
Copy `Tests/SearchSourcesTests/NominatimSearchSourceTests.swift` shape:
- Happy path with fixture JSON (one node, one way).
- Empty `elements` array → empty results.
- Network error → empty results, error thrown.
- No location available → empty results, no network call.
- Category mapping test: query with `categories = ["book"]` produces an Overpass body containing `shop=books`.

### Verification
- Run app at a location with known indie bookstore (e.g. Portland: Powell's at 45.5232, -122.6814). Search "books." Confirm Powell's appears in local-stores tab.
- Existing Nominatim tests still pass.

---

## Milestone A4 + C5 — Ethics ledger + badges

**Goal:** Replace the binary deny list semantics with a continuous ethics signal. Surface ownership/certification info visually on every card.

### Files to create
- `Sources/InTheNeighborhood/Resources/EthicsLedger.json` — initial bundled dataset (50-100 well-known hostnames).
- `Sources/SharedModels/EthicsLedger.swift` — Codable model + `Bundle.main` loader.
- `Sources/MetasearchCore/EthicsScorer.swift` — hostname lookup, score derivation, integration helpers.
- `Sources/InTheNeighborhood/Views/EthicsBadgeView.swift` — small pill-row SwiftUI view.
- `Tests/MetasearchCoreTests/EthicsScorerTests.swift`
- `Tests/InTheNeighborhoodTests/EthicsBadgeViewTests.swift`

### Files to modify
- `Sources/MetasearchCore/DenyListFilter.swift` — delegate the "is this a mega-retailer?" decision to `EthicsScorer.isBlocked(host:)`; keep the legacy hard-coded list as a fallback seed when the ledger has no entry.
- `Sources/MetasearchCore/ResultAggregator.swift` — at filter time, attach `metadata["ethics"]` to every passing result by looking up via `EthicsScorer`.
- `Sources/MetasearchCore/ResultPrioritizer.swift` — add a sub-tier comparator: within the same `SourceType` tier, prefer entries with higher ethics scores (B-Corp / employee-owned / co-op / indie > unknown > mega-affiliated).
- 4 card views: `LocalBusinessCard.swift`, `LibraryCard.swift`, `AmazonProductCard.swift`, `OnlineResultCard.swift` — render `EthicsBadgeView(entry:)` if `result.metadata["ethics"]` is present.
- `project.yml` — add the resource entry (lines around 57-60 in the `InTheNeighborhood` target's `resources:` block):
  ```yaml
  resources:
    - path: Sources/InTheNeighborhood/Resources/Localizable.strings
    - path: Sources/InTheNeighborhood/Resources/EthicsLedger.json
  ```

### Key changes

`EthicsLedger.swift`:
```swift
public struct EthicsEntry: Codable, Hashable, Sendable {
    public enum Ownership: String, Codable, Sendable {
        case indie, employeeOwned = "employee-owned", coop, bCorp = "b-corp", mega, unknown
    }
    public let ownership: Ownership
    public let region: String?           // "local" | "regional" | "national" | "global"
    public let certifications: [String]  // free-form: "b-corp", "fair-trade", "union"
    public let notes: String?
}

public struct EthicsLedger: Codable, Sendable {
    public let version: String
    public let entries: [String: EthicsEntry]  // keyed by base domain
    public static func loadBundled() -> EthicsLedger { /* Bundle.main lookup */ }
}
```

`EthicsScorer.swift`:
```swift
public struct EthicsScorer: Sendable {
    private let ledger: EthicsLedger
    public init(ledger: EthicsLedger = .loadBundled()) { self.ledger = ledger }

    public func entry(forHost host: String) -> EthicsEntry? {
        // reuse DenyListFilter.extractBaseDomain() logic — promote that helper out of DenyListFilter
        let base = Self.extractBaseDomain(from: host.lowercased())
        return ledger.entries[base] ?? ledger.entries[host.lowercased()]
    }

    public func isBlocked(host: String) -> Bool {
        entry(forHost: host)?.ownership == .mega
    }

    public func score(forHost host: String) -> Int {
        // Higher = better. Used for tiebreak in ResultPrioritizer.
        switch entry(forHost: host)?.ownership {
        case .coop, .bCorp, .employeeOwned: return 3
        case .indie:                         return 2
        case .unknown, .none:                return 1
        case .mega:                          return 0
        }
    }
}
```

`DenyListFilter.swift`: keep `shouldFilter(url:)` API, but delegate:
```swift
public func shouldFilter(url: URL, scorer: EthicsScorer? = nil) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    if let scorer, scorer.isBlocked(host: host) { return true }
    // existing hard-coded list logic as fallback
}
```

`ResultAggregator.filter()`: when a result passes the filter, attach `result.metadata["ethics"] = scorer.entry(forHost: host)` (use a copying initializer on `SearchResult`).

`ResultPrioritizer.prioritize()`: in the in-tier comparator, add `scorer.score(forHost:)` as a tiebreak between `tierPriority` and `relevanceScore`.

`EthicsBadgeView.swift`:
```swift
struct EthicsBadgeView: View {
    let entry: EthicsEntry
    var body: some View {
        HStack(spacing: 4) {
            badge(for: entry.ownership)
            ForEach(entry.certifications.prefix(2), id: \.self) { Text($0).pill() }
        }
    }
    @ViewBuilder private func badge(for ownership: EthicsEntry.Ownership) -> some View {
        switch ownership {
        case .indie:          Label("Indie", systemImage: "house").pill(.green)
        case .employeeOwned:  Label("Employee-owned", systemImage: "person.3").pill(.green)
        case .coop:           Label("Co-op", systemImage: "hands.sparkles").pill(.green)
        case .bCorp:          Label("B-Corp", systemImage: "leaf").pill(.green)
        case .mega:           Label("Mega-owned", systemImage: "exclamationmark.triangle").pill(.orange)
        case .unknown:        EmptyView()
        }
    }
}
```

Card integration — example for `LocalBusinessCard.swift` (insert after description, around line 24-25):
```swift
if let entry = result.metadata["ethics"] as? EthicsEntry {
    EthicsBadgeView(entry: entry)
}
```

### Initial `EthicsLedger.json` seed
Start with ~50 entries covering the existing deny list (all → `mega`) plus well-known positive examples:
- `powells.com` → employee-owned
- `bookshop.org` → b-corp
- `replacements.com`, `kingarthurflour.com`, `eileenfisher.com` → employee-owned / b-corp
- `rei.com` → coop
- Major indie bookstore chains, regional grocery co-ops.

The JSON is small and human-curated for now. Remote refresh is **out of scope for this plan** (follow-up).

### Tests
- `EthicsScorerTests.swift`: hostname normalization (`www.amazon.com` → `amazon.com`), subdomain matching, exact match, unknown → `.unknown` ownership, scoring monotonicity.
- `EthicsBadgeViewTests.swift`: rendering produces expected SF Symbols for each ownership type. Use SwiftUI ViewInspector or assert presence via accessibility identifiers.
- `ResultPrioritizerTests.swift`: extend existing tests to assert a co-op result outranks an indie one in the same tier with the same relevance score.

### Verification
- Search "books." Confirm `bookshop.org` shows a "B-Corp" badge and ranks above generic online bookstores.
- Search a query that historically returned an Amazon result; confirm filter still drops it.
- Run full test suite.

---

## Milestone C2 — Barcode scan via Vision

**Goal:** Tap a button, scan a UPC/EAN/ISBN, app routes to the right lookup flow.

### Files to create
- `Sources/InTheNeighborhood/Views/BarcodeScannerView.swift` — `UIViewControllerRepresentable` wrapping `AVCaptureSession` + Vision `VNDetectBarcodesRequest`.
- `Tests/InTheNeighborhoodTests/BarcodeRoutingTests.swift` — unit-tests for the ISBN-vs-UPC routing logic (the AVFoundation/Vision pieces aren't unit-testable without a device).

### Files to modify
- `Sources/InTheNeighborhood/Info.plist` — add:
  ```xml
  <key>NSCameraUsageDescription</key>
  <string>Scan product barcodes to find local and ethical alternatives.</string>
  ```
- `project.yml` — mirror the Info.plist key via `INFOPLIST_KEY_NSCameraUsageDescription` if other keys use that convention; otherwise the direct Info.plist edit is enough.
- `Sources/InTheNeighborhood/Views/SearchView.swift` — add a scanner button in `SearchBarView` (the HStack at lines 156-186). Place between the magnifying glass and the TextField, or as a leading toolbar item. Sheet-present `BarcodeScannerView` on tap. On scan completion, call `viewModel.handleScannedBarcode(_:)`.
- `Sources/InTheNeighborhood/ViewModels/SearchViewModel.swift` — add:
  ```swift
  public func handleScannedBarcode(_ code: String) async {
      let trimmed = code.trimmingCharacters(in: .whitespaces)
      if isISBN(trimmed) {
          searchText = "isbn:\(trimmed)"   // OpenLibrary handles this natively
      } else {
          searchText = trimmed              // treat as plain query; UPC→product lookup is a follow-up
      }
      await search(query: searchText)
  }
  private func isISBN(_ s: String) -> Bool {
      let digits = s.filter(\.isNumber)
      return digits.count == 10 || digits.count == 13
  }
  ```

### Key changes in `BarcodeScannerView.swift`
- `UIViewControllerRepresentable` wrapping a `UIViewController` that:
  - Configures `AVCaptureSession` with `.builtInWideAngleCamera`.
  - Adds `AVCaptureVideoDataOutput` with `sampleBufferDelegate = self`.
  - On each sample buffer, runs `VNDetectBarcodesRequest` with `symbologies = [.ean13, .ean8, .upce, .qr, .code128]`.
  - On first detection, calls `onScan(payload)` and stops the session.
- Cleanup: stops session in `viewWillDisappear`.
- Permission flow: check `AVCaptureDevice.authorizationStatus(for: .video)`; request if `.notDetermined`; if `.denied`, show in-app message linking to Settings.

### Tests
- `BarcodeRoutingTests.swift`:
  - `handleScannedBarcode("9780143105985")` → `searchText` starts with `"isbn:"`.
  - `handleScannedBarcode("012345678905")` → `searchText` is the raw UPC (no `isbn:` prefix).
  - Whitespace trimming.

### Verification
- Run on a physical device (simulator can't access camera). Grant camera permission. Scan a book's ISBN — confirm an Open Library result appears in the Library tab. Scan a non-book UPC — confirm a generic search runs.
- Confirm denying camera permission shows a graceful in-app message rather than crashing.

---

## Cross-Cutting Notes

### Sequencing & commit boundaries
- **A2** is standalone; no other milestone depends on it. Ship first.
- **A1** depends on A2 (uses the new `source.timeoutBudget`).
- **B1** is standalone but benefits from A1 (Overpass gets local-tier latency budget and parallel start).
- **A4** depends on nothing but should land before **C5** since C5 reads its data.
- **C5** is presentation-only once A4 is in.
- **C2** is fully independent of A1–A4.

Recommend **one commit per milestone**, in this order: A2, A1, B1, A4, C5, C2.

### Existing utilities to reuse — do NOT reinvent
- `URLSessionProtocol` / `URLSessionAdapter` at `Sources/SearchSources/URLSessionProtocol.swift` — for B1's networking.
- `LocationServiceProtocol.getLocationOrFallback()` — for B1's location resolution (same pattern as Nominatim).
- `DenyListFilter.extractBaseDomain(from:)` (currently private at line 66) — for A4 hostname normalization. **Promote it to internal/public** and call from `EthicsScorer` rather than duplicating.
- `SearchResult.metadata` dict — for A4's ethics-entry injection; no schema change needed.
- The `Tests/SearchSourcesTests/NominatimSearchSourceTests.swift` test pattern — copy for B1 and any new source.

### Test infrastructure
All milestones extend existing test targets. No new test targets needed. Coverage stays enabled (`project.yml:37 gatherCoverageData: true`).

### Out of scope for this plan (follow-ups)
- Remote refresh of `EthicsLedger.json` via background fetch.
- Open Food Facts source as a non-ISBN barcode lookup (C2 currently routes non-ISBN codes to a generic query).
- Replacing the binary deny-list semantics entirely with a continuous ethics score (A4 adds the data; the prioritizer uses it as a tiebreak, but `DenyListFilter` still hard-blocks `ownership == .mega`).
- Wikidata SPARQL parent-company lookup (Track B3).
- `NaturalLanguage`-based category routing (Track C3).
- Map view tab (Track C4).
- "Why this result?" explainability drawer (Track C7).

### End-to-end verification
After all milestones land:
1. `xcodebuild test -scheme InTheNeighborhood` — full test suite green.
2. Cold-launch the app and time a search for "wireless headphones." Targets: TTFR local ≤ 2s, TTC overall ≤ 8s (down from 10-20s today).
3. Run the 30-query fixture set described in `docs/improvement_plan.md` Verification section; before/after diff on non-deny-listed result counts.
4. Visually confirm: ethics badges appear on cards, Powell's-class indie stores rank above generic results, barcode scan opens the camera and surfaces an Open Library result for a book ISBN.
