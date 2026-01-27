import SwiftUI
import MetasearchCore
import LLMIntegration

public struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var downloadManager = LLMModelDownloadManager.shared
    @State private var showSettings = false
    
    public init(
        coordinator: MetasearchCoordinator,
        queryEnhancer: QueryEnhancer,
        amazonSource: any SearchSource,
        googleBooksSource: any SearchSource,
        mapKitSource: any SearchSource
    ) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(
            coordinator: coordinator,
            queryEnhancer: queryEnhancer,
            amazonSource: amazonSource,
            googleBooksSource: googleBooksSource,
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
                        // Show loading view only if no results yet
                        if viewModel.webResults.isEmpty && viewModel.amazonResults.isEmpty && viewModel.localResults.isEmpty {
                            LoadingView()
                        } else {
                            // Show results with loading indicators
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
                                        await viewModel.refineSearch(with: result.metadata, originalQuery: viewModel.originalQuery)
                                    }
                                }
                            )
                            .accessibilityLabel("Search results")
                            .accessibilityValue("\(viewModel.webResults.count + viewModel.amazonResults.count + viewModel.localResults.count) results found")
                        }
                        
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
                                        await viewModel.refineSearch(with: result.metadata, originalQuery: viewModel.originalQuery)
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
                    
                    // Model download overlay - appears on top
                    if downloadManager.downloadState == .downloading {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .zIndex(1)
                        
                        ModelDownloadView(
                            downloadManager: downloadManager,
                            onCancel: {
                                downloadManager.cancelDownload()
                            }
                        )
                        .padding()
                        .zIndex(2)
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
