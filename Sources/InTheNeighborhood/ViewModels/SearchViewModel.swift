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
        case localStores
    }
    
    public init(
        coordinator: MetasearchCoordinator,
        queryEnhancer: QueryEnhancer,
        amazonSource: any SearchSource,
        googleBooksSource: any SearchSource,
        mapKitSource: any SearchSource
    ) {
        self.coordinator = coordinator
        self.queryEnhancer = queryEnhancer
        self.amazonSource = amazonSource
        self.googleBooksSource = googleBooksSource
        self.mapKitSource = mapKitSource
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
            // Launch three concurrent search threads - they update results independently
            // Don't wait for all to complete - each thread updates its results as it finishes
            print("[SearchViewModel] Starting all three search threads concurrently for query: '\(query)'")
            
            // Use async let to ensure all tasks start immediately and run concurrently
            async let webTask = searchWeb(query: query)
            async let amazonTask = searchAmazon(query: query)
            async let localTask = searchLocal(query: query)
            
            // Wait for each task to complete and update state
            _ = await webTask
            await MainActor.run {
                updateStateAfterThreadCompletion()
            }
            
            _ = await amazonTask
            await MainActor.run {
                updateStateAfterThreadCompletion()
            }
            
            _ = await localTask
            await MainActor.run {
                updateStateAfterThreadCompletion()
            }
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
    
    // Thread 1: Web search (excluding Amazon and MapKit)
    private func searchWeb(query: String) async -> [SearchResult] {
        print("[SearchViewModel] Thread 1 (Web): Starting web search for query: '\(query)'")
        do {
            let enhancedQuery = try await queryEnhancer.enhance(query: query)
            
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
            
            let searchResults = try await coordinator.search(
                query: modifiedQuery,
                excludingSources: ["amazon", "mapkit"]
            )
            
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoadingWeb = false
                }
                return []
            }
            
            await MainActor.run {
                webResults = searchResults
                isLoadingWeb = false
                // Update legacy results array
                results = webResults + amazonResults + localResults
            }
            
            return searchResults
        } catch {
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoadingWeb = false
                }
                return []
            }
            
            await MainActor.run {
                webResults = []
                isLoadingWeb = false
                // Only set error if no other results exist
                if webResults.isEmpty && amazonResults.isEmpty && localResults.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
            return []
        }
    }
    
    // Thread 2: Amazon and Google Books search (combined)
    private func searchAmazon(query: String) async -> [SearchResult] {
        print("[SearchViewModel] Thread 2 (Amazon/Google Books): Starting product search for query: '\(query)'")
        do {
            let enhancedQuery = try await queryEnhancer.enhance(query: query)
            
            // Search both Amazon and Google Books concurrently
            async let amazonTask = amazonSource.search(query: enhancedQuery)
            async let googleBooksTask = googleBooksSource.search(query: enhancedQuery)
            
            // Wait for both to complete
            let amazonSearchResults = try? await amazonTask
            let googleBooksSearchResults = try? await googleBooksTask
            
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoadingAmazon = false
                }
                return []
            }
            
            // Combine results from both sources
            var combinedResults: [SearchResult] = []
            combinedResults.append(contentsOf: amazonSearchResults ?? [])
            combinedResults.append(contentsOf: googleBooksSearchResults ?? [])
            
            await MainActor.run {
                amazonResults = combinedResults
                isLoadingAmazon = false
                // Update legacy results array
                results = webResults + amazonResults + localResults
            }
            
            print("[SearchViewModel] Thread 2: Combined \(amazonSearchResults?.count ?? 0) Amazon + \(googleBooksSearchResults?.count ?? 0) Google Books = \(combinedResults.count) total product results")
            
            return combinedResults
        } catch {
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoadingAmazon = false
                }
                return []
            }
            
            await MainActor.run {
                amazonResults = []
                isLoadingAmazon = false
            }
            return []
        }
    }
    
    // Thread 3: Local stores (LLM + MapKit)
    private func searchLocal(query: String) async -> [SearchResult] {
        print("[SearchViewModel] Thread 3 (Local): Starting local/MapKit search for query: '\(query)'")
        do {
            // Step 1: Ask LLM what store types would carry this product
            print("[SearchViewModel] Thread 3 (Local): Asking LLM for store categories for query: '\(query)'")
            let storeCategories = await queryEnhancer.determineStoreCategories(for: query)
            print("[SearchViewModel] Thread 3 (Local): LLM returned \(storeCategories.count) store categories: \(storeCategories)")
            
            // Step 2: Enhance query (for productType, priceMax, condition)
            let enhancedQuery = try await queryEnhancer.enhance(query: query)
            print("[SearchViewModel] Thread 3 (Local): Enhanced query has \(enhancedQuery.categories.count) categories from enhancement")
            
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
    
    public func refineSearch(with metadata: ProductMetadata, originalQuery: String) async {
        // Cancel previous search
        searchTask?.cancel()
        
        // Build refined query from original query and metadata for search engines
        // We'll also pass structured metadata to the LLM for better categorization
        var refinedQueryParts: [String] = [originalQuery]
        
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
        
        // Note: We don't add ISBN/SKU/ASIN to the text query as they're not useful for search engines
        // Instead, we pass them as structured metadata to the LLM
        
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
        
        searchTask = Task {
            do {
                // Enhance query with LLM, passing structured metadata for better categorization
                let enhancedQuery = try await queryEnhancer.enhance(query: refinedQuery, metadata: metadata)
                
                // For web search, use only the categories from enhance (not store categories)
                // Store categories are only used for local MapKit search
                let webQuery = enhancedQuery
                
                // Search using coordinator, excluding Amazon and MapKit sources
                // MapKit results should only appear in Local Stores tab, not Web tab
                let searchResults = try await coordinator.search(query: webQuery, excludingSources: ["amazon", "mapkit"])
                
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
