import XCTest
final class SunSmartAppSmokeUITests: XCTestCase {
    func testFinalSpaceState() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.azoula.sunsmart")
        app.activate()
        XCTAssertTrue(app.navigationBars["Group 1"].waitForExistence(timeout: 10))
        app.navigationBars["Group 1"].buttons["navigation back"].tap()
        XCTAssertTrue(app.navigationBars["Space 2"].waitForExistence(timeout: 10))
        let frame = app.buttons["Main"].frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.staticTexts["Group 1-L2"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Group 1-L3"].exists)
        XCTAssertEqual(app.images.matching(identifier: "device_Lighting").count, 2)
        capture(app, "Final Space 2 both devices online")
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
