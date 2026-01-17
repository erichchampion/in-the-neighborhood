import XCTest

final class SettingsViewUITests: XCTestCase {
    // XCTest setup runs on main thread by default, so nonisolated(unsafe) is safe here
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
    func testSettingsView() throws {
        // Wait for settings button and navigate to settings
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5.0), "Settings button should exist")
        settingsButton.tap()
        
        // Verify settings view appears
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 5.0), "Settings navigation bar should appear")
        
        // Verify settings view content exists by checking for unique elements
        // SwiftUI Form section headers may not be exposed as staticTexts in XCUI
        // Instead, verify the presence of buttons and controls unique to settings
        
        // Verify "Add Domain" button exists (unique to Deny List section)
        // The button uses an accessibility label which overrides the displayed text
        let addDomainButton = app.buttons["Add domain to deny list"]
        XCTAssertTrue(addDomainButton.waitForExistence(timeout: 2.0), "Add Domain button should exist")
        
        // Verify "Clear Search History" button exists (unique to Privacy section)
        // This button also uses an accessibility label
        let clearHistoryButton = app.buttons["Clear search history"]
        XCTAssertTrue(clearHistoryButton.waitForExistence(timeout: 2.0), "Clear Search History button should exist")
        
        // Verify settings view has content by checking for "Done" button in toolbar
        // "Done" button uses accessibility label, but the text "Done" should also work
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2.0), "Done button should exist in settings toolbar")
    }
}
