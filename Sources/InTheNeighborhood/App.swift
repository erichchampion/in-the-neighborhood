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
    
    init() {
        // Initialize location service
        locationService = LocationService()
        
        // Initialize LLM service (llama.cpp-based, falls back to rule-based parsing)
        let llmService: LLMService = LlamaCppLLMService()
        queryEnhancer = QueryEnhancer(llmService: llmService)
        
        // Initialize search sources
        let mapKitSource = MapKitSearchSource(locationService: locationService)
        let webSearchSource = WebSearchSource()
        let bookshopSource = BookshopSearchSource()
        let marketplaceSource = MarketplaceSearchSource()
        
        // Initialize coordinator
        coordinator = MetasearchCoordinator(sources: [
            mapKitSource,
            webSearchSource,
            bookshopSource,
            marketplaceSource
        ])
    }
    
    var body: some Scene {
        WindowGroup {
            SearchView(
                coordinator: coordinator,
                queryEnhancer: queryEnhancer
            )
        }
    }
}
