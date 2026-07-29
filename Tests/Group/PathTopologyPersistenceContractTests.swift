import Foundation

@main
struct PathTopologyPersistenceContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }

        let root = CommandLine.arguments[1]
        let spaceController = try source(
            root,
            "SunSmart/Main/Space/Controller/SpaceViewController.swift"
        )
        let groupPathController = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequencePageController.swift"
        )
        let groupPathSequenceController = try source(
            root,
            "SunSmart/Main/Group/Path/Controller/GroupPathSequenceViewController.swift"
        )
        let groupController = try source(
            root,
            "SunSmart/Main/Group/Controller/GroupViewController.swift"
        )
        let exportData = try source(
            root,
            "SunSmart/Common/Data/ExportData.swift"
        )
        let importData = try source(
            root,
            "SunSmart/Common/Data/ImportData.swift"
        )
        let triggerZoneController = try source(
            root,
            "SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift"
        )
        let syncDevicesController = try source(
            root,
            "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift"
        )

        require(
            spaceController.contains("func markLocalChangePendingCloudSync()"),
            "SpaceData must expose a write-ahead cloud dirty marker"
        )

        let cloudCommit = section(
            in: spaceController,
            from: "func commitLocalChangeForCloudSync",
            to: "private func refreshSummaryCountsFromCurrentMesh"
        )
        require(
            cloudCommit.contains("markLocalChangePendingCloudSync()"),
            "The existing cloud commit helper must reuse the write-ahead marker"
        )

        let groupSave = section(
            in: groupPathController,
            from: "@objc private func saveAction()",
            to: "@objc private func addItemAction()"
        )
        require(
            groupPathController.contains("let space: SpaceData"),
            "Group Path page must retain the owning Space"
        )
        require(
            groupPathController.contains("init(space: SpaceData, group: Group)"),
            "Group Path page must receive Space explicitly"
        )
        require(
            groupSave.contains("if edit"),
            "Unchanged Group Path data must not be marked dirty"
        )
        require(
            appearsBefore(
                "let equalPath = groupPath.copy()",
                "groupPath.paths = vc.setPaths",
                in: groupSave
            ),
            "Group Path must snapshot persisted data before merging child edits"
        )
        require(
            appearsBefore(
                "space.markLocalChangePendingCloudSync()",
                "group.info.save()",
                in: groupSave
            ),
            "Group Path must persist the cloud dirty marker before GroupInfo"
        )
        require(
            groupController.contains(
                "GroupPathSequencePageController(space: space, group: group)"
            ),
            "GroupViewController must pass the owning Space to Group Path"
        )

        let addPath = section(
            in: groupPathSequenceController,
            from: "func addPath()",
            to: "/// 停止设置路径"
        )
        require(
            !addPath.contains("groupPath.paths.append"),
            "Adding a Sequence must not mutate the parent Group Path before save"
        )
        require(
            addPath.contains("setPaths.append"),
            "Adding a Sequence must update the editable path copy"
        )

        let spaceExport = section(
            in: exportData,
            from: "extension SpaceData",
            to: "extension Node"
        )
        require(
            !spaceExport.contains("if !self.triggerZones.isEmpty"),
            "Empty Space Trigger Zones must not be omitted from export"
        )
        require(
            spaceExport.contains(
                "spaceJsonData.updateValue(triggerZonesArray, forKey: \"triggerZones\")"
            ),
            "Space export must write the triggerZones key after successful encoding"
        )
        require(
            importData.contains(
                "if let triggerZonesArray = json[\"triggerZones\"].arrayObject as? [[String: Any]]"
            ),
            "Space import must accept a present triggerZones array, including an empty array"
        )
        require(
            importData.contains("self.triggerZones = triggerZones"),
            "Space import must retain successfully decoded triggerZones"
        )
        require(
            importData.contains("self.triggerZones = []"),
            "Space import must normalize a missing or invalid triggerZones field to an empty array"
        )

        let triggerZoneSave = section(
            in: triggerZoneController,
            from: "@objc private func saveAction()",
            to: "private func zonesEqual"
        )
        let notificationCall =
            "NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName)"
        require(
            occurrenceCount(notificationCall, in: triggerZoneSave) == 1,
            "Space Trigger Zone save must own only the no-device common notification"
        )
        require(
            triggerZoneSave.contains("object: SpaceChangeDataType.common"),
            "The no-device branch must retain its common cloud notification"
        )
        require(
            syncDevicesController.contains("object: SpaceChangeDataType.device"),
            "The shared device sync controller must remain the device notification owner"
        )

        require(
            triggerZoneController.contains(
                "private struct SpaceTriggerZoneMemberKey: Hashable"
            ),
            "Trigger Zone eligibility must use a group and device address key"
        )
        require(
            triggerZoneController.contains(
                "private func eligibleZoneMemberKeys() -> Set<SpaceTriggerZoneMemberKey>"
            ),
            "Trigger Zone must build one current eligibility set"
        )
        require(
            triggerZoneController.contains("private func sanitizeSetZones()"),
            "Trigger Zone must expose one sanitizer for its working copy"
        )

        let initializer = section(
            in: triggerZoneController,
            from: "init(site: SiteData, space: SpaceData)",
            to: "required init?(coder:"
        )
        require(
            initializer.contains("sanitizeSetZones()"),
            "Trigger Zone must sanitize the working copy during initialization"
        )
        require(
            appearsBefore("sanitizeSetZones()", "let oldZones", in: triggerZoneSave),
            "Trigger Zone must sanitize again before save comparison"
        )
        require(
            appearsBefore(
                "space.markLocalChangePendingCloudSync()",
                "space.triggerZones = newZones",
                in: triggerZoneSave
            ),
            "Space Trigger Zone must write the cloud marker before logical persistence"
        )

        let desiredNeighbors = section(
            in: triggerZoneController,
            from: "private func desiredNeighborAddresses",
            to: "private func appendNode"
        )
        require(
            !desiredNeighbors.contains("eligibleZoneMemberKeys()"),
            "Per-node neighbor calculation must not rebuild global eligibility"
        )
        require(
            desiredNeighbors.contains(
                "eligibleKeys: Set<SpaceTriggerZoneMemberKey>"
            ),
            "Per-node neighbor calculation must receive the operation eligibility set"
        )

        let sanitizer = section(
            in: triggerZoneController,
            from: "private func sanitizeSetZones()",
            to: "private var quickAddGroupFilterOptions"
        )
        require(
            sanitizer.contains("zone.items.removeAll"),
            "Sanitizer must remove invalid members"
        )
        require(
            !sanitizer.contains("setZones.removeAll"),
            "Sanitizer must retain empty zones"
        )

        let syncBuilder = section(
            in: triggerZoneController,
            from: "private func buildSyncDatas()",
            to: "private func desiredNeighborAddresses"
        )
        require(
            syncBuilder.contains(".proximityLightingEnabled(false)"),
            "An eligible node with no desired neighbors must retain disable behavior"
        )
        require(
            occurrenceCount("eligibleZoneMemberKeys()", in: syncBuilder) == 1,
            "One device-task build must calculate eligibility exactly once"
        )
        require(
            syncBuilder.contains(
                "desiredNeighborAddresses(for: node, eligibleKeys: eligibleKeys)"
            ),
            "Device-task construction must reuse the operation eligibility set"
        )

        print("PASS: Path topology persistence contracts hold.")
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
              let end = source.range(
                of: endMarker,
                range: start..<source.endIndex
              )?.lowerBound else {
            fatalError("Unable to locate section: \(startMarker) ... \(endMarker)")
        }
        return String(source[start..<end])
    }

    private static func appearsBefore(
        _ first: String,
        _ second: String,
        in source: String
    ) -> Bool {
        guard let firstIndex = source.range(of: first)?.lowerBound,
              let secondIndex = source.range(of: second)?.lowerBound else {
            return false
        }
        return firstIndex < secondIndex
    }

    private static func occurrenceCount(_ needle: String, in source: String) -> Int {
        return source.components(separatedBy: needle).count - 1
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
