import XCTest
final class SunSmartAppSmokeUITests: XCTestCase {
    func testProfileStop() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.azoula.sunsmart")
        app.activate()
        XCTAssertTrue(app.buttons["SAVE"].waitForExistence(timeout: 10))
        let plus = app.buttons.matching(identifier: "scene data value add").element(boundBy: 1)
        for _ in 0..<4 {
            if plus.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["11 min"].exists)
        XCTAssertTrue(plus.isHittable)
        capture(app, "Timeout original 11 min")
        plus.tap()
        XCTAssertTrue(app.staticTexts["12 min"].exists)
        capture(app, "Timeout test 12 min")
        app.buttons["SAVE"].tap()
        let stop = app.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        XCTAssertTrue(app.buttons["RE-SYNC"].waitForExistence(timeout: 10))
        capture(app, "Sync stopped")
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
