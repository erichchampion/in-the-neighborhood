import Foundation

public protocol URLSessionProtocol: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// Adapter to make URLSession conform to URLSessionProtocol without recursion
public struct URLSessionAdapter: URLSessionProtocol {
    private let session: URLSession
    
    public init(_ session: URLSession = .shared) {
        self.session = session
    }
    
    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
    
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
