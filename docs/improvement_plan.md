# Plan: Strategic Review & New Ideas for *In the Neighborhood*

## Context

*In the Neighborhood* is an iOS 26+ SwiftUI app whose stated mission (per `README.md` and `docs/prd.md`) is to help conscious consumers find products at **local merchants** and **ethical online retailers** while filtering out mega-retailers (Amazon, Walmart, Target, etc.). Hard constraints from the user: code stays on-device, every API must be open and free, no crowdsourcing or social features.

Current pain points the user named:
- **Searches are slow** (observed: 10–20s typical end-to-end)
- **Results are sporadic** (uneven coverage across product categories)
- **API coverage is limited** — BestBuy/Bookshop/etc. cover only narrow slices of what users actually search for

This plan is a **research/strategy plan** — a menu of ideas to evaluate, not an implementation plan for a single feature. The deliverable is the prioritized roadmap below; the user picks which tracks to pursue next.

---

## 1. Review of Current State Against Mission

### What aligns well
- **Deny-list filtering** (`DenyListFilter.swift`): hard-coded mega-retailer domains are stripped from results, with mutable runtime API. Aligns directly with mission.
- **Metadata-only scraping of Amazon/BestBuy**: results are used for brand/ISBN extraction then filtered out before display (`ResultAggregator.swift:44-46`). Clever — extracts intelligence without endorsing the retailer.
- **Tier-based prioritization** (`ResultPrioritizer.swift`): local > regional > online. Right shape.
- **On-device privacy**: `SystemLanguageModel` (iOS 26) used for relevance scoring and `AgentSearchCoordinator` planning, never leaves device.
- **Open/free sources already integrated**: Nominatim (OSM), Open Library, DPLA, DuckDuckGo, Google Books, MapKit.

### Where the code is misaligned with mission or the user's constraints
- **`regional` tier is defined but unused** (`SourceType.swift`). Cooperatives, regional indie chains, B-Corps have no home in the ranking.
- **Deny list is binary** — every result is either deny-listed or fully equal. No notion of "less bad" (e.g. employee-owned chain) vs. "mega-retailer." No notion of "actively good" (B-Corp, certified union shop, indie).
- **`Phase 2` (MapKit local) waits on `Phase 1` (web/products) to finish** before running with the enriched query (`MetasearchCoordinator.swift` streaming flow). This makes the **most mission-critical tier (local) the slowest to appear**. The user sees web/product results first, local results last — backwards from the app's stated values.
- **60-second per-source timeout** (`SearchToolExecutor.swift`): far too lenient for a search UX. Slow scrapers (Amazon, Bookshop HTML) drag the perceived latency up.
- **No caching layer** anywhere — repeat searches re-hit every source from scratch. There is no `query → results` memo, no `hostname → ethical-metadata` lookup table.
- **Amazon/BestBuy scrapers are brittle**: HTML-based, no real fallback if DOM shifts. Recent commits (`8de1800`, debug logging in `AmazonProductScraper.swift`) suggest active troubleshooting.
- **Categories don't drive routing**: a query for "screwdriver" hits the same sources as "wireless headphones" or "Moby Dick." No category-aware source selection beyond what the LLM agent plan does optionally.
- **No use of Vision, NaturalLanguage, or Core ML** — three on-device frameworks that match the user's constraints perfectly and are sitting unused.
- **No map view** despite MapKit being a primary local source. Results are list-only.

### Root causes of the user's two complaints
- **Slow**: two-phase serialization + 60s timeouts + no caching + HTML scraping latency.
- **Sporadic**: deny list filters away the bulk of results without offering ethical replacements; category-blind source routing; no fallback when specialty APIs (BestBuy, DPLA) lack coverage for a given query.

---

## 2. Proposed Tracks of Work

Three independent tracks. Pick any combination. Each item lists rough effort and impact.

### Track A — Speed & Reliability (fix what's slow/sporadic)

**A1. Decouple local search from intelligence extraction** *(M effort, high impact)*
Start `MapKitSearchSource` and `NominatimSearchSource` **immediately with the raw query** in parallel with Phase 1. When Phase 1 finishes and yields enriched metadata, fire a *second* local search and merge. User sees nearby results within 1-2s instead of 5-10s. Modify `MetasearchCoordinator.swift` streaming flow.

**A2. Tighten per-source budgets** *(S effort, high impact)*
Drop the 60s per-source timeout in `SearchToolExecutor.swift` to a tiered budget: **2s for local, 4s for fast APIs, 6s for scrapers, 8s hard ceiling**. Whatever didn't return by the deadline is dropped. Search feels snappier; slow sources can't gate the UI.

