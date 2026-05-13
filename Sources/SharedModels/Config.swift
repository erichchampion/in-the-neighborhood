import Foundation

public enum Config {
    public static let bingAPIKey: String = {
        Bundle.main.infoDictionary?["BING_API_KEY"] as? String ?? ""
    }()
    
    public static let bestBuyAPIKey: String = {
        Bundle.main.infoDictionary?["BESTBUY_API_KEY"] as? String ?? ""
    }()
    
    public static let dplaAPIKey: String = {
        Bundle.main.infoDictionary?["DPLA_API_KEY"] as? String ?? ""
    }()
}
