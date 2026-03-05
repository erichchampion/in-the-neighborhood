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
    @Published public var localResults: [SearchResult] = []
    @Published public var selectedTab: TabSelection = .web
    @Published public var isLoadingWeb: Bool = false
    @Published public var isLoadingAmazon: Bool = false
    @Published public var isLoadingLocal: Bool = false
    @Published public var errorMessage: String?
    @Published public var originalQuery: String = ""
    @Published public var localStoreCategories: [String] = []
    
    private let coordinator: MetasearchCoordinator
    private let queryEnhancer: QueryEnhancing
    private let amazonSource: any SearchSource
    private let googleBooksSource: any SearchSource
    private let bestBuySource: any SearchSource
    private let mapKitSource: any SearchSource
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
        case localStores
    }
    
    public init(
        coordinator: MetasearchCoordinator,
        queryEnhancer: QueryEnhancing,
        amazonSource: any SearchSource,
        googleBooksSource: any SearchSource,
        bestBuySource: any SearchSource,
        mapKitSource: any SearchSource
    ) {
        self.coordinator = coordinator
        self.queryEnhancer = queryEnhancer
        self.amazonSource = amazonSource
        self.googleBooksSource = googleBooksSource
        self.bestBuySource = bestBuySource
        self.mapKitSource = mapKitSource
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
        
        searchTask = Task {
            // Use Foundation Models to securely parse input into an EnhancedQuery
            let enhancedQuery = (try? await queryEnhancer.enhanceQuery(query)) ?? EnhancedQuery(original: query, productType: nil, categories: [], priceMax: nil, condition: nil)
            await executeUnifiedSearch(query: enhancedQuery)
        }
    }

    private func startNewSearch(originalQuery: String) {
        state = .loading
        errorMessage = nil
        self.originalQuery = originalQuery
        
        webResults = []
        amazonResults = []
        localResults = []
        results = []
        localStoreCategories = []
        
        isLoadingWeb = true
        isLoadingAmazon = true
        isLoadingLocal = true
    }

    private func executeUnifiedSearch(query: EnhancedQuery) async {
        guard !Task.isCancelled else { return }
        
        print("[SearchViewModel] Executing unified MetasearchCoordinator stream for query: '\(query.original)'")
        
        let localStores = query.categories
        
        await coordinator.searchStreaming(
            query: query,
            excludingSources: []
        ) { [weak self] sourceIdentifier, batchResults in
            Task { @MainActor in
                guard let self else { return }
                guard !Task.isCancelled else { return }
                
                let existingIds = Set(self.results.map { $0.id })
                let newResults = batchResults.filter { !existingIds.contains($0.id) }
                
                guard !newResults.isEmpty else { return }
                
                // Route new results to visual buckets based on source
                let isProductSource = ["amazon", "bestbuy", "googlebooks"].contains(sourceIdentifier.lowercased())
                let isLocalSource = sourceIdentifier.lowercased() == "mapkit"
                
                if isProductSource {
                    self.amazonResults.append(contentsOf: newResults)
                    self.isLoadingAmazon = false
                } else if isLocalSource {
                    self.localResults.append(contentsOf: newResults)
                    self.localStoreCategories = localStores
                    self.isLoadingLocal = false
                } else {
                    self.webResults.append(contentsOf: newResults)
                    self.isLoadingWeb = false
                }
                
                self.results = self.webResults + self.amazonResults + self.localResults
                self.updateStateAfterThreadCompletion()
            }
        }
        
        await MainActor.run {
            self.isLoadingWeb = false
            self.isLoadingAmazon = false
            self.isLoadingLocal = false
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
        
        startNewSearch(originalQuery: refinedQuery)
        
        // Automatically switch back to the web tab to show new comprehensive results
        selectedTab = .web
        
        searchTask = Task {
            let enhancedQuery = (try? await queryEnhancer.enhanceQuery(refinedQuery)) ?? EnhancedQuery(original: refinedQuery, productType: nil, categories: [], priceMax: nil, condition: nil)
            await executeUnifiedSearch(query: enhancedQuery)
        }
        
        await searchTask?.value
    }
    
    // Check if a product is a book based on EnhancedQuery indicators
    private func isBookProduct(enhancedQuery: EnhancedQuery) -> Bool {
        // Check productType
        if let productType = enhancedQuery.productType,
           productType.lowercased().contains("book") {
            return true
        }
        
        // Check categories
        if enhancedQuery.categories.contains(where: { $0.lowercased().contains("book") }) {
            return true
        }
        
        // Check original query
        if enhancedQuery.original.lowercased().contains("book") {
            return true
        }
        
        return false
    }
}
