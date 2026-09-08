import XCTest
final class SunSmartAppSmokeUITests: XCTestCase {
    func testRestoreWithImmediateRetry() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.azoula.sunsmart")
        app.activate()
        XCTAssertTrue(app.buttons["SAVE"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["12 min"].exists)
        app.buttons.matching(identifier: "scene data value minus").element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["11 min"].exists)
        capture(app, "Restoring original timeout 11 min")
        app.buttons["SAVE"].tap()
        app.buttons["Stop"].tap()
        app.buttons["Select all"].tap()
        XCTAssertTrue(app.buttons["RE-SYNC"].isEnabled)
        app.buttons["RE-SYNC"].tap()
        capture(app, "Immediate retry during restoration")
        XCTAssertTrue(app.navigationBars["Group 1"].buttons["more vertical"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.navigationBars["Sync device(s)"].exists)
        capture(app, "Restoration sync completed")
        app.navigationBars["Group 1"].buttons["more vertical"].tap()
        app.staticTexts["Profile"].firstMatch.tap()
        XCTAssertTrue(app.buttons["SAVE"].waitForExistence(timeout: 10))
        let minus = app.buttons.matching(identifier: "scene data value minus").element(boundBy: 1)
        for _ in 0..<4 { if minus.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["11 min"].exists)
        capture(app, "Restored persisted timeout 11 min")
        app.buttons["SAVE"].tap()
        XCTAssertTrue(app.navigationBars["Group 1"].buttons["more vertical"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["Sync device(s)"].exists)
        capture(app, "Unchanged profile no pending sync")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.height, frame.width)
    }
}
