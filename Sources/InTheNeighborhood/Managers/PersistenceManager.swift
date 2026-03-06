import Foundation
import SwiftData
import MetasearchCore
import SharedModels

/// Manages the SwiftData `ModelContainer` and provides convenient save/fetch helpers.
///
/// Use `PersistenceManager.shared` for app-wide access, or inject a custom instance
/// (with in-memory `ModelConfiguration`) for testing.
@MainActor
final class PersistenceManager: ObservableObject {

    static let shared: PersistenceManager = {
        // swiftlint:disable:next force_try
        return try! PersistenceManager()
    }()

    let container: ModelContainer

    init(inMemory: Bool = false) throws {
        let schema = Schema([SavedStore.self, SearchHistoryEntry.self, FavoriteResult.self])
        let config: ModelConfiguration
        
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            // Use App Group container for sharing with the Widget Extension
            if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.in-the-neighborhood.shared") {
                let storeURL = groupURL.appendingPathComponent("InTheNeighborhood.sqlite")
                config = ModelConfiguration(schema: schema, url: storeURL)
            } else {
                // Fallback for tests or if App Group is missing
                config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            }
        }
        
        container = try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Saved Stores

    func saveStore(from result: SearchResult) {
        guard let location = result.location else { return }
        let store = SavedStore(
            id: result.id,
            name: result.title,
            address: result.description,
            phone: result.metadata["phone"] as? String,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            categories: []
        )
        container.mainContext.insert(store)
        try? container.mainContext.save()
    }

    func fetchSavedStores() -> [SavedStore] {
        let descriptor = FetchDescriptor<SavedStore>(
            sortBy: [SortDescriptor(\.savedDate, order: .reverse)]
        )
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    func deleteSavedStore(_ store: SavedStore) {
        container.mainContext.delete(store)
        try? container.mainContext.save()
    }

    // MARK: - Favorites

    func saveFavorite(from result: SearchResult) {
        // Encode metadata as JSON
        let stringDict = result.metadata.compactMapValues { $0 as? String }
        let jsonData = try? JSONEncoder().encode(stringDict)
        let jsonString = jsonData.flatMap { String(data: $0, encoding: .utf8) }

        let favorite = FavoriteResult(
            id: result.id,
            title: result.title,
            source: result.source,
            urlString: result.url?.absoluteString,
            metadataJSON: jsonString
        )
        container.mainContext.insert(favorite)
        try? container.mainContext.save()
    }

    func fetchFavorites() -> [FavoriteResult] {
        let descriptor = FetchDescriptor<FavoriteResult>(
            sortBy: [SortDescriptor(\.savedDate, order: .reverse)]
        )
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    func deleteFavorite(_ favorite: FavoriteResult) {
        container.mainContext.delete(favorite)
        try? container.mainContext.save()
    }

    // MARK: - Search History

    func addSearchHistory(query: String, resultCount: Int) {
        // Avoid duplicate consecutive entries
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let entry = SearchHistoryEntry(query: trimmed, resultCount: resultCount)
        container.mainContext.insert(entry)

        // Prune history to most recent 50 entries
        let descriptor = FetchDescriptor<SearchHistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let all = try? container.mainContext.fetch(descriptor), all.count > 50 {
            all.dropFirst(50).forEach { container.mainContext.delete($0) }
        }

        try? container.mainContext.save()
    }

    func fetchSearchHistory() -> [SearchHistoryEntry] {
        let descriptor = FetchDescriptor<SearchHistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    func clearSearchHistory() {
        let descriptor = FetchDescriptor<SearchHistoryEntry>()
        if let all = try? container.mainContext.fetch(descriptor) {
            all.forEach { container.mainContext.delete($0) }
            try? container.mainContext.save()
        }
    }
}
