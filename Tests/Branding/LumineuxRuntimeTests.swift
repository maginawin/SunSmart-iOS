import XCTest
import UIKit
import CryptoKit
@testable import Lumineux

@MainActor
final class LumineuxRuntimeTests: XCTestCase {
    private var window: UIWindow!
    private var originalWindow: UIWindow?

    override func setUp() {
        super.setUp()
        originalWindow = (UIApplication.shared.delegate as? AppDelegate)?.window
        if let scene = originalWindow?.windowScene {
            window = UIWindow(windowScene: scene)
            window.frame = UIScreen.main.bounds
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        // A separate window leaves the running app's root controller intact and
        // avoids interrupting its appearance transitions between test cases.
        (UIApplication.shared.delegate as? AppDelegate)?.window = window
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        window.isHidden = true
        settleAppearance()
        window.rootViewController = nil
        (UIApplication.shared.delegate as? AppDelegate)?.window = originalWindow
        originalWindow?.makeKey()
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private func show(_ controller: UIViewController) {
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        settleAppearance()
    }

    private func settleAppearance() {
        // UIKit completes appearance transitions on the next main-loop pass.
        // Drain that pass before replacing another root controller in a test.
        let settled = expectation(description: "UIKit appearance transition")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func assertBlue(_ color: UIColor?, alpha: CGFloat = 1, file: StaticString = #filePath, line: UInt = #line) {
        guard let color else { return XCTFail("Missing brand color", file: file, line: line) }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, actualAlpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &actualAlpha), file: file, line: line)
        XCTAssertEqual(red, 77.0 / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(green, 115.0 / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(blue, 138.0 / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualAlpha, alpha, accuracy: 0.001, file: file, line: line)
    }

    private func snapshot(_ view: UIView, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name + "-" + (Locale.preferredLanguages.first ?? "unknown")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertNamedImage(_ name: String, size: CGFloat,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let image = try XCTUnwrap(UIImage(named: name), "Missing Lumineux asset: \(name)", file: file, line: line)
        XCTAssertEqual(image.size.width, size, accuracy: 0.01, name, file: file, line: line)
        XCTAssertEqual(image.size.height, size, accuracy: 0.01, name, file: file, line: line)
    }

    private struct AssetManifest: Decodable {
        struct Asset: Decodable {
            let asset: String
            let size: CGFloat
        }
        let assets: [Asset]
    }

    private func oraclePixels(_ image: UIImage) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let context = try XCTUnwrap(CGContext(data: nil, width: cgImage.width, height: cgImage.height,
            bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let bytes = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        return (cgImage.width, cgImage.height,
                Array(UnsafeBufferPointer(start: bytes, count: cgImage.width * cgImage.height * 4)))
    }

    private func assertResolvedImageMatchesLumineuxSource(_ actual: UIImage?, name: String,
                                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try XCTUnwrap(actual, "Missing resolved Lumineux image: \(name)", file: file, line: line)
        let scale = Int(actual.scale.rounded())
        XCTAssertTrue((1...3).contains(scale), "Unexpected image scale for \(name): \(actual.scale)", file: file, line: line)
        let bundle = Bundle(for: LumineuxRuntimeTests.self)
        let referenceBundleIdentifier = try XCTUnwrap(bundle.bundleIdentifier,
                                                       "Reference bundle must have an identifier", file: file, line: line)
        let mainBundleIdentifier = try XCTUnwrap(Bundle.main.bundleIdentifier,
                                                  "Lumineux app bundle must have an identifier", file: file, line: line)
        XCTAssertNotEqual(referenceBundleIdentifier, mainBundleIdentifier,
                          "Reference catalog must not share the Lumineux app bundle identity", file: file, line: line)
        let sourceTraits = UITraitCollection(displayScale: actual.scale)
        let source = try XCTUnwrap(UIImage(named: name, in: bundle, compatibleWith: sourceTraits),
                                   "Missing independently compiled Lumineux reference image: \(name)", file: file, line: line)
        XCTAssertEqual(source.scale, actual.scale, "Reference scale differs for \(name)", file: file, line: line)
        let rendered = try oraclePixels(actual)
        let expected = try oraclePixels(source)
        XCTAssertEqual(rendered.width, expected.width, "Pixel width differs for \(name)", file: file, line: line)
        XCTAssertEqual(rendered.height, expected.height, "Pixel height differs for \(name)", file: file, line: line)
        let differences = zip(rendered.rgba, expected.rgba).map { abs(Int($0.0) - Int($0.1)) }
        if rendered.rgba != expected.rgba {
            print("ASSET_ORACLE \(name) maxDelta=\(differences.max() ?? 0) meanDelta=\(Double(differences.reduce(0, +)) / Double(max(differences.count, 1)))")
            if ["launch_logo", "space_main_selected"].contains(name) {
                for (label, value) in [("actual", actual), ("source", source)] {
                    let attachment = XCTAttachment(image: value)
                    attachment.name = "\(name)-\(label)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        XCTAssertTrue(rendered.rgba == expected.rgba, "Resolved image does not match Lumineux source PNG: \(name)", file: file, line: line)
    }

    func testWelcomeLayoutAndConsentStates() throws {
        let welcome = WelcomeViewController()
        show(NavigationViewController(rootViewController: welcome))
        let views = descendants(welcome.view)
        let logo = try XCTUnwrap(views.compactMap { $0 as? UIImageView }.first { $0.superview === welcome.view })
        XCTAssertEqual(logo.bounds.width, 120, accuracy: 0.5)
        XCTAssertEqual(logo.bounds.height, 120, accuracy: 0.5)
        try assertResolvedImageMatchesLumineuxSource(logo.image, name: "launch_logo_120")
        let title = try XCTUnwrap(views.compactMap { $0 as? UILabel }.first { $0.attributedText?.string.contains("Lumineux") == true })
        let policy = try XCTUnwrap(views.compactMap { $0 as? UITextView }.first)
        let button = try XCTUnwrap(views.compactMap { $0 as? UIButton }.first { $0.title(for: .normal) == "get_started".localizedString })
        let checkbox = try XCTUnwrap(views.compactMap { $0 as? UIButton }.first { $0 !== button })
        XCTAssertFalse(button.isUserInteractionEnabled)
        assertBlue(button.backgroundColor, alpha: 0.5)
        checkbox.sendActions(for: .touchUpInside)
        XCTAssertTrue(button.isUserInteractionEnabled)
        assertBlue(button.backgroundColor)
        try assertResolvedImageMatchesLumineuxSource(checkbox.currentImage, name: "select")
        XCTAssertEqual(checkbox.currentImage?.size, CGSize(width: 30, height: 30))
        XCTAssertGreaterThanOrEqual(checkbox.bounds.height, 30)
        XCTAssertFalse(checkbox.hasAmbiguousLayout)
        XCTAssertLessThan(logo.frame.maxY, title.frame.minY)
        let policyFrame = policy.convert(policy.bounds, to: welcome.view)
        XCTAssertLessThan(title.frame.maxY, policyFrame.minY, "Welcome title overlaps policy text")
        XCTAssertLessThan(policyFrame.maxY, button.frame.minY)
        for element in [logo, title, policy, button] {
            XCTAssertFalse(element.hasAmbiguousLayout, "Ambiguous layout: \(type(of: element))")
            let frame = element.convert(element.bounds, to: welcome.view)
            XCTAssertTrue(welcome.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "Element outside screen: \(frame)")
        }
        snapshot(window, "Welcome-enabled")
        checkbox.sendActions(for: .touchUpInside)
        XCTAssertFalse(button.isUserInteractionEnabled)
        snapshot(window, "Welcome-disabled")
    }

    func testMenuLogoAndServerMenuPreserved() throws {
        let host = UIViewController()
        host.view.backgroundColor = Background_Color
        show(host)
        let menu = MainMenuView(frame: host.view.bounds)
        host.view.addSubview(menu)
        menu.layoutIfNeeded()
        let logo = try XCTUnwrap(descendants(menu).compactMap { $0 as? UIImageView }.first { $0.image?.size == CGSize(width: 88, height: 88) })
        try assertResolvedImageMatchesLumineuxSource(logo.image, name: "launch_logo")
        XCTAssertEqual(logo.bounds.width, logo.bounds.height, accuracy: 0.5)
        XCTAssertFalse(logo.hasAmbiguousLayout)
        let table = try XCTUnwrap(descendants(menu).compactMap { $0 as? UITableView }.first)
        XCTAssertEqual(table.numberOfRows(inSection: 0), 3, "Server selection must remain available for Lumineux")
        XCTAssertTrue(descendants(menu).compactMap { $0 as? UILabel }.contains { $0.text == "Lumineux" })
        snapshot(window, "Menu")
    }

    func testBrandControlsAndSitesCell() throws {
        [Bar_Color, Bottom_Done_Color, Title_Done_Color, Slider_Color].forEach { assertBlue($0) }
        let host = UIViewController()
        host.view.backgroundColor = Background_Color
        show(host)
        let width = host.view.bounds.width - 32
        let segment = CustomSegmentedControl(frame: CGRect(x: 16, y: 100, width: width, height: 44), titles: ["all_sites".localizedString, "favourites_sites".localizedString])
        host.view.addSubview(segment)
        segment.layoutIfNeeded()
        assertBlue(segment.selectBgColor)
        segment.selectedIndex = 1
        XCTAssertEqual(segment.selectedIndex, 1)
        let cell = SitesViewCell(frame: CGRect(x: 16, y: 170, width: width, height: SCRYFrom(100)))
        // Test-only labels exercise the production cell's constraints. No app data is saved.
        cell.nameLabel.text = "sites".localizedString
        cell.timeLabel.text = "2026/08/28 12:00"
        cell.spaceNumLabel.text = "15"
        host.view.addSubview(cell)
        cell.layoutIfNeeded()
        var selected: Bool?
        cell.clickFavouriteCallback = { selected = $0 }
        cell.favoriteBtn.sendActions(for: .touchUpInside)
        XCTAssertEqual(selected, true)
        XCTAssertTrue(cell.favoriteBtn.isSelected)
        XCTAssertLessThan(cell.nameLabel.frame.maxX, cell.favoriteBtn.frame.minX)
        XCTAssertLessThan(cell.favoriteBtn.frame.maxX, cell.moreBtn.frame.minX)
        XCTAssertLessThan(cell.spaceNumLabel.frame.maxY, cell.bounds.height)
        let sliderView = DeviceSliderFunctionView(frame: CGRect(x: 16, y: 320, width: width, height: 160), title: "", value: 50, functionType: .level())
        host.view.addSubview(sliderView)
        sliderView.layoutIfNeeded()
        assertBlue(sliderView.slider.minimumTrackTintColor)
        for button in [sliderView.addBtn, sliderView.minusBtn] {
            let image = try XCTUnwrap(button?.image(for: .normal))
            XCTAssertEqual(image.size, CGSize(width: 40, height: 40))
            XCTAssertGreaterThanOrEqual(button!.bounds.width, image.size.width)
            XCTAssertGreaterThanOrEqual(button!.bounds.height, image.size.height)
            XCTAssertFalse(button!.hasAmbiguousLayout)
        }
        let header = DeviceLightHeaderView(frame: CGRect(x: 16, y: 500, width: width, height: 160))
        host.view.addSubview(header)
        header.layoutIfNeeded()
        for state in [UIControl.State.normal, .selected] {
            let image = try XCTUnwrap(header.controlBtn.image(for: state))
            XCTAssertEqual(image.size, CGSize(width: 40, height: 40))
        }
        XCTAssertGreaterThanOrEqual(header.controlBtn.bounds.width, 40)
        XCTAssertGreaterThanOrEqual(header.controlBtn.bounds.height, 40)
        XCTAssertFalse(header.controlBtn.hasAmbiguousLayout)
        var changed: Int?
        sliderView.valueChangedCallback = { changed = $0 }
        sliderView.addBtn.sendActions(for: .touchUpInside)
        XCTAssertNotNil(changed, "Branding must preserve the slider button callback")
        XCTAssertGreaterThan(sliderView.value, 50)
        for element in [segment, cell.nameLabel!, cell.favoriteBtn!, sliderView.slider!] {
            XCTAssertFalse(element.hasAmbiguousLayout)
        }
        snapshot(window, "Sites-controls-selected")
    }

    func testLaunchStoryboardAndCopiedProtocols() throws {
        let launchName = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UILaunchStoryboardName") as? String)
        let launch = try XCTUnwrap(UIStoryboard(name: launchName, bundle: .main).instantiateInitialViewController())
        show(launch)
        let logo = try XCTUnwrap(descendants(launch.view).compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(logo.bounds.width, 88, accuracy: 0.5)
        XCTAssertEqual(logo.bounds.height, 88, accuracy: 0.5)
        XCTAssertEqual(logo.center.x, launch.view.bounds.midX, accuracy: 0.5)
        try assertResolvedImageMatchesLumineuxSource(logo.image, name: "launch_logo")
        XCTAssertFalse(logo.hasAmbiguousLayout)
        snapshot(window, "Launch")
        let expected = [
            "Privacy Policy": "25c028291a17557bd9bb4d9f79b491f5dde9186868d5de2bd16fc593aed0d969",
            "User Agreement": "39e7a4ddbb8d996fabef0ea84191135ae68f7a81e5bfc32c17ac221dd5fc2d40"
        ]
        for (name, digest) in expected {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "html"))
            let actual = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actual, digest, "App must package the unchanged SLG copy for \(name)")
        }
        let welcome = WelcomeViewController()
        let navigation = RecordingNavigationController(rootViewController: welcome)
        _ = welcome.textView(UITextView(), shouldInteractWith: URL(string: "Agreement://use")!, in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        XCTAssertEqual((navigation.recorded as? WebViewController)?.loadUrl, Bundle.main.url(forResource: "User Agreement", withExtension: "html"))
        _ = welcome.textView(UITextView(), shouldInteractWith: URL(string: "Agreement://privacy")!, in: NSRange(location: 0, length: 1), interaction: .invokeDefaultAction)
        XCTAssertEqual((navigation.recorded as? WebViewController)?.loadUrl, Bundle.main.url(forResource: "Privacy Policy", withExtension: "html"))
        let about = AboutViewController()
        let aboutNavigation = RecordingNavigationController(rootViewController: about)
        for (row, name) in ["Privacy Policy", "User Agreement"].enumerated() {
            about.tableView(UITableView(), didSelectRowAt: IndexPath(row: row, section: 0))
            XCTAssertEqual((aboutNavigation.recorded as? WebViewController)?.loadUrl, Bundle.main.url(forResource: name, withExtension: "html"))
        }
    }

    func testZSitesScreenLayoutWithoutCreatingData() throws {
        // Render the real screen with the simulator's local data. Do not tap
        // Add, import, sign in, choose a server, or create test sites.
        let needsRegionSelection = Keychain.getServerRegion() == nil
        let sites = SitesViewController()
        let navigation = NavigationViewController(rootViewController: sites)
        show(navigation)
        if needsRegionSelection {
            let appeared = expectation(for: NSPredicate { [weak self] _, _ in
                guard let self else { return false }
                return self.descendants(self.window).contains { $0 is ServerSelectionView }
            }, evaluatedWith: nil)
            wait(for: [appeared], timeout: 3)
            descendants(window).filter { $0 is ServerSelectionView }.forEach { $0.removeFromSuperview() }
        }
        sites.view.layoutIfNeeded()
        let segment = try XCTUnwrap(descendants(sites.view).compactMap { $0 as? CustomSegmentedControl }.first)
        assertBlue(segment.selectBgColor)
        XCTAssertFalse(segment.hasAmbiguousLayout)
        XCTAssertEqual(segment.frame.width, sites.view.bounds.width - SCRXFrom(32), accuracy: 1)
        let add = try XCTUnwrap(sites.view.subviews.compactMap { $0 as? UIButton }.first)
        XCTAssertFalse(add.hasAmbiguousLayout)
        XCTAssertTrue(sites.view.bounds.contains(add.frame))
        try assertResolvedImageMatchesLumineuxSource(add.currentImage, name: "add")
        XCTAssertEqual(add.currentImage?.size, CGSize(width: 48, height: 48))
        XCTAssertGreaterThanOrEqual(add.bounds.width, 48)
        XCTAssertGreaterThanOrEqual(add.bounds.height, 48)

        func renderedLeftNavigationButton() throws -> UIButton {
            navigation.navigationBar.layoutIfNeeded()
            return try XCTUnwrap(descendants(navigation.navigationBar).compactMap { $0 as? UIButton }.first {
                $0.currentImage != nil && $0.convert($0.bounds, to: navigation.navigationBar).midX < navigation.navigationBar.bounds.midX
            })
        }

        let menuItem = try XCTUnwrap(sites.navigationItem.leftBarButtonItem)
        try assertResolvedImageMatchesLumineuxSource(menuItem.image, name: "menu_icon")
        XCTAssertEqual(menuItem.image?.size, CGSize(width: 30, height: 30))
        XCTAssertTrue((menuItem.target as AnyObject?) === sites)
        XCTAssertEqual(NSStringFromSelector(try XCTUnwrap(menuItem.action)), "menuClick")
        let menuButton = try renderedLeftNavigationButton()
        try assertResolvedImageMatchesLumineuxSource(menuButton.currentImage, name: "menu_icon")
        XCTAssertGreaterThanOrEqual(menuButton.bounds.width, 30)
        XCTAssertGreaterThanOrEqual(menuButton.bounds.height, 30)
        XCTAssertFalse(menuButton.hasAmbiguousLayout)

        // A blank detail controller exercises NavigationViewController's real
        // back-item path without opening a site, Mesh view, or cloud workflow.
        let detail = UIViewController()
        navigation.pushViewController(detail, animated: false)
        navigation.view.layoutIfNeeded()
        let backItem = try XCTUnwrap(detail.navigationItem.leftBarButtonItem)
        try assertResolvedImageMatchesLumineuxSource(backItem.image, name: "navigation_back")
        XCTAssertEqual(backItem.image?.size, CGSize(width: 30, height: 30))
        XCTAssertTrue((backItem.target as AnyObject?) === navigation)
        XCTAssertEqual(NSStringFromSelector(try XCTUnwrap(backItem.action)), "backItemClick")
        let backButton = try renderedLeftNavigationButton()
        try assertResolvedImageMatchesLumineuxSource(backButton.currentImage, name: "navigation_back")
        XCTAssertGreaterThanOrEqual(backButton.bounds.width, 30)
        XCTAssertGreaterThanOrEqual(backButton.bounds.height, 30)
        XCTAssertFalse(backButton.hasAmbiguousLayout)
        _ = UIApplication.shared.sendAction(try XCTUnwrap(backItem.action), to: backItem.target, from: nil, for: nil)
        XCTAssertTrue(navigation.topViewController === sites)
        snapshot(window, "Sites-screen")
    }

    func testSharedNameAssetsResolveAtTheirNativeGeometry() throws {
        try assertNamedImage("launch_logo", size: 88)
        try assertNamedImage("launch_logo_120", size: 120)
        try assertResolvedImageMatchesLumineuxSource(UIImage(named: "launch_logo"), name: "launch_logo")
        try assertResolvedImageMatchesLumineuxSource(UIImage(named: "launch_logo_120"), name: "launch_logo_120")
        let expectedManifestAssets: [(String, CGFloat)] = [
            ("space_main", 28),
            ("space_main_selected", 28),
            ("space_group", 28),
            ("space_group_selected", 28),
            ("space_scene", 28),
            ("space_scene_selected", 28),
            ("space_timed", 28),
            ("space_timed_selected", 28),
            ("space_more", 28),
            ("space_more_selected", 28),
            ("menu_icon", 30),
            ("import", 30),
            ("navigation_back", 30),
            ("device_add_setting", 30),
            ("firmware_history", 30),
            ("more_vertical", 30),
            ("no_Internet", 30),
            ("reset", 30),
            ("server_download", 30),
            ("firmware_delete", 30),
            ("light_value_add", 40),
            ("light_value_minus", 40),
            ("device_control_on", 40),
            ("device_control_on_big", 56),
            ("device_control_off", 40),
            ("device_control_off_big", 56),
            ("group_on", 40),
            ("group_on_big", 56),
            ("group_off", 40),
            ("group_off_big", 56),
            ("group_control_disable", 40),
            ("group_control_disable_big", 56),
            ("device_all_on", 30),
            ("device_all_off", 30),
            ("scene_group_on", 30),
            ("scene_group_off", 30),
            ("scene_group_disable", 30),
            ("device_restore", 30),
            ("device_restore_disable", 30),
            ("scene_data_value_add", 30),
            ("scene_data_value_minus", 30),
            ("device_add", 30),
            ("device_add_disable", 30),
            ("device_identify", 30),
            ("slider_point", 40),
            ("slider_point_disable", 40),
            ("favourite_normal", 30),
            ("favourite_selected", 30),
            ("loading", 30),
            ("loading_big", 56),
            ("hud_loading", 48),
            ("space_energy_data", 30),
            ("device_add_waiting", 30),
            ("sync_loading_small", 24),
            ("add", 48),
            ("select", 30),
            ("space_add", 30)
        ]
        XCTAssertEqual(expectedManifestAssets.count, 57)
        for (name, size) in expectedManifestAssets {
            try assertNamedImage(name, size: size)
        }
        let bundle = Bundle(for: LumineuxRuntimeTests.self)
        let manifestURL = try XCTUnwrap(bundle.url(forResource: "icon-manifest", withExtension: "json"))
        let manifest = try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(manifest.assets.count, 57)
        for asset in manifest.assets {
            try assertNamedImage(asset.asset, size: asset.size)
            try assertResolvedImageMatchesLumineuxSource(UIImage(named: asset.asset), name: asset.asset)
        }
    }

    func testSharedOnlyReferenceCannotPassAsLumineuxLaunchLogo() throws {
        let resolved = try XCTUnwrap(UIImage(named: "launch_logo"))
        let scale = Int(resolved.scale.rounded())
        let bundle = Bundle(for: LumineuxRuntimeTests.self)
        let negativeURL = try XCTUnwrap(bundle.url(forResource: "shared_only_launch_logo@\(scale)x", withExtension: "png"))
        let negativeData = try Data(contentsOf: negativeURL)
        let wrongImage = try XCTUnwrap(UIImage(data: negativeData, scale: resolved.scale))
        try XCTExpectFailure("The shared-only negative fixture must not match Lumineux's launch logo", strict: true) {
            try assertResolvedImageMatchesLumineuxSource(wrongImage, name: "launch_logo")
        }
    }

    func testSpaceMenuUsesNamedTabImagesAcrossSelectionStates() throws {
        let host = UIViewController()
        show(host)
        let menu = SpaceMenuView(frame: CGRect(x: 0, y: 100, width: host.view.bounds.width, height: 72))
        menu.itemDatas = SpaceMenuView.defalutItems
        host.view.addSubview(menu)
        menu.layoutIfNeeded()
        let buttons = menu.subviews.compactMap { $0 as? UIButton }
        XCTAssertEqual(buttons.count, 5)
        for (index, item) in SpaceMenuView.defalutItems.enumerated() {
            let button = try XCTUnwrap(buttons[safe: index])
            try assertResolvedImageMatchesLumineuxSource(button.image(for: .normal), name: item.imageName)
            try assertResolvedImageMatchesLumineuxSource(button.image(for: .selected), name: item.selectImageName)
            XCTAssertEqual(button.image(for: .normal)?.size, CGSize(width: 28, height: 28))
            menu.selectIndex = index
            XCTAssertTrue(button.isSelected)
            try assertResolvedImageMatchesLumineuxSource(button.currentImage, name: item.selectImageName)
            XCTAssertFalse(button.hasAmbiguousLayout)
        }
        snapshot(window, "Space-menu-tabs")
    }

    func testSpaceFooterAddAssetLayoutAndActions() throws {
        // Exercise the actual footer without opening a Mesh space or changing data.
        let host = UIViewController()
        host.view.backgroundColor = Background_Color
        show(host)
        let footer = SpaceFunctionFooterView(frame: CGRect(x: 0,
            y: host.view.safeAreaLayoutGuide.layoutFrame.maxY - 40,
            width: host.view.bounds.width, height: 40))
        let recorder = RecordingSpaceFooterDelegate()
        footer.delegate = recorder
        host.view.addSubview(footer)
        footer.layoutIfNeeded()
        try assertResolvedImageMatchesLumineuxSource(footer.addBtn.currentImage, name: "space_add")
        XCTAssertEqual(footer.addBtn.currentImage?.size, CGSize(width: 30, height: 30))
        XCTAssertEqual(footer.addBtn.bounds.size, CGSize(width: 30, height: 30))
        let controls = [footer.countBtn!, footer.sortBtn!, footer.editBtn!, footer.addBtn!]
        for control in controls {
            XCTAssertFalse(control.hasAmbiguousLayout)
            XCTAssertTrue(footer.bounds.contains(control.frame), "Footer control outside bounds: \(control.frame)")
        }
        for (left, right) in zip(controls, controls.dropFirst()) {
            XCTAssertLessThan(left.frame.maxX, right.frame.minX, "Footer controls overlap")
        }
        footer.addBtn.sendActions(for: .touchUpInside)
        XCTAssertEqual(recorder.addCount, 1)
        footer.sortBtn.sendActions(for: .touchUpInside)
        XCTAssertEqual(recorder.sortCount, 1)
        snapshot(window, "Space-footer")
        footer.editBtn.sendActions(for: .touchUpInside)
        XCTAssertTrue(footer.isEditing)
        XCTAssertTrue(footer.addBtn.isHidden)
        footer.cancelBtn.sendActions(for: .touchUpInside)
        XCTAssertFalse(footer.isEditing)
        XCTAssertFalse(footer.addBtn.isHidden)
        XCTAssertEqual(recorder.editStates, [true, false])
    }

    func testSitesFavouriteControlUsesItsNativeSelectedAsset() throws {
        let host = UIViewController()
        show(host)
        let cell = SitesViewCell(frame: CGRect(x: 16, y: 100, width: 320, height: 100))
        host.view.addSubview(cell)
        cell.layoutIfNeeded()
        try assertResolvedImageMatchesLumineuxSource(cell.favoriteBtn.image(for: .normal), name: "favourite_normal")
        try assertResolvedImageMatchesLumineuxSource(cell.favoriteBtn.image(for: .selected), name: "favourite_selected")
        XCTAssertEqual(cell.favoriteBtn.image(for: .selected)?.size, CGSize(width: 30, height: 30))
        cell.favoriteBtn.sendActions(for: .touchUpInside)
        XCTAssertTrue(cell.favoriteBtn.isSelected)
        try assertResolvedImageMatchesLumineuxSource(cell.favoriteBtn.currentImage, name: "favourite_selected")
        XCTAssertFalse(cell.favoriteBtn.hasAmbiguousLayout)
    }
}

private final class RecordingSpaceFooterDelegate: SpaceFunctionFooterViewDelegate {
    var addCount = 0
    var sortCount = 0
    var editStates: [Bool] = []
    func functionDidClickAdd(view: SpaceFunctionFooterView) { addCount += 1 }
    func functionDidClickSort(view: SpaceFunctionFooterView) { sortCount += 1 }
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) { editStates.append(editing) }
}

@MainActor
private final class RecordingNavigationController: UINavigationController {
    var recorded: UIViewController?
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if viewControllers.isEmpty { super.pushViewController(viewController, animated: false) }
        else { recorded = viewController }
    }
}
