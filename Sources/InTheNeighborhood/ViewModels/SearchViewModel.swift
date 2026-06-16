import Foundation
import SwiftUI
import MetasearchCore

@MainActor
public class SearchViewModel: ObservableObject {
    @Published public var searchText = ""
    @Published public var state: SearchState = .idle
    @Published public var results: [SearchResult] = [] // Legacy - kept for backward compatibility
    /// C1: intent-shaped result buckets.
    /// - `local`  — geo-tagged results (MapKit / Nominatim / Overpass non-repair)
    /// - `online` — web + product results (DuckDuckGo / Bing / Bookshop / Amazon-metadata / Open Facts)
    /// - `borrow` — library sources (Open Library / DPLA / Internet Archive)
    /// - `repair` — Overpass results with a repair-tag signal
    @Published public var localResults: [SearchResult] = []
    @Published public var onlineResults: [SearchResult] = []
    @Published public var borrowResults: [SearchResult] = []
    @Published public var repairResults: [SearchResult] = []
    @Published public var selectedTab: TabSelection = .local
    @Published public var isLoadingLocal: Bool = false
    @Published public var isLoadingOnline: Bool = false
    @Published public var isLoadingBorrow: Bool = false
    @Published public var isLoadingRepair: Bool = false
    @Published public var isRefining: Bool = false
    @Published public var errorMessage: String?
    @Published public var originalQuery: String = ""
    @Published public var localStoreCategories: [String] = []

    @Published public var agentSummary: String? = nil

    private let coordinator: MetasearchCoordinator
    private let agentCoordinator: AgentSearchCoordinator
    private let queryEnhancer: QueryEnhancing
    private var searchTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.5 // seconds

    public enum SearchState {
        case idle
        case loading
        case loaded
        case error
    }

    /// C1: intent-driven tabs. Each case names a *user intent* — "I want
    /// to buy locally / borrow this / get this repaired / find an
    /// ethical online source" — rather than a search-source category.
    public enum TabSelection {
        case local       // was .localStores
        case online      // replaces .web + .products
        case borrow      // was .library
        case repair      // new
    }

    /// Classifies a result into its intent tab. Used by both the
    /// agent-driven and standard search paths so the routing rule
    /// lives in exactly one place. `nonisolated` and `static` so it's
    /// trivially unit-testable.
    nonisolated public static func tab(for result: SearchResult) -> TabSelection {
        // Library sources always feed the Borrow tab regardless of category.
        if result.source == SourceIdentifier.openlibrary
            || result.source == SourceIdentifier.dpla
            || result.source == SourceIdentifier.internetarchive {
            return .borrow
        }
        // Any source that flagged this result as repair-shaped (today
        // only Overpass via OverpassTagMap.categoryTag) feeds Repair.
        if result.metadata["category_tag"] as? String == "repair" {
            return .repair
        }
        // Borrow-shaped local results (tool libraries, libraries of things,
        // little free libraries) join the digitized-book sources in Borrow.
        if result.metadata["category_tag"] as? String == "borrow" {
            return .borrow
        }
        // Anything else geo-tagged is Local.
        if result.sourceType == .local {
            return .local
        }
        // Web + product results fall to Online.
        return .online
    }
    
    public init(
        coordinator: MetasearchCoordinator,
        agentCoordinator: AgentSearchCoordinator? = nil,
        queryEnhancer: QueryEnhancing,
        allSources: [any SearchSource]
    ) {
        self.coordinator = coordinator
        self.agentCoordinator = agentCoordinator ?? AgentSearchCoordinator(
            executor: SearchToolExecutor(sources: allSources, denyListFilter: SettingsManager.shared.denyList)
        )
        self.queryEnhancer = queryEnhancer
    }
    
    /// Cancels any in-flight search (e.g. when app goes to background to avoid Metal GPU work).
    public func cancelInFlightSearch() {
        searchTask?.cancel()
    }
    
    public func search(query: String) async {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            clearResults()
            return
        }
        
        startNewSearch(originalQuery: query)
        agentSummary = nil
        
