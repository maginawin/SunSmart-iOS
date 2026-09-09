import XCTest

/// Device-hosted acceptance; use an isolated app embedding the production controller.
final class SiteTriggerZoneInteractionUITests: XCTestCase {
    func testEnglishInteractions() { exercise(language: "en") }
    func testChineseInteractions() { exercise(language: "zh-Hans") }

    func testConfirmationLayouts() {
        for language in ["en", "zh-Hans"] {
            let app = launch(language: language)
            app.buttons["site-zones-preview-toggle"].tap()
            for operation in ["reset", "delete"] {
                visibleButton(app, "site-zone-item-\(operation)-FADE0000-0000-4000-8000-000000000011").tap()
                let cancel = app.buttons["site-zone-preview-cancel"]
                let confirm = app.buttons["site-zone-preview-confirm"]
                XCTAssertTrue(confirm.waitForExistence(timeout: 5))
                XCTAssertEqual(cancel.frame.union(confirm.frame).width, 302, accuracy: 1)
                attach(app, operation + "-confirmation-" + language)
                cancel.tap()
            }
            app.terminate()
        }
    }

    func testLandscapeDialog() {
        let app = launch(language: "en")
        app.buttons["site-zones-preview-toggle"].tap()
        visibleButton(app, "site-zone-space-sync").tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        wait(for: [landscape], timeout: 5)
        let settled = expectation(description: "Rotation animation completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        let ok = app.buttons["site-zone-sync-ok"]
        XCTAssertTrue(ok.isHittable)
        XCTAssertTrue(app.frame.contains(ok.frame))
        attach(app, "sync-landscape-settled-en")
        ok.tap()
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testProductionLayouts() {
        for language in ["en", "zh-Hans"] {
            let app = launch(language: language, probe: true)
            let result = app.staticTexts["layout-probe-result"]
            XCTAssertTrue(result.waitForExistence(timeout: 60))
            XCTAssertEqual(result.label, "PASS")
            attach(app, "layout-" + language)
            app.terminate()
        }
    }

    private func launch(language: String, probe: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if probe { app.launchArguments.append("layout-probe") }
        app.launch()
        XCTAssertTrue(app.buttons["site-zones-preview-toggle"].waitForExistence(timeout: 30))
        return app
    }

    private func exercise(language: String) {
        let app = launch(language: language)
        let toggle = app.buttons["site-zones-preview-toggle"]
        toggle.tap()
        let firstDevice = app.buttons["site-zone-device-preview-D02-space-0-device-0"]
        XCTAssertTrue(firstDevice.waitForExistence(timeout: 5))
        let resetID = "site-zone-item-reset-FADE0000-0000-4000-8000-000000000011"
        let deleteID = "site-zone-item-delete-FADE0000-0000-4000-8000-000000000011"
        XCTAssertTrue(app.buttons[resetID].firstMatch.isEnabled)
        visibleButton(app, "site-zone-space-sync").tap()
        XCTAssertTrue(app.buttons["site-zone-sync-ok"].waitForExistence(timeout: 5))
        attach(app, "sync-" + language)
        app.buttons["site-zone-sync-ok"].tap()
        for (space, count) in [(0, 3), (1, 4)] {
            for device in 0..<count {
                let tile = app.buttons["site-zone-device-preview-D02-space-\(space)-device-\(device)"]
                XCTAssertTrue(tile.exists)
                tile.tap()
                let remove = app.staticTexts[language == "en" ? "Remove" : "移除"].firstMatch
                XCTAssertTrue(remove.waitForExistence(timeout: 3))
                XCTAssertFalse(app.staticTexts[language == "en" ? "Identify" : "识别"].exists)
                remove.tap()
                XCTAssertFalse(tile.exists)
            }
            attach(app, "removed-space-\(space)-" + language)
        }
        XCTAssertFalse(app.buttons[resetID].firstMatch.isEnabled)
        XCTAssertTrue(app.buttons[deleteID].firstMatch.isEnabled)
        visibleButton(app, "site-zone-metadata-sync").tap()
        XCTAssertTrue(app.buttons["site-zone-sync-ok"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        attach(app, "empty-sync-landscape-" + language)
        app.buttons["site-zone-sync-ok"].tap()
        XCUIDevice.shared.orientation = .portrait
        toggle.tap()
        toggle.tap()
        XCTAssertTrue(firstDevice.waitForExistence(timeout: 5))
        visibleButton(app, resetID).tap()
        app.buttons["site-zone-preview-cancel"].tap()
        XCTAssertTrue(firstDevice.exists)
        visibleButton(app, resetID).tap()
        app.buttons["site-zone-preview-confirm"].tap()
        XCTAssertFalse(firstDevice.exists)
        XCTAssertFalse(app.buttons[resetID].firstMatch.isEnabled)
        visibleButton(app, deleteID).tap()
        app.buttons["site-zone-preview-cancel"].tap()
        XCTAssertTrue(app.buttons[deleteID].firstMatch.exists)
        visibleButton(app, deleteID).tap()
        app.buttons["site-zone-preview-confirm"].tap()
        XCTAssertFalse(app.buttons[deleteID].firstMatch.exists)
        attach(app, "deleted-" + language)
        toggle.tap()
        toggle.tap()
        XCTAssertTrue(firstDevice.waitForExistence(timeout: 5))
        let locked = app.buttons["site-zone-device-preview-D04-space-0-device-0"]
        for _ in 0..<6 where !locked.isHittable { app.tables["site-zones-list"].swipeUp() }
        XCTAssertTrue(locked.isHittable)
        XCTAssertFalse(app.cells["site-zone-13"].isSelected)
        locked.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.staticTexts[language == "en" ? "Remove" : "移除"].exists)
        XCTAssertTrue(locked.exists)
        XCTAssertFalse(app.cells["site-zone-13"].isSelected)
        visibleButton(app, "site-zone-space-sync").tap()
        XCTAssertTrue(app.buttons["site-zone-sync-ok"].waitForExistence(timeout: 5))
        app.buttons["site-zone-sync-ok"].tap()
        XCTAssertFalse(app.cells["site-zone-13"].isSelected)
        attach(app, "locked-" + language)
        app.terminate()
    }

    private func visibleButton(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let matches = app.buttons.matching(identifier: identifier)
        return matches.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? matches.firstMatch
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
