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
        - Should we search online product listings?
        - Is this specifically a book search?
        - Should we do a general web search? (Highly recommended for context, comparison, and verifying availability unless query is extremely specific).
        - Provide a refined/clarified search query

        For the 'localStoreType', identify the category of store to look for locally \
        (e.g. 'bookstore', 'hardware store', 'grocery store', 'electronics store'). Leave it empty if not applicable.
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
        let effectiveQuery = plan.refinedQuery.isEmpty ? originalQuery : plan.refinedQuery
        var allResults: [SearchResult] = []
        var toolsUsed: [String] = []

        await withTaskGroup(of: ([SearchResult], String).self) { group in
            if plan.searchWeb {
                group.addTask { (await self.executor.searchWeb(query: effectiveQuery), "web") }
            }
            if plan.searchProducts {
                group.addTask { (await self.executor.searchProducts(query: effectiveQuery, maxPrice: nil, condition: nil), "products") }
            }
            if plan.searchLocalStores {
                let storeType = plan.localStoreType ?? effectiveQuery
                group.addTask { (await self.executor.searchLocalStores(storeType: storeType, radiusKm: nil), "local_stores") }
            }
            if plan.searchBooks {
                group.addTask { (await self.executor.searchBooks(query: effectiveQuery), "books") }
            }

            for await (results, tool) in group {
                allResults.append(contentsOf: results)
                toolsUsed.append(tool)
            }
        }

        return AgentSearchResult(results: allResults, summary: nil, toolsUsed: toolsUsed, plan: plan)
    }

    // MARK: - Helpers

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
        async let web = executor.searchWeb(query: query)
        async let products = executor.searchProducts(query: query, maxPrice: nil, condition: nil)
        async let local = executor.searchLocalStores(storeType: query, radiusKm: nil)
        let (w, p, l) = await (web, products, local)
        return AgentSearchResult(results: w + p + l, summary: nil, toolsUsed: ["web", "products", "local_stores"])
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
