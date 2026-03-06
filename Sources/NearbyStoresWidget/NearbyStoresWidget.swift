import WidgetKit
import SwiftUI
import SwiftData
import SharedModels

// MARK: - Entry

struct NearbyStoresEntry: TimelineEntry {
    let date: Date
    let stores: [StoreSnapshot]
}

/// Lightweight Sendable snapshot used by the widget timeline — avoids
/// passing SwiftData model objects across concurrency domains.
struct StoreSnapshot: Identifiable, Sendable {
    let id: String
    let name: String
    let address: String?
}

// MARK: - Timeline Provider

struct NearbyStoresProvider: TimelineProvider {
    typealias Entry = NearbyStoresEntry

    func placeholder(in context: Context) -> NearbyStoresEntry {
        NearbyStoresEntry(
            date: .now,
            stores: [
                StoreSnapshot(id: "1", name: "Local Bookshop", address: "123 Main St"),
                StoreSnapshot(id: "2", name: "Hardware Store", address: "456 Oak Ave")
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NearbyStoresEntry) -> Void) {
        let stores = fetchStores()
        completion(NearbyStoresEntry(date: .now, stores: stores))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyStoresEntry>) -> Void) {
        let stores = fetchStores()
        let entry = NearbyStoresEntry(date: .now, stores: stores)
        // Refresh after 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: - Private

    private func fetchStores() -> [StoreSnapshot] {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.in-the-neighborhood.shared"
        ) else { return [] }

        let storeURL = groupURL.appendingPathComponent("InTheNeighborhood.sqlite")
        let schema = Schema([SavedStore.self, SearchHistoryEntry.self, FavoriteResult.self])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        guard let container = try? ModelContainer(for: schema, configurations: [config])
        else { return [] }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SavedStore>(
            sortBy: [SortDescriptor(\.savedDate, order: .reverse)]
        )
        let results = (try? context.fetch(descriptor)) ?? []
        return results.prefix(3).map { StoreSnapshot(id: $0.id, name: $0.name, address: $0.address) }
    }
}

// MARK: - Widget Views

struct NearbyStoresWidgetView: View {
    var entry: NearbyStoresEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.stores.isEmpty {
            emptyView
        } else {
            filledView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "building.2.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No saved stores yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var filledView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13, weight: .semibold))
                Text("Nearby Stores")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.bottom, 8)

            // Store rows
            ForEach(entry.stores.prefix(displayCount(for: family))) { store in
                StoreRowView(store: store)
                    .padding(.bottom, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func displayCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        default: return 3
        }
    }
}

struct StoreRowView: View {
    let store: StoreSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(.green.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "storefront")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(store.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let address = store.address {
                    Text(address)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Widget Declaration

@main
struct NearbyStoresWidget: Widget {
    let kind: String = "NearbyStoresWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NearbyStoresProvider()) { entry in
            NearbyStoresWidgetView(entry: entry)
        }
        .configurationDisplayName("Nearby Stores")
        .description("Your saved local stores at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    NearbyStoresWidget()
} timeline: {
    NearbyStoresEntry(
        date: .now,
        stores: [
            StoreSnapshot(id: "1", name: "Green Apple Bookstore", address: "506 Clement St"),
            StoreSnapshot(id: "2", name: "Cliff's Variety", address: "479 Castro St"),
            StoreSnapshot(id: "3", name: "Cole Hardware", address: "956 Cole St")
        ]
    )
}
