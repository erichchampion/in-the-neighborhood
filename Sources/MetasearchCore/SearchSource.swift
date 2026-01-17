import Foundation

public protocol SearchSource: Sendable {
    var identifier: String { get }
    var sourceType: SourceType { get }
    
    func search(query: EnhancedQuery) async throws -> [SearchResult]
}
