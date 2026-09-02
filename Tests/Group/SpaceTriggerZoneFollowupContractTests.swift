import Foundation

@main
struct SpaceTriggerZoneFollowupContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let topologyPolicy = try source(
            root,
            "SunSmart/Main/Group/Model/ProximityLightingTopologyPolicy.swift"
        )
        let topologyPlanner = try source(
            root,
            "SunSmart/Main/Group/Model/GroupProximityLightingData.swift"
        )
        let groupPage = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift"
        )
        let spacePage = try source(
            root,
            "SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift"
        )
        let spaceMorePage = try source(
            root,
            "SunSmart/Main/Space/Controller/SpaceMoreViewController.swift"
        )
        let testView = try source(
            root,
            "SunSmart/Main/Group/Path/View/GroupPathSequencePathTestView.swift"
        )
        let restoreData = try source(
            root,
            "SunSmart/Common/Data/MeshNetwork+SunSmart.swift"
        )
        let restoreController = try source(
            root,
            "SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift"
        )
        let syncModel = try source(
            root,
            "SunSmart/Main/Space/Model/SyncDevicesCellModel.swift"
        )
        let syncDevicesController = try source(
            root,
            "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift"
        )
        let emergencySyncModel = try source(
            root,
            "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift"
        )
        let sequencePage = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift"
        )
        let groupZonePage = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequenceTriggerZoneController.swift"
        )
        let english = try source(root, "SunSmart/en.lproj/Localizable.strings")
        let chinese = try source(root, "SunSmart/zh-Hans.lproj/Localizable.strings")

        require(
            topologyPolicy.contains("static let maximumNeighborCount = 184")
                && topologyPolicy.contains("let capacityViolations: [CapacityViolation]"),
            "Unified topology must enforce the 184-neighbor limit"
        )
        require(
            topologyPlanner.contains("func capacityLimitMessage(for plan: Plan)")
                && english.contains("\"proximity_lighting_neighbor_limit_exceeded\"")
                && chinese.contains("\"proximity_lighting_neighbor_limit_exceeded\""),
            "Capacity failures must have English and Chinese UI messages"
        )

        let groupSave = section(
            in: groupPage,
            from: "@objc private func saveAction()",
            to: "private func makeSyncDatas("
        )
        require(
            appearsBefore(
                "showCapacityLimitIfNeeded(for: plan)",
                "space.markLocalChangePendingCloudSync()",
                in: groupSave
            ),
            "Group Path must reject over-capacity topology before persistence"
        )

        let spaceSave = section(
            in: spacePage,
            from: "@objc private func saveAction()",
            to: "private func zonesEqual"
        )
        require(
            appearsBefore(
                "showCapacityLimitIfNeeded(for: plan)",
                "space.markLocalChangePendingCloudSync()",
                in: spaceSave
            ),
            "Space Trigger Zone must reject over-capacity topology before persistence"
        )
        require(
            groupSave.contains("let syncDatas = makeSyncDatas(using: plan)")
                && groupSave.contains(
                    "SyncDevicesViewController(\n            type: .proximityLightingPath(datas: syncDatas)\n        )"
                ),
            "Group Sequence and Trigger Zone SAVE must enter an auto-starting sync page for every outstanding Group task"
        )
        require(
            spaceSave.contains("let syncDatas = buildAllSyncDatas(using: plan)")
                && spaceSave.contains(
                    "SyncDevicesViewController(type: .spaceTriggerZones(datas: syncDatas))"
                ),
            "Space Trigger Zone SAVE must enter an auto-starting sync page for every outstanding Space task"
        )
        require(
            spacePage.contains("title: \"devices_not_synced\".localizedString")
                && spacePage.contains("private func buildAllSyncDatas(")
                && spacePage.contains("reSync: true"),
            "Space Trigger Zone must expose Devices not synced and Re-sync"
        )

        let syncViewDidLoad = section(
            in: syncDevicesController,
            from: "override func viewDidLoad()",
            to: "override func viewDidAppear"
        )
        require(
            syncViewDidLoad.contains("if self.syncState == .inSync")
                && syncViewDidLoad.contains("self.startSync()"),
            "SAVE-created Sync device(s) pages must start their task automatically"
        )

        let spaceTriggerZoneEntry = section(
            in: spaceMorePage,
            from: "let vc = SpacePathTriggerZoneController(site: site, space: space)",
            to: "case .contentDisplay:"
        )
        require(
            spaceTriggerZoneEntry.contains("present(NavigationViewController(rootViewController: vc), animated: true)"),
            "Space More must present Space Trigger Zone in a modal navigation controller"
        )
        let noSyncSaveSuccess = section(
            in: spaceSave,
            from: "guard syncDatas.count > 0 else {",
            to: "let vc = SyncDevicesViewController"
        )
        let meshSyncSaveSuccess = section(
            in: spaceSave,
            from: "vc.syncSuccessCallback =",
            to: "navigationController?.pushViewController(vc, animated: true)"
        )
        require(
            noSyncSaveSuccess.contains("exitToSpaceMore()")
                && meshSyncSaveSuccess.contains("exitToSpaceMore()")
                && !noSyncSaveSuccess.contains("popViewController")
                && !meshSyncSaveSuccess.contains("popViewController"),
            "Every successful Space Trigger Zone SAVE path must exit to Space More"
        )
        require(
            spacePage.contains("private func exitToSpaceMore()")
                && spacePage.contains("navigationController?.dismiss(animated: true)"),
            "Space Trigger Zone must dismiss its modal navigation controller after SAVE"
        )

        let migration = section(
            in: topologyPlanner,
            from: "func migrateProximityLightingReferences(",
            to: "/// 邻近照明-节点信息"
        )
        require(
            migration.contains("path.paths.forEach")
                && migration.contains("path.zones.forEach")
                && migration.contains("triggerZones.forEach"),
            "Space migration must cover Group paths, Group zones, and Space zones"
        )
        require(
            appearsBefore(
                "markLocalChangePendingCloudSync()",
                "group.info.save()",
                in: migration
            ),
            "Restore migration must use one write-ahead cloud dirty marker"
        )
        let nodeRestore = section(
            in: restoreData,
            from: "func updateResoreData(oldNode:",
            to: "/// 获取恢复节点需要数据"
        )
        require(
            !nodeRestore.contains("proximityLightingPath"),
            "Node restore must not retain the old Group-only topology migration"
        )
        require(
            restoreController.contains("migrateProximityLightingReferences(")
                && restoreController.contains("private func proximityLightingRestoreSpace("),
            "Device Restore must route topology migration through Space"
        )
        let restoreCall = section(
            in: restoreController,
            from: "node.updateResoreData(oldNode:",
            to: "node.batteryPowerSwitchRestoreTargetSubscriptionSnapshots"
        )
        require(
            !restoreCall.contains("addToGroup != nil"),
            "Space reference migration must also run when Restore has no selected Group"
        )

        require(
            spacePage.contains("headerView.testBtn.isEnabled = !zone.items.isEmpty")
                && !spacePage.contains("groupCount == 1"),
            "Cross-Group Space Zone Test must be enabled"
        )
        let testStart = section(
            in: testView,
            from: "@objc private func startBtnAction",
            to: "@objc private func stopBtnAction"
        )
        require(
            testView.contains("private let groupAddresses: [Address]")
                && appearsBefore(
                    "groupAddresses.forEach",
                    "startControlTimer(fireDelay:",
                    in: testStart
                ),
            "Test must turn off every unique Group before lighting devices"
        )

        for (name, sourceText) in [
            ("normal", syncModel),
            ("emergency", emergencySyncModel)
        ] {
            let successCase = section(
                in: sourceText,
                from: "case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):",
                to: "case .gateway"
            )
            require(
                successCase.contains("node.proximityLightingEnabled")
                    && successCase.contains("node.proximityLightingRelayCount == relayNumber")
                    && successCase.contains("node.proximityLightingNeighborAddresses.sorted()"),
                "\(name) Neighbor Set success must include Enabled, Relay, and neighbors"
            )
        }

        require(
            sequencePage.contains("\"not_paths_remaining\".localizedString")
                && groupZonePage.contains("\"not_zones_remaining\".localizedString")
                && spacePage.contains("\"not_zones_remaining\".localizedString"),
            "All Path and Zone limit tips must resolve localization values"
        )

        print("PASS: Space Trigger Zone follow-up contracts hold.")
    }

    private static func source(_ root: String, _ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: root).appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) -> String {
        guard let start = source.range(of: startMarker)?.lowerBound,
              let end = source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound else {
            return ""
        }
        return String(source[start..<end])
    }

    private static func appearsBefore(
        _ first: String,
        _ second: String,
        in source: String
    ) -> Bool {
        guard let firstRange = source.range(of: first),
              let secondRange = source.range(of: second) else {
            return false
        }
        return firstRange.lowerBound < secondRange.lowerBound
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
