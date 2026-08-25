import Foundation

@main
struct DeviceNameFilterExpansionContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let menu = try source(root, "SunSmart/Main/Device/Filter/View/DeviceNameFilterMenuView.swift")
        let groupFooter = try source(root, "SunSmart/Main/Group/View/GroupDevicesFunctionView.swift")
        let members = try source(root, "SunSmart/Main/Group/Controller/GroupMembersViewController.swift")
        let schedule = try source(root, "SunSmart/Main/Timed/View/ScheduleDevicesView.swift")
        let page = try source(root, "SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift")
        let addView = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceDeviceAddView.swift")
        let manuallyAdd = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceManuallyAddView.swift")
        let quickAdd = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceQuickAddView.swift")
        let triggerAdd = try source(root, "SunSmart/Main/Group/Path/View/GroupPathSequenceTriggerAddView.swift")

        require(menu.contains("let preferredMenuY"),
                "Filter menu should calculate its preferred position above the source")
        require(menu.contains("let fallbackMenuY"),
                "Filter menu should fall back below top-anchored source views")

        require(groupFooter.contains("var deviceFilterBtn: UIButton!"),
                "Group footer should expose the filter button")
        require(groupFooter.contains("func functionDidFilterDevicesAction"),
                "Group footer should route filter taps through its delegate")
        require(groupFooter.contains("make.width.height.equalTo(30)"),
                "Group filter button should remain exactly 30 by 30")
        require(groupFooter.contains("make.left.equalTo(syncBtn.snp.right)"),
                "Visible Sync should remain left of the Group filter button")

        require(members.contains("private let deviceNameFilterSession = DeviceNameFilterSession()"),
                "Members should own an isolated filter session")
        require(members.contains("private var visibleNodes: [Node] = []"),
                "Members should keep complete and visible node collections separate")
        require(members.contains("return visibleNodes.count"),
                "Members collection data source should expose only visible nodes")
        require(members.contains("let canEditDevices = visibleNodes.filter"),
                "Members Select All should operate only on visible nodes")
        require(!members.contains("selectNodes.removeAll { !visibleAddresses.contains"),
                "Members filtering must preserve hidden selections")

        require(schedule.contains("private let deviceNameFilterSession = DeviceNameFilterSession()"),
                "Scheduler Devices should own an isolated filter session")
        require(schedule.contains("private var visibleNodes: [Node] = []"),
                "Scheduler Devices should keep complete and visible node collections separate")
        require(schedule.contains("return visibleNodes.count"),
                "Scheduler collection data source should expose only visible nodes")
        require(schedule.contains("let canSelectNodes = visibleNodes.filter"),
                "Scheduler Select All should operate only on visible nodes")
        require(schedule.contains("canSelectNodes.contains($0) && !disableUnselectNodes.contains($0)"),
                "Scheduler Select All must preserve visible devices that cannot be unselected")
        require(!schedule.contains("selectNodes.removeAll { !visibleAddresses.contains"),
                "Scheduler filtering must preserve hidden selections")

        require(page.contains("private let deviceNameFilterSession = DeviceNameFilterSession()"),
                "Path Sequence parent should own the shared Path and Zone session")
        require(page.contains("deviceNameFilterSession: deviceNameFilterSession"),
                "Path and Zone children should receive the parent session")
        require(addView.contains("deviceFilterBtn"),
                "Device Add view should provide a Manually Add filter button")
        require(addView.contains("make.centerY.equalTo(collapseBtn)"),
                "Path filter button should align vertically with the arrow button")
        require(addView.contains("make.right.equalTo(collapseBtn.snp.left).offset(-16)"),
                "Path filter button should stay 16 points left of the arrow button")
        require(addView.contains("make.width.height.equalTo(30)"),
                "Path filter button should remain exactly 30 by 30")
        require(manuallyAdd.contains("deviceNameFilterSession"),
                "Only Manually Add should receive and apply the Path filter session")
        require(manuallyAdd.contains("private(set) var visibleDevices: [Node] = []"),
                "Manually Add should keep complete and visible collections separate")
        require(!quickAdd.contains("DeviceNameFilterSession"),
                "Quick Add must not apply name filtering")
        require(!triggerAdd.contains("DeviceNameFilterSession"),
                "Trigger Add must not apply name filtering")

        print("DeviceNameFilterExpansionContractTests passed")
    }

    private static func source(_ root: String, _ relativePath: String) throws -> String {
        try String(contentsOfFile: "\(root)/\(relativePath)", encoding: .utf8)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
