import XCTest

final class SearchViewUITests: XCTestCase {
    // XCTest setup runs on main thread, so nonisolated(unsafe) is safe here
    nonisolated(unsafe) var app: XCUIApplication!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        
        // XCUIApplication initialization
        // Ensure we're on main thread (XCTest guarantees this)
        precondition(Thread.isMainThread, "setUpWithError must run on main thread")
        
        // Use MainActor.assumeIsolated to satisfy Swift 6 actor isolation requirements
        // This is safe because we've verified we're on the main thread
        let application = MainActor.assumeIsolated {
            // Explicitly specify bundle identifier to work around XcodeGen limitation
            // where bundle.unit-test doesn't automatically populate targetApplicationPath
            let app = XCUIApplication(bundleIdentifier: "com.in-the-neighborhood")
            app.launchArguments = []
            app.launchEnvironment = [:]
            app.launch()
            return app
        }
        self.app = application
    }
    
    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }
    
    @MainActor
    func testSearchFlow() throws {
        // SwiftUI TextFields are textFields, not searchFields
        // Wait for the app to launch and UI to be ready
        let searchField = app.textFields["Search for products"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5.0), "Search field should exist")
        
        // Enter search query
        searchField.tap()
        searchField.typeText("bicycle")
        
        // Wait for results or "no results" message (with timeout)
        // The results might appear in scrollViews, lists, or as staticTexts
        let results = app.scrollViews.firstMatch
        let noResults = app.staticTexts["No results found"]
        let hasResults = results.waitForExistence(timeout: 10.0)
        let hasNoResults = noResults.waitForExistence(timeout: 10.0)
        XCTAssertTrue(hasResults || hasNoResults, "Should show either results or 'no results' message")
    }
    
    @MainActor
    func testSettingsNavigation() throws {
        // Wait for settings button to appear and tap it
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5.0), "Settings button should exist")
        settingsButton.tap()
        
        // Verify settings view appears
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 5.0), "Settings navigation bar should appear")
        
        // Verify settings view content exists by checking for unique buttons
        // SwiftUI Form section headers may not be exposed as staticTexts in XCUI
        // The button uses an accessibility label which overrides the displayed text
        let addDomainButton = app.buttons["Add domain to deny list"]
        XCTAssertTrue(addDomainButton.waitForExistence(timeout: 2.0), "Add Domain button should exist in settings")
    }
}
