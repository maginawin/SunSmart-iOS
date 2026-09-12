import XCTest
final class DebugCloudJSONUITests: XCTestCase {
    func testEnglishPortrait() { exercise(language: "en", landscape: false) }
    func testChinesePortrait() { exercise(language: "zh-Hans", landscape: false) }
    func testEnglishLandscape() { exercise(language: "en", landscape: true) }
    func testChineseLandscape() { exercise(language: "zh-Hans", landscape: true) }
    private func exercise(language: String, landscape: Bool) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let title = language == "en" ? "Export Json" : "导出 JSON"
        for scope in ["site", "space"] {
            for role in ["owner", "editor", "visitor"] {
                let app = XCUIApplication()
                app.launchArguments = [scope, role, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
                app.launch()
                XCTAssertTrue(app.staticTexts["Snapshot tests passed"].waitForExistence(timeout: 10))
                app.navigationBars.buttons["Menu"].tap()
                XCTAssertTrue(app.staticTexts["Layout passed"].waitForExistence(timeout: 5))
                let item = app.tables.staticTexts[title]
                if role == "visitor" { XCTAssertFalse(item.exists); app.terminate(); continue }
                XCTAssertTrue(item.isHittable)
                attach(app, name: "\(scope)-\(role)-\(language)-\(landscape)-menu")
                item.tap()
                XCTAssertTrue(app.staticTexts["Share presented"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.otherElements["json-share"].waitForExistence(timeout: 5))
                attach(app, name: "\(scope)-\(role)-\(language)-\(landscape)-share")
                app.terminate()
            }
        }
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
