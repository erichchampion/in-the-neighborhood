import Foundation
import MetasearchCore

@MainActor
public class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    @Published public var denyList: DenyListFilter
    @Published public var searchRadius: Double {
        didSet {
            UserDefaults.standard.set(searchRadius, forKey: "searchRadius")
        }
    }
    
    private let denyListKey = "denyListDomains"
    private let searchRadiusKey = "searchRadius"
    
    private init() {
        // Load deny list from UserDefaults
        if let domains = UserDefaults.standard.array(forKey: denyListKey) as? [String] {
            denyList = DenyListFilter(defaultDomains: domains)
        } else {
            // Default deny list
            denyList = DenyListFilter(defaultDomains: [
                "amazon.com",
                "walmart.com",
                "target.com",
                "homedepot.com",
                "lowes.com",
                "bestbuy.com"
            ])
        }
        
        // Load search radius from UserDefaults
        if UserDefaults.standard.object(forKey: searchRadiusKey) != nil {
            searchRadius = UserDefaults.standard.double(forKey: searchRadiusKey)
        } else {
            searchRadius = 16093.0 // 10 miles default
        }
    }
    
    public func addDenyDomain(_ domain: String) {
        denyList.addDomain(domain)
        saveDenyList()
    }
    
    public func removeDenyDomain(_ domain: String) {
        denyList.removeDomain(domain)
        saveDenyList()
    }
    
    private func saveDenyList() {
        let domains = denyList.allDeniedDomains
        UserDefaults.standard.set(domains, forKey: denyListKey)
    }
    
    public func clearSearchHistory() {
        // Clear any cached search history
        // Implementation depends on storage mechanism
        UserDefaults.standard.removeObject(forKey: "searchHistory")
    }
}
