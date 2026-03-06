import SwiftUI
import SwiftData
import SharedModels
import MetasearchCore
import CoreLocation
import MapKit

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedStore.savedDate, order: .reverse) private var savedStores: [SavedStore]
    @Query(sort: \FavoriteResult.savedDate, order: .reverse) private var favorites: [FavoriteResult]
    
    @State private var selectedTab: FavoriteTab = .stores
    
    enum FavoriteTab: String, CaseIterable {
        case stores = "Local Stores"
        case products = "Online Products"
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Favorites Type", selection: $selectedTab) {
                    ForEach(FavoriteTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == .stores {
                    storesList
                } else {
                    productsList
                }
            }
            .navigationTitle("Favorites")
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private var storesList: some View {
        List {
            if savedStores.isEmpty {
                emptyState(systemImage: "building.2", message: "No stores saved yet.")
            } else {
                ForEach(savedStores) { store in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.name)
                            .font(.headline)
                        if let address = store.address {
                            Text(address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(store.savedDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button {
                                openInMaps(store: store)
                            } label: {
                                Label("Open in Maps", systemImage: "map")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteStores)
            }
        }
    }
    
    private var productsList: some View {
        List {
            if favorites.isEmpty {
                emptyState(systemImage: "cart", message: "No products favorited yet.")
            } else {
                ForEach(favorites) { favorite in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(favorite.title)
                            .font(.headline)
                            .lineLimit(2)
                        
                        HStack {
                            Text(favorite.source.uppercased())
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                            
                            Spacer()
                            
                            if let url = favorite.url {
                                Link(destination: url) {
                                    Label("View Online", systemImage: "safari")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteFavorites)
            }
        }
    }
    
    private func emptyState(systemImage: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .listRowBackground(Color.clear)
    }
    
    private func deleteStores(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(savedStores[index])
        }
    }
    
    private func deleteFavorites(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
    }
    
    private func openInMaps(store: SavedStore) {
        let location = CLLocation(latitude: store.latitude, longitude: store.longitude)
        let address = MKAddress(fullAddress: store.address ?? "", shortAddress: nil)
        let mapItem = MKMapItem(location: location, address: address)
        mapItem.name = store.name
        mapItem.openInMaps()
    }
}

#Preview {
    FavoritesView()
        .modelContainer(for: [SavedStore.self, FavoriteResult.self], inMemory: true)
}
