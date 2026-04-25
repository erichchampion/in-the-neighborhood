import Foundation
import Combine
import SwiftUI
import MetasearchCore

/// Manages interactions between AppIntents / Siri and the application UI.
@MainActor
public class IntentManager: ObservableObject {
    public static let shared = IntentManager()
    
    public enum SearchType {
        case general
        case localStores
        case products
    }
    
    public struct PendingSearch {
        public let query: String
        public let type: SearchType
    }
    
    @Published public var pendingSearch: PendingSearch?
    
    private init() {}
    
    public func handleSearchIntent(query: String, type: SearchType) {
        self.pendingSearch = PendingSearch(query: query, type: type)
    }
    
    public func clearPendingSearch() {
        self.pendingSearch = nil
    }
}
