import SwiftUI
import MetasearchCore
import LLMIntegration

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
    let localStoreCategories: [String]
    @ObservedObject var downloadManager: LLMModelDownloadManager
    
    public init(
        webResults: [SearchResult],
        amazonResults: [SearchResult],
        localResults: [SearchResult],
        originalQuery: String = "",
        selectedTab: Binding<SearchViewModel.TabSelection>,
        isLoadingWeb: Bool = false,
        isLoadingAmazon: Bool = false,
        isLoadingLocal: Bool = false,
        localStoreCategories: [String] = [],
        downloadManager: LLMModelDownloadManager = .shared,
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
        self.localStoreCategories = localStoreCategories
        self.downloadManager = downloadManager
        self.onRefine = onRefine
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Tab selector - always visible so user can switch away from Local Stores while model downloads
            Picker("Results Tab", selection: $selectedTab) {
                Text("Web").tag(SearchViewModel.TabSelection.web)
                Text("Local Stores").tag(SearchViewModel.TabSelection.localStores)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Tab content with download overlay only over this area when on Local Stores
            ZStack {
                if selectedTab == .web {
                    webTabContent
                } else {
                    localStoresTabContent
                }
                
                if selectedTab == .localStores && downloadManager.downloadState == .downloading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ModelDownloadView(
                        downloadManager: downloadManager,
                        onCancel: { downloadManager.cancelDownload() }
                    )
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // Filter Amazon results to only include those with at least one metadata key useful for refinement
    private var filteredAmazonResults: [SearchResult] {
        amazonResults.filter { hasRefinementMetadata($0) }
    }
    
    private func hasRefinementMetadata(_ result: SearchResult) -> Bool {
        let brand = result.metadata["brand"] as? String
        let isbn = result.metadata["isbn"] as? String
        let sku = result.metadata["sku"] as? String
        let author = result.metadata["author"] as? String
        let artist = result.metadata["artist"] as? String
        return brand != nil || isbn != nil || sku != nil || author != nil || artist != nil
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
                
                // Amazon Results Section — only show products with refinement metadata (brand, isbn, sku, author, artist)
                if !filteredAmazonResults.isEmpty {
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
                        
                        ForEach(filteredAmazonResults) { result in
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
                if !isLoadingWeb && !isLoadingAmazon && webResults.isEmpty && filteredAmazonResults.isEmpty {
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
                        HStack(alignment: .firstTextBaseline) {
                            Text("Local Stores")
                                .font(.headline)
                            
                            if !localStoreCategories.isEmpty {
                                Text("• " + localStoreCategories.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
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
