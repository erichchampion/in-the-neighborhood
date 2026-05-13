import Foundation

/// API keys loaded from build configuration
/// Keys are set via xcconfig files or build environment variables
/// 
/// To set API keys:
/// 1. Copy Config/Debug.xcconfig.example to Config/Debug.xcconfig and add your keys
/// 2. Copy Config/Release.xcconfig.example to Config/Release.xcconfig and add your keys
/// 3. Or set BING_API_KEY as an environment variable
/// 4. After updating xcconfig files, regenerate the Xcode project: xcodegen generate
enum APIKeys {
    /// Bing Search API key
    static var bingAPIKey: String? {
        // Try multiple methods to read the key
        
        // Method 1: Read from Info.plist (set via INFOPLIST_KEY_* in project.yml)
        if let key = Bundle.main.object(forInfoDictionaryKey: "BING_API_KEY") as? String,
           !key.isEmpty, key != "$(BING_API_KEY)" {
            print("[APIKeys] Found BING_API_KEY in Info.plist")
            return key
        }
        
        // Method 2: Read from environment variable (for CI/CD or direct builds)
        if let key = ProcessInfo.processInfo.environment["BING_API_KEY"],
           !key.isEmpty {
            print("[APIKeys] Found BING_API_KEY in environment")
            return key
        }
        
        // Method 3: Try reading from Info.plist with different key format
        if let key = Bundle.main.object(forInfoDictionaryKey: "BingAPIKey") as? String,
           !key.isEmpty {
            print("[APIKeys] Found BingAPIKey in Info.plist")
            return key
        }
        
        print("[APIKeys] BING_API_KEY not found")
        return nil
    }
    
    /// Best Buy API key for product search
    static var bestbuyAPIKey: String? {
        // Method1: Read from Info.plist (set via INFOPLIST_KEY_* in project.yml)
        if let key = Bundle.main.object(forInfoDictionaryKey: "BESTBUY_API_KEY") as? String,
           !key.isEmpty, key != "$(BESTBUY_API_KEY)" {
            print("[APIKeys] Found BESTBUY_API_KEY in Info.plist")
            return key
        }
        
        // Method2: Read from environment variable (for CI/CD or direct builds)
        if let key = ProcessInfo.processInfo.environment["BESTBUY_API_KEY"],
           !key.isEmpty {
            print("[APIKeys] Found BESTBUY_API_KEY in environment")
            return key
        }
        
        print("[APIKeys] BESTBUY_API_KEY not found")
        return nil
    }
    
    /// Digital Public Library of America API key
    static var dplaAPIKey: String? {
        // Method1: Read from Info.plist (set via INFOPLIST_KEY_* in project.yml)
        if let key = Bundle.main.object(forInfoDictionaryKey: "DPLA_API_KEY") as? String,
           !key.isEmpty, key != "$(DPLA_API_KEY)" {
            print("[APIKeys] Found DPLA_API_KEY in Info.plist")
            return key
        }
        
        // Method2: Read from environment variable
        if let key = ProcessInfo.processInfo.environment["DPLA_API_KEY"],
           !key.isEmpty {
            print("[APIKeys] Found DPLA_API_KEY in environment")
            return key
        }
        
        print("[APIKeys] DPLA_API_KEY not found")
        return nil
    }
}
