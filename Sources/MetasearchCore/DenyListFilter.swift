import Foundation

public struct DenyListFilter: Sendable {
    private var deniedDomains: Set<String>
    
    public init(defaultDomains: [String] = []) {
        let initialDomains = defaultDomains.isEmpty ? [
            "amazon.com", "amazon.ca", "amazon.co.uk", "amazon.de", "amazon.fr", "amazon.co.jp",
            "walmart.com", "walmart.ca",
            "target.com",
            "bestbuy.com", "bestbuy.ca", // Added BestBuy since we use it behind the scenes for metadata
            "homedepot.com", "homedepot.ca",
            "lowes.com", "lowes.ca",
            "macys.com",
            "costco.com", "costco.ca"
        ] : defaultDomains
        
        self.deniedDomains = Set(initialDomains.map { $0.lowercased() })
    }
    
    public func shouldFilter(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        
        // Check exact match
        if deniedDomains.contains(host) {
            return true
        }
        
        // Extract base domain from host (e.g., "amazon" from "www.amazon.ca")
        let hostBaseDomain = extractBaseDomain(from: host)
        
        // Check if any denied domain matches this host
        for deniedDomain in deniedDomains {
            // Check exact match
            if host == deniedDomain {
                return true
            }
            
            // Extract base domain from denied domain (e.g., "amazon" from "amazon.com")
            let deniedBaseDomain = extractBaseDomain(from: deniedDomain)
            
            // Match if base domains are the same (handles different TLDs and subdomains)
            // e.g., "amazon.com" will match "amazon.ca", "www.amazon.com", "www.amazon.ca", etc.
            if !deniedBaseDomain.isEmpty && hostBaseDomain == deniedBaseDomain {
                return true
            }
            
            // Also check if host ends with the denied domain (for subdomain matching)
            // e.g., "www.amazon.com" ends with "amazon.com"
            if host.hasSuffix("." + deniedDomain) || host == deniedDomain {
                return true
            }
        }
        
        return false
    }
    
    /// Extracts the base domain name from a full domain
    /// Examples:
    /// - "amazon.com" -> "amazon"
    /// - "www.amazon.com" -> "amazon"
    /// - "amazon.ca" -> "amazon"
    /// - "www.amazon.co.uk" -> "amazon"
    private func extractBaseDomain(from domain: String) -> String {
        let components = domain.components(separatedBy: ".")
        
        guard components.count >= 2 else {
            return components.first ?? ""
        }
        
        // Known two-part TLD prefixes (e.g., .co.uk, .com.au, .co.nz)
        // These are second-level domains that are part of the TLD, not the base domain
        let twoPartTLDPrefixes = Set(["co", "com", "net", "org", "ac", "gov", "edu", "sch"])
        
        // For domains with 3+ components, check if we have a two-part TLD
        if components.count >= 3 {
            let secondToLast = components[components.count - 2]
            if twoPartTLDPrefixes.contains(secondToLast) {
                // Two-part TLD: e.g., "amazon.co.uk" -> ["amazon", "co", "uk"]
                // Return the third-to-last component (the base domain)
                return components[components.count - 3]
            }
        }
        
        // Single-part TLD or subdomain with single-part TLD
        // e.g., "amazon.com" -> ["amazon", "com"] -> return "amazon"
        // e.g., "www.amazon.com" -> ["www", "amazon", "com"] -> return "amazon"
        return components[components.count - 2]
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
