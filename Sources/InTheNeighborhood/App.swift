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
    let mapKitSource: any SearchSource
    
    init() {
        // Initialize location service
        locationService = LocationService()
        
        // Initialize LLM service (llama.cpp-based, falls back to rule-based parsing)
        let llmService: LLMService = LlamaCppLLMService()
        queryEnhancer = QueryEnhancer(llmService: llmService)
        
        // Initialize search sources
        mapKitSource = MapKitSearchSource(locationService: locationService)
        let webSearchSource = WebSearchSource()
        let bookshopSource = BookshopSearchSource()
        let marketplaceSource = MarketplaceSearchSource()
        amazonSource = AmazonSearchSource()
        
        // Initialize coordinator
        coordinator = MetasearchCoordinator(sources: [
            mapKitSource,
            webSearchSource,
            bookshopSource,
            marketplaceSource,
            amazonSource
        ])
    }
    
    var body: some Scene {
        WindowGroup {
            SearchView(
                coordinator: coordinator,
                queryEnhancer: queryEnhancer,
                amazonSource: amazonSource,
                mapKitSource: mapKitSource
            )
        }
    }
}
