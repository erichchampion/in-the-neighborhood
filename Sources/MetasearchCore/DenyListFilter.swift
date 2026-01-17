import Foundation

public struct DenyListFilter {
    private var deniedDomains: Set<String>
    
    public init(defaultDomains: [String] = []) {
        self.deniedDomains = Set(defaultDomains.map { $0.lowercased() })
    }
    
    public func shouldFilter(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        
        // Check exact match
        if deniedDomains.contains(host) {
            return true
        }
        
        // Check if host contains any denied domain (for subdomains)
        for domain in deniedDomains {
            if host.contains(domain) {
                return true
            }
        }
        
        return false
    }
    
    public mutating func addDomain(_ domain: String) {
        deniedDomains.insert(domain.lowercased())
    }
    
    public mutating func removeDomain(_ domain: String) {
        deniedDomains.remove(domain.lowercased())
    }
    
    public func isDenied(_ domain: String) -> Bool {
        deniedDomains.contains(domain.lowercased())
    }
    
    public var allDeniedDomains: [String] {
        Array(deniedDomains)
    }
}
