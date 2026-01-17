import SwiftUI
import MetasearchCore
import LLMIntegration

public struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @StateObject private var downloadManager = LLMModelDownloadManager.shared
    @State private var showSettings = false
    
    public init(
        coordinator: MetasearchCoordinator,
        queryEnhancer: QueryEnhancer
    ) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(
            coordinator: coordinator,
            queryEnhancer: queryEnhancer
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
                    },
                    onTextChange: {
                        viewModel.debouncedSearch()
                    }
                )
                .padding()
                
                // Results
                ZStack {
                    // Model download overlay
                    if downloadManager.downloadState == .downloading {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        ModelDownloadView(
                            downloadManager: downloadManager,
                            onCancel: {
                                downloadManager.cancelDownload()
                            }
                        )
                        .padding()
                    }
                    
                    switch viewModel.state {
                    case .idle:
                        EmptyStateView(message: NSLocalizedString("Search for products at local merchants and ethical online retailers", comment: ""))
                        
                    case .loading:
                        LoadingView()
                        
                    case .loaded:
                        if viewModel.results.isEmpty {
                            EmptyStateView(message: NSLocalizedString("No results found. Try a different search term.", comment: ""))
                        } else {
                            ResultsView(results: viewModel.results)
                                .accessibilityLabel("Search results")
                                .accessibilityValue("\(viewModel.results.count) results found")
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
        }
    }
}

struct SearchBarView: View {
    @Binding var searchText: String
    let onSearch: () -> Void
    let onTextChange: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search for products...", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search for products")
                .accessibilityHint("Enter a search query to find products at local merchants and ethical online retailers")
                .onSubmit {
                    onSearch()
                }
                .onChange(of: searchText) {
                    onTextChange()
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
    }
}
