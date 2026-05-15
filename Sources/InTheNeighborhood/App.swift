import SwiftUI
import SwiftData
import MetasearchCore
import SearchSources
import LocationServices
import AppIntents
import SharedModels

@main
struct InTheNeighborhoodApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let coordinator: MetasearchCoordinator
    let locationService: LocationService
    let amazonSource: any SearchSource
    let googleBooksSource: any SearchSource
    let bestBuySource: any SearchSource
    let mapKitSource: any SearchSource
    let dplaSource: any SearchSource
    let nominatimSource: any SearchSource
    let overpassSource: any SearchSource
    let internetArchiveSource: any SearchSource
    let openFoodFactsSource: any SearchSource
    let openBeautyFactsSource: any SearchSource
    let openProductsFactsSource: any SearchSource
    let openPetFoodFactsSource: any SearchSource
    let queryEnhancer: QueryEnhancing
    
    init() {
        // Register App Shortcuts
        if #available(iOS 16.0, *) {
            SearchShortcutsProvider.updateAppShortcutParameters()
        }
        
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
        
        // Initialize DPLA source (library search)
        dplaSource = DPLASearchSource(apiKey: APIKeys.dplaAPIKey ?? "")
        
        // Initialize Nominatim (OpenStreetMap) source for local search
        nominatimSource = NominatimSearchSource(locationService: locationService)

        // Initialize Overpass (OpenStreetMap) source for tag-based local discovery
        // — finds specialty shops by their OSM `shop=…` / `amenity=…` tags.
        overpassSource = OverpassSearchSource(locationService: locationService)

        // Initialize Internet Archive source — surfaces free digitized
        // texts, audio, and films in the Library tab (B4).
        internetArchiveSource = InternetArchiveSearchSource()

        // Initialize Open Facts sources (B2) — open, key-less product
        // databases with Nutri-Score / Eco-Score / Nova metadata. Four
        // sibling hosts share one source class.
        openFoodFactsSource     = OpenFactsSearchSource.food()
        openBeautyFactsSource   = OpenFactsSearchSource.beauty()
        openProductsFactsSource = OpenFactsSearchSource.products()
        openPetFoodFactsSource  = OpenFactsSearchSource.petFood()

        // Initialize coordinator (DuckDuckGo and Bing as separate sources enable incremental display)
        let allSources: [any SearchSource] = [
            mapKitSource,
            nominatimSource,
            overpassSource,
            duckDuckGoSource,
            bingSource,
            bookshopSource,
            marketplaceSource,
            amazonSource,
            googleBooksSource,
            OpenLibrarySearchSource(),
            dplaSource,
            internetArchiveSource,
            openFoodFactsSource,
            openBeautyFactsSource,
            openProductsFactsSource,
            openPetFoodFactsSource
        ]
        
        coordinator = MetasearchCoordinator(sources: allSources, denyListFilter: SettingsManager.shared.denyList)
        self.allSources = allSources
    }
    
    private let allSources: [any SearchSource]
    
    var body: some Scene {
        WindowGroup {
            TabView {
                SearchView(
                    coordinator: coordinator,
                    queryEnhancer: queryEnhancer,
                    allSources: allSources
                )
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                
                FavoritesView()
                    .tabItem {
                        Label("Favorites", systemImage: "star.fill")
                    }
            }
        }
        .modelContainer(for: [SavedStore.self, SearchHistoryEntry.self, FavoriteResult.self])
    }
}
