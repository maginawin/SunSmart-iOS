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
        let networkAPI = try source(root, "SunSmart/Common/Network/NetowrkReqeustApi.swift")
        let sync = try source(root, "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift")
        let planBuilder = try source(root, "SunSmart/Main/Space/Model/SyncTaskPlanBuilder.swift")
        let proximityBuilder = try source(root, "SunSmart/Main/Space/Model/SyncProximityTaskBuilder.swift")

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
            nodeDelete.contains("transaction.removeConfirmedAddresses")
                && nodeDelete.contains("confirmedDeletionAddresses: addresses")
                && nodeDelete.contains("try cleanExtensions")
                && nodeDelete.contains("readback.isValid"),
            "Permanent deletion must persist confirmed references and verify cleanup before completion"
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
            appearsBefore("await ProximityLightingImportPreflight.prepare(", "network.forceRemove(node:", in: importUpdate),
            "Import must parse and validate proximity topology before destructive node replacement"
        )
        require(
            importUpdate.contains("ProximityLightingImportValidationPolicy.resolve(")
                && importUpdate.contains("case .preserveLocalSnapshot:")
                && importUpdate.contains("continuation.resume(returning: .skipped)"),
            "Invalid proximity data must preserve a usable local snapshot without blocking Space entry"
        )
        require(
            importUpdate.contains("case .applyWithoutProximityMutation:")
                && importUpdate.contains("shouldCommitProximityTopology = false"),
            "A first import must remain accessible by isolating invalid proximity extension data"
        )
        require(
            !importUpdate.contains(".rejected(\"invalidProximityLightingPayload\")")
                && !importUpdate.contains("\"invalidProximityLightingTopology\""),
            "Proximity-only validation failures must not reject the whole Space"
        )
        require(
            importData.contains("version == 1")
                && importData.contains("triggerZones = initialize ? [] : nil")
                && importData.contains("allowExistingHardErrors: proximityPreflight.schemaVersion == nil"),
            "Import must distinguish schema-v1 authority from legacy missing-field preservation"
        )
        require(
            exportData.contains("spaceExtensionData.updateValue(1, forKey: \"proximityLightingSchemaVersion\")")
                && exportData.contains("spaceJsonData.updateValue(spaceExtensionData, forKey: \"spaceData\")")
                && exportData.contains("ProximityLightingLifecycleCoordinator.isEligible(group.info.profile.type)")
                && appearsBefore("ProximityLightingLifecycleCoordinator.begin(", "spaceJsonData.updateValue(self.id", in: exportData),
            "Export must validate first, emit schema v1 under spaceData, and omit ineligible Group paths"
        )
        require(
            exportData.contains("snapshotExportAuthorization(")
                && exportData.contains("verified remote orphanedGroupMembership")
                && exportData.contains("reason=remoteSnapshotDiffers")
                && exportData.contains("localSnapshotChangedDuringVerification")
                && exportData.contains("snapshotAuthorization.orphanPreservationReason != nil")
                && !exportData.contains("ProximityLightingLifecycleCoordinator.commit(")
                && appearsBefore("snapshotExportAuthorization(", "spaceJsonData.updateValue(self.id", in: exportData),
            "An orphaned Space upload must verify the remote baseline and avoid proximity mutation"
        )
        require(
            importData.contains("if rootJson[\"spaceData\"].exists()")
                && importData.contains("payloadJson = rootJson")
                && importData.contains("payloadJson[\"proximityLightingSchemaVersion\"]"),
            "Import must support the nested Space extension contract and legacy root payloads"
        )
        require(
            networkAPI.contains("case spaceUpload(siteId: String, spaceId: String, spaceData: [String: Any])")
                && networkAPI.contains("\"spaceId\": spaceId")
                && networkAPI.contains("\"spaces\": [spaceData]"),
            "Standalone Space uploads must include the explicit Space id and exported spaceData container"
        )
        require(
            exportData.contains("purpose: SpaceSnapshotExportPurpose = .localBackup")
                && exportData.contains("space.export(purpose: purpose)")
                && cloudSync.contains("space.export(purpose: .cloudSync)")
                && exportData.contains("purpose=localBackup")
                && cloudSync.contains("guard let api = await self.operation.getNetworkApi() else")
                && cloudSync.contains("self.finishExportFailure()"),
            "Cloud uploads must verify orphan baselines while local backups remain recoverable"
        )
        require(
            importData.contains("struct SpaceImportOutcome")
                && importData.contains("status: .rejected")
                && importData.contains("hardErrors: proximityPreparation.hardErrors"),
            "Space import must retain core rejection and topology diagnostic outcomes"
        )
        require(
            sync.contains("SyncTaskPlanBuilder(")
                && proximityBuilder.contains("func appendProximityLightingItems(")
                && occurrenceCount("appendProximityLightingItems(", in: planBuilder) == 3,
            "Sync UI must share one precomputed proximity task renderer"
        )

        require(
            importUpdate.contains("persistedPreparation.sourceSnapshot == proximityPreparation.normalized.snapshot")
                && appearsBefore("persistedPreparation.sourceSnapshot ==", "SpaceConfigurationSafety.finishImport(", in: importUpdate)
                && importUpdate.contains("validatedTopology: shouldCommitProximityTopology"),
            "Import must verify persisted logical topology before lifting the barrier or confirming its baseline"
        )
        require(
            space.contains("request.meshUUID == self.space.meshUUID")
                && space.contains("request.networkId == self.space.meshNetworkId")
                && space.contains("ProximityLightingTopologyContext.realNodes(in: network).compactMap")
                && space.contains("node.getNodeSyncProximityLighting(topologyPlan: result.plan)")
                && !space.contains("pendingProximityLightingRepairSyncDatas"),
            "Deferred import sync must retain only scope and regenerate tasks after activation"
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
