import SwiftUI
import MetasearchCore

public struct ResultsView: View {
    let webResults: [SearchResult]
    let amazonResults: [SearchResult]
    let localResults: [SearchResult]
    let originalQuery: String
    let onRefine: ((SearchResult) -> Void)?
    @Binding var selectedTab: SearchViewModel.TabSelection
    let isLoadingWeb: Bool
    let isLoadingAmazon: Bool
    let isLoadingLocal: Bool
    
    public init(
        webResults: [SearchResult],
        amazonResults: [SearchResult],
        localResults: [SearchResult],
        originalQuery: String = "",
        selectedTab: Binding<SearchViewModel.TabSelection>,
        isLoadingWeb: Bool = false,
        isLoadingAmazon: Bool = false,
        isLoadingLocal: Bool = false,
        onRefine: ((SearchResult) -> Void)? = nil
    ) {
        self.webResults = webResults
        self.amazonResults = amazonResults
        self.localResults = localResults
        self.originalQuery = originalQuery
        self._selectedTab = selectedTab
        self.isLoadingWeb = isLoadingWeb
        self.isLoadingAmazon = isLoadingAmazon
        self.isLoadingLocal = isLoadingLocal
        self.onRefine = onRefine
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Results Tab", selection: $selectedTab) {
                Text("Web").tag(SearchViewModel.TabSelection.web)
                Text("Local Stores").tag(SearchViewModel.TabSelection.localStores)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Tab content - show based on selection
            if selectedTab == .web {
                webTabContent
            } else {
                localStoresTabContent
            }
        }
    }
    
    private var webTabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Web Results Section
                if !webResults.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Web Results")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        ForEach(webResults) { result in
                            ResultRowView(result: result)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                } else if isLoadingWeb {
                    VStack {
                        ProgressView()
                            .padding()
                        Text("Searching web...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
                
                // Amazon Results Section
                if !amazonResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !webResults.isEmpty {
                            Text("Products")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                        } else {
                            Text("Products")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                        }
                        
                        ForEach(amazonResults) { result in
                            AmazonProductCard(result: result) {
                                onRefine?(result)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .padding(.bottom, 16)
                } else if isLoadingAmazon {
                    VStack {
                        ProgressView()
                            .padding()
                        Text("Searching for Products...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, webResults.isEmpty ? 40 : 20)
                }
                
                // Empty state
                if !isLoadingWeb && !isLoadingAmazon && webResults.isEmpty && amazonResults.isEmpty {
                    VStack {
                        Text("No web results found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var localStoresTabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !localResults.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Local Stores")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        ForEach(localResults) { result in
                            ResultRowView(result: result)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                } else if isLoadingLocal {
                    VStack {
                        ProgressView()
                            .padding()
                        Text("Finding local stores...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack {
                        Text("No local stores found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct ResultRowView: View {
    let result: SearchResult
    
    var body: some View {
        Group {
            // Check if this is an Amazon result - use AmazonProductCard if so
            if result.source.lowercased() == "amazon" {
                // This shouldn't happen since Amazon results are filtered out,
                // but handle it just in case
                AmazonProductCard(result: result, onRefine: nil)
            } else {
                switch result.sourceType {
                case .local:
                    LocalBusinessCard(result: result)
                case .regional, .online:
                    OnlineResultCard(result: result)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
