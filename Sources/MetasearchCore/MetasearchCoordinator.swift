import Foundation

public actor MetasearchCoordinator {
    private let sources: [any SearchSource]
    private let timeout: TimeInterval
    private let resultAggregator: ResultAggregator
    private let resultPrioritizer: ResultPrioritizer
    private let denyListFilter: DenyListFilter
    
    public init(
        sources: [any SearchSource],
        timeout: TimeInterval = 3.0,
        denyListFilter: DenyListFilter = DenyListFilter(defaultDomains: [
            "amazon.com",
            "walmart.com",
            "target.com",
            "homedepot.com",
            "lowes.com",
            "bestbuy.com"
        ])
    ) {
        self.sources = sources
        self.timeout = timeout
        self.resultAggregator = ResultAggregator()
        self.resultPrioritizer = ResultPrioritizer()
        self.denyListFilter = denyListFilter
    }
    
    public func search(query: EnhancedQuery) async throws -> [SearchResult] {
        // Execute searches in parallel with timeout
        var allResults: [SearchResult] = []
        let sourcesToSearch = sources
        let queryToSearch = query
        let timeoutValue = timeout
        
        try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            for i in sourcesToSearch.indices {
                let source = sourcesToSearch[i]
                group.addTask {
                    do {
                        return try await self.withTimeout(seconds: timeoutValue) {
                            try await source.search(query: queryToSearch)
                        }
                    } catch {
                        // Return empty results on timeout or error
                        return []
                    }
                }
            }
            
            for try await results in group {
                allResults.append(contentsOf: results)
            }
        }
        
        // Aggregate, filter, and prioritize results
        var filteredResults = resultAggregator.filter(results: allResults, denyList: denyListFilter)
        filteredResults = resultAggregator.aggregate(results: filteredResults)
        filteredResults = resultPrioritizer.prioritize(results: filteredResults)
        
        return filteredResults
    }
    
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    public func updateDenyList(filter: DenyListFilter) {
        // Note: This would need proper actor synchronization
        // For now, deny list is set at initialization
    }
}

private struct TimeoutError: Error {}
