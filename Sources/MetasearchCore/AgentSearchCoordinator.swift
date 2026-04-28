import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Agent Search Plan (Structured Output)

/// The agent produces this plan describing which sources to query and how.
/// Using @Generable so the on-device model outputs structured JSON rather than free-form text.
#if canImport(FoundationModels)
@Generable
#endif
public struct AgentSearchPlan: Sendable {

    #if canImport(FoundationModels)
    @Guide(description: "True if the query is asking for something you can buy on a website.")
    #endif
    public let searchProducts: Bool

    #if canImport(FoundationModels)
    @Guide(description: "True if the query asks about physical local stores, places, or shops nearby.")
    #endif
    public let searchLocalStores: Bool

    #if canImport(FoundationModels)
    @Guide(description: "True if the query is specifically about books, authors, ISBNs, or reading.")
    #endif
    public let searchBooks: Bool

    #if canImport(FoundationModels)
    @Guide(description: "True if the query is a general web search or informational question. Highly recommended for context, reviews, and broader info.")
    #endif
    public let searchWeb: Bool

    #if canImport(FoundationModels)
    @Guide(description: "A refined, specific search query to use when searching. May differ from the original.")
    #endif
    public let refinedQuery: String

    #if canImport(FoundationModels)
    @Guide(description: "Optional: the specific local store type to search for, e.g. 'bookstore', 'hardware store'. Leave empty if not applicable.")
    #endif
    public let localStoreType: String?

    public init(
        searchProducts: Bool = true,
        searchLocalStores: Bool = true,
        searchBooks: Bool = false,
        searchWeb: Bool = true,
        refinedQuery: String = "",
        localStoreType: String? = nil
    ) {
        self.searchProducts = searchProducts
        self.searchLocalStores = searchLocalStores
        self.searchBooks = searchBooks
        self.searchWeb = searchWeb
        self.refinedQuery = refinedQuery
        self.localStoreType = localStoreType
    }
}

// MARK: - Agent Search Coordinator

/// Intelligence-first search coordinator using FoundationModels structured output
/// to plan which sources to query for a given user query.
///
/// The on-device model generates an `AgentSearchPlan` that routes the query
/// to the appropriate combination of sources (products, local, books, web),
/// rather than running all sources in parallel regardless of relevance.
public final class AgentSearchCoordinator: @unchecked Sendable {

    private let executor: SearchToolExecutor

    public init(executor: SearchToolExecutor) {
        self.executor = executor
    }

    // MARK: - Public API

