import Foundation

@main
struct ProximityLightingLifecycleContractTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected repository root path")
        }
        let root = CommandLine.arguments[1]
        let coordinator = try source(root, "SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift")
        let project = try source(root, "SunSmart.xcodeproj/project.pbxproj")
        let profile = try source(root, "SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift")
        let groupView = try source(root, "SunSmart/Main/Group/Controller/GroupViewController.swift")
        let groupAdd = try source(root, "SunSmart/Main/Group/Controller/GroupAddViewController.swift")
        let members = try source(root, "SunSmart/Main/Group/Controller/GroupMembersViewController.swift")
        let groupServer = try source(root, "SunSmart/Main/Group/Model/GroupServer.swift")
        let deletion = try source(root, "SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift")
        let deviceProtocol = try source(root, "SunSmart/Main/Device/Model/DeviceProtocol.swift")
        let dongle = try source(root, "SunSmart/Main/Device/Dongle/Controller/DeviceDongleViewController.swift")
        let restore = try source(root, "SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift")
        let topologyAdapter = try source(root, "SunSmart/Main/Group/Model/GroupProximityLightingData.swift")
        let space = try source(root, "SunSmart/Main/Space/Controller/SpaceViewController.swift")
        let importData = try source(root, "SunSmart/Common/Data/ImportData.swift")
        let exportData = try source(root, "SunSmart/Common/Data/ExportData.swift")
        let cloudSync = try source(root, "SunSmart/Common/Cloud/CloudSynchronizationManager.swift")
        let sync = try source(root, "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift")

        require(
            occurrenceCount("ProximityLightingTopologyReconciler.swift in Sources", in: project) == 10
                && occurrenceCount("ProximityLightingLifecycleCoordinator.swift in Sources", in: project) == 10,
            "Lifecycle sources must be compiled by all five app targets"
        )
        require(
            coordinator.contains("transaction.space.markLocalChangePendingCloudSync()")
                && appearsBefore("transaction.space.markLocalChangePendingCloudSync()", "applyAdditionalChanges()", in: coordinator),
            "Lifecycle commit must use write-ahead cloud marking"
        )
        require(
            coordinator.contains("candidateDeviceAddresses(")
                && coordinator.contains("transaction.nodes")
                && coordinator.contains("clearSyncStateCache"),
            "Lifecycle results must cover old/new candidates and invalidate caches"
        )

        require(
            profile.contains("((Profile) -> ProximityLightingLifecycleResult?)?")
                && profile.contains("supplementaryProximityLightingSyncDatas"),
            "Profile save must consume and present lifecycle results"
        )
        let profileSave = section(in: groupView, from: "vc.saveActionCallback =", to: "navigationController?.pushViewController(vc")
        require(
            profileSave.contains("transaction.updateProfile")
                && profileSave.contains("ProximityLightingLifecycleCoordinator.commit"),
            "Group Profile persistence must route through the lifecycle coordinator"
        )
        require(
            groupAdd.contains("transaction.updateProfile")
                && groupAdd.contains("finishGroupEdit")
                && groupAdd.contains("supplementaryProximityLightingSyncDatas"),
            "The general Group edit page must not bypass profile lifecycle reconciliation"
        )

        let memberSave = section(in: members, from: "private func performSave(", to: "private func updateEmptyUI")
        require(
            appearsBefore("isMeshNetworkConnected", "groupState = .exitFailure", in: memberSave)
                && memberSave.contains("transaction.updateMembers")
                && memberSave.contains("supplementaryProximityLightingSyncDatas")
                && !memberSave.contains("path.removeNode"),
            "Member mutations must validate first and use full-space lifecycle cleanup"
        )

        let groupDelete = section(in: groupServer, from: "static func deleteGroup(", to: "/// 组设备同步数据")
        require(
            groupDelete.contains("transaction.removeGroup")
                && groupDelete.contains("syncProximityLightingDatas")
                && appearsBefore("peerSyncSucceeded", "unsubscribeLocalProvisioner", in: groupDelete)
                && appearsBefore("remove(group: group)", "unsubscribeLocalProvisioner", in: groupDelete),
            "Group deletion must sync peers before final local removal"
        )
        let nodeDelete = section(in: deletion, from: "func commit()", to: "print(")
        require(
            nodeDelete.contains("transaction.removeNode")
                && nodeDelete.contains("allowExistingHardErrors: true")
                && nodeDelete.contains("applyAdditionalChanges: applyDeletion"),
            "Permanent deletion must atomically clean topology and extension data"
        )
        require(
            deviceProtocol.contains("syncPermanentDeletionPeers")
                && deviceProtocol.contains("mergedSyncDatas"),
            "Batch and protocol-based deletion must present deduplicated peer tasks"
        )
        require(
            dongle.contains("completePermanentDeletion(lifecycleResult)")
                && dongle.contains("spaceTriggerZones(datas: syncDatas)"),
            "Every permanent deletion caller must consume proximity peer tasks"
        )

        require(
            topologyAdapter.contains("transaction.replaceNodeAddress")
                && topologyAdapter.contains("transaction.removeNode"),
            "Restore migration must replace or remove every old reference"
        )
        require(
            restore.contains("proximityLightingRestoreSyncDatasByAddress")
                && restore.contains("$0.syncData.getMessageHandles(node: $0.node)"),
            "Restore must append cross-device proximity tasks to the same restore flow"
        )
        require(
            space.contains("reconcileLegacyProximityLightingTopology")
                && space.contains("presentProximityLightingRepairSyncIfNeeded"),
            "Space entry must normalize legacy topology and expose convergence tasks"
        )

        let importUpdate = section(
            in: importData,
            from: "@discardableResult\n    func update(",
            to: "extension Node"
        )
        require(
            appearsBefore("ProximityLightingImportPreflight.parse(", "network.forceRemove(node:", in: importUpdate),
            "Import must parse and validate proximity topology before destructive node replacement"
        )
        require(
            importData.contains("version == 1")
                && importData.contains("triggerZones = initialize ? [] : nil")
                && importData.contains("allowExistingHardErrors: proximityPreflight.schemaVersion == nil"),
            "Import must distinguish schema-v1 authority from legacy missing-field preservation"
        )
        require(
            exportData.contains("forKey: \"proximityLightingSchemaVersion\"")
                && exportData.contains("ProximityLightingLifecycleCoordinator.isEligible(group.info.profile.type)")
                && appearsBefore("ProximityLightingLifecycleCoordinator.begin(", "spaceJsonData.updateValue(self.id", in: exportData),
            "Export must normalize first, emit schema v1, and omit ineligible Group paths"
        )
        require(
            exportData.contains("func export() async -> [String: Any]?")
                && cloudSync.contains("guard let api = await self.operation.getNetworkApi() else")
                && cloudSync.contains("self.finishExportFailure()"),
            "Invalid local export must fail cloud sync without sending an empty payload"
        )
        require(
            importData.contains("struct SpaceImportOutcome")
                && importData.contains("status: .rejected")
                && importData.contains("hardErrors: proximityPreflight.hardErrors"),
            "Space import must expose rejected and hard-error outcomes"
        )
        require(
            sync.contains("private func appendProximityLightingItems(")
                && occurrenceCount("appendProximityLightingItems(", in: sync) >= 4,
            "Sync UI must share one precomputed proximity task renderer"
        )

        print("PASS: Proximity Lighting lifecycle integration contracts hold.")
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
        guard condition() else { fatalError(message) }
    }
}
