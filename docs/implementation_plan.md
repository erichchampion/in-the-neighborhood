---
name: In the Neighborhood Metasearch Implementation
overview: Implement an iOS metasearch app using TDD and xcodegen, featuring on-device LLM query enhancement, multi-source search aggregation (MapKit, web search, specialized APIs), result filtering/prioritization, and SwiftUI UI.
todos:
  - id: setup-xcodegen
    content: Create project.yml with all targets (App, MetasearchCore, SearchSources, LocationServices, LLMIntegration) and test targets. Configure Swift 6.0, iOS 18.0, bundle ID com.in-the-neighborhood
    status: completed
  - id: core-models-protocols
    content: Define SearchResult, EnhancedQuery, SearchSource protocol, DenyListFilter with comprehensive unit tests using TDD
    status: completed
    dependencies:
      - setup-xcodegen
  - id: llm-integration
    content: Implement QueryEnhancer and LLMService (MLX Swift/Mistral 3B) with fallback mechanism. Write TDD tests for query extraction (product type, price, categories)
    status: completed
    dependencies:
      - core-models-protocols
  - id: mapkit-source
    content: Implement MapKitSearchSource using MKLocalSearch for local business discovery. Map MKMapItem to SearchResult with TDD tests
    status: completed
    dependencies:
      - core-models-protocols
  - id: web-search-source
    content: Implement WebSearchSource aggregating DuckDuckGo and Bing APIs. Handle rate limiting and normalize results with TDD tests
    status: completed
    dependencies:
      - core-models-protocols
  - id: specialized-sources
    content: Implement BookshopSearchSource and MarketplaceSearchSource with API integrations and error handling tests
    status: completed
    dependencies:
      - core-models-protocols
  - id: metasearch-coordinator
    content: Create MetasearchCoordinator to execute searches in parallel across all sources with timeout handling. Implement ResultAggregator for deduplication and prioritization with comprehensive tests
    status: completed
    dependencies:
      - mapkit-source
      - web-search-source
      - specialized-sources
  - id: location-services
    content: Implement LocationService wrapper for Core Location with permission handling, distance calculation, and fallback to zip code entry with TDD tests
    status: completed
    dependencies:
      - metasearch-coordinator
  - id: swiftui-ui
    content: Create SearchViewModel and SwiftUI views (SearchView, ResultsView, LocalBusinessCard, OnlineResultCard) with state management and debouncing. Write ViewModel tests and basic UI tests
    status: completed
    dependencies:
      - location-services
      - llm-integration
  - id: settings-config
    content: Implement SettingsView and SettingsManager for deny list management, search radius preferences, and privacy controls with persistence tests
    status: completed
    dependencies:
      - swiftui-ui
  - id: performance-caching
    content: Implement result caching, LLM lazy loading, and UI optimization with performance tests
    status: completed
    dependencies:
      - settings-config
  - id: integration-polish
    content: Write end-to-end integration tests, UI tests for user flows, accessibility improvements, and localization preparation
    status: completed
    dependencies:
      - performance-caching
---

# In the Neighborhood Metasearch Implementation Plan

## Overview

This plan implements the iOS metasearch app "In the Neighborhood" following Test-Driven Development (TDD) principles, using XcodeGen for project management. The app aggregates search results from multiple sources (MapKit for local businesses, web search, specialized APIs) while filtering out mega-retailers and prioritizing local merchants.

## Architecture Overview

