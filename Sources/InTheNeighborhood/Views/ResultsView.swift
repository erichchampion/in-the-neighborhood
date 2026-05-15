import SwiftUI
import MetasearchCore

/// C1: intent-driven results UI. Four tabs — Local / Online / Borrow /
/// Repair — each reflecting a user intent rather than a search-source
/// category. The classifier in `SearchViewModel.tab(for:)` decides which
/// bucket every result lands in; this view just renders the buckets.
public struct ResultsView: View {
    let localResults: [SearchResult]
    let onlineResults: [SearchResult]
    let borrowResults: [SearchResult]
    let repairResults: [SearchResult]
    let originalQuery: String
    let onRefine: ((SearchResult) -> Void)?
    @Binding var selectedTab: SearchViewModel.TabSelection
    let isLoadingLocal: Bool
    let isLoadingOnline: Bool
    let isLoadingBorrow: Bool
    let isLoadingRepair: Bool
    let localStoreCategories: [String]
    let agentSummary: String?

    public init(
        localResults: [SearchResult],
        onlineResults: [SearchResult],
        borrowResults: [SearchResult],
        repairResults: [SearchResult],
        originalQuery: String = "",
        selectedTab: Binding<SearchViewModel.TabSelection>,
        isLoadingLocal: Bool = false,
        isLoadingOnline: Bool = false,
        isLoadingBorrow: Bool = false,
        isLoadingRepair: Bool = false,
        localStoreCategories: [String] = [],
        agentSummary: String? = nil,
        onRefine: ((SearchResult) -> Void)? = nil
    ) {
        self.localResults = localResults
        self.onlineResults = onlineResults
        self.borrowResults = borrowResults
        self.repairResults = repairResults
        self.originalQuery = originalQuery
        self._selectedTab = selectedTab
        self.isLoadingLocal = isLoadingLocal
        self.isLoadingOnline = isLoadingOnline
        self.isLoadingBorrow = isLoadingBorrow
        self.isLoadingRepair = isLoadingRepair
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
            // Intent tab selector. Always visible so the user can move
            // between intents while a slow source is still streaming.
            Picker("Results Tab", selection: $selectedTab) {
                Text("Local").tag(SearchViewModel.TabSelection.local)
                Text("Online").tag(SearchViewModel.TabSelection.online)
                Text("Borrow").tag(SearchViewModel.TabSelection.borrow)
                Text("Repair").tag(SearchViewModel.TabSelection.repair)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ZStack {
                switch selectedTab {
                case .local:
                    localTabContent
                case .online:
                    onlineTabContent
                case .borrow:
                    borrowTabContent
                case .repair:
                    repairTabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Online tab (web + products combined)

    /// Within Online, split into "Products" (cards with refinement
    /// metadata) and "Web" (everything else) — same visual grouping
    /// the user got when these were separate tabs.
    private var onlineProductResults: [SearchResult] {
        onlineResults.filter { $0.category == .product || $0.category == .book }
            .filter(Self.hasRefinementMetadata)
    }

    private var onlineWebResults: [SearchResult] {
        onlineResults.filter { $0.category == .web }
    }

    nonisolated static func hasRefinementMetadata(_ result: SearchResult) -> Bool {
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

    private var onlineTabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if onlineProductResults.isEmpty && onlineWebResults.isEmpty {
                    if isLoadingOnline {
                        VStack {
                            ProgressView()
                                .padding()
                            Text("Searching ethical online sources...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        VStack {
                            Text("No online results found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.top, 40)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // Products section
                    if !onlineProductResults.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Products")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            ForEach(onlineProductResults) { result in
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
                    }

                    // Web section
                    if !onlineWebResults.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Web")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            ForEach(onlineWebResults) { result in
                                ResultRowView(result: result)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Borrow tab (was Library)

    private var borrowTabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !filteredBorrowResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Borrow")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(filteredBorrowResults) { result in
                            LibraryCard(result: result)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .padding(.bottom, 16)
                } else if isLoadingBorrow {
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
                        Text("No borrow options found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var filteredBorrowResults: [SearchResult] {
        borrowResults.filter(Self.renderableInBorrowTab)
    }

    /// Returns `true` if the result has enough metadata for a `LibraryCard`
    /// to render something useful. Some sources (Open Library via
    /// `ProductMetadata`) store the joined author string under
    /// `metadata["author"]`; the raw Open Library shape uses an array under
    /// `metadata["author_name"]`. DPLA uses `metadata["providers"]`. Accept
    /// any of them so a perfectly valid Open Library result with just an
    /// author string doesn't get silently dropped.
    nonisolated static func renderableInBorrowTab(_ result: SearchResult) -> Bool {
        let isbn = result.metadata["isbn"] as? String
        let authorsArray = result.metadata["author_name"] as? [String]
        let authorString = result.metadata["author"] as? String
        let providers = result.metadata["providers"] as? [[String: Any]]
        let coverId = result.metadata["cover_i"] as? Int
        let imageUrl = result.metadata["imageUrl"] as? String
        return isbn != nil
            || authorsArray != nil
            || authorString != nil
            || providers != nil
            || coverId != nil
            || imageUrl != nil
    }

    /// Back-compat shim so older test files referring to the previous
    /// predicate name continue to compile. New callers should use
    /// `renderableInBorrowTab(_:)`.
    nonisolated static func renderableInLibraryTab(_ result: SearchResult) -> Bool {
        renderableInBorrowTab(result)
    }

    // MARK: - Local tab (was Local Stores)

    private var localTabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !localResults.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Local")
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
                        Text("Finding local options...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack {
                        Text("No local options found")
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

    // MARK: - Repair tab (new)

    private var repairTabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !repairResults.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Repair")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(repairResults) { result in
                            ResultRowView(result: result)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                } else if isLoadingRepair {
                    VStack {
                        ProgressView()
                            .padding()
                        Text("Looking for repair options...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 8) {
                        Text("No repair options found nearby")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Try a related term like \"bicycle repair\" or \"phone repair\".")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
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
