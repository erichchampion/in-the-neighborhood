import XCTest
@testable import InTheNeighborhood

final class SettingsManagerTests: XCTestCase {
    nonisolated(unsafe) var manager: SettingsManager!
    
    override func setUp() {
        super.setUp()
    }
    
    @MainActor
    func test_SettingsManager_PersistsDenyList() {
        manager = SettingsManager.shared
        manager.clearSearchHistory()
        
        manager.addDenyDomain("test.com")
        
        XCTAssertTrue(manager.denyList.isDenied("test.com"))
        
        // Create a new manager instance to verify persistence
        let newManager = SettingsManager.shared
        XCTAssertTrue(newManager.denyList.isDenied("test.com"))
        
        // Cleanup
        manager.removeDenyDomain("test.com")
    }
    
    @MainActor
    func test_SettingsManager_ValidatesRadius() {
        manager = SettingsManager.shared
        
        let validRadius = 8047.0 // 5 miles
        manager.searchRadius = validRadius
        
        XCTAssertEqual(manager.searchRadius, validRadius)
        
        // Should accept valid values
        manager.searchRadius = 16093.0 // 10 miles
        XCTAssertEqual(manager.searchRadius, 16093.0)
    }
    
    @MainActor
    func test_SettingsManager_ClearsSearchHistory() {
        manager = SettingsManager.shared
        
        // Add some test data
        UserDefaults.standard.set(["test"], forKey: "searchHistory")
        
        manager.clearSearchHistory()
        
        // Verify cleared
        let history = UserDefaults.standard.array(forKey: "searchHistory")
        XCTAssertNil(history)
    }
}
