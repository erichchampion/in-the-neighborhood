import SwiftUI
import MetasearchCore

public struct SearchView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: SearchViewModel
    @State private var showSettings = false
    
    public init(
        coordinator: MetasearchCoordinator,
        queryEnhancer: QueryEnhancing,
        amazonSource: any SearchSource,
        googleBooksSource: any SearchSource,
        bestBuySource: any SearchSource,
        mapKitSource: any SearchSource
    ) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(
            coordinator: coordinator,
            queryEnhancer: queryEnhancer,
            amazonSource: amazonSource,
            googleBooksSource: googleBooksSource,
            bestBuySource: bestBuySource,
            mapKitSource: mapKitSource
        ))
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                SearchBarView(
                    searchText: $viewModel.searchText,
                    onSearch: {
                        Task {
                            await viewModel.search(query: viewModel.searchText)
                        }
                    }
                )
                .padding()
                
                // Results
                ZStack {
                    switch viewModel.state {
                    case .idle:
                        EmptyStateView(message: NSLocalizedString("Search for products at local merchants and ethical online retailers", comment: ""))
                        
                    case .loading:
                        // Show results area with per-section progress indicators (same layout as loaded state)
                        ResultsView(
                            webResults: viewModel.webResults,
                            amazonResults: viewModel.amazonResults,
                            localResults: viewModel.localResults,
                            originalQuery: viewModel.originalQuery,
                            selectedTab: $viewModel.selectedTab,
                            isLoadingWeb: viewModel.isLoadingWeb,
                            isLoadingAmazon: viewModel.isLoadingAmazon,
                            isLoadingLocal: viewModel.isLoadingLocal,
                            localStoreCategories: viewModel.localStoreCategories,
                            onRefine: { result in
                                Task {
                                    let productMetadata = ProductMetadata(from: result.metadata) ?? ProductMetadata()
                                    await viewModel.refineSearch(
                                        with: productMetadata,
                                        originalQuery: viewModel.originalQuery,
                                        resultTitle: result.title
                                    )
                                }
                            }
                        )
                        .accessibilityLabel("Search results")
                        .accessibilityValue(viewModel.webResults.isEmpty && viewModel.amazonResults.isEmpty && viewModel.localResults.isEmpty ? "Searching…" : "\(viewModel.webResults.count + viewModel.amazonResults.count + viewModel.localResults.count) results found")
                        
                    case .loaded:
                        if viewModel.webResults.isEmpty && viewModel.amazonResults.isEmpty && viewModel.localResults.isEmpty {
                            EmptyStateView(message: NSLocalizedString("No results found. Try a different search term.", comment: ""))
                        } else {
                            ResultsView(
                                webResults: viewModel.webResults,
                                amazonResults: viewModel.amazonResults,
                                localResults: viewModel.localResults,
                                originalQuery: viewModel.originalQuery,
                                selectedTab: $viewModel.selectedTab,
                                isLoadingWeb: viewModel.isLoadingWeb,
                                isLoadingAmazon: viewModel.isLoadingAmazon,
                                isLoadingLocal: viewModel.isLoadingLocal,
                                localStoreCategories: viewModel.localStoreCategories,
                                onRefine: { result in
                                    Task {
                                        let productMetadata = ProductMetadata(from: result.metadata) ?? ProductMetadata()
                                        await viewModel.refineSearch(
                                            with: productMetadata,
                                            originalQuery: viewModel.originalQuery,
                                            resultTitle: result.title
                                        )
                                    }
                                }
                            )
                            .accessibilityLabel("Search results")
                            .accessibilityValue("\(viewModel.webResults.count + viewModel.amazonResults.count + viewModel.localResults.count) results found")
                        }
                        
                    case .error:
                        ErrorView(
                            message: viewModel.errorMessage ?? "An error occurred",
                            onRetry: {
                                Task {
                                    await viewModel.search(query: viewModel.searchText)
                                }
                            }
                        )
                    }
                }
            }
            .navigationTitle(NSLocalizedString("In the Neighborhood", comment: ""))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel(NSLocalizedString("Settings", comment: ""))
                    .accessibilityHint(NSLocalizedString("Open app settings", comment: ""))
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    viewModel.cancelInFlightSearch()
                }
            }
        }
    }
}

struct SearchBarView: View {
    @Binding var searchText: String
    let onSearch: () -> Void
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search for products...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .accessibilityLabel("Search for products")
                .accessibilityHint("Enter a search query to find products at local merchants and ethical online retailers")
                .onSubmit {
                    onSearch()
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .onAppear {
            // Focus the search field when the view appears
            isSearchFieldFocused = true
        }
    }
}