    public func search(query: String) async -> AgentSearchResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let plan = await buildSearchPlan(for: query) ?? defaultPlan(for: query)
            return await execute(plan: plan, originalQuery: query)
        }
        #endif
        return await fallbackSearch(query: query)
    }

    public func searchStreaming(
        query: String,
        onPlan: (@Sendable (AgentSearchPlan) -> Void)? = nil,
        onResults: @escaping @Sendable (String, [SearchResult]) -> Void
    ) async -> AgentSearchResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let plan = await buildSearchPlan(for: query) ?? defaultPlan(for: query)
            onPlan?(plan)
            return await executeStreaming(plan: plan, originalQuery: query, onResults: onResults)
        }
        #endif
        let plan = defaultPlan(for: query)
        onPlan?(plan)
        return await fallbackSearchStreaming(query: query, onResults: onResults)
    }

    // MARK: - Plan Generation

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func buildSearchPlan(for query: String) async -> AgentSearchPlan? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            print("[AgentSearchCoordinator] SystemLanguageModel not available.")
            return nil
        }

        let prompt = """
        Analyze this user search query and determine how to best search for it.
        The app helps find products locally (in nearby stores) rather than buying from Amazon.

        User query: "\(query)"

        Based on this query, determine:
        - Should we search local physical stores nearby?
        - Should we search online product listings? (DEFAULT: YES - always search products unless user explicitly says they don't want to buy online)
        - Is this specifically a book search?
        - Should we do a general web search? (Highly recommended for context, comparison, and verifying availability unless query is extremely specific).
        - Provide a refined search query - but ONLY refine if you can make it明显ly better. Otherwise, keep the original query exactly as-is.
        - Identify the specific local store type (e.g., 'bookstore', 'hardware store', 'grocery store', 'electronics store'). If unsure, use the main noun from the query.

        IMPORTANT RULES:
        1. Always set searchProducts to true unless user explicitly says they DON'T want to buy online.
        2. For refinedQuery: Keep it simple. If user searches "On tyranny", refinedQuery should be "On tyranny" or "On tyranny book", NOT "products near me that start with 'On tyranny'".
        3. For localStoreType: If user says "local bookstore", set localStoreType to "bookstore". If unsure, use the main product/category from the query.
        """

        do {
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt, generating: AgentSearchPlan.self)
            let plan = response.content
            print("[AgentSearchCoordinator] Agent plan — web:\(plan.searchWeb) products:\(plan.searchProducts) local:\(plan.searchLocalStores) books:\(plan.searchBooks) query:'\(plan.refinedQuery)'")
            return plan
        } catch {
            print("[AgentSearchCoordinator] Plan generation failed: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    // MARK: - Execute Plan

    private func execute(plan: AgentSearchPlan, originalQuery: String) async -> AgentSearchResult {
        let collector = SearchResultsCollector()
        var toolsUsed: [String] = []

        await withTaskGroup(of: String.self) { group in
            if plan.searchWeb {
                group.addTask {
                    let results = await self.executor.searchWeb(query: self.resolveQuery(plan: plan, originalQuery: originalQuery))
                    await collector.append(results)
                    return "web"
                }
            }
            if plan.searchProducts {
                group.addTask {
                    let results = await self.executor.searchProducts(query: self.resolveQuery(plan: plan, originalQuery: originalQuery), maxPrice: nil, condition: nil)
                    await collector.append(results)
                    return "products"
                }
            }
            if plan.searchLocalStores {
                let storeType = resolveLocalStoreType(plan: plan, originalQuery: originalQuery)
                group.addTask {
                    let results = await self.executor.searchLocalStores(storeType: storeType, radiusKm: nil)
                    await collector.append(results)
                    return "local_stores"
                }
            }
            if plan.searchBooks {
                group.addTask {
                    let results = await self.executor.searchBooks(query: self.resolveQuery(plan: plan, originalQuery: originalQuery))
                    await collector.append(results)
                    return "books"
                }
            }

            for await tool in group {
                toolsUsed.append(tool)
            }
        }

        return AgentSearchResult(results: await collector.allResults, summary: nil, toolsUsed: toolsUsed, plan: plan)
    }

    private func executeStreaming(plan: AgentSearchPlan, originalQuery: String, onResults: @escaping @Sendable (String, [SearchResult]) -> Void) async -> AgentSearchResult {
        var toolsUsed: [String] = []
        let collector = SearchResultsCollector()

        await withTaskGroup(of: String.self) { group in
            if plan.searchWeb {
                group.addTask {
                    let query = self.resolveQuery(plan: plan, originalQuery: originalQuery)
                    await self.executor.searchWebStreaming(query: query) { sourceId, results in
                        onResults(sourceId, results)
                        Task { await collector.append(results) }
                    }
                    return "web"
                }
            }
            if plan.searchProducts {
                group.addTask {
                    let query = self.resolveQuery(plan: plan, originalQuery: originalQuery)
                    await self.executor.searchProductsStreaming(query: query, maxPrice: nil, condition: nil) { sourceId, results in
                        onResults(sourceId, results)
                        Task { await collector.append(results) }
                    }
                    return "products"
                }
            }
            if plan.searchLocalStores {
                let storeType = resolveLocalStoreType(plan: plan, originalQuery: originalQuery)
                group.addTask {
                    await self.executor.searchLocalStoresStreaming(storeType: storeType, radiusKm: nil) { sourceId, results in
                        onResults(sourceId, results)
                        Task { await collector.append(results) }
                    }
                    return "local_stores"
                }
            }
            if plan.searchBooks {
                let bookQuery = resolveQuery(plan: plan, originalQuery: originalQuery)
                group.addTask {
                    await self.executor.searchBooksStreaming(query: bookQuery) { sourceId, results in
                        onResults(sourceId, results)
                        Task { await collector.append(results) }
                    }
                    return "books"
                }
            }

            for await tool in group {
                toolsUsed.append(tool)
            }
        }

        return AgentSearchResult(results: await collector.allResults, summary: nil, toolsUsed: toolsUsed, plan: plan)
    }

    // MARK: - Helpers

    private func resolveQuery(plan: AgentSearchPlan, originalQuery: String) -> String {
        let refined = plan.refinedQuery.isEmpty ? originalQuery : plan.refinedQuery
        if isValidQuery(refined, originalQuery: originalQuery) {
            return refined
        }
        return originalQuery
    }

    private func isValidQuery(_ query: String, originalQuery: String) -> Bool {
        let lowercased = query.lowercased()
        let originalLower = originalQuery.lowercased()
        let originalWords = Set(originalLower.split(separator: " ").map(String.init))
        let queryWords = Set(lowercased.split(separator: " ").map(String.init))
        if originalWords.isEmpty { return true }
        let matches = originalWords.intersection(queryWords)
        return matches.count >= min(2, originalWords.count)
    }

    private func resolveLocalStoreType(plan: AgentSearchPlan, originalQuery: String) -> String {
        guard let storeType = plan.localStoreType, !storeType.isEmpty else {
            return originalQuery
        }
        let invalidTypes = ["unknown", "none", "nil", "", "null"]
        if invalidTypes.contains(storeType.lowercased()) {
            return extractStoreTypeFromQuery(originalQuery)
        }
        return storeType
    }

    private func extractStoreTypeFromQuery(_ query: String) -> String {
        let lowercased = query.lowercased()
        let storeKeywords = ["bookstore", "book store", "hardware", "grocery", "supermarket", "electronics", "clothing", "shoes", "pharmacy", "restaurant", "cafe", "coffee", "pet", "toy", "furniture"]
        for keyword in storeKeywords {
            if lowercased.contains(keyword) {
                if keyword == "book store" { return "bookstore" }
                return keyword
            }
        }
        return query
    }

    private func defaultPlan(for query: String) -> AgentSearchPlan {
        AgentSearchPlan(
            searchProducts: true,
            searchLocalStores: true,
            searchBooks: false,
            searchWeb: true,
            refinedQuery: query,
            localStoreType: nil
        )
    }

    private func fallbackSearch(query: String) async -> AgentSearchResult {
        let collector = SearchResultsCollector()
        async let web = executor.searchWeb(query: query)
        async let products = executor.searchProducts(query: query, maxPrice: nil, condition: nil)
        async let local = executor.searchLocalStores(storeType: query, radiusKm: nil)
        let (w, p, l) = await (web, products, local)
        await collector.append(w)
        await collector.append(p)
        await collector.append(l)
        return AgentSearchResult(results: await collector.allResults, summary: nil, toolsUsed: ["web", "products", "local_stores"])
    }

    private func fallbackSearchStreaming(query: String, onResults: @escaping @Sendable (String, [SearchResult]) -> Void) async -> AgentSearchResult {
        let collector = SearchResultsCollector()
        var toolsUsed: [String] = []
        
        await withTaskGroup(of: String.self) { group in
            group.addTask {
                await self.executor.searchWebStreaming(query: query) { sourceId, results in
                    onResults(sourceId, results)
                    Task { await collector.append(results) }
                }
                return "web"
            }
            group.addTask {
                await self.executor.searchProductsStreaming(query: query, maxPrice: nil, condition: nil) { sourceId, results in
                    onResults(sourceId, results)
                    Task { await collector.append(results) }
                }
                return "products"
            }
            group.addTask {
                await self.executor.searchLocalStoresStreaming(storeType: query, radiusKm: nil) { sourceId, results in
                    onResults(sourceId, results)
                    Task { await collector.append(results) }
                }
                return "local_stores"
            }
            
            for await tool in group {
                toolsUsed.append(tool)
            }
        }
        
        return AgentSearchResult(results: await collector.allResults, summary: nil, toolsUsed: toolsUsed)
    }
}

// MARK: - Result Type

public struct AgentSearchResult: Sendable {
    public let results: [SearchResult]
    public let summary: String?
    public let toolsUsed: [String]
    public let plan: AgentSearchPlan?

    public init(results: [SearchResult], summary: String?, toolsUsed: [String], plan: AgentSearchPlan? = nil) {
        self.results = results
        self.summary = summary
        self.toolsUsed = toolsUsed
        self.plan = plan
    }
}
