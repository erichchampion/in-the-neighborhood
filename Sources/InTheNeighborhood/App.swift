import SwiftUI
import MetasearchCore
import SearchSources
import LocationServices

@main
struct InTheNeighborhoodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let coordinator: MetasearchCoordinator
    let locationService: LocationService
    let amazonSource: any SearchSource
    let googleBooksSource: any SearchSource
    let bestBuySource: any SearchSource
    let mapKitSource: any SearchSource
    let queryEnhancer: QueryEnhancing
    
    init() {
        // Initialize location service
        locationService = LocationService()
        
        // Initialize intelligence services
        queryEnhancer = FoundationModelQueryEnhancer()
        
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
    }
    
    var body: some Scene {
        WindowGroup {
            SearchView(
                coordinator: coordinator,
                queryEnhancer: queryEnhancer,
                amazonSource: amazonSource,
                googleBooksSource: googleBooksSource,
                bestBuySource: bestBuySource,
                mapKitSource: mapKitSource
            )
        }
    }
}
