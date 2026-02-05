import Foundation
import SwiftUI
import MetasearchCore
import LLMIntegration

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
    private let queryEnhancer: QueryEnhancer
    private let amazonSource: any SearchSource
    private let googleBooksSource: any SearchSource
    private let bestBuySource: any SearchSource
    private let mapKitSource: any SearchSource
    private let searchAgent: SearchAgent?
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
        queryEnhancer: QueryEnhancer,
        amazonSource: any SearchSource,
        googleBooksSource: any SearchSource,
        bestBuySource: any SearchSource,
        mapKitSource: any SearchSource,
        searchAgent: SearchAgent? = nil
    ) {
        self.coordinator = coordinator
        self.queryEnhancer = queryEnhancer
        self.amazonSource = amazonSource
        self.googleBooksSource = googleBooksSource
        self.bestBuySource = bestBuySource
        self.mapKitSource = mapKitSource
        self.searchAgent = searchAgent
    }
    
    /// Cancels any in-flight search (e.g. when app goes to background to avoid Metal GPU work).
    public func cancelInFlightSearch() {
        searchTask?.cancel()
    }
    
    public func search(query: String) async {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            state = .idle
            webResults = []
            amazonResults = []
            localResults = []
            results = []
            isLoadingWeb = false
            isLoadingAmazon = false
            isLoadingLocal = false
            return
        }
        
        state = .loading
        errorMessage = nil
        originalQuery = query
        
        // Clear previous results
        webResults = []
        amazonResults = []
        localResults = []
        results = []
        localStoreCategories = []
        
        // Set loading states
        isLoadingWeb = true
        isLoadingAmazon = true
        isLoadingLocal = true
        
        searchTask = Task {
            if SettingsManager.shared.useAgentSearch, let agent = searchAgent {
                // Agent-driven search: LLM chooses tools; fallback to classic on parse failure or max iterations
                print("[SearchViewModel] Using agent search for query: '\(query)'")
                // Run product search in parallel so we always get Best Buy, Amazon, Google Books results
                // even when the LLM only calls search_web and never search_products
                let productSearchTask = Task { [weak self] in
                    guard let self else { return }
                    let eq = EnhancedQuery(original: query, productType: nil, categories: [], priceMax: nil, condition: nil)
                    _ = await self.searchAmazon(enhancedQuery: eq)
                }
                do {
                    let result = try await agent.run(
                        userQuery: query,
                        metadata: nil,
                        classicFallback: { [weak self] fallbackQuery in
                            await self?.runClassicSearch(query: fallbackQuery) ?? AgentSearchResult(
                                webResults: [], amazonResults: [], localResults: [], localStoreCategories: []
                            )
                        },
                        onToolResult: { [weak self] tool, results in
                            Task { @MainActor in
                                guard let self else { return }
                                switch tool {
                                case "search_web":
                                    self.webResults = results
                                case "search_products":
                                    self.amazonResults = results
                                case "search_local_stores":
                                    self.localResults = results
                                default:
                                    break
                                }
                                self.results = self.webResults + self.amazonResults + self.localResults
                            }
                        }
                    )
                    guard !Task.isCancelled else { return }
                    await productSearchTask.value
                    guard !Task.isCancelled else { return }
                    // Prefer larger counts so we never overwrite incremental streaming with a stale snapshot
                    applyFinalResults(
                        webResults: result.webResults,
                        amazonResults: result.amazonResults.isEmpty ? amazonResults : result.amazonResults,
                        localResults: result.localResults,
                        localStoreCategories: result.localStoreCategories
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    let fallback = await runClassicSearch(query: query)
                    applyFinalResults(
                        webResults: fallback.webResults,
                        amazonResults: fallback.amazonResults,
                        localResults: fallback.localResults,
                        localStoreCategories: fallback.localStoreCategories
                    )
                    if webResults.isEmpty && amazonResults.isEmpty && localResults.isEmpty {
                        errorMessage = error.localizedDescription
                    }
                }
                isLoadingWeb = false
                isLoadingAmazon = false
                isLoadingLocal = false
                state = .loaded
                return
            }
            
            // Classic path: shared enhance + determineStoreCategories, then three concurrent search threads
            print("[SearchViewModel] Starting shared enhance and determineStoreCategories for query: '\(query)'")
            async let enhancedTask = queryEnhancer.enhance(query: query)
            async let storeCategoriesTask = queryEnhancer.determineStoreCategories(for: query)
            
            let enhancedQuery: EnhancedQuery
            let storeCategories: [String]
            do {
                enhancedQuery = try await enhancedTask
                storeCategories = await storeCategoriesTask
                print("[SearchViewModel] Shared enhance done; store categories: \(storeCategories)")
            } catch {
                guard !Task.isCancelled else { return }
                // Fallback to basic query on enhance failure
                enhancedQuery = EnhancedQuery(original: query, productType: nil, categories: [], priceMax: nil, condition: nil)
                storeCategories = []
            }
            
            guard !Task.isCancelled else { return }
            
            print("[SearchViewModel] Starting all three search threads concurrently for query: '\(query)'")
            async let webTask = searchWeb(enhancedQuery: enhancedQuery)
            async let amazonTask = searchAmazon(enhancedQuery: enhancedQuery)
            async let localTask = searchLocal(enhancedQuery: enhancedQuery, storeCategories: storeCategories)
            
            _ = await webTask
            await MainActor.run { updateStateAfterThreadCompletion() }
            _ = await amazonTask
            await MainActor.run { updateStateAfterThreadCompletion() }
            _ = await localTask
            await MainActor.run { updateStateAfterThreadCompletion() }
        }
    }
    
    /// Runs web, product, and local search for the given query and returns combined result (used for agent fallback).
    private func runClassicSearch(query: String) async -> AgentSearchResult {
        // Shared enhance + determineStoreCategories (same as classic path)
        async let enhancedTask = queryEnhancer.enhance(query: query)
        async let storeCategoriesTask = queryEnhancer.determineStoreCategories(for: query)
        let enhancedQuery: EnhancedQuery
        let storeCategories: [String]
        do {
            enhancedQuery = try await enhancedTask
            storeCategories = await storeCategoriesTask
        } catch {
            enhancedQuery = EnhancedQuery(original: query, productType: nil, categories: [], priceMax: nil, condition: nil)
            storeCategories = []
        }
        
        async let w = searchWeb(enhancedQuery: enhancedQuery)
        async let a = searchAmazon(enhancedQuery: enhancedQuery)
        async let l = searchLocal(enhancedQuery: enhancedQuery, storeCategories: storeCategories)
        _ = await w
        _ = await a
        _ = await l
        return AgentSearchResult(
            webResults: webResults,
            amazonResults: amazonResults,
            localResults: localResults,
            localStoreCategories: localStoreCategories
        )
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
    
    /// Applies final result arrays without overwriting with a smaller set, so incremental streaming is never erased.
    private func applyFinalResults(
        webResults newWeb: [SearchResult],
        amazonResults newAmazon: [SearchResult],
        localResults newLocal: [SearchResult],
        localStoreCategories newCategories: [String]
    ) {
        if newWeb.count >= webResults.count { webResults = newWeb }
        if newAmazon.count >= amazonResults.count { amazonResults = newAmazon }
        if newLocal.count >= localResults.count { localResults = newLocal }
        if !newCategories.isEmpty { localStoreCategories = newCategories }
        results = webResults + amazonResults + localResults
    }
    
    // Thread 1: Web search (excluding Amazon, MapKit, and Google Books; products section handles Google Books)
    // Uses streaming coordinator to display results incrementally as each source completes
    private func searchWeb(enhancedQuery: EnhancedQuery) async -> [SearchResult] {
        print("[SearchViewModel] Thread 1 (Web): Starting streaming web search for query: '\(enhancedQuery.original)'")
        // If we have indications that the product is a book, append "bookshop.org" to the query
        let isBook = isBookProduct(enhancedQuery: enhancedQuery)
        let modifiedQuery: EnhancedQuery
        if isBook {
            let modifiedOriginal = "\(enhancedQuery.original) bookshop.org"
            modifiedQuery = EnhancedQuery(
                original: modifiedOriginal,
                productType: enhancedQuery.productType,
                categories: enhancedQuery.categories,
                priceMax: enhancedQuery.priceMax,
                condition: enhancedQuery.condition
            )
            print("[SearchViewModel] Thread 1 (Web): Detected book product, appending 'bookshop.org' to query: '\(modifiedOriginal)'")
        } else {
            modifiedQuery = enhancedQuery
        }
        
        await coordinator.searchStreaming(
            query: modifiedQuery,
            excludingSources: ["amazon", "mapkit", "googlebooks"],
            onResults: { [weak self] _, batchResults in
                Task { @MainActor in
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    // Deduplicate: filter out results we already have
                    let existingIds = Set(self.webResults.map { $0.id })
                    let newResults = batchResults.filter { !existingIds.contains($0.id) }
                    if !newResults.isEmpty {
                        self.webResults.append(contentsOf: newResults)
                        self.results = self.webResults + self.amazonResults + self.localResults
                    }
                }
            }
        )
        
        // Yield to MainActor so any pending onResults Task { @MainActor } blocks run
        // before we read webResults. Otherwise we can return (and callers can assign)
        // a stale snapshot and overwrite the incremental updates already displayed.
        await MainActor.run { }
        
        guard !Task.isCancelled else {
            isLoadingWeb = false
            return []
        }
        
        isLoadingWeb = false
        results = webResults + amazonResults + localResults
        return webResults
    }
    
    // Thread 2: Amazon and Google Books search (combined)
    // Updates amazonResults incrementally as each source completes
    private func searchAmazon(enhancedQuery: EnhancedQuery) async -> [SearchResult] {
        print("[SearchViewModel] Thread 2 (Amazon/Google Books/Best Buy): Starting product search for query: '\(enhancedQuery.original)'")
        // Search all product sources concurrently; display results as each completes
        var combinedResults: [SearchResult] = []
        await withTaskGroup(of: [SearchResult].self) { group in
            group.addTask { (try? await self.amazonSource.search(query: enhancedQuery)) ?? [] }
            group.addTask { (try? await self.googleBooksSource.search(query: enhancedQuery)) ?? [] }
            group.addTask { (try? await self.bestBuySource.search(query: enhancedQuery)) ?? [] }
            
            for await batchResults in group {
                guard !Task.isCancelled else { break }
                if !batchResults.isEmpty {
                    let existingIds = Set(combinedResults.map { $0.id })
                    let newResults = batchResults.filter { !existingIds.contains($0.id) }
                    if !newResults.isEmpty {
                        combinedResults.append(contentsOf: newResults)
                        amazonResults = combinedResults
                        results = webResults + amazonResults + localResults
                    }
                }
            }
        }
        
        guard !Task.isCancelled else {
            isLoadingAmazon = false
            return []
        }
        
        amazonResults = combinedResults
        isLoadingAmazon = false
        results = webResults + amazonResults + localResults
        
        print("[SearchViewModel] Thread 2: Product results count = \(combinedResults.count)")
        
        return combinedResults
    }
    
    // Thread 3: Local stores (MapKit; enhancedQuery and storeCategories provided by caller)
    private func searchLocal(enhancedQuery: EnhancedQuery, storeCategories: [String]) async -> [SearchResult] {
        print("[SearchViewModel] Thread 3 (Local): Starting local/MapKit search for query: '\(enhancedQuery.original)'")
        do {
            print("[SearchViewModel] Thread 3 (Local): Using \(storeCategories.count) store categories: \(storeCategories)")
            
            // Use storeCategories if available (product-specific), otherwise fall back to enhancedQuery.categories
            // Filter out known example categories from enhance prompt that may be incorrectly returned
            let categoriesToUse: [String]
            if !storeCategories.isEmpty {
                // Prefer storeCategories as they are product-specific and avoid example categories
                categoriesToUse = storeCategories
                print("[SearchViewModel] Thread 3 (Local): Using store categories: \(categoriesToUse)")
            } else {
                // Fall back to enhancedQuery.categories, but filter out known example categories
                // that are commonly returned incorrectly (e.g., "furniture store" for non-furniture items)
                let exampleCategories = Set(["furniture store", "electronics store"])
                categoriesToUse = enhancedQuery.categories.filter { !exampleCategories.contains($0.lowercased()) }
                print("[SearchViewModel] Thread 3 (Local): Store categories empty, using filtered enhance categories: \(categoriesToUse)")
            }
            
            // Create new EnhancedQuery with selected categories
            let localQuery = EnhancedQuery(
                original: enhancedQuery.original,
                productType: enhancedQuery.productType,
                categories: categoriesToUse,
                priceMax: enhancedQuery.priceMax,
                condition: enhancedQuery.condition
            )
            
            // Step 3: Search MapKit
            print("[SearchViewModel] Thread 3 (Local): Searching MapKit with query: '\(localQuery.original)', categories: \(localQuery.categories)")
            let searchResults = try await mapKitSource.search(query: localQuery)
            print("[SearchViewModel] Thread 3 (Local): MapKit search returned \(searchResults.count) results")
            
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoadingLocal = false
                }
                return []
            }
            
            await MainActor.run {
                localResults = searchResults
                localStoreCategories = categoriesToUse
                isLoadingLocal = false
                // Update legacy results array
                results = webResults + amazonResults + localResults
            }
            
            return searchResults
        } catch {
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoadingLocal = false
                }
                return []
            }
            
            await MainActor.run {
                localResults = []
                isLoadingLocal = false
            }
            return []
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
    
    /// Refines the current search using product metadata and optional full result title (e.g. from the card the user tapped).
    /// - Parameters:
    ///   - metadata: Product metadata (ISBN, SKU, author, brand, etc.).
    ///   - originalQuery: The query that produced the results.
    ///   - resultTitle: Optional full product title from the result card; when provided, used to build a more specific refined query.
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
        
        guard !refinedQuery.isEmpty else {
            return
        }
        
        state = .loading
        errorMessage = nil
        self.originalQuery = refinedQuery
        webResults = []
        amazonResults = []
        localResults = []
        results = []
        localStoreCategories = []
        isLoadingWeb = true
        isLoadingAmazon = true
        isLoadingLocal = true
        
        searchTask = Task {
            if SettingsManager.shared.useAgentSearch, let agent = searchAgent {
                let productSearchTask = Task { [weak self] in
                    guard let self else { return }
                    let eq = EnhancedQuery(original: refinedQuery, productType: nil, categories: [], priceMax: nil, condition: nil)
                    _ = await self.searchAmazon(enhancedQuery: eq)
                }
                do {
                    let result = try await agent.run(
                        userQuery: refinedQuery,
                        metadata: metadata,
                        classicFallback: { [weak self] fallbackQuery in
                            await self?.runClassicSearch(query: fallbackQuery) ?? AgentSearchResult(
                                webResults: [], amazonResults: [], localResults: [], localStoreCategories: []
                            )
                        },
                        onToolResult: { [weak self] tool, results in
                            Task { @MainActor in
                                guard let self else { return }
                                switch tool {
                                case "search_web":
                                    self.webResults = results
                                case "search_products":
                                    self.amazonResults = results
                                case "search_local_stores":
                                    self.localResults = results
                                default:
                                    break
                                }
                                self.results = self.webResults + self.amazonResults + self.localResults
                            }
                        }
                    )
                    guard !Task.isCancelled else { return }
                    await productSearchTask.value
                    guard !Task.isCancelled else { return }
                    let amazonToApply = result.amazonResults.isEmpty ? amazonResults : result.amazonResults
                    applyFinalResults(
                        webResults: result.webResults,
                        amazonResults: amazonToApply,
                        localResults: result.localResults,
                        localStoreCategories: result.localStoreCategories
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    let fallback = await runClassicSearch(query: refinedQuery)
                    applyFinalResults(
                        webResults: fallback.webResults,
                        amazonResults: fallback.amazonResults,
                        localResults: fallback.localResults,
                        localStoreCategories: fallback.localStoreCategories
                    )
                    if webResults.isEmpty && amazonResults.isEmpty && localResults.isEmpty {
                        errorMessage = error.localizedDescription
                    }
                }
                isLoadingWeb = false
                isLoadingAmazon = false
                isLoadingLocal = false
                state = .loaded
                return
            }
            
            do {
                // Enhance query with LLM, passing structured metadata for better categorization
                let enhancedQuery = try await queryEnhancer.enhance(query: refinedQuery, metadata: metadata)
                
                // For web search, use only the categories from enhance (not store categories)
                // Store categories are only used for local MapKit search
                let webQuery = enhancedQuery
                
                // Search using coordinator, excluding Amazon, MapKit, and Google Books sources
                // MapKit results should only appear in Local Stores tab, not Web tab
                // Google Books is handled in products section
                let searchResults = try await coordinator.search(query: webQuery, excludingSources: ["amazon", "mapkit", "googlebooks"])
                
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    return
                }
                
                // Also update local results using the same logic as initial search
                // This ensures MapKit uses determineStoreCategories (not example categories from enhance)
                Task {
                    do {
                        // Step 1: Ask LLM what store types would carry this product
                        // Pass metadata to help with better categorization
                        let storeCategories = await queryEnhancer.determineStoreCategories(for: refinedQuery, metadata: metadata)
                        
                        // Step 2: Use store categories if available, otherwise fall back to enhancedQuery.categories
                        // Filter out known example categories from enhance prompt
                        let categoriesToUse: [String]
                        if !storeCategories.isEmpty {
                            categoriesToUse = storeCategories
                        } else {
                            let exampleCategories = Set(["furniture store", "electronics store"])
                            categoriesToUse = enhancedQuery.categories.filter { !exampleCategories.contains($0.lowercased()) }
                        }
                        
                        // Create EnhancedQuery with selected categories
                        let localQuery = EnhancedQuery(
                            original: enhancedQuery.original,
                            productType: enhancedQuery.productType,
                            categories: categoriesToUse,
                            priceMax: enhancedQuery.priceMax,
                            condition: enhancedQuery.condition
                        )
                        
                        // Step 3: Search MapKit with store categories only
                        let localSearchResults = try await mapKitSource.search(query: localQuery)
                        
                        guard !Task.isCancelled else {
                            return
                        }
                        
                        await MainActor.run {
                            localResults = localSearchResults
                            localStoreCategories = categoriesToUse
                            results = webResults + amazonResults + localResults
                        }
                    } catch {
                        // If local search fails, keep existing local results
                        // Don't update state as web search may have succeeded
                    }
                }
                
                // Keep Amazon and local results from original search, add new refined web results
                // Filter out both Amazon and MapKit results (MapKit should only be in localResults)
                let existingAmazonResults = amazonResults
                let refinedResults = searchResults.filter { 
                    $0.source.lowercased() != "amazon" && $0.source.lowercased() != "mapkit"
                }
                webResults = refinedResults
                results = webResults + existingAmazonResults + localResults
                state = .loaded
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                
                errorMessage = error.localizedDescription
                state = .error
            }
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
