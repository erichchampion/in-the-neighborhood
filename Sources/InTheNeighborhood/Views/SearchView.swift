import SwiftUI
import MetasearchCore
import LLMIntegration

public struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
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
                    switch viewModel.state {
                    case .idle:
                        EmptyStateView(message: "Search for products at local merchants and ethical online retailers")
                        
                    case .loading:
                        LoadingView()
                        
                    case .loaded:
                        if viewModel.results.isEmpty {
                            EmptyStateView(message: "No results found. Try a different search term.")
                        } else {
                            ResultsView(results: viewModel.results)
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
            .navigationTitle("In the Neighborhood")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                    }
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
