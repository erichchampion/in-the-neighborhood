import XCTest

final class SearchViewUITests: XCTestCase {
    nonisolated(unsafe) var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        let appInstance = MainActor.assumeIsolated {
            let application = XCUIApplication()
            application.launch()
            return application
        }
        app = appInstance
    }
    
    @MainActor
    func testSearchFlow() throws {
        // Find search field
        let searchField = app.searchFields["Search for products"]
        XCTAssertTrue(searchField.exists)
        
        // Enter search query
        searchField.tap()
        searchField.typeText("bicycle")
        
        // Wait for results (with timeout)
        // Use scrollViews or otherElements instead of lists which doesn't exist
        let results = app.scrollViews.firstMatch
        let exists = results.waitForExistence(timeout: 10.0)
        XCTAssertTrue(exists || app.staticTexts["No results found"].exists)
    }
    
    @MainActor
    func testSettingsNavigation() throws {
        // Tap settings button
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.exists)
        settingsButton.tap()
        
        // Verify settings view appears
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 2.0))
        
        // Verify deny list section exists
        XCTAssertTrue(app.staticTexts["Deny List"].exists)
    }
}
