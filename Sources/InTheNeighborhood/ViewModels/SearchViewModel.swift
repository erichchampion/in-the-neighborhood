import Foundation
import SwiftUI
import MetasearchCore

@MainActor
public class SearchViewModel: ObservableObject {
    @Published public var searchText = ""
    @Published public var state: SearchState = .idle
    @Published public var results: [SearchResult] = [] // Legacy - kept for backward compatibility
    @Published public var webResults: [SearchResult] = []
    @Published public var amazonResults: [SearchResult] = []
    @Published public var libraryResults: [SearchResult] = []
    @Published public var localResults: [SearchResult] = []
    @Published public var selectedTab: TabSelection = .web
    @Published public var isLoadingWeb: Bool = false
    @Published public var isLoadingAmazon: Bool = false
    @Published public var isLoadingLibrary: Bool = false
    @Published public var isLoadingLocal: Bool = false
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
    
    public enum TabSelection {
        case web
        case products
        case library
        case localStores
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
                        
                        // Categorize and append new results
                        for result in newResults {
                            // Always route library sources to library tab, regardless of category
                            if result.source == SourceIdentifier.openlibrary || result.source == SourceIdentifier.dpla {
                                self.libraryResults.append(result)
                                self.isLoadingLibrary = false
                            } else {
                                switch result.category {
                                case .product, .book:
                                    self.amazonResults.append(result)
                                case .local:
                                    self.localResults.append(result)
                                case .web:
                                    self.webResults.append(result)
                                }
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
                    self.isLoadingWeb = false
                    self.isLoadingAmazon = false
                    self.isLoadingLibrary = false
                    self.isLoadingLocal = false
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
        
        webResults = []
        amazonResults = []
        libraryResults = []
        localResults = []
        results = []
        localStoreCategories = []
        
        isLoadingWeb = true
        isLoadingAmazon = true
        isLoadingLibrary = true
        isLoadingLocal = true
    }

    private func startRefinedSearch(originalQuery: String) {
        state = .loading
        errorMessage = nil
        self.originalQuery = originalQuery
        
        webResults = []
        amazonResults = []
        // PRESERVE localResults
        // PRESERVE localStoreCategories
        
        // Remove old web and amazon results from `results`
        results = localResults
        
        isLoadingWeb = true
        isLoadingAmazon = true
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
                
                // Route new results to visual buckets based on category
                if let first = newResults.first {
                    // Always route library sources to library tab, regardless of category
                    if first.source == SourceIdentifier.openlibrary || first.source == SourceIdentifier.dpla {
                        self.libraryResults.append(contentsOf: newResults)
                        self.isLoadingLibrary = false
                    } else {
                        switch first.category {
                        case .product, .book:
                            self.amazonResults.append(contentsOf: newResults)
                            self.isLoadingAmazon = false
                        case .local:
                            // Only update local if we are explicitly not excluding them (e.g not refining)
                            if !excludeLocal {
                                self.localResults.append(contentsOf: newResults)
                                self.localStoreCategories = localStores
                                self.isLoadingLocal = false
                            }
                        case .web:
                            self.webResults.append(contentsOf: newResults)
                            self.isLoadingWeb = false
                        }
                    }
                }
                
                self.results = self.webResults + self.amazonResults + self.libraryResults + self.localResults
                self.updateStateAfterThreadCompletion()
            }
        }
        
        await MainActor.run {
            self.isLoadingWeb = false
            self.isLoadingAmazon = false
            if !excludeLocal {
                self.isLoadingLocal = false
            }
            self.updateStateAfterThreadCompletion()
        }
    }
    
    /// Updates the overall state after a search thread completes
    /// Transitions to .loaded when all threads are done OR when we have results and at least one thread is done
    private func updateStateAfterThreadCompletion() {
        let allThreadsComplete = !isLoadingWeb && !isLoadingAmazon && !isLoadingLocal
        let hasResults = !webResults.isEmpty || !amazonResults.isEmpty || !localResults.isEmpty
        
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
        webResults = []
        amazonResults = []
        localResults = []
        localStoreCategories = []
        errorMessage = nil
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
        
        // Automatically switch back to the web tab to show new comprehensive results
        selectedTab = .web
        
        searchTask = Task {
            let enhancedQuery = (try? await queryEnhancer.enhanceQuery(refinedQuery)) ?? EnhancedQuery(original: refinedQuery, productType: nil, categories: [], priceMax: nil, condition: nil)
            await executeUnifiedSearch(query: enhancedQuery, excludeLocal: true)
        }
        
        await searchTask?.value
    }
    }
