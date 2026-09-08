import XCTest
final class SunSmartAppSmokeUITests: XCTestCase {
    func testProfileRetry() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.azoula.sunsmart")
        app.activate()
        XCTAssertTrue(app.navigationBars["Sync device(s)"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["RE-SYNC"].isEnabled)
        app.buttons["Select all"].tap()
        XCTAssertTrue(app.buttons["RE-SYNC"].isEnabled)
        capture(app, "Stopped task selected")
        app.buttons["RE-SYNC"].tap()
        capture(app, "Retry running")
        XCTAssertTrue(app.navigationBars["Group 1"].buttons["more vertical"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.navigationBars["Sync device(s)"].exists)
        capture(app, "Retry completed Group 1")
        app.navigationBars["Group 1"].buttons["more vertical"].tap()
        app.staticTexts["Profile"].firstMatch.tap()
        XCTAssertTrue(app.buttons["SAVE"].waitForExistence(timeout: 10))
        let minus = app.buttons.matching(identifier: "scene data value minus").element(boundBy: 1)
        for _ in 0..<4 { if minus.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["12 min"].exists)
        capture(app, "Persisted test timeout 12 min")
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
