import XCTest
final class SunSmartAppSmokeUITests: XCTestCase {
    func testSunSmartPortraitNavigation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.azoula.sunsmart")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.navigationBars["Sites"].waitForExistence(timeout: 10))
        let allSites = app.buttons["ALL SITES"]
        let favourites = app.buttons["FAVOURITES"]
        XCTAssertTrue(allSites.exists && favourites.exists)
        favourites.tap()
        XCTAssertTrue(favourites.isSelected)
        capture(app, "Favourites")
        allSites.tap()
        XCTAssertTrue(allSites.isSelected)
        let site = app.staticTexts["Site 1"].firstMatch
        XCTAssertTrue(site.waitForExistence(timeout: 5))
        site.tap()
        XCTAssertTrue(app.navigationBars["Site 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No Spaces!"].waitForExistence(timeout: 5))
        capture(app, "Site 1 spaces")
        app.navigationBars["Site 1"].buttons["navigation back"].tap()
        XCTAssertTrue(app.navigationBars["Sites"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ALL SITES"].isSelected)
        capture(app, "Returned to Sites")
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