        searchTask = Task {
            if UserDefaults.standard.bool(forKey: SettingsManager.useAgentSearchKey) {
                // Agent-driven search: LLM selects which tools to invoke
                let agentResult = await agentCoordinator.searchStreaming(
                    query: query,
                    onPlan: { [weak self] (plan: AgentSearchPlan) in
                        Task { @MainActor in
                            if let localType = plan.localStoreType, !localType.isEmpty {
                                self?.localStoreCategories = [localType]
                            }
                        }
                    },
                    onResults: { [weak self] (sourceIdentifier: String, batchResults: [SearchResult]) in
                    Task { @MainActor in
                        guard let self else { return }
                        guard !Task.isCancelled else { return }
                        
                        let existingIds = Set(self.results.map { $0.id })
                        let newResults = batchResults.filter { !existingIds.contains($0.id) }
                        
                        guard !newResults.isEmpty else { return }
                        
                        // C1: route each new result to its intent tab via the
                        // shared `tab(for:)` classifier.
                        for result in newResults {
                            switch Self.tab(for: result) {
                            case .borrow:
                                self.borrowResults.append(result)
                                self.isLoadingBorrow = false
                            case .repair:
                                self.repairResults.append(result)
                                self.isLoadingRepair = false
                            case .local:
                                self.localResults.append(result)
                                self.isLoadingLocal = false
                            case .online:
                                self.onlineResults.append(result)
                                self.isLoadingOnline = false
                            }
                            self.results.append(result)
                        }
                    }
                })

                await MainActor.run {
                    self.agentSummary = agentResult.summary
                    if let plan = agentResult.plan, let localType = plan.localStoreType, !localType.isEmpty {
                        self.localStoreCategories = [localType]
                    }
                    self.isLoadingLocal = false
                    self.isLoadingOnline = false
                    self.isLoadingBorrow = false
                    self.isLoadingRepair = false
                    self.updateStateAfterThreadCompletion()
                }
            } else {
                // Standard parallel search via MetasearchCoordinator
                let enhancedQuery = (try? await queryEnhancer.enhanceQuery(query)) ?? EnhancedQuery(original: query, productType: nil, categories: [], priceMax: nil, condition: nil)
                
                await MainActor.run {
                    self.localStoreCategories = enhancedQuery.categories
                }
                
                await executeUnifiedSearch(query: enhancedQuery)
            }
        }
    }

    private func startNewSearch(originalQuery: String) {
        state = .loading
        errorMessage = nil
        self.originalQuery = originalQuery

        localResults = []
        onlineResults = []
        borrowResults = []
        repairResults = []
        results = []
        localStoreCategories = []

        isLoadingLocal = true
        isLoadingOnline = true
        isLoadingBorrow = true
        isLoadingRepair = true
    }

    private func startRefinedSearch(originalQuery: String) {
        state = .loading
        errorMessage = nil
        self.originalQuery = originalQuery

        onlineResults = []
        borrowResults = []
        repairResults = []
        // PRESERVE localResults
        // PRESERVE localStoreCategories

        // Remove non-local results from `results`; keep local in place.
        results = localResults

        isLoadingOnline = true
        isLoadingBorrow = true
        isLoadingRepair = true
        isLoadingLocal = false // Do not show loading for local since we are skipping it
    }

    private func executeUnifiedSearch(query: EnhancedQuery, excludeLocal: Bool = false) async {
        guard !Task.isCancelled else { return }
        
        print("[SearchViewModel] Executing unified MetasearchCoordinator stream for query: '\(query.original)'")
        
        let localStores = excludeLocal ? self.localStoreCategories : query.categories
        
        await coordinator.searchStreaming(
            query: query,
            excludingSources: [],
            excludeLocal: excludeLocal
        ) { [weak self] sourceIdentifier, batchResults in
            Task { @MainActor in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                
                let existingIds = Set(self.results.map { $0.id })
                let newResults = batchResults.filter { !existingIds.contains($0.id) }
                
                guard !newResults.isEmpty else { return }
                
                // C1: route each result individually to its intent tab.
                // The old code routed by inspecting `first.category`,
                // which forced all results in a batch into the same
                // bucket — wrong when a batch mixes (e.g.) repair
                // shops and non-repair shops from one Overpass call.
                for result in newResults {
                    switch Self.tab(for: result) {
                    case .borrow:
                        self.borrowResults.append(result)
                        self.isLoadingBorrow = false
                    case .repair:
                        self.repairResults.append(result)
                        self.isLoadingRepair = false
                    case .local:
                        if !excludeLocal {
                            self.localResults.append(result)
                            self.localStoreCategories = localStores
                            self.isLoadingLocal = false
                        }
                    case .online:
                        self.onlineResults.append(result)
                        self.isLoadingOnline = false
                    }
                }

                self.results = self.localResults + self.onlineResults + self.borrowResults + self.repairResults
                self.updateStateAfterThreadCompletion()
            }
        }

        await MainActor.run {
            self.isLoadingOnline = false
            self.isLoadingBorrow = false
            self.isLoadingRepair = false
            if !excludeLocal {
                self.isLoadingLocal = false
            }
            self.updateStateAfterThreadCompletion()
        }
    }
    
    /// Updates the overall state after a search thread completes
    /// Transitions to .loaded when all threads are done OR when we have results and at least one thread is done
    private func updateStateAfterThreadCompletion() {
        let allThreadsComplete = !isLoadingLocal
            && !isLoadingOnline
            && !isLoadingBorrow
            && !isLoadingRepair
        let hasResults = !localResults.isEmpty
            || !onlineResults.isEmpty
            || !borrowResults.isEmpty
            || !repairResults.isEmpty

        if allThreadsComplete {
            // All threads are done - transition to loaded
            state = .loaded
        } else if hasResults && state == .loading {
            // We have some results and at least one thread is still running
            // Keep state as loading so UI shows partial results with loading indicators
            // The UI already handles showing results while loading
        }
    }
    
    public func debouncedSearch() {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            state = .idle
            results = []
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            
            guard !Task.isCancelled else {
                return
            }
            
            await search(query: searchText)
        }
    }
    
    public func clearResults() {
        searchTask?.cancel()
        searchText = ""
        state = .idle
        results = []
        localResults = []
        onlineResults = []
        borrowResults = []
        repairResults = []
        localStoreCategories = []
        errorMessage = nil
    }

    /// Entry point for the barcode scanner. Routes the scanned payload to a
    /// search-text string (ISBN-prefixed for books, raw otherwise) and runs
    /// the normal search flow. Pulling the routing into BarcodeRouter keeps
    /// it independently testable.
    public func handleScannedBarcode(_ code: String) async {
        searchText = BarcodeRouter.route(code)
        await search(query: searchText)
    }
    
    public func refineSearch(with metadata: ProductMetadata, originalQuery: String, resultTitle: String? = nil) async {
        print("[SearchViewModel] refineSearch called — originalQuery: '\(originalQuery)', resultTitle: '\(resultTitle ?? "")', hasMetadata: \(!metadata.isEmpty)")
        
        // Cancel previous search
        searchTask?.cancel()
        
        // Build refined query: prefer full product title when provided, then add original query and metadata
        var refinedQueryParts: [String] = []
        if let title = resultTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            refinedQueryParts.append(title)
        }
        refinedQueryParts.append(originalQuery)
        
        // Add brand/manufacturer if available
        if let brand = metadata.brand {
            refinedQueryParts.append(brand)
        }
        
        // Add author if available (for books)
        if let author = metadata.author {
            refinedQueryParts.append(author)
        }
        
        // Add artist if available (for media)
        if let artist = metadata.artist {
            refinedQueryParts.append(artist)
        }
        
        // Add concrete identifiers when available (ISBN, SKU) for more precise search
        if let isbn = metadata.isbn {
            refinedQueryParts.append(isbn)
        }
        if let sku = metadata.sku {
            refinedQueryParts.append(sku)
        }
        
        // Combine parts, remove duplicates, and trim
        var seen = Set<String>()
        let refinedQuery = refinedQueryParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
            .joined(separator: " ")
        
        guard !refinedQuery.isEmpty else { return }
        
        startRefinedSearch(originalQuery: refinedQuery)
        
        // Automatically switch to the Online tab to show new comprehensive results
        // (refinement is product/web-shaped, not local-shaped).
        selectedTab = .online
        
        searchTask = Task {
            let enhancedQuery = (try? await queryEnhancer.enhanceQuery(refinedQuery)) ?? EnhancedQuery(original: refinedQuery, productType: nil, categories: [], priceMax: nil, condition: nil)
            await executeUnifiedSearch(query: enhancedQuery, excludeLocal: true)
        }
        
        await searchTask?.value
    }
    }
