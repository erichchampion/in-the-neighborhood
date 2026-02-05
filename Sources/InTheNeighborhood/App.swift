import SwiftUI
import MetasearchCore
import LLMIntegration
import SearchSources
import LocationServices

@main
struct InTheNeighborhoodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let coordinator: MetasearchCoordinator
    let queryEnhancer: QueryEnhancer
    let locationService: LocationService
    let amazonSource: any SearchSource
    let googleBooksSource: any SearchSource
    let bestBuySource: any SearchSource
    let mapKitSource: any SearchSource
    let searchAgent: SearchAgent?
    
    init() {
        // Initialize location service
        locationService = LocationService()
        
        // Initialize LLM service (llama.cpp-based, falls back to rule-based parsing)
        let llmService = LlamaCppLLMService()
        queryEnhancer = QueryEnhancer(llmService: llmService)
        
        // Initialize search sources
        mapKitSource = MapKitSearchSource(locationService: locationService)
        
        // Initialize web search sources (DuckDuckGo + Bing as separate sources for incremental display)
        let bingApiKey = APIKeys.bingAPIKey
        let duckDuckGoSource = DuckDuckGoSearchSource()
        let bingSource = BingSearchSource(apiKey: bingApiKey)
        
        let bookshopSource = BookshopSearchSource()
        let marketplaceSource = MarketplaceSearchSource()
        amazonSource = AmazonSearchSource()
        
        // Initialize Google Books source (no API key required - works without authentication)
        googleBooksSource = GoogleBooksSearchSource(apiKey: nil)
        
        // Initialize Best Buy source (returns empty when no API key)
        bestBuySource = BestBuySearchSource(apiKey: APIKeys.bestbuyAPIKey)
        
        // Initialize coordinator (DuckDuckGo and Bing as separate sources enable incremental display)
        coordinator = MetasearchCoordinator(sources: [
            mapKitSource,
            duckDuckGoSource,
            bingSource,
            bookshopSource,
            marketplaceSource,
            amazonSource,
            googleBooksSource
        ])
        
        // Tool executor: wire coordinator and sources (async closures; errors return empty)
        let toolExecutor = SearchToolExecutor(
            webSearch: { [coordinator] query, excluding in
                (try? await coordinator.search(query: query, excludingSources: excluding)) ?? []
            },
            productSearch: { [amazonSource, googleBooksSource, bestBuySource] query in
                async let a = try? amazonSource.search(query: query)
                async let b = try? googleBooksSource.search(query: query)
                async let c = try? bestBuySource.search(query: query)
                let amazon = await a ?? []
                let google = await b ?? []
                let bestbuy = await c ?? []
                var combined = amazon + google + bestbuy
                // Deduplicate by id
                var seen = Set<String>()
                combined = combined.filter { seen.insert($0.id).inserted }
                return combined
            },
            localSearch: { [mapKitSource] query in
                (try? await mapKitSource.search(query: query)) ?? []
            }
        )
        
        // Agent: generate from LLM multi-turn; fallback provided by ViewModel at run time
        searchAgent = SearchAgent(
            generateFromMessages: { [llmService] messages in
                try await llmService.generateFromAgentMessages(messages: messages)
            },
            toolExecutor: toolExecutor,
            classicFallback: {
                AgentSearchResult(webResults: [], amazonResults: [], localResults: [], localStoreCategories: [])
            }
        )
    }
    
    var body: some Scene {
        WindowGroup {
            SearchView(
                coordinator: coordinator,
                queryEnhancer: queryEnhancer,
                amazonSource: amazonSource,
                googleBooksSource: googleBooksSource,
                bestBuySource: bestBuySource,
                mapKitSource: mapKitSource,
                searchAgent: searchAgent
            )
        }
    }
}
