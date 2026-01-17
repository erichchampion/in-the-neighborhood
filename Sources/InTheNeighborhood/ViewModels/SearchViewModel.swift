import Foundation
import SwiftUI
import MetasearchCore
import LLMIntegration

@MainActor
public class SearchViewModel: ObservableObject {
    @Published public var searchText = ""
    @Published public var state: SearchState = .idle
    @Published public var results: [SearchResult] = []
    @Published public var errorMessage: String?
    
    private let coordinator: MetasearchCoordinator
    private let queryEnhancer: QueryEnhancer
    private var searchTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval = 0.5 // seconds
    
    public enum SearchState {
        case idle
        case loading
        case loaded
        case error
    }
    
    public init(
        coordinator: MetasearchCoordinator,
        queryEnhancer: QueryEnhancer
    ) {
        self.coordinator = coordinator
        self.queryEnhancer = queryEnhancer
    }
    
    public func search(query: String) async {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            state = .idle
            results = []
            return
        }
        
        state = .loading
        errorMessage = nil
        
        searchTask = Task {
            do {
                // Enhance query with LLM
                let enhancedQuery = try await queryEnhancer.enhance(query: query)
                
                // Search using coordinator
                let searchResults = try await coordinator.search(query: enhancedQuery)
                
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    return
                }
                
                results = searchResults
                state = .loaded
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                
                errorMessage = error.localizedDescription
                state = .error
            }
        }
        
        await searchTask?.value
    }
    
    public func debouncedSearch() {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            state = .idle
            results = []
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            
            guard !Task.isCancelled else {
                return
            }
            
            await search(query: searchText)
        }
    }
    
    public func clearResults() {
        searchTask?.cancel()
        searchText = ""
        state = .idle
        results = []
        errorMessage = nil
    }
}
