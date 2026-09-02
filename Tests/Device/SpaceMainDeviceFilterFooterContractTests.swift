import Foundation

@main
struct SpaceMainDeviceFilterFooterContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let footer = try source(root, "SunSmart/Main/Space/View/SpaceFunctionFooterView.swift")
        let lights = try source(root, "SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift")
        let switches = try source(root, "SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift")
        let sensors = try source(root, "SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift")
        let others = try source(root, "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift")

        require(footer.contains("var deviceFilterBtn: UIButton!"),
                "Space footer should expose an independent device filter button")
        require(footer.contains("normalImageName: \"device_filter\""),
                "Space filter should use the requested normal image")
        require(footer.contains("selectedImageName: \"device_filter_selected\""),
                "Space filter should use the requested selected image")
        require(footer.contains("make.width.height.equalTo(30)"),
                "Space filter should match the 30 by 30 Group Members control")
        require(footer.contains("deviceFilterBtn.isSelected = deviceNameFilterActive"),
                "Committed filter state should drive the new button selected state")

        require(footer.contains("countBtn.isUserInteractionEnabled = false"),
                "The device count should be presentation-only")
        require(footer.contains("countBtn.accessibilityTraits = .staticText"),
                "The device count should expose static accessibility semantics")
        require(!footer.contains("countBtn.addTarget"),
                "The device count must no longer open the filter menu")
        require(!footer.contains("space_device_count_selected"),
                "Filtering must no longer replace the device count image")

        require(footer.contains("case beforeSort"),
                "Space footer should support the Lights filter placement")
        require(footer.contains("make.right.equalTo(sortBtn.snp.left).offset(SCRXFrom(-20))"),
                "Lights filter should stay left of Sort using Space footer spacing")
        require(footer.contains("make.right.equalTo(deviceFilterBtn.snp.left).offset(SCRXFrom(-20))"),
                "Visible Sync should stay left of the Lights filter")
        require(footer.contains("case beforeEdit"),
                "Space footer should support the other Main category placement")
        require(footer.contains("make.right.equalTo(editBtn.snp.left).offset(SCRXFrom(-20))"),
                "Other Main filters should stay left of Edit using Space footer spacing")
        require(footer.contains("deviceFilterBtn.isHidden = true"),
                "Editing should hide the filter control")
        require(footer.contains("deviceFilterBtn.isHidden = deviceFilterPlacement == nil"),
                "Leaving editing should restore only explicitly configured filters")

        requireMainController(lights, placement: ".beforeSort", name: "Lights")
        requireMainController(switches, placement: ".beforeEdit", name: "Switches")
        requireMainController(sensors, placement: ".beforeEdit", name: "Sensors")
        requireMainController(others, placement: ".beforeEdit", name: "Others")

        let nonMainFooterUsers = [
            "SunSmart/Main/Group/Controller/GroupsViewController.swift",
            "SunSmart/Main/Scene/Controller/ScenesViewController.swift",
            "SunSmart/Main/Timed/Controller/TimedViewController.swift",
            "SunSmart/Main/Device/Gateway/Controller/GatewaysViewController.swift",
            "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmDevicesController.swift"
        ]
        for path in nonMainFooterUsers {
            let content = try source(root, path)
            require(!content.contains("configureDeviceNameFilter"),
                    "Non-Main footer user should not enable the new filter: \(path)")
        }

        print("SpaceMainDeviceFilterFooterContractTests passed")
    }

    private static func requireMainController(_ content: String, placement: String, name: String) {
        require(content.contains("configureDeviceNameFilter(placement: \(placement))"),
                "\(name) should configure the expected filter placement")
        require(content.contains("showDeviceNameFilterMenu(from: view.deviceFilterBtn)"),
                "\(name) should anchor the menu to the new filter button")
        require(!content.contains("showDeviceNameFilterMenu(from: view.countBtn)"),
                "\(name) must not anchor the menu to the device count")
    }

    private static func source(_ root: String, _ relativePath: String) throws -> String {
        try String(contentsOfFile: "\(root)/\(relativePath)", encoding: .utf8)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
