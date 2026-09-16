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

    func testSpaceCardIconBackgroundMatchesArtwork() throws {
        let space = SpaceData(name: "Space 1", id: "space-background-layout", siteId: "space-background-site",
            create: 0, isFavourite: false, permission: .owner, sourceType: .create,
            meshUUID: "space-background-mesh", meshNetworkId: "space-background-network")
        let cell = SpacesViewCell(frame: .zero)
        space.imageId = 1
        cell.space = space
        let height = isIPad ? max(SCRYFrom(192), 192) : SCRYFrom(192)
        let width = isIPad ? (SCREEN_WIDTH - SCRXFrom(60)) / 2 : SCREEN_WIDTH - SCRXFrom(32)
        _ = host(cell, size: CGSize(width: width, height: height))
        let icon = try XCTUnwrap(descendants(cell).compactMap { $0 as? UIImageView }
            .first { image($0.image, matchesNamed: "space_picture_1") })
        assertContained(icon, in: cell.contentView)
        XCTAssertEqual(icon.contentMode, .center)
        for id in 1...60 {
            space.imageId = id
            cell.space = space
            cell.layoutIfNeeded()
            let artwork = try XCTUnwrap(icon.image)
            XCTAssertGreaterThanOrEqual(icon.bounds.width, artwork.size.width)
            XCTAssertGreaterThanOrEqual(icon.bounds.height, artwork.size.height)
            let rendered = UIGraphicsImageRenderer(bounds: icon.bounds).image { _ in
                icon.drawHierarchy(in: icon.bounds, afterScreenUpdates: true)
            }
            let pixels = try oraclePixels(rendered)
            let inset = (icon.bounds.width - artwork.size.width) / 2
            func middlePixel(at x: CGFloat) -> [UInt8] {
                let offset = ((pixels.height / 2) * pixels.width + Int(x * rendered.scale)) * 4
                return Array(pixels.rgba[offset..<(offset + 4)])
            }
            // Compare the exposed view margin with the PNG's white left gutter.
            let canvas = middlePixel(at: inset + 4)
            XCTAssertEqual(canvas, [255, 255, 255, 255], "Space icon \(id) canvas")
            XCTAssertEqual(middlePixel(at: inset / 2), canvas,
                "Space icon \(id) has a visible seam between its background and artwork")
            if id == 1 {
                // Figma 16001:96781: 1pt #4D738A at 10% opacity over white.
                let border = middlePixel(at: 0.5)
                for (actual, expected) in zip(border, [237, 241, 243, 255]) {
                    XCTAssertEqual(Int(actual), expected, accuracy: 1, "Space icon border color")
                }
                XCTAssertEqual(middlePixel(at: 1.5), canvas, "Space icon border must remain 1pt wide")
                snapshot(window, "Space-agriculture-background")
            }
        }
    }

    func testSpaceIconPickerShowsAllFigmaIconsAndSavesLastSelection() throws {
        XCTAssertEqual(SpaceData.iconImageNames, (1...60).map { "space_picture_\($0)" })
        let controller = InfoEditViewController(name: "Space icon layout", imageNames: SpaceData.iconImageNames,
            selectImageIndex: 0, columnNum: isIPad ? 4 : 2)
        controller.itemHeight = isIPad ? SCRYFrom(104) : nil
        if isIPad { controller.preferredContentSize = iPadPreferredContentSize }
        let presenter = UIViewController()
        show(presenter)
        let navigation = NavigationViewController(rootViewController: controller)
        presenter.present(navigation, animated: false)
        settleAppearance()
        controller.view.layoutIfNeeded()
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 60)
        snapshot(window, "Space-icons-first-page")
        for index in 0..<60 {
            let path = IndexPath(item: index, section: 0)
            collection.scrollToItem(at: path, at: .centeredVertically, animated: false)
            collection.layoutIfNeeded()
            let cell = try XCTUnwrap(collection.cellForItem(at: path) as? ImageCollectionViewCell)
            let imageView = try XCTUnwrap(cell.imageView)
            try assertResolvedImageMatchesLumineuxSource(imageView.image, name: "space_picture_\(index + 1)")
            XCTAssertEqual(imageView.image?.size, CGSize(width: 120, height: 96))
            XCTAssertFalse(imageView.hasAmbiguousLayout)
            XCTAssertTrue(cell.contentView.bounds.insetBy(dx: -0.5, dy: -0.5).contains(imageView.frame),
                "Space icon \(index + 1) is clipped")
        }
        let last = IndexPath(item: 59, section: 0)
        collection.delegate?.collectionView?(collection, didSelectItemAt: last)
        collection.layoutIfNeeded()
        XCTAssertEqual(collection.cellForItem(at: last)?.layer.borderWidth, 1)
        var savedIndex: Int?
        controller.doneCallback = { _, index in savedIndex = index; return false }
        let done = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }
            .first { $0.title(for: .normal) == "done".localizedString })
        done.sendActions(for: .touchUpInside)
        XCTAssertEqual(savedIndex, 59)
        snapshot(window, "Space-icons-last-selected")
        navigation.dismiss(animated: false)
        settleAppearance()

        let space = SpaceData(name: "Space 60", id: "space-icon-layout", siteId: "space-icon-site",
            create: 0, isFavourite: false, permission: .owner, sourceType: .create,
            meshUUID: "space-icon-mesh", meshNetworkId: "space-icon-network")
        space.imageId = 60
        let cell = SpacesViewCell(frame: .zero)
        cell.space = space
        _ = host(cell, size: CGSize(width: isIPad ? 640 : 343, height: 210))
        let selected = try XCTUnwrap(descendants(cell).compactMap { $0 as? UIImageView }
            .first { image($0.image, matchesNamed: "space_picture_60") })
        try assertResolvedImageMatchesLumineuxSource(selected.image, name: "space_picture_60")
        XCTAssertGreaterThanOrEqual(selected.bounds.width, 120)
        XCTAssertGreaterThanOrEqual(selected.bounds.height, 96)
        snapshot(window, "Space-icons-list-card")
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
        try assertNamedImage(name, size: CGSize(width: size, height: size), file: file, line: line)
    }

    private func assertNamedImage(_ name: String, size: CGSize,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let image = try XCTUnwrap(UIImage(named: name), "Missing Lumineux asset: \(name)", file: file, line: line)
        XCTAssertEqual(image.size.width, size.width, accuracy: 0.01, name, file: file, line: line)
        XCTAssertEqual(image.size.height, size.height, accuracy: 0.01, name, file: file, line: line)
    }

    private struct AssetManifest: Decodable {
        struct Asset: Decodable {
            let asset: String
            let size: CGFloat?
            let width: CGFloat?
            let height: CGFloat?

            var geometry: CGSize? {
                if let size {
                    return CGSize(width: size, height: size)
                }
                guard let width, let height else { return nil }
                return CGSize(width: width, height: height)
            }
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
            if ["launch_logo", "lumineux_launch_logo", "space_main_selected"].contains(name) {
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

    private func image(_ image: UIImage?, matchesNamed name: String) -> Bool {
        guard let image,
              let expected = UIImage(named: name),
              let actualPixels = try? oraclePixels(image),
              let expectedPixels = try? oraclePixels(expected) else {
            return false
        }
        return actualPixels.width == expectedPixels.width &&
               actualPixels.height == expectedPixels.height &&
               actualPixels.rgba == expectedPixels.rgba
    }

    private func host(_ contentView: UIView, size: CGSize) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = Background_Color
        contentView.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            contentView.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            contentView.widthAnchor.constraint(equalToConstant: size.width),
            contentView.heightAnchor.constraint(equalToConstant: size.height)
        ])
        show(controller)
        return controller
    }

    private func assertContained(_ child: UIView, in parent: UIView,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let frame = child.convert(child.bounds, to: parent)
        XCTAssertTrue(parent.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                      "View is outside its production container: \(frame)",
                      file: file, line: line)
        XCTAssertFalse(child.hasAmbiguousLayout, file: file, line: line)
    }

    func testBluetoothRequiredPageUsesLumineuxOverrideWithoutLayoutAmbiguity() throws {
        let controller = BluetoothRequiredViewController()
        show(NavigationViewController(rootViewController: controller))
        defer { SRAlertView.hide() }

        let emptyView = try XCTUnwrap(controller.view.emptyView)
        let imageView = try XCTUnwrap(emptyView.imageView)
        let titleLabel = try XCTUnwrap(emptyView.titleLabel)
        let tipLabel = try XCTUnwrap(emptyView.tipLabel)

        XCTAssertEqual(titleLabel.text, "Bluetooth required")
        XCTAssertEqual(tipLabel.text, "Turn on bluetooth to use the app.")
        XCTAssertEqual(imageView.image?.size, CGSize(width: 240, height: 194))
        try assertResolvedImageMatchesLumineuxSource(imageView.image, name: "bluetooth_required")

        for view in [emptyView, imageView, titleLabel, tipLabel] {
            XCTAssertFalse(view.hasAmbiguousLayout,
                           "Ambiguous Bluetooth-required layout: \(type(of: view))")
            assertContained(view, in: controller.view)
        }
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: controller.view)
        let imageFrame = imageView.convert(imageView.bounds, to: controller.view)
        let tipFrame = tipLabel.convert(tipLabel.bounds, to: controller.view)
        XCTAssertLessThan(titleFrame.maxY, imageFrame.minY)
        XCTAssertLessThanOrEqual(imageFrame.maxY, tipFrame.minY)
        snapshot(window, "Bluetooth-required-page")
    }

    func testProfileAndSafeModeSupplementalAssetsResolveFromLumineuxSources() throws {
        let assets: [(String, CGSize)] = [
            ("profile_chart_occupancy_daylight", CGSize(width: 212, height: 234)),
            ("schedule_target_select", CGSize(width: 30, height: 30)),
            ("sensor_move", CGSize(width: 20, height: 20)),
            ("device_select", CGSize(width: 30, height: 30))
        ]
        for (name, size) in assets {
            try assertNamedImage(name, size: size)
            try assertResolvedImageMatchesLumineuxSource(UIImage(named: name), name: name)
        }
    }

    func testProfileSupplementalArtworkUsesRealViews() throws {
        let phases = ProfileTriggerConditionPhasesView(frame: .zero)
        _ = host(phases, size: CGSize(width: 343, height: 690))
        let chart = try XCTUnwrap(descendants(phases).compactMap { $0 as? UIImageView }
            .first { image($0.image, matchesNamed: "profile_chart_occupancy_daylight") })
        try assertResolvedImageMatchesLumineuxSource(chart.image, name: "profile_chart_occupancy_daylight")
        let chartFrame = chart.convert(chart.bounds, to: phases)
        XCTAssertTrue(phases.bounds.insetBy(dx: -0.5, dy: -0.5).contains(chartFrame))
        XCTAssertFalse(chart.hasAmbiguousLayout)
        snapshot(window, "Profile-occupancy-daylight-chart")

        let powerUp = ProfilePowerUpBehaviorView(frame: .zero)
        _ = host(powerUp, size: CGSize(width: 343, height: 320))
        let selectedButton = try XCTUnwrap(descendants(powerUp).compactMap { $0 as? UIButton }
            .first { image($0.image(for: .selected), matchesNamed: "schedule_target_select") })
        try assertResolvedImageMatchesLumineuxSource(selectedButton.image(for: .selected),
                                                     name: "schedule_target_select")
        XCTAssertFalse(selectedButton.hasAmbiguousLayout)
        let buttonFrame = selectedButton.convert(selectedButton.bounds, to: powerUp)
        XCTAssertTrue(powerUp.bounds.insetBy(dx: -0.5, dy: -0.5).contains(buttonFrame))
        snapshot(window, "Profile-schedule-selected")
    }

    func testSensorMovementAndDeviceSelectionArtworkUsesLumineuxSources() throws {
        let sensor = GroupSensorView(frame: .zero)
        _ = host(sensor, size: CGSize(width: 343, height: 500))
        let movement = try XCTUnwrap(descendants(sensor).compactMap { $0 as? UIImageView }
            .first { image($0.image, matchesNamed: "sensor_move") })
        try assertResolvedImageMatchesLumineuxSource(movement.image, name: "sensor_move")
        XCTAssertFalse(movement.hasAmbiguousLayout)
        let movementFrame = movement.convert(movement.bounds, to: sensor)
        XCTAssertTrue(sensor.bounds.insetBy(dx: -0.5, dy: -0.5).contains(movementFrame))
        snapshot(window, "Group-sensor-movement")

        let selectedControl = UIButton(normalImageName: "device_select_un",
                                       selectedImageName: "device_select")
        selectedControl.isSelected = true
        _ = host(selectedControl, size: CGSize(width: 44, height: 44))
        try assertResolvedImageMatchesLumineuxSource(selectedControl.currentImage, name: "device_select")
        XCTAssertEqual(selectedControl.currentImage?.size, CGSize(width: 30, height: 30))
        XCTAssertFalse(selectedControl.hasAmbiguousLayout)
        snapshot(window, "SafeMode-device-selected")
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

    func testEuropeRegionAndMenuWithoutServerSelection() throws {
        XCTAssertEqual(ServerRegion.defaultRegions.map(\.rawValue), [ServerRegion.europe.rawValue],
                       "Lumineux must expose Europe as its only server region")
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
        XCTAssertEqual(table.numberOfRows(inSection: 0), 2,
                       "Lumineux must hide server selection like SLGSync")
        XCTAssertTrue(descendants(menu).compactMap { $0 as? UILabel }.contains { $0.text == "Lumineux" })
        snapshot(window, "Menu")
    }

    func testProvidedCommonRetinaAssetsFitProductionControls() throws {
        for name in [
            "filter_selected", "menu_select", "order_down",
            "order_up", "server_select", "user_big"
        ] {
            try assertResolvedImageMatchesLumineuxSource(UIImage(named: name), name: name)
        }

        let user = UserSettingsViewController()
        show(NavigationViewController(rootViewController: user))
        let userIcon = try XCTUnwrap(descendants(user.view).compactMap { $0 as? UIImageView }
            .first { $0.image?.size == CGSize(width: 88, height: 88) })
        try assertResolvedImageMatchesLumineuxSource(userIcon.image, name: "user_big")
        XCTAssertFalse(userIcon.hasAmbiguousLayout)
        let userIconFrame = userIcon.convert(userIcon.bounds, to: user.view)
        XCTAssertTrue(user.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(userIconFrame))
        snapshot(window, "Provided-common-user")

        let server = ServerSelectionViewController()
        show(NavigationViewController(rootViewController: server))
        server.view.layoutIfNeeded()
        let serverCell = try XCTUnwrap(
            descendants(server.view).compactMap { $0 as? ServerSelectionViewCell }.first
        )
        try assertResolvedImageMatchesLumineuxSource(
            serverCell.selectedImageView.image,
            name: "server_select"
        )
        XCTAssertFalse(serverCell.selectedImageView.hasAmbiguousLayout)
        let serverIconFrame = serverCell.selectedImageView.convert(
            serverCell.selectedImageView.bounds,
            to: serverCell.contentView
        )
        XCTAssertTrue(serverCell.contentView.bounds.insetBy(dx: -0.5, dy: -0.5)
            .contains(serverIconFrame))
        snapshot(window, "Provided-common-server")

        let menuHost = UIViewController()
        show(menuHost)
        TitleSelectView.show(
            titles: ["First", "Second"],
            anchorPoint: CGPoint(x: 20, y: 80),
            selectIndex: 1,
            menuWidth: 180,
            itemHeight: 44,
            selectBack: { _ in }
        )
        settleAppearance()
        let titleSelect = try XCTUnwrap(window.viewWithTag(100) as? TitleSelectView)
        titleSelect.layoutIfNeeded()
        let titleTable = try XCTUnwrap(
            descendants(titleSelect).compactMap { $0 as? UITableView }.first
        )
        titleTable.layoutIfNeeded()
        let selectedCell = try XCTUnwrap(
            titleTable.cellForRow(at: IndexPath(row: 1, section: 0)) as? CustomTableViewCell
        )
        try assertResolvedImageMatchesLumineuxSource(
            selectedCell.iconImageView.image,
            name: "menu_select"
        )
        XCTAssertFalse(selectedCell.iconImageView.hasAmbiguousLayout)
        let menuIconFrame = selectedCell.iconImageView.convert(
            selectedCell.iconImageView.bounds,
            to: selectedCell.contentView
        )
        XCTAssertTrue(selectedCell.contentView.bounds.insetBy(dx: -0.5, dy: -0.5)
            .contains(menuIconFrame))
        snapshot(window, "Provided-common-title-select")
        titleSelect.dismiss()
        settleAppearance()

        let space = SpaceData(
            name: "Common asset layout",
            id: "common-asset-space",
            siteId: "common-asset-site",
            create: 0,
            isFavourite: false,
            permission: .owner,
            sourceType: .create,
            meshUUID: "common-asset-mesh",
            meshNetworkId: "common-asset-network"
        )
        let energy = EnergyStaticDataViewController(space: space)
        show(NavigationViewController(rootViewController: energy))
        let buttons = descendants(energy.view).compactMap { $0 as? UIButton }
        let filter = try XCTUnwrap(buttons.first {
            image($0.image(for: .selected), matchesNamed: "filter_selected")
        })
        let order = try XCTUnwrap(buttons.first {
            image($0.image(for: .normal), matchesNamed: "order_down") &&
                image($0.image(for: .selected), matchesNamed: "order_up")
        })
        try assertResolvedImageMatchesLumineuxSource(
            filter.image(for: .selected),
            name: "filter_selected"
        )
        try assertResolvedImageMatchesLumineuxSource(
            order.image(for: .normal),
            name: "order_down"
        )
        try assertResolvedImageMatchesLumineuxSource(
            order.image(for: .selected),
            name: "order_up"
        )
        for button in [filter, order] {
            XCTAssertFalse(button.hasAmbiguousLayout)
            let frame = button.convert(button.bounds, to: energy.view)
            XCTAssertTrue(energy.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame))
        }
        snapshot(window, "Provided-common-energy-controls")
    }

    func testProvidedGroupedRetinaAssetsFitProductionControls() throws {
        let expectedGeometry: [(String, CGSize)] = [
            ("switch_proxy_instructions_1", CGSize(width: 310, height: 328)),
            ("switch_proxy_instructions_2", CGSize(width: 287, height: 312)),
            ("energy_device", CGSize(width: 20, height: 20)),
            ("energy_csv", CGSize(width: 20, height: 20)),
            ("energy_phone", CGSize(width: 20, height: 20)),
            ("switch_press", CGSize(width: 30, height: 30)),
            ("switch_press_long", CGSize(width: 30, height: 30)),
            ("switch_save", CGSize(width: 40, height: 40)),
            ("path_item_add", CGSize(width: 9, height: 9))
        ]
        for (name, size) in expectedGeometry {
            try assertResolvedImageMatchesLumineuxSource(UIImage(named: name), name: name)
            try assertNamedImage(name, size: size)
        }
        for name in ["path_direction_left", "path_direction_right"] {
            let direction = try XCTUnwrap(UIImage(named: name))
            try assertResolvedImageMatchesLumineuxSource(direction, name: name)
            XCTAssertEqual(direction.size.height, 6, accuracy: 0.01, name)
            XCTAssertGreaterThan(direction.size.width, 15, name)
            XCTAssertLessThan(direction.size.width, 16, name)
        }

        let instructions = SwitchProxyInstructionsViewController()
        show(NavigationViewController(rootViewController: instructions))
        let guides = descendants(instructions.view)
            .compactMap { $0 as? SwitchProxyInstructionsGuideView }
        XCTAssertEqual(guides.count, 2)
        for name in ["switch_proxy_instructions_1", "switch_proxy_instructions_2"] {
            let guide = try XCTUnwrap(guides.first {
                image($0.imageView.image, matchesNamed: name)
            })
            try assertResolvedImageMatchesLumineuxSource(guide.imageView.image, name: name)
            assertContained(guide.imageView, in: guide)
        }
        snapshot(window, "Provided-grouped-device-instructions")

        let importView = EnergyTimeSeriesDataImportView(frame: .zero)
        _ = host(importView, size: CGSize(width: 343, height: 190))
        for name in ["energy_device", "energy_csv", "energy_phone"] {
            let imageView = try XCTUnwrap(descendants(importView)
                .compactMap { $0 as? UIImageView }
                .first { image($0.image, matchesNamed: name) })
            try assertResolvedImageMatchesLumineuxSource(imageView.image, name: name)
            assertContained(imageView, in: importView)
        }
        snapshot(window, "Provided-grouped-energy-import")

        let exportView = EnergyTimeSeriesDataExportView(frame: .zero)
        _ = host(exportView, size: CGSize(width: 343, height: 330))
        for name in ["energy_phone", "energy_csv"] {
            let imageView = try XCTUnwrap(descendants(exportView)
                .compactMap { $0 as? UIImageView }
                .first { image($0.image, matchesNamed: name) })
            try assertResolvedImageMatchesLumineuxSource(imageView.image, name: name)
            assertContained(imageView, in: exportView)
        }
        snapshot(window, "Provided-grouped-energy-export")

        let switchCell = GroupSwitchPanelViewCell(style: .default, reuseIdentifier: nil)
        _ = host(switchCell, size: CGSize(width: 343, height: 520))
        for (button, name) in [
            (switchCell.key1ShortPressBtn!, "switch_press"),
            (switchCell.key1LongPressBtn!, "switch_press_long"),
            (switchCell.saveBtn!, "switch_save")
        ] {
            try assertResolvedImageMatchesLumineuxSource(button.image(for: .normal), name: name)
            assertContained(button, in: switchCell.contentView)
        }
        snapshot(window, "Provided-grouped-switch-panel")

        let path = GroupProximityLightingSequencePath(
            items: GroupProximityLightingSequencePath.GroupProximityLightingPathItem.default(count: 1)
        )
        let pathCell = GroupPathSequencePathViewCell(style: .default, reuseIdentifier: nil)
        pathCell.reloadData(pathIndex: 0, path: path)
        _ = host(pathCell, size: CGSize(width: 343, height: 116))
        let selected = GroupPathSequenceSelectData()
        selected.path = path
        selected.item = path.items[0]
        selected.direction = .right
        pathCell.selectPathData = selected
        pathCell.layoutIfNeeded()
        let collection = try XCTUnwrap(descendants(pathCell)
            .compactMap { $0 as? UICollectionView }.first)
        collection.layoutIfNeeded()
        let addItem = try XCTUnwrap(
            collection.cellForItem(at: IndexPath(item: 0, section: 0))
                as? GroupPathSequencePathAddItem
        )
        try assertResolvedImageMatchesLumineuxSource(addItem.addImageView.image,
                                                     name: "path_item_add")
        assertContained(addItem.addImageView, in: addItem.boxView)
        var pathItem = try XCTUnwrap(
            collection.cellForItem(at: IndexPath(item: 1, section: 0))
                as? GroupPathSequencePathItem
        )
        try assertResolvedImageMatchesLumineuxSource(pathItem.arrowImageView.image,
                                                     name: "path_direction_right")
        assertContained(pathItem.arrowImageView, in: pathItem.boxView)
        selected.direction = .left
        pathCell.selectPathData = selected
        collection.layoutIfNeeded()
        pathItem = try XCTUnwrap(
            collection.cellForItem(at: IndexPath(item: 1, section: 0))
                as? GroupPathSequencePathItem
        )
        try assertResolvedImageMatchesLumineuxSource(pathItem.arrowImageView.image,
                                                     name: "path_direction_left")
        assertContained(pathItem.arrowImageView, in: pathItem.boxView)
        snapshot(window, "Provided-grouped-path")
    }

    func testSceneGroupOffButtonUsesLumineuxThemeAndKeepsLayout() throws {
        window.makeKeyAndVisible()
        SceneExecuteDataPickerView.show(
            lightness: 50,
            isOn: true,
            cct: 4500,
            showCct: true,
            showDelete: false,
            picker: nil
        )

        let picker = try XCTUnwrap(
            window.subviews.compactMap { $0 as? SceneExecuteDataPickerView }.last
        )
        defer { picker.removeFromSuperview() }
        window.layoutIfNeeded()
        picker.layoutIfNeeded()

        let offButton = try XCTUnwrap(
            descendants(picker).compactMap { $0 as? UIButton }
                .first { $0.title(for: .normal) == "OFF" }
        )
        let container = try XCTUnwrap(offButton.superview)

        XCTAssertEqual(offButton.bounds.width, SCRXFrom(52), accuracy: 0.5)
        XCTAssertEqual(offButton.bounds.height, SCRYFrom(32), accuracy: 0.5)
        XCTAssertEqual(offButton.layer.cornerRadius, SCRYFrom(10), accuracy: 0.5)
        XCTAssertFalse(offButton.hasAmbiguousLayout)
        assertContained(offButton, in: container)
        XCTAssertEqual(offButton.backgroundColor, .white)
        assertBlue(offButton.titleColor(for: .normal))
        assertBlue(UIColor(cgColor: try XCTUnwrap(offButton.layer.borderColor)), alpha: 0.6)
        XCTAssertEqual(offButton.layer.borderWidth, 1, accuracy: 0.01)

        offButton.sendActions(for: .touchUpInside)

        assertBlue(offButton.backgroundColor)
        XCTAssertEqual(offButton.titleColor(for: .normal), .white)
        XCTAssertEqual(offButton.layer.borderWidth, 0, accuracy: 0.01)
        XCTAssertFalse(offButton.hasAmbiguousLayout)
        assertContained(offButton, in: container)
        snapshot(window, "Scene-group-off-theme")
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
        try assertResolvedImageMatchesLumineuxSource(logo.image, name: "lumineux_launch_logo")
        XCTAssertFalse(logo.hasAmbiguousLayout)
        snapshot(window, "Launch")
        let expected = [
            "Privacy Policy": "90d85bfa42fd93d8b514bc81fc3afd1359734416568c817d382bfd6131ddcd76",
            "User Agreement": "8a9806f280875132f487cd74f02b7ef59cc937ef86dff516072ed166dc74821f"
        ]
        for (name, digest) in expected {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "html"))
            let actual = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actual, digest, "App must package the approved LumiSmart copy for \(name)")
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
        try assertNamedImage("lumineux_launch_logo", size: 88)
        try assertResolvedImageMatchesLumineuxSource(UIImage(named: "launch_logo"), name: "launch_logo")
        try assertResolvedImageMatchesLumineuxSource(UIImage(named: "launch_logo_120"), name: "launch_logo_120")
        try assertResolvedImageMatchesLumineuxSource(UIImage(named: "lumineux_launch_logo"), name: "lumineux_launch_logo")
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
            ("sync_success_small", 24),
            ("sync_failed_small", 24),
            ("sync_waiting_small", 24),
            ("sync_loading_small", 24),
            ("device_scan", 24),
            ("add", 48),
            ("select", 30),
            ("space_add", 30)
        ]
        XCTAssertEqual(expectedManifestAssets.count, 61)
        for (name, size) in expectedManifestAssets {
            try assertNamedImage(name, size: size)
        }
        let bundle = Bundle(for: LumineuxRuntimeTests.self)
        let manifestURL = try XCTUnwrap(bundle.url(forResource: "icon-manifest", withExtension: "json"))
        let manifest = try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(manifest.assets.count, 65)
        let expectedSupplementalGeometry: [(String, CGSize)] = [
            ("profile_chart_occupancy_daylight", CGSize(width: 212, height: 234)),
            ("schedule_target_select", CGSize(width: 30, height: 30)),
            ("sensor_move", CGSize(width: 20, height: 20)),
            ("device_select", CGSize(width: 30, height: 30))
        ]
        let manifestNames = manifest.assets.map(\.asset)
        XCTAssertEqual(Set(manifestNames).count, manifestNames.count,
                       "Manifest asset names must be unique")
        let expectedManifestNames = Set(
            expectedManifestAssets.map(\.0) + expectedSupplementalGeometry.map(\.0)
        )
        XCTAssertEqual(Set(manifestNames), expectedManifestNames,
                       "Manifest asset names must exactly match the approved runtime assets")
        for (name, expectedGeometry) in expectedSupplementalGeometry {
            let asset = try XCTUnwrap(manifest.assets.first { $0.asset == name },
                                      "Missing independently expected manifest asset: \(name)")
            XCTAssertEqual(try XCTUnwrap(asset.geometry,
                                         "Manifest asset \(name) must define size or width and height"),
                           expectedGeometry, name)
        }
        for asset in manifest.assets {
            let geometry = try XCTUnwrap(asset.geometry,
                                         "Manifest asset \(asset.asset) must define size or width and height")
            try assertNamedImage(asset.asset, size: geometry)
            try assertResolvedImageMatchesLumineuxSource(UIImage(named: asset.asset), name: asset.asset)
        }
    }

    func testCompactStatusAssetsFitRealSyncCellAndScanControl() throws {
        let host = UIViewController()
        host.view.backgroundColor = Background_Color
        show(host)

        let statusCases: [(SyncDevicesState, String)] = [
            (.successful, "sync_success_small"),
            (.failed, "sync_failed_small"),
            (.wait, "sync_waiting_small"),
            (.inSettings, "sync_loading_small")
        ]
        for (index, statusCase) in statusCases.enumerated() {
            let cell = SyncDeviceViewCell(style: .default, reuseIdentifier: nil)
            cell.frame = CGRect(x: 0, y: 80 + CGFloat(index * 70), width: host.view.bounds.width, height: 70)
            let model = SyncDevicesModel(name: statusCase.1, address: UInt16(index + 1))
            model.state = statusCase.0
            cell.model = model
            host.view.addSubview(cell)
            cell.setNeedsLayout()
            cell.layoutIfNeeded()

            try assertResolvedImageMatchesLumineuxSource(cell.stateImageView.image, name: statusCase.1)
            XCTAssertEqual(cell.stateImageView.image?.size, CGSize(width: 24, height: 24))
            XCTAssertFalse(cell.stateImageView.hasAmbiguousLayout)
            let stateFrame = cell.stateImageView.convert(cell.stateImageView.bounds, to: cell.contentView)
            XCTAssertTrue(cell.contentView.bounds.insetBy(dx: -0.5, dy: -0.5).contains(stateFrame),
                          "Status artwork is outside the real sync cell: \(statusCase.1) \(stateFrame)")
        }
        host.view.layoutIfNeeded()
        snapshot(window, "Compact-sync-statuses")

        let space = SpaceData(name: "Asset layout test", id: "asset-layout-space", siteId: "asset-layout-site",
                              create: 0, isFavourite: false, permission: .owner, sourceType: .create,
                              meshUUID: "asset-layout-mesh", meshNetworkId: "asset-layout-network")
        let candidateView = DeviceAddCandidateDeviceListView(frame: window.bounds, space: space)
        candidateView.lightSeningMode = true
        host.view.addSubview(candidateView)
        candidateView.setNeedsLayout()
        candidateView.layoutIfNeeded()
        candidateView.show()
        settleAppearance()

        let scanButton = try XCTUnwrap(descendants(candidateView).compactMap { $0 as? UIButton }
            .first { $0.title(for: .normal) == "scan".localizedString })
        XCTAssertFalse(scanButton.isHidden)
        XCTAssertFalse(scanButton.hasAmbiguousLayout)
        XCTAssertGreaterThanOrEqual(scanButton.bounds.width, 72)
        XCTAssertGreaterThanOrEqual(scanButton.bounds.height, 24)
        try assertResolvedImageMatchesLumineuxSource(scanButton.image(for: .normal), name: "device_scan")
        XCTAssertEqual(scanButton.image(for: .normal)?.size, CGSize(width: 24, height: 24))
        scanButton.layoutIfNeeded()
        let scanImageView = try XCTUnwrap(scanButton.imageView)
        let imageFrame = scanImageView.convert(scanImageView.bounds, to: scanButton)
        XCTAssertTrue(scanButton.bounds.insetBy(dx: -0.5, dy: -0.5).contains(imageFrame),
                      "Scan artwork is outside the real scan button: \(imageFrame)")
        snapshot(window, "Device-scan-control")
        candidateView.removeFromSuperview()
    }

    func testProvidedAutoAssetFitsRealForcedAutoPopup() throws {
        let popup = PJEightKeySwitchForcedAutoPopupController()
        show(popup)
        settleAppearance()

        let expectedName = isIPad ? "auto_big" : "auto"
        let expectedSize: CGFloat = isIPad ? 56 : 40
        let expectedButtonSize: CGFloat = 40
        let autoButton = try XCTUnwrap(descendants(popup.view).compactMap { $0 as? UIButton }
            .first { $0.image(for: .normal) != nil })
        try assertResolvedImageMatchesLumineuxSource(autoButton.image(for: .normal), name: expectedName)
        XCTAssertEqual(autoButton.image(for: .normal)?.size,
                       CGSize(width: expectedSize, height: expectedSize))
        XCTAssertEqual(autoButton.bounds.width, expectedButtonSize, accuracy: 0.01)
        XCTAssertEqual(autoButton.bounds.height, expectedButtonSize, accuracy: 0.01)
        XCTAssertFalse(autoButton.hasAmbiguousLayout)
        autoButton.layoutIfNeeded()
        let imageView = try XCTUnwrap(autoButton.imageView)
        let imageFrame = imageView.convert(imageView.bounds, to: autoButton)
        XCTAssertTrue(autoButton.bounds.insetBy(dx: -0.5, dy: -0.5).contains(imageFrame),
                      "AUTO artwork is outside its production button: \(imageFrame)")
        let buttonFrame = autoButton.convert(autoButton.bounds, to: popup.view)
        XCTAssertTrue(popup.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(buttonFrame),
                      "AUTO artwork is outside the real forced-auto popup: \(buttonFrame)")
        snapshot(window, "Provided-auto-popup")
    }

    func testEmptyStateIllustrationsUseLumineuxAssetsAndFitRealEmptyView() throws {
        let host = UIViewController()
        host.view.backgroundColor = Background_Color
        show(host)
        let assets: [(name: String, size: CGSize)] = [
            ("site_empty", CGSize(width: 353, height: 298)),
            ("space_empty", CGSize(width: 240, height: 194)),
            ("group_empty", CGSize(width: 343, height: 288)),
            ("scene_empty", CGSize(width: 343, height: 288))
        ]
        for asset in assets {
            host.view.showEmptyDataView(imageName: asset.name,
                                        title: "Empty-state layout check",
                                        tipText: nil,
                                        position: .center)
            host.view.layoutIfNeeded()
            let emptyView = try XCTUnwrap(host.view.emptyView)
            let imageView = try XCTUnwrap(emptyView.imageView)
            try assertNamedImage(asset.name, size: asset.size)
            try assertResolvedImageMatchesLumineuxSource(imageView.image, name: asset.name)
            XCTAssertEqual(imageView.bounds.size, asset.size)
            XCTAssertFalse(imageView.hasAmbiguousLayout)
            let frame = imageView.convert(imageView.bounds, to: host.view)
            XCTAssertTrue(host.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                          "\(asset.name) falls outside the empty-state screen: \(frame)")
            snapshot(window, "Empty-\(asset.name)")
            host.view.hideEmptyDataView()
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

    func testProvidedNew3RetinaAssetsFitProductionControls() throws {
        let names = [
            "value_buoy",
            "distributor_nodes_highlight", "updatating_nodes", "firmware_cloud_version",
            "initiator", "mesh_distributor_guide_4", "mesh_upgrade_guide_1",
            "mesh_upgrade_guide_2", "mesh_upgrade_guide_3", "single_device",
            "adjust_speed_fast", "adjust_speed_slow", "daylight_scheme4",
            "daylight_scheme5", "daylight_scheme6", "daylight_scheme7",
            "daylight_standalone_sensor", "power_state_defined", "power_state_off",
            "power_state_restore", "profile_chart_daylight", "profile_chart_manual_control",
            "profile_chart_occupancy", "profile_person", "profile_person_big",
            "profile_proximity_lighting", "sensor_manul_override_timeout",
            "scene_data_add", "locked"
        ]
        XCTAssertEqual(names.count, 29)
        for name in names {
            try assertResolvedImageMatchesLumineuxSource(UIImage(named: name), name: name)
        }

        func assertAcceptedCompactFirmwareGuideOverflow(_ imageView: UIImageView,
                                                        named name: String,
                                                        in parent: UIView) {
            // SunSmart and SLGSync use the same @2x canvases (344x202 and
            // 288x80) inside these fixed-height production rows. The user
            // accepted the existing compact-iPhone overflow for only these
            // two guide images, so keep concrete layout evidence while the
            // outer guide container remains subject to strict containment.
            let expectedSizes: [String: CGSize] = [
                "mesh_upgrade_guide_1": CGSize(width: 172, height: 101),
                "mesh_upgrade_guide_3": CGSize(width: 144, height: 40)
            ]
            let expectedSize = expectedSizes[name]!
            let frame = imageView.convert(imageView.bounds, to: parent)
            let components = [frame.minX, frame.minY, frame.width, frame.height]

            XCTAssertFalse(imageView.isHidden)
            XCTAssertGreaterThan(imageView.alpha, 0.99)
            XCTAssertTrue(components.allSatisfy(\.isFinite),
                          "\(name) must retain a finite production frame: \(frame)")
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertEqual(frame.width, expectedSize.width, accuracy: 0.01)
            XCTAssertEqual(frame.height, expectedSize.height, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(frame.minX, -0.5)
            XCTAssertGreaterThanOrEqual(frame.minY, -0.5)
            let intersection = parent.bounds.intersection(frame)
            XCTAssertFalse(intersection.isNull,
                           "\(name) must intersect its fixed-height production row")
            XCTAssertGreaterThan(intersection.width * intersection.height, 0)
            XCTAssertFalse(imageView.hasAmbiguousLayout)
        }

        func imageView(named name: String, in container: UIView) throws -> UIImageView {
            let imageView = try XCTUnwrap(descendants(container).compactMap { $0 as? UIImageView }
                .first { image($0.image, matchesNamed: name) },
                "Production view did not load image: \(name)")
            try assertResolvedImageMatchesLumineuxSource(imageView.image, name: name)
            let parent = imageView.superview ?? container
            let compactIPhoneGeometry = !isIPad &&
                window.bounds.width <= 375 && window.bounds.height <= 667
            let acceptsCompactFirmwareGuideOverflow = compactIPhoneGeometry &&
                ["mesh_upgrade_guide_1", "mesh_upgrade_guide_3"].contains(name)
            if acceptsCompactFirmwareGuideOverflow {
                assertAcceptedCompactFirmwareGuideOverflow(imageView, named: name, in: parent)
            } else {
                assertContained(imageView, in: parent)
            }
            assertContained(imageView, in: container)
            return imageView
        }

        let buoy = BuoySliderView(frame: .zero, functionType: .level())
        _ = host(buoy, size: CGSize(width: 300, height: 100))
        buoy.value = 40
        buoy.slider.setNeedsLayout()
        buoy.slider.layoutIfNeeded()
        buoy.slider.sendActions(for: .touchDown)
        buoy.slider.sendActions(for: .valueChanged)
        buoy.layoutIfNeeded()
        let buoyImage = try imageView(named: "value_buoy", in: buoy)
        XCTAssertGreaterThan(buoyImage.alpha, 0.99)
        XCTAssertEqual(buoyImage.bounds.width, 50, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(buoyImage.bounds.height, 36.33)
        XCTAssertLessThanOrEqual(buoyImage.bounds.height, 36.5)
        snapshot(window, "New3-common-buoy")

        let firmwareHeader = MeshFirmwareUpgradeHeaderView(frame: .zero)
        _ = host(firmwareHeader, size: CGSize(width: 343, height: 130))
        firmwareHeader.step = .upgradeNodes
        firmwareHeader.layoutIfNeeded()
        let nodesButton = try XCTUnwrap(descendants(firmwareHeader).compactMap { $0 as? UIButton }
            .first { image($0.image(for: .selected), matchesNamed: "distributor_nodes_highlight") })
        XCTAssertTrue(nodesButton.isSelected)
        try assertResolvedImageMatchesLumineuxSource(nodesButton.currentImage,
                                                     name: "distributor_nodes_highlight")
        assertContained(nodesButton, in: firmwareHeader)
        snapshot(window, "New3-firmware-header-and-flow")

        let flow = BLEUpgradeInstructionsController()
        flow.datas = [
            .init(iconName: "initiator", name: "initiator".localizedString,
                  message: "initiator_message".localizedString + "\n\n",
                  showArrow: true, arrowX: SCRXFrom(149), ratio: 0.33),
            .init(iconName: "single_device", name: "Distributor".localizedString,
                  message: "distributor_message".localizedString + "\n\n",
                  showArrow: true, arrowX: SCRXFrom(219), ratio: 0.33),
            .init(iconName: "updatating_nodes", name: "updatating_nodes".localizedString,
                  message: "updatating_nodes_message".localizedString,
                  showArrow: false, arrowX: 0, ratio: 0.34)
        ]
        show(NavigationViewController(rootViewController: flow))
        for name in ["initiator", "single_device", "updatating_nodes"] {
            let button = try XCTUnwrap(descendants(flow.view).compactMap { $0 as? UIButton }
                .first { image($0.image(for: .normal), matchesNamed: name) })
            try assertResolvedImageMatchesLumineuxSource(button.image(for: .normal), name: name)
            assertContained(button, in: flow.view)
        }
        snapshot(window, "New3-firmware-header-and-flow")

        let firmware = NoRequestFirmwareVersionViewController(
            type: FirmwareUpdateTypeData(productId: 0x0001, targetVersion: nil, nodes: [])
        )
        show(NavigationViewController(rootViewController: firmware))
        _ = try imageView(named: "firmware_cloud_version", in: firmware.view)
        snapshot(window, "New3-firmware-header-and-flow")

        let upgradeGuide = MeshFirmwareUpgradeGuideView(
            title: "how_to_mesh_upgrade".localizedString,
            message: "mesh_upgrade_instructions_message".localizedString,
            steps: [.selectDistributor, .selectDevices, .waiting],
            contentHeight: 700
        )
        upgradeGuide.show()
        upgradeGuide.layoutIfNeeded()
        descendants(upgradeGuide).compactMap { $0 as? UITableView }.forEach { $0.layoutIfNeeded() }
        for name in ["mesh_upgrade_guide_1", "mesh_upgrade_guide_2", "mesh_upgrade_guide_3"] {
            _ = try imageView(named: name, in: upgradeGuide)
        }
        snapshot(window, "New3-firmware-guides")
        upgradeGuide.removeFromSuperview()

        let distributorGuide = MeshFirmwareUpgradeGuideView(
            title: "how_to_select_a_distributor".localizedString,
            message: "distributor_message".localizedString,
            steps: [.distributor],
            contentHeight: 400
        )
        distributorGuide.show()
        distributorGuide.layoutIfNeeded()
        descendants(distributorGuide).compactMap { $0 as? UITableView }.forEach { $0.layoutIfNeeded() }
        _ = try imageView(named: "mesh_distributor_guide_4", in: distributorGuide)
        snapshot(window, "New3-firmware-guides")
        distributorGuide.removeFromSuperview()

        let power = PowerUpBehaviorInstructionController()
        show(NavigationViewController(rootViewController: power))
        for name in ["power_state_off", "power_state_restore", "power_state_defined"] {
            _ = try imageView(named: name, in: power.view)
        }
        snapshot(window, "New3-profile-instructions")

        let speed = AdjustSpeedInstructionController()
        show(NavigationViewController(rootViewController: speed))
        for name in ["adjust_speed_slow", "adjust_speed_fast"] {
            _ = try imageView(named: name, in: speed.view)
        }
        snapshot(window, "New3-profile-instructions")

        let timeout = ManualOverrideTimeoutInstructionController()
        show(NavigationViewController(rootViewController: timeout))
        _ = try imageView(named: "sensor_manul_override_timeout", in: timeout.view)
        snapshot(window, "New3-profile-instructions")

        let daylightHeader = DaylightSensorInstructionsHeaderView(frame: .zero)
        _ = host(daylightHeader, size: CGSize(width: 343, height: 227))
        let standalone = try XCTUnwrap(descendants(daylightHeader).compactMap { $0 as? UIButton }
            .first { image($0.image(for: .normal), matchesNamed: "daylight_standalone_sensor") })
        try assertResolvedImageMatchesLumineuxSource(standalone.image(for: .normal),
                                                     name: "daylight_standalone_sensor")
        assertContained(standalone, in: daylightHeader)
        snapshot(window, "New3-profile-instructions")

        let proximityNumber = ProfileProximityLightingNumberView(frame: .zero)
        _ = host(proximityNumber, size: CGSize(width: 343, height: 250))
        _ = try imageView(named: "profile_person", in: proximityNumber)
        snapshot(window, "New3-profile-instructions")

        let daylight = DaylightSensorInstructionsController()
        show(NavigationViewController(rootViewController: daylight))
        let daylightCollection = try XCTUnwrap(descendants(daylight.view)
            .compactMap { $0 as? UICollectionView }.first)
        for index in 3...6 {
            let indexPath = IndexPath(item: index, section: 0)
            daylightCollection.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            daylightCollection.layoutIfNeeded()
            let cell = try XCTUnwrap(daylightCollection.cellForItem(at: indexPath)
                as? DaylightSensorInstructionsViewCell)
            let name = "daylight_scheme\(index + 1)"
            try assertResolvedImageMatchesLumineuxSource(cell.imageView.image, name: name)
            XCTAssertTrue(daylightCollection.visibleCells.contains { $0 === cell })
            XCTAssertNotNil(cell.window)
            XCTAssertFalse(cell.imageView.isHidden)
            XCTAssertGreaterThan(cell.imageView.alpha, 0.99)
            let imageFrame = cell.imageView.convert(cell.imageView.bounds, to: cell.contentView)
            XCTAssertTrue(cell.contentView.bounds.insetBy(dx: -0.5, dy: -0.5).contains(imageFrame),
                          "\(name) is outside its production cell: \(imageFrame)")
            // The production cell has a known 2.934pt vertical hugging ambiguity.
            // Production Swift is intentionally unchanged per user direction, so this
            // path verifies its concrete visible frame without the generic ambiguity check.
        }
        snapshot(window, "New3-profile-instructions")

        let neighbour = NumberOfNeghbourNodeInstructionsController()
        show(NavigationViewController(rootViewController: neighbour))
        _ = try imageView(named: "profile_person_big", in: neighbour.view)
        snapshot(window, "New3-profile-instructions")

        let profileInstructions = ProfileInstructionsViewCell(style: .default, reuseIdentifier: nil)
        profileInstructions.type = .proximityLighting
        _ = host(profileInstructions, size: CGSize(width: 343, height: 360))
        _ = try imageView(named: "profile_proximity_lighting", in: profileInstructions)
        snapshot(window, "New3-profile-instructions")

        func assertProductionChart(_ type: Profile.ProfileType, named name: String) throws {
            let phases = ProfileSettingsSphasesView(frame: .zero)
            phases.profile = Profile(type: type)
            _ = host(phases, size: CGSize(width: isIPad ? 720 : 343, height: 500))
            let expectedName = isIPad ? "\(name)_ipad" : name
            let chart = try XCTUnwrap(descendants(phases).compactMap { $0 as? UIImageView }
                .first { image($0.image, matchesNamed: expectedName) },
                "Production phase view did not load image: \(expectedName)")
            try assertResolvedImageMatchesLumineuxSource(chart.image, name: expectedName)
            assertContained(chart, in: phases)
            snapshot(window, "New3-profile-charts")
        }
        try assertProductionChart(.daylight, named: "profile_chart_daylight")
        try assertProductionChart(.manualControl, named: "profile_chart_manual_control")
        try assertProductionChart(.occupancy, named: "profile_chart_occupancy")
        try assertProductionChart(.occupancy_daylight, named: "profile_chart_occupancy_daylight")

        let standbyProfile = Profile(type: .proximityLightingWithPhotocell)
        let triggerPhases = ProfileTriggerConditionPhasesView(frame: .zero)
        triggerPhases.updateData(profile: standbyProfile,
                                 conditionData: try XCTUnwrap(standbyProfile.nightData))
        _ = host(triggerPhases, size: CGSize(width: isIPad ? 720 : 343, height: 690))
        let standbyName = isIPad
            ? "profile_chart_occupancy_standby_ipad"
            : "profile_chart_occupancy_standby"
        let standbyChart = try XCTUnwrap(descendants(triggerPhases).compactMap { $0 as? UIImageView }
            .first { image($0.image, matchesNamed: standbyName) },
            "Production trigger phase view did not load image: \(standbyName)")
        try assertResolvedImageMatchesLumineuxSource(standbyChart.image, name: standbyName)
        assertContained(standbyChart, in: triggerPhases)
        snapshot(window, "Generated-profile-standby-chart")

        let sceneAndSpace = UIView()
        let sceneCell = SceneAddDataAddCell(frame: .zero)
        let spaceCell = SpacesViewCell(frame: .zero)
        sceneAndSpace.addSubview(sceneCell)
        sceneAndSpace.addSubview(spaceCell)
        sceneCell.translatesAutoresizingMaskIntoConstraints = false
        spaceCell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sceneCell.topAnchor.constraint(equalTo: sceneAndSpace.topAnchor),
            sceneCell.centerXAnchor.constraint(equalTo: sceneAndSpace.centerXAnchor),
            sceneCell.widthAnchor.constraint(equalToConstant: 64),
            sceneCell.heightAnchor.constraint(equalToConstant: 64),
            spaceCell.topAnchor.constraint(equalTo: sceneCell.bottomAnchor, constant: 16),
            spaceCell.leftAnchor.constraint(equalTo: sceneAndSpace.leftAnchor),
            spaceCell.rightAnchor.constraint(equalTo: sceneAndSpace.rightAnchor),
            spaceCell.heightAnchor.constraint(equalToConstant: 210)
        ])
        _ = host(sceneAndSpace, size: CGSize(width: 343, height: 300))
        _ = try imageView(named: "scene_data_add", in: sceneCell)

        let protectedSpace = SpaceData(
            name: "Protected space", id: "new3-space", siteId: "new3-site",
            create: 0, isFavourite: false, permission: .editor, sourceType: .share,
            meshUUID: "new3-mesh", meshNetworkId: "new3-network"
        )
        protectedSpace.requiresPasswordVerification = true
        spaceCell.space = protectedSpace
        sceneAndSpace.layoutIfNeeded()
        let lock = try imageView(named: "locked", in: spaceCell)
        XCTAssertFalse(lock.isHidden)
        snapshot(window, "New3-scene-and-space")
    }
}

@MainActor
private final class NoRequestFirmwareVersionViewController: FirmwareVersionViewController {
    override var createsUIBeforeCloudRequest: Bool { true }
    override func loadFirmwareData() {}
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