The app follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────┐
│          SwiftUI UI Layer           │
│  (SearchView, ResultsView, Settings)│
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│         ViewModel Layer             │
│   (SearchViewModel, ResultViewModel)│
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│      Service/Coordinator Layer      │
│  (MetasearchCoordinator, QueryEnhancer)│
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│       Search Source Layer           │
│  (MapKitSource, WebSearchSource,    │
│   SpecializedSource, etc.)          │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│     Infrastructure Layer            │
│  (Networking, Location, LLM, Cache) │
└─────────────────────────────────────┘
```

## Phase 1: Project Setup with XcodeGen

### Tasks

1. **Create `project.yml`** defining:

   - App target (`InTheNeighborhood`)
   - Framework targets: `MetasearchCore`, `SearchSources`, `LocationServices`, `LLMIntegration`
   - Test targets for each framework
   - Shared settings (Swift 6.0, iOS 18.0, bundle ID prefix `com.in-the-neighborhood`)

2. **Define project structure**:
   ```
   Sources/
     InTheNeighborhood/          # Main app
     MetasearchCore/             # Core search orchestration
     SearchSources/              # Individual search source implementations
       MapKit/
       WebSearch/
       Specialized/
     LocationServices/           # Core Location wrapper
     LLMIntegration/             # On-device LLM (MLX Swift/Mistral 3B)
   Tests/
     InTheNeighborhoodTests/
     MetasearchCoreTests/
     SearchSourcesTests/
     LocationServicesTests/
     LLMIntegrationTests/
   ```

3. **Configure SPM dependencies** (in `project.yml`):

   - MLX Swift for on-device LLM (if available via SPM)
   - Or configure for manual framework integration

4. **Set up CI script** to run `xcodegen generate` before builds

### TDD Checkpoint

- Write a failing test: `test_ProjectBuildsAndRuns()` - verify project structure compiles
- Write a failing test: `test_AppTargetExists()` - verify app target is configured

**Deliverable**: Generated Xcode project with all targets and test infrastructure ready

## Phase 2: Core Models and Protocols (TDD Foundation)

### Tasks

1. **Define `SearchResult` model**:
   ```swift
   struct SearchResult: Identifiable, Equatable {
     let id: String
     let title: String
     let description: String?
     let source: SearchSource
     let sourceType: SourceType // .local, .regional, .online
     let url: URL?
     let location: CLLocation?
     let distance: Double? // meters
     let metadata: [String: Any]
   }
   ```

2. **Define `SearchSource` protocol**:
   ```swift
   protocol SearchSource {
     var identifier: String { get }
     var sourceType: SourceType { get }
     func search(query: EnhancedQuery) async throws -> [SearchResult]
   }
   ```

3. **Define `EnhancedQuery` model** (output from LLM):
   ```swift
   struct EnhancedQuery {
     let original: String
     let productType: String?
     let categories: [String]
     let priceMax: Double?
     let condition: ProductCondition?
   }
   ```

4. **Define `DenyListFilter`** for domain filtering

### TDD Tests to Write First

- `test_SearchResult_Initialization()`
- `test_SearchResult_Equality()`
- `test_EnhancedQuery_Parsing()`
- `test_DenyListFilter_FiltersDomains()` - test deny list filtering logic
- `test_SearchSource_ProtocolRequirement()` - ensure protocol has required methods

**Deliverable**: Core domain models with 100% test coverage

## Phase 3: Query Enhancement with On-Device LLM

### Tasks

1. **Create `QueryEnhancer` service**:

   - Wraps MLX Swift/Mistral 3B integration
   - Processes natural language queries
   - Extracts: product type, categories, price constraints, condition
   - Falls back to direct search if LLM unavailable

2. **Create `LLMService` protocol** and `MLXLLMService` implementation:

   - Load Mistral 3B model
   - Process prompts to extract query parameters
   - Handle model loading errors gracefully

3. **Implement prompt templates** for query enhancement

### TDD Tests to Write First

- `test_QueryEnhancer_ExtractsProductType()` - given "ergonomic office chair", extracts product="office chair"
- `test_QueryEnhancer_ExtractsPriceConstraint()` - given "under $300", extracts priceMax=300
- `test_QueryEnhancer_ExtractsCategories()` - given context, identifies relevant business categories
- `test_QueryEnhancer_FallbackWhenLLMUnavailable()` - returns basic query when LLM fails
- `test_LLMService_ErrorHandling()` - test model loading failures

**Deliverable**: Query enhancement system with fallback mechanism

## Phase 4: Search Source Implementations

### 4a. MapKit Search Source

**Tasks**:

- Create `MapKitSearchSource` conforming to `SearchSource`
- Use `MKLocalSearch` to find businesses by category
- Map `MKMapItem` to `SearchResult`
- Handle location services authorization

**TDD Tests**:

- `test_MapKitSource_SearchesByCategory()` - verify category-based search
- `test_MapKitSource_MapsResultsCorrectly()` - verify MapItem → SearchResult mapping
- `test_MapKitSource_HandlesNoResults()` - test empty result handling
- `test_MapKitSource_LocationPermissionDenied()` - test fallback behavior

### 4b. Web Search Source

**Tasks**:

- Create `WebSearchSource` aggregating DuckDuckGo and Bing
- Implement API clients for each provider
- Parse and normalize results from different formats
- Handle rate limiting

**TDD Tests**:

- `test_WebSearchSource_AggregatesMultipleProviders()` - test parallel requests
- `test_WebSearchSource_NormalizesResults()` - verify consistent result format
- `test_WebSearchSource_HandlesRateLimit()` - test throttling behavior
- `test_WebSearchSource_FallbackOnSingleFailure()` - one provider fails, others succeed

### 4c. Specialized Search Sources

**Tasks**:

- Create `BookshopSearchSource` for Bookshop.org API
- Create `MarketplaceSearchSource` for Craigslist/Facebook Marketplace (where accessible)
- Implement source-specific result mapping

**TDD Tests**:

- `test_BookshopSource_FetchesBooks()` - verify API integration
- `test_MarketplaceSource_HandlesAccessLimitations()` - test graceful degradation

**Deliverable**: All search sources implemented with comprehensive test coverage

## Phase 5: Metasearch Coordination

### Tasks

1. **Create `MetasearchCoordinator`**:

   - Manages collection of `SearchSource`s
   - Executes searches in parallel using `async let` or `TaskGroup`
   - Aggregates results from all sources
   - Applies timeout (e.g., 3 seconds max per source)

2. **Implement `ResultAggregator`**:

   - Deduplicates results (by URL, title similarity)
   - Prioritizes results by tier (Local → Regional → Online)
   - Sorts by distance (for local results) and relevance
   - Filters using `DenyListFilter`

3. **Create `ResultPrioritizer`**:

   - Tier 1: Local merchants (with distance)
   - Tier 2: Regional/Ethical online
   - Tier 3: General online (non-denied)

### TDD Tests to Write First

- `test_MetasearchCoordinator_QueriesAllSources()` - verify parallel execution
- `test_MetasearchCoordinator_HandlesPartialFailures()` - some sources fail, others succeed
- `test_MetasearchCoordinator_RespectsTimeout()` - slow sources timeout appropriately
- `test_ResultAggregator_DeduplicatesResults()` - same result from multiple sources appears once
- `test_ResultPrioritizer_LocalBeforeOnline()` - local results appear first
- `test_ResultAggregator_FiltersDenyList()` - Amazon, Walmart, etc. are filtered out

**Deliverable**: Full metasearch orchestration with prioritization and filtering

## Phase 6: Location Services Integration

### Tasks

1. **Create `LocationService` wrapper**:

   - Manages Core Location authorization
   - Provides current location or fallback (zip code entry)
   - Caches last known location (with user consent)

2. **Integrate location into search**:

   - Pass location context to MapKit searches
   - Calculate distances for local results
   - Use location for query enhancement

### TDD Tests to Write First

- `test_LocationService_RequestsPermission()` - verify permission flow
- `test_LocationService_FallbackToZipCode()` - when permission denied, uses manual entry
- `test_LocationService_CalculatesDistance()` - verify distance calculation
- `test_LocationService_CachesLastLocation()` - verify caching behavior

**Deliverable**: Location services integrated with search

## Phase 7: UI Layer with SwiftUI

### Tasks

1. **Create `SearchViewModel`**:

   - ObservableObject managing search state (`.idle`, `.loading`, `.results`, `.error`)
   - Debounces user input
   - Cancels in-flight requests on new queries
   - Injects `MetasearchCoordinator`

2. **Create SwiftUI views**:

   - `SearchView`: Main search interface with search bar
   - `ResultsView`: Displays prioritized results in tiers
   - `LocalBusinessCard`: Card for local merchants with call/directions
   - `OnlineResultCard`: Card for online results
   - `LoadingView`, `ErrorView`, `EmptyStateView`

3. **Implement result actions**:

   - Call button (using `tel:` URL)
   - Directions button (using MapKit directions)
   - Open URL button for online results

### TDD Tests to Write First

- `test_SearchViewModel_DebouncesInput()` - verify debounce behavior
- `test_SearchViewModel_CancelsPreviousRequests()` - new query cancels old
- `test_SearchViewModel_StateTransitions()` - idle → loading → results
- `test_SearchViewModel_ErrorHandling()` - error state management
- UI tests: `test_SearchFlow_EndToEnd()` - basic user flow

**Deliverable**: Complete SwiftUI interface with state management

## Phase 8: Settings and Configuration

### Tasks

1. **Create `SettingsView`**:

   - Manage deny list (add/remove retailers)
   - Search radius preference (5/10/25/50 miles)
   - Toggle result categories
   - Privacy controls (clear history, export data)

2. **Implement `SettingsManager`**:

   - Persists preferences to UserDefaults
   - Manages deny list configuration
   - Validates user inputs

### TDD Tests to Write First

- `test_SettingsManager_PersistsDenyList()` - verify persistence
- `test_SettingsManager_ValidatesRadius()` - ensure valid radius values
- `test_SettingsManager_ClearsSearchHistory()` - verify data clearing

**Deliverable**: Settings interface with persistent configuration

## Phase 9: Performance Optimization and Caching

### Tasks

1. **Implement result caching**:

   - Cache recent queries/results (in-memory)
   - Optional Core Data persistence for search history
   - Cache invalidation strategy

2. **Optimize LLM performance**:

   - Cache common query patterns
   - Lazy load LLM model (only when needed)
   - Measure and optimize inference time

3. **Optimize UI rendering**:

   - Lazy loading for result lists
   - Image caching for result thumbnails (if applicable)

### TDD Tests to Write First

- `test_ResultCache_StoresAndRetrieves()` - verify caching works
- `test_ResultCache_ExpiresAfterTTL()` - verify expiration
- `test_LLMService_LazyLoadsModel()` - verify model loaded on demand

**Deliverable**: Performance optimizations with measurable improvements

## Phase 10: Integration Testing and Polish

### Tasks

1. **End-to-end integration tests**:

   - Full search flow: query → enhancement → search → aggregation → display
   - Error scenarios: network failures, LLM failures, location denied
   - Edge cases: empty results, duplicate results, slow sources

2. **UI tests**:

   - First-time user flow (permissions, tutorial)
   - Returning user flow (quick search)
   - Settings navigation and configuration

3. **Accessibility**:

   - VoiceOver support
   - Dynamic type support
   - Color contrast compliance

4. **Localization preparation**:

   - Extract strings for localization
   - Test with different locales

### TDD Tests to Write First

- `test_EndToEndSearchFlow()` - complete user journey
- `test_ErrorRecovery()` - app handles errors gracefully
- `test_Accessibility()` - VoiceOver navigation works

**Deliverable**: Fully tested, polished application ready for beta

## Technical Specifications

### Key Files Structure

- `project.yml` - XcodeGen project specification
- `Sources/MetasearchCore/MetasearchCoordinator.swift` - Main orchestration
- `Sources/MetasearchCore/ResultAggregator.swift` - Result merging and prioritization
- `Sources/LLMIntegration/QueryEnhancer.swift` - LLM-based query enhancement
- `Sources/SearchSources/MapKit/MapKitSearchSource.swift` - MapKit integration
- `Sources/SearchSources/WebSearch/WebSearchSource.swift` - Web search aggregation
- `Sources/InTheNeighborhood/Views/SearchView.swift` - Main UI
- `Sources/InTheNeighborhood/ViewModels/SearchViewModel.swift` - State management

### Dependencies

- **MLX Swift** (or llama.cpp) for on-device LLM
- **MapKit** (iOS framework)
- **Core Location** (iOS framework)
- External APIs: DuckDuckGo, Bing, Bookshop.org (rate-limited)

### Performance Targets

- Search results in <3 seconds
- LLM inference <1 second (or fallback)
- Smooth UI scrolling (60 FPS)

### Privacy Considerations

- No search history sent to external servers
- LLM runs entirely on-device
- Location data only used locally
- User can clear all data

## Risk Mitigation

1. **LLM Performance**: Test on iPhone 12+ hardware, provide fallback if too slow
2. **API Rate Limits**: Implement exponential backoff, user-facing rate limit messages
3. **Empty Results**: Graceful empty states, suggestions for broadening search
4. **Legal Concerns**: Review ToS for all APIs, implement attribution where required

## Success Criteria

- All unit tests pass with >80% code coverage
- All integration tests pass
- App runs smoothly on iPhone 12+ (iOS 18+)
- Search completes in <3 seconds
- Successfully filters deny-listed retailers
- Local results prioritized correctly