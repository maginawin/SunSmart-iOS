import XCTest

final class WarningButtonUITests: XCTestCase {
    func testEnglish() { exercise(language: "en") }
    func testChinese() { exercise(language: "zh-Hans") }

    func testCameraPhotoAndRestart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["camera-smoke"]
        app.launch()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 4) {
            permission.buttons.element(boundBy: permission.buttons.count - 1).tap()
        }
        let result = app.staticTexts["camera-result"]
        expectation(for: NSPredicate(format: "label BEGINSWITH 'PASS:' OR label BEGINSWITH 'FAIL:'"), evaluatedWith: result)
        waitForExpectations(timeout: 25)
        XCTAssertEqual(result.label, "PASS: camera photo and restart", String(describing: result.value))
        app.terminate()
    }

    private func exercise(language: String) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        let result = app.staticTexts["result"]
        expectation(for: NSPredicate(format: "label BEGINSWITH 'PASS:' OR label BEGINSWITH 'FAIL:'"), evaluatedWith: result)
        waitForExpectations(timeout: 20)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Buttons-\(language)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result.label, "PASS: 11 button layouts", String(describing: result.value))
        app.buttons["button-0"].tap()
        XCTAssertEqual(app.staticTexts["taps"].label, "Taps: 1")
        app.terminate()
    }
}
