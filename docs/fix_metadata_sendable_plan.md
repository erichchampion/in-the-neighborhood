# Plan: Fix Metadata Sendable Build Errors

## Problem
Swift 6 strict concurrency checking is treating `[String: AnyHashable]?` as non-Sendable, causing build errors when passing metadata across actor boundaries in:
- `QueryEnhancer.swift:52` - Sending 'metadataCopy' to `callEnhanceQuery`
- `QueryEnhancer.swift:76` - Sending 'metadata' to `llmService.determineStoreTypes`
- `QueryEnhancer.swift:92` - Sending 'metadataCopy' to `callDetermineStoreTypes`

## Solution
Create a Sendable wrapper type for metadata that only contains Sendable values (String, Int, Double, Bool) and update all code to use it.

## Implementation Steps

### Step 1: Create Sendable Metadata Type
- Create `ProductMetadata.swift` in `Sources/MetasearchCore/`
- Define a `struct ProductMetadata: Sendable` with optional properties for:
  - `isbn: String?`
  - `author: String?`
  - `sku: String?`
  - `asin: String?`
  - `brand: String?`
  - `artist: String?`
  - `price: Double?`
  - `imageUrl: String?`
  - Any other commonly used metadata fields
- Add initializer from `[String: AnyHashable]` dictionary
- Add method to convert back to `[String: AnyHashable]` for backward compatibility with `SearchResult`

### Step 2: Update LLMService Protocol
- Change `LLMService.swift` protocol method signature:
  - `func enhanceQuery(_ query: String, metadata: [String: AnyHashable]?)` 
  - → `func enhanceQuery(_ query: String, metadata: ProductMetadata?)`
- Remove `@preconcurrency` from protocol (no longer needed)

### Step 3: Update LlamaCppLLMService
- Update `enhanceQuery` method signature to accept `ProductMetadata?`
- Update `determineStoreTypes` method signature to accept `ProductMetadata?`
- Update all internal methods that use metadata:
  - `enhanceQueryWithLLM`
  - `determineStoreTypesWithLLM`
  - `buildQueryEnhancementPrompt`
  - `buildStoreTypeDetectionPrompt`
  - `parseQuery`
- Convert `ProductMetadata` to dictionary format when needed for internal processing

### Step 4: Update QueryEnhancer
- Update `enhance` method to accept `ProductMetadata?` instead of `[String: AnyHashable]?`
- Update `determineStoreCategories` method to accept `ProductMetadata?`
- Remove `nonisolated` helper functions (no longer needed)
- Remove `copyMetadataSafely` helper (no longer needed)
- Call service methods directly since metadata is now Sendable

### Step 5: Update SearchViewModel
- Update `refineSearch` method signature:
  - `func refineSearch(with metadata: [String: AnyHashable], originalQuery: String)`
  - → `func refineSearch(with metadata: ProductMetadata, originalQuery: String)`
- Convert `SearchResult.metadata` to `ProductMetadata` when calling `refineSearch`
- Update calls to `queryEnhancer.enhance` and `queryEnhancer.determineStoreCategories`

### Step 6: Update SearchSource Implementations
- Update all `SearchSource` implementations to create `ProductMetadata` instead of `[String: AnyHashable]`:
  - `GoogleBooksSearchSource`
  - `BingProvider`
  - `DuckDuckGoProvider`
  - `BookshopSearchSource`
  - `AmazonSearchSource`
  - `MapKitSearchSource`
- Keep `SearchResult.metadata` as `[String: AnyHashable]` for backward compatibility
- Convert `ProductMetadata` to dictionary when creating `SearchResult`

### Step 7: Update Tests
- Update `QueryEnhancerTests` to use `ProductMetadata`
- Update `LlamaCppLLMServiceTests` to use `ProductMetadata`
- Update `SearchViewModelTests` to use `ProductMetadata`
- Update any other tests that use metadata

### Step 8: Clean Up
- Remove `@preconcurrency` imports where no longer needed
- Remove helper functions that are no longer needed
- Update documentation comments

## Files to Modify

1. **New File**: `Sources/MetasearchCore/ProductMetadata.swift`
2. **Modify**: `Sources/LLMIntegration/LLMService.swift`
3. **Modify**: `Sources/LLMIntegration/LlamaCppLLMService.swift`
4. **Modify**: `Sources/LLMIntegration/QueryEnhancer.swift`
5. **Modify**: `Sources/InTheNeighborhood/ViewModels/SearchViewModel.swift`
6. **Modify**: `Sources/SearchSources/Specialized/GoogleBooksSearchSource.swift`
7. **Modify**: `Sources/SearchSources/WebSearch/BingProvider.swift`
8. **Modify**: `Sources/SearchSources/WebSearch/DuckDuckGoProvider.swift`
9. **Modify**: `Sources/SearchSources/Specialized/BookshopSearchSource.swift`
10. **Modify**: `Sources/SearchSources/Specialized/AmazonSearchSource.swift`
11. **Modify**: `Sources/SearchSources/MapKit/MapKitSearchSource.swift`
12. **Modify**: `Tests/LLMIntegrationTests/QueryEnhancerTests.swift`
13. **Modify**: `Tests/LLMIntegrationTests/LlamaCppLLMServiceTests.swift`
14. **Modify**: `Tests/InTheNeighborhoodTests/SearchViewModelTests.swift`

## Benefits
- ✅ Fixes build errors
- ✅ Makes metadata type-safe and Sendable
- ✅ Improves code clarity (explicit fields vs dictionary)
- ✅ Better Swift 6 concurrency compliance
- ✅ No runtime performance impact

## Migration Notes
- This is a breaking change for any external code using the `LLMService` protocol
- Internal code will need updates but the conversion is straightforward
- `SearchResult.metadata` remains `[String: AnyHashable]` for backward compatibility
