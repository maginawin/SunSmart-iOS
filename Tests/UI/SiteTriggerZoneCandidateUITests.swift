import XCTest

final class SiteTriggerZoneCandidateUITests: XCTestCase {
    func testCandidateLayouts() {
        for language in ["en", "zh-Hans"] {
            let app = launch(language: language, probe: true)
            let result = app.staticTexts["candidate-layout-probe-result"]
            XCTAssertTrue(result.waitForExistence(timeout: 60))
            XCTAssertEqual(result.label, "PASS")
            capture("candidate-layout-" + language)
            app.terminate()
        }
    }

    func testEnglishCandidateInteractions() { exercise(language: "en") }
    func testChineseCandidateInteractions() { exercise(language: "zh-Hans") }

    private func launch(language: String, probe: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if probe { app.launchArguments.append("candidate-layout-probe") }
        app.launch()
        XCTAssertTrue(app.buttons["site-zones-preview-toggle"].waitForExistence(timeout: 30))
        return app
    }

    private func exercise(language: String) {
        let app = launch(language: language)
        app.buttons["site-zones-preview-toggle"].tap()
        // Selecting the current item expands the candidate panel.
        app.cells["site-zone-11"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        let start = app.buttons["site-zone-quick-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(start.exists)
        capture("quick-idle-" + language)
        app.staticTexts[language == "en" ? "Manually add" : "手动添加"].tap()
        let candidates = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'site-zone-candidate-'"))
        XCTAssertGreaterThan(candidates.count, 0)
        let first = candidates.firstMatch
        let firstID = first.identifier
        first.tap()
        XCTAssertTrue(app.cells[firstID].exists)
        XCTAssertFalse(app.staticTexts[language == "en" ? "Remove" : "移除"].exists)
        capture("manual-offline-" + language)
        let filter = app.buttons["site-zone-added-filter"].firstMatch
        filter.tap()
        let include = app.staticTexts[language == "en" ? "Show the devices added in other Zones" : "显示在其他区域中添加的设备"]
        XCTAssertTrue(include.waitForExistence(timeout: 5))
        capture("added-filter-" + language)
        include.tap()
        app.buttons["site-zone-space-filter"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No Proximity Groups"].waitForExistence(timeout: 5))
        capture("space-menu-" + language)
        app.staticTexts["No Proximity Groups"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["No Proximity Groups"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)).tap()
        app.staticTexts[language == "en" ? "Trigger add" : "触发添加"].tap()
        XCTAssertEqual(app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'site-zone-candidate-'" )).count, 0)
        capture("trigger-offline-" + language)
        app.terminate()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