**A3. Query-result cache** *(S effort, moderate impact)*
On-device LRU `[String: [SearchResult]]` with 24h TTL, keyed by normalized query. Speeds up repeat searches (which are common in real use — user tweaks a query, scrolls back). Store in `FileManager` or `CoreData`.

**A4. Hostname → ethics metadata cache** *(S effort, structural impact)*
Ship a static JSON file (`Resources/EthicsLedger.json`) mapping hostnames to: `{ownership: indie|employee-owned|coop|b-corp|mega, region: local|regional|national, certifications: [...]}`. Refresh from GitHub on background fetch. Reused everywhere — prioritizer, card badges, deny-list expansion. Replaces the binary deny list.

**A5. Replace HTML scrapers with API-first fallbacks** *(M effort, moderate impact)*
Amazon and BestBuy scraping is the brittlest part of the codebase. For metadata extraction, prefer **Wikidata SPARQL** + **Open Library** + **Open Food Facts** lookups (all open & free) before falling back to HTML scrape. Even simple ISBN/UPC barcode-to-metadata via Open Library covers most book queries without touching Amazon.

### Track B — Expand Coverage with New Free/Open Sources

**B1. OpenStreetMap Overpass API** *(M effort, high impact)*
Nominatim does geocoding; **Overpass** queries OSM by tag — `shop=hardware`, `shop=books`, `shop=bicycle`, `shop=greengrocer`, `amenity=library`, `amenity=tool_library`. This is the **single biggest unlock for local coverage** because OSM tags categorize specialty shops far better than MapKit's free-text. Free, open, no key.

**B2. Open Food Facts (and siblings)** *(M effort, high impact for groceries)*
Fully open, has product database with **ethical/environmental ratings** (Nutri-Score, Eco-Score, Nova). Same group: **Open Beauty Facts**, **Open Products Facts**, **Open Pet Food Facts**. For grocery/personal-care/pet queries, these slot in cleanly. No key required.

**B3. Wikidata SPARQL** *(M effort, structural impact)*
Free, open, no key. Use for:
- Brand → parent company lookup ("does Method belong to a mega-corp now?")
- Product → alternatives ("brands of dish soap that aren't owned by Unilever/P&G")
- Company → B-Corp / employee-owned / cooperative status
Powerful but slow; cache aggressively.

**B4. Internet Archive / Open Library expanded** *(S effort, moderate impact)*
Already have Open Library and DPLA for books. Internet Archive has a **searchable API for media** (films, music, software) — open, free, no key. Expands the "borrow instead of buy" angle beyond books.

**B5. Library of Things / tool libraries via OSM** *(S effort, niche but mission-aligned)*
Subset of B1: OSM tags `amenity=library` with `library:type=tool_library` or `service:repair=*` find tool libraries and repair cafés. Mission-aligned (borrow/repair instead of buy) and currently invisible to users.

**B6. WorldCat Discovery API or library system catalogs** *(L effort, moderate impact)*
WorldCat has a free tier with limits. Alternatively, many public library systems expose **SIP2/Z39.50** or **OverDrive/Libby** APIs. Wiring "is this book available at MY local library?" closes a loop the user explicitly cares about. May exceed free/open constraint depending on system — needs validation per region.

### Track C — Strategic Reframing (make it more useful)

**C1. From "search" to "need fulfillment"** *(L effort, high impact)*
A query like "wireless headphones" today returns products to buy new. Reframe: when the user submits, surface tabs/sections for **Buy local**, **Buy ethical online**, **Buy used**, **Repair**, **Borrow** (library of things), **Alternatives** (Wikidata "is similar to"). Each backed by different sources. Turns the app into a values-aligned consumption advisor, not just a search engine.

**C2. Barcode scan via Vision framework** *(M effort, high delight)*
On-device, no API, fully free. User scans a UPC/EAN/ISBN on a product in a store; app does **"find this locally"** + **"find ethical alternative"** + **"is this on Open Food Facts?"** flows. Vision is already on every modern iOS device. This is the highest-leverage on-device-only feature still untapped.

**C3. Category-aware routing via NaturalLanguage** *(S effort, moderate impact)*
Use `NLTagger` / `NLLanguageRecognizer` (no LLM needed) to classify the query into book/grocery/hardware/electronics/clothing/media/general. Route each category to a tuned source set. Replaces the brittle "if includes('book') → bookshop" heuristic with something principled. Pairs well with the LLM agent for queries the classifier can't resolve.

**C4. Map view tab** *(S effort, high delight)*
MapKit is already a dependency. Show local results on a map with pins, distance circles, optional category filter. Currently `LocalBusinessCard` shows distance numerically — a map view is the natural next step.

**C5. Ethics badges in cards** *(S effort, mission visibility)*
Once `EthicsLedger.json` (A4) exists, show small badges on every result card: 🏠 Local, 🤝 Co-op, 🏢 Indie, 🌱 B-Corp, ⚠ Mega-owned. Makes the app's values tangible to the user rather than implicit in the filtering.

**C6. Saved alerts / watch list** *(M effort, moderate impact, fully local)*
User saves a desired item ("a used copy of *Gravity's Rainbow* under $15"); background fetch re-runs the search daily, posts a local notification when a match appears. Stays on-device. Turns the app from one-shot search into ongoing assistant.

**C7. "Why this result?" explainability** *(S effort, trust impact)*
Tap a card → small drawer explains: "Ranked above Amazon because Powell's is an independent, employee-owned bookstore in Portland. Distance: 2.4 mi." Builds user trust in the prioritizer.

---

## 3. Recommended Starting Sequence

If the user wants concrete next steps, this is my recommended order — chosen for ratio of impact to effort, and to address the two stated pain points (slow + sporadic) first:

1. **A2** (tiered per-source budgets) — half-day of work, immediate snappiness win.
2. **A1** (decouple local search from intelligence extraction) — local results appear first instead of last.
3. **B1** (Overpass API for OSM tag-based local search) — biggest single jump in local coverage; addresses "sporadic."
4. **A4** (ethics ledger JSON) + **C5** (badges) — makes the values visible and unlocks better ranking.
5. **C2** (barcode scan via Vision) — highest-delight on-device-only feature still untapped.

Items 1–3 alone should noticeably improve the "slow and sporadic" problem the user named.

---

## 4. Constraints That Constrained This Plan

Everything proposed above:
- **Stays on device** — no server, no cloud, no third-party backend.
- **Uses free, open APIs only** — Overpass, Open Food Facts, Wikidata, Open Library, DPLA, Internet Archive, OSM Nominatim are all explicitly free, open, no key required (or have generous free tiers with no payment ever needed). Items that might cross the line (WorldCat regional tiers in B6) are flagged.
- **Avoids crowdsourcing/social** — no user contributions, no shared data, no accounts.
- **Respects the existing architecture** — every proposal slots into the `SearchSource` protocol or extends `MetasearchCoordinator` / `ResultPrioritizer` rather than rebuilding the core.

Frameworks newly invoked: **Vision** (C2), **NaturalLanguage** (C3), **MapKit's `MKMapView` SwiftUI bridge** (C4), `UserNotifications` (C6). All free, on-device, Apple-provided.

---

## 5. Verification Approach

Per track, the user can measure success as follows:

- **Track A (speed)**: instrument `MetasearchCoordinator` to log time-to-first-result and time-to-completion per search. Targets: TTFB local ≤ 2s, TTC overall ≤ 6s. Add an opt-in debug overlay in the UI for development.
- **Track B (coverage)**: build a fixture set of 30 representative queries (5 books, 5 groceries, 5 hardware items, 5 electronics, 5 clothing, 5 media). Before/after comparison: count of non-deny-listed results returned. Existing tests under `Tests/SearchSourcesTests/` provide the pattern (use `URLSessionProtocol` stubs).
- **Track C (usefulness)**: harder to measure quantitatively. Tracks the user's own feel for the app, plus targeted tests for new tabs/views.

Run the existing test suite (`xcodebuild test -scheme InTheNeighborhood`) after each change. New search sources need: protocol conformance test + happy-path test + empty-result test + network-error test (the existing pattern in `Tests/SearchSourcesTests/NominatimSearchSourceTests.swift` and `DPLASearchSourceTests.swift`).

---

## 6. What This Plan Does NOT Do

- **Does not write code.** This is a strategy/menu plan. Once the user picks one or more tracks, a follow-up implementation plan would scope the specific files to modify.
- **Does not redesign the deny list semantics today.** A4 proposes the data layer; how exactly the ranking math changes (replace deny-list with continuous ethical score? keep deny-list AND add scoring?) is a follow-up design decision.
- **Does not commit to specific UI mockups.** C1, C4, C5, C7 are described conceptually; layout/visual design is a separate phase.
