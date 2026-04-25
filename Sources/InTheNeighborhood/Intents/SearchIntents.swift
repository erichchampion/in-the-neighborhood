import AppIntents
import Foundation

// MARK: - Find Local Store Intent

@available(iOS 16.0, macOS 13.0, *)
public struct FindLocalStoreIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Local Store"
    public static let description = IntentDescription("Searches for a local store or business near you.")
    
    public static let openAppWhenRun: Bool = true
    
    @Parameter(title: "Store Type or Name", description: "The type of store to find (e.g., hardware, bookstore)")
    public var query: String
    
    public init() {}
    
    public init(query: String) {
        self.query = query
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentManager.shared.handleSearchIntent(query: query, type: .localStores)
        return .result()
    }
}

// MARK: - Search Product Intent

@available(iOS 16.0, macOS 13.0, *)
public struct SearchProductIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search for Product"
    public static let description = IntentDescription("Searches for a product across local stores and online retailers.")
    
    public static let openAppWhenRun: Bool = true
    
    @Parameter(title: "Product Name", description: "The product to search for")
    public var query: String
    
    public init() {}
    
    public init(query: String) {
        self.query = query
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentManager.shared.handleSearchIntent(query: query, type: .products)
        return .result()
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, macOS 13.0, *)
public struct SearchShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindLocalStoreIntent(),
            phrases: [
                "Find a local store in \(.applicationName)",
                "Search for a store near me in \(.applicationName)",
                "Look for local businesses in \(.applicationName)"
            ],
            shortTitle: "Find Local Store",
            systemImageName: "building.2"
        )
        
        AppShortcut(
            intent: SearchProductIntent(),
            phrases: [
                "Search for a product in \(.applicationName)",
                "Find a product in \(.applicationName)",
                "Look up an item on \(.applicationName)"
            ],
            shortTitle: "Search Product",
            systemImageName: "magnifyingglass"
        )
    }
}
