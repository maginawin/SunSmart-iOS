import Foundation

@main
struct ProximityLightingReviewRegressionContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }
        let root = CommandLine.arguments[1]
        let importData = try source(root, "SunSmart/Common/Data/ImportData.swift")
        let groupServer = try source(root, "SunSmart/Main/Group/Model/GroupServer.swift")
        let groupView = try source(root, "SunSmart/Main/Group/Controller/GroupViewController.swift")
        let groupAdd = try source(root, "SunSmart/Main/Group/Controller/GroupAddViewController.swift")
        let deviceProtocol = try source(root, "SunSmart/Main/Device/Model/DeviceProtocol.swift")
        let deviceLights = try source(root, "SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift")

        require(
            importData.contains("struct SpaceImportResult")
                && importData.contains("serverSpaceId")
                && importData.contains("serverSpaceIds")
                && importData.contains("snapshotHasUnidentifiableSpace"),
            "Space import must preserve server presence independently of whether the payload was applied"
        )
        let siteSpaces = section(
            in: importData,
            from: "if let spaceDicts = json[\"spaces\"]",
            to: "// 更新Site网关数据"
        )
        require(
            siteSpaces.contains("serverSpaceIds.insert")
                && siteSpaces.contains("!serverSpaceIds.contains(localSpace.id)")
                && siteSpaces.contains("if !snapshotHasUnidentifiableSpace"),
            "Site reconciliation must only mark Spaces deleted from an identifiable authoritative server list"
        )

        let groupDelete = section(
            in: groupServer,
            from: "static func deleteGroup(",
            to: "/// 组设备同步数据"
        )
        require(
            !groupDelete.contains("originalGroupStates")
                && section(
                    in: groupDelete,
                    from: "guard deleteFailedNodes.isEmpty else {",
                    to: "syncProximityLightingDatas("
                ).contains("failed?(group)"),
            "Group deletion must keep per-node exit results instead of restoring every original state"
        )
        let deleteRetry = section(
            in: groupView,
            from: "private func deleteFailedCheck()",
            to: "/// 查看成员"
        )
        require(
            deleteRetry.contains("$0.groupState == .exitFailure")
                && deleteRetry.contains("outNodes: exitFailedNodes"),
            "Group deletion retry must include only nodes whose exit failed"
        )

        let profileSave = section(
            in: groupView,
            from: "vc.saveActionCallback =",
            to: "navigationController?.pushViewController(vc"
        )
        require(
            profileSave.contains("self.group.updateGroupSyncState()")
                && appearsBefore("self.group.updateGroupSyncState()", "return result", in: profileSave),
            "Profile save must invalidate general Group sync caches before returning to the settings page"
        )
        let applyGroupInfo = section(
            in: groupAdd,
            from: "private func applyGroupInfoEdits(",
            to: "private func finishGroupEdit("
        )
        let finishGroupEdit = section(
            in: groupAdd,
            from: "private func finishGroupEdit(",
            to: "private func setupUI()"
        )
        require(
            applyGroupInfo.contains("group.updateGroupSyncState()")
                && finishGroupEdit.contains("group.needSync || !lifecycleResult.syncDatas.isEmpty"),
            "General Group edit must invalidate and evaluate full Group sync independently of proximity tasks"
        )

        let protocolCallbacks = section(
            in: deviceProtocol,
            from: "let vc = SyncDevicesViewController(type: .spaceTriggerZones(datas: datas))",
            to: "navigationController?.pushViewController(vc, animated: true)"
        )
        requireCallbackClosesBeforeCompletion(protocolCallbacks, owner: "Protocol-based deletion")

        let batchSync = section(
            in: deviceLights,
            from: "private func syncDeletionPeersIfNeeded(",
            to: "/// 修复设备"
        )
        let batchCallbacks = section(
            in: batchSync,
            from: "let vc = SyncDevicesViewController(type: .spaceTriggerZones(datas: datas))",
            to: "navigationController?.pushViewController(vc, animated: true)"
        )
        requireCallbackClosesBeforeCompletion(batchCallbacks, owner: "Batch deletion")

        print("PASS: Proximity Lighting review regression contracts hold.")
    }

    private static func requireCallbackClosesBeforeCompletion(
        _ source: String,
        owner: String
    ) {
        require(
            source.contains("var didFinish = false")
                && source.contains("topViewController === vc")
                && appearsBefore("popViewController(animated: false)", "completion()", in: source)
                && occurrenceCount("finish()", in: source) >= 2,
            "\(owner) must close its Sync Devices page before invoking the original completion"
        )
    }

    private static func source(_ root: String, _ relativePath: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: root).appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static func section(in source: String, from start: String, to end: String) -> String {
        guard let startIndex = source.range(of: start)?.lowerBound,
              let endIndex = source.range(of: end, range: startIndex..<source.endIndex)?.lowerBound else {
            fatalError("Unable to locate section: \(start) ... \(end)")
        }
        return String(source[startIndex..<endIndex])
    }

    private static func appearsBefore(_ first: String, _ second: String, in source: String) -> Bool {
        guard let firstIndex = source.range(of: first)?.lowerBound,
              let secondIndex = source.range(of: second)?.lowerBound else {
            return false
        }
        return firstIndex < secondIndex
    }

    private static func occurrenceCount(_ value: String, in source: String) -> Int {
        source.components(separatedBy: value).count - 1
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
