import XCTest

final class SettingsViewUITests: XCTestCase {
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
    func testSettingsView() throws {
        // Navigate to settings
        app.buttons["Settings"].tap()
        
        // Verify settings view appears
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 2.0))
        
        // Verify sections exist
        XCTAssertTrue(app.staticTexts["Deny List"].exists)
        XCTAssertTrue(app.staticTexts["Search Radius"].exists)
        XCTAssertTrue(app.staticTexts["Privacy"].exists)
        
        // Verify add domain button exists
        let addDomainButton = app.buttons["Add Domain"]
        XCTAssertTrue(addDomainButton.exists)
    }
}
