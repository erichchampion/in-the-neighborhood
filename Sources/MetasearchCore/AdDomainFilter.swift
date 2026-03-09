import Foundation

/// Filters URLs based on known advertising domains
/// Loads ad domains from AdDomainListDownloadManager's cached list
public struct AdDomainFilter: Sendable {
    private var adDomains: Set<String>
    
    /// Initialize with ad domains from download manager
    /// Returns empty set if list not available yet (graceful degradation)
    public init() {
        // Try to load from download manager
        if let domains = AdDomainListDownloadManager.shared.getAdDomains() {
            self.adDomains = domains
        } else {
            // If list not available yet, use empty set (graceful degradation)
            // This allows the app to work even if download hasn't completed
            self.adDomains = Set<String>()
        }
    }
    
    /// Initialize with custom domain set (for testing)
    /// - Parameter domains: Set of ad domains to use
    public init(domains: Set<String>) {
        self.adDomains = domains
    }
    
    /// Check if a URL should be filtered based on ad domains
    /// - Parameter url: URL to check
    /// - Returns: True if URL should be filtered (is an ad domain)
    public func shouldFilter(url: URL) -> Bool {
        // Check special URL path patterns first (e.g., Bing ad click URLs)
        if isAdPath(url: url) {
            return true
        }
        
        guard let host = url.host?.lowercased() else {
            return false
        }
        
        // Check exact match
        if adDomains.contains(host) {
            return true
        }
        
        // Extract base domain from host (e.g., "amazon" from "www.amazon.ca")
        let hostBaseDomain = extractBaseDomain(from: host)
        
        // Check if any ad domain matches this host
        for adDomain in adDomains {
            // Check exact match
            if host == adDomain {
                return true
            }
            
            // Extract base domain from ad domain (e.g., "amazon" from "amazon.com")
            let adBaseDomain = extractBaseDomain(from: adDomain)
            
            // Match if base domains are the same (handles different TLDs and subdomains)
            // e.g., "amazon.com" will match "amazon.ca", "www.amazon.com", "www.amazon.ca", etc.
            if !adBaseDomain.isEmpty && hostBaseDomain == adBaseDomain {
                return true
            }
            
            // Also check if host ends with the ad domain (for subdomain matching)
            // e.g., "www.amazon.com" ends with "amazon.com"
            if host.hasSuffix("." + adDomain) || host == adDomain {
                return true
            }
        }
        
        return false
    }
    
    /// Check if URL path indicates an ad (e.g., Bing ad click URLs)
    /// - Parameter url: URL to check
    /// - Returns: True if path indicates an ad
    private func isAdPath(url: URL) -> Bool {
        let path = url.path.lowercased()
        
        // Check for Bing ad click patterns
        if path.contains("/aclk") || path.contains("/clk") {
            return true
        }
        
        // Check for other known ad path patterns
        let adPathPatterns = [
            "/ads/",
            "/advertisement",
            "/sponsored",
            "adclick",
            "adclick.net"
        ]
        
        let urlString = url.absoluteString.lowercased()
        return adPathPatterns.contains { urlString.contains($0) }
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
    
    /// Get count of ad domains in filter
    public var domainCount: Int {
        return adDomains.count
    }
}
