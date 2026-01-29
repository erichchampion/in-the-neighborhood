import Foundation
import MetasearchCore
import LLMIntegration

@MainActor
public class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    /// UserDefaults key for selected model ID (shared with LLMModelDownloadManager)
    public static let selectedModelIDKey = "selectedModelID"
    /// UserDefaults key for agent-driven search (AI chooses which tools to call)
    public static let useAgentSearchKey = "useAgentSearch"
    
    @Published public var denyList: DenyListFilter
    @Published public var searchRadius: Double {
        didSet {
            UserDefaults.standard.set(searchRadius, forKey: "searchRadius")
        }
    }
    
    @Published public var selectedModelID: LLMModelID {
        didSet {
            UserDefaults.standard.set(selectedModelID.rawValue, forKey: Self.selectedModelIDKey)
        }
    }
    
    @Published public var useAgentSearch: Bool {
        didSet {
            UserDefaults.standard.set(useAgentSearch, forKey: Self.useAgentSearchKey)
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
        
        // Load selected model ID from UserDefaults
        if let rawValue = UserDefaults.standard.string(forKey: Self.selectedModelIDKey),
           let modelID = LLMModelID(rawValue: rawValue) {
            selectedModelID = modelID
        } else {
            selectedModelID = LLMModelCatalog.defaultModelID
        }
        
        useAgentSearch = UserDefaults.standard.object(forKey: Self.useAgentSearchKey) as? Bool ?? false
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
