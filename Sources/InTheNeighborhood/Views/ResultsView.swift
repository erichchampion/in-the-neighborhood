import SwiftUI
import MetasearchCore

public struct ResultsView: View {
    let webResults: [SearchResult]
    let amazonResults: [SearchResult]
    let libraryResults: [SearchResult]
    let localResults: [SearchResult]
    let originalQuery: String
    let onRefine: ((SearchResult) -> Void)?
    @Binding var selectedTab: SearchViewModel.TabSelection
    let isLoadingWeb: Bool
    let isLoadingAmazon: Bool
    let isLoadingLibrary: Bool
    let isLoadingLocal: Bool
    let localStoreCategories: [String]
    let agentSummary: String?
    
    public init(
        webResults: [SearchResult],
        amazonResults: [SearchResult],
        libraryResults: [SearchResult],
        localResults: [SearchResult],
        originalQuery: String = "",
        selectedTab: Binding<SearchViewModel.TabSelection>,
        isLoadingWeb: Bool = false,
        isLoadingAmazon: Bool = false,
        isLoadingLibrary: Bool = false,
        isLoadingLocal: Bool = false,
        localStoreCategories: [String] = [],
        agentSummary: String? = nil,
        onRefine: ((SearchResult) -> Void)? = nil
    ) {
        self.webResults = webResults
        self.amazonResults = amazonResults
        self.libraryResults = libraryResults
        self.localResults = localResults
        self.originalQuery = originalQuery
        self._selectedTab = selectedTab
        self.isLoadingWeb = isLoadingWeb
        self.isLoadingAmazon = isLoadingAmazon
        self.isLoadingLibrary = isLoadingLibrary
        self.isLoadingLocal = isLoadingLocal
        self.localStoreCategories = localStoreCategories
        self.agentSummary = agentSummary
        self.onRefine = onRefine
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Agent AI Summary Banner
            if let summary = agentSummary, !summary.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "brain")
                        .foregroundColor(.purple)
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            // Tab selector - always visible so user can switch away from Local Stores while model downloads
            Picker("Results Tab", selection: $selectedTab) {
                Text("Web").tag(SearchViewModel.TabSelection.web)
                Text("Products").tag(SearchViewModel.TabSelection.products)
                Text("Library").tag(SearchViewModel.TabSelection.library)
                Text("Local Stores").tag(SearchViewModel.TabSelection.localStores)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Tab content with download overlay only over this area when on Local Stores
            ZStack {
                switch selectedTab {
                case .web:
                    webTabContent
                case .products:
                    productsTabContent
                case .library:
                    libraryTabContent
                case .localStores:
                    localStoresTabContent
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
    
    /// Returns the URL to open for Best Buy cards when bestbuy.com is not in the deny list.
    private func urlToOpen(for result: SearchResult) -> URL? {
        guard result.source.lowercased() == SourceIdentifier.bestbuy,
              let url = result.url,
              !SettingsManager.shared.denyList.isDenied("bestbuy.com") else {
            return nil
        }
        return url
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
                } else {
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
    
    private var productsTabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !filteredAmazonResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Products")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        ForEach(filteredAmazonResults) { result in
                            ProductCard(
                                result: result,
                                onRefine: { onRefine?(result) },
                                urlToOpen: urlToOpen(for: result)
                            )
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
                    .padding(.top, 40)
                } else {
                    VStack {
                        Text("No products found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var libraryTabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !filteredLibraryResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Library")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        ForEach(filteredLibraryResults) { result in
                            LibraryCard(result: result)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .padding(.bottom, 16)
                } else if isLoadingLibrary {
                    VStack {
                        ProgressView()
                            .padding()
                        Text("Searching libraries...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack {
                        Text("No library results found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var filteredLibraryResults: [SearchResult] {
        libraryResults.filter { result in
            let isbn = result.metadata["isbn"] as? String
            let authors = result.metadata["author_name"] as? [String]
            let providers = result.metadata["providers"] as? [[String: Any]]
            let coverId = result.metadata["cover_i"] as? Int
            let imageUrl = result.metadata["imageUrl"] as? String
            return isbn != nil || authors != nil || providers != nil || coverId != nil || imageUrl != nil
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
                
                // Link to Apple Business Connect
                if let url = URL(string: "https://businessconnect.apple.com/") {
                    Link(destination: url) {
                        Text("Learn more about Apple Business Connect")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

struct ResultRowView: View {
    let result: SearchResult
    
    var body: some View {
        Group {
            // Check if this is a product or book result - use ProductCard if so
            if result.category == .product || result.category == .book {
                // This shouldn't happen since product results are in the Products section,
                // but handle it just in case
                ProductCard(
                    result: result,
                    onRefine: nil,
                    urlToOpen: result.source.lowercased() == SourceIdentifier.bestbuy && result.url != nil && !SettingsManager.shared.denyList.isDenied("bestbuy.com") ? result.url : nil
                )
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
