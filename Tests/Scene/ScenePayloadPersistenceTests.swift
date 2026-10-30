import Foundation
import SQLite

@main struct ScenePayloadPersistenceTests {
    static func main() throws {
        SunSmartDataManager.shared.db = try Connection(CommandLine.arguments[1])
        let manager = MeshNetworkManager.instance
        let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
        let node = Node(1); node.state = false; manager.realNodes = [node]
        let member = SceneDeviceMember(identity: node.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 1234, cct: 4500))
        let unresolved = TimedSchedulerNodeIdentity(nodeUUID: UUID().uuidString, unicastAddress: "0002", deviceKeyFingerprint: String(repeating: "B", count: 64))
        let configs: [SceneConfiguration] = [
            .init(kind: .devices, name: "Done", deviceMembers: [member]),
            .init(kind: .devices, name: "Write", deviceMembers: [member], pendingOperations: [.init(identity: member.identity, action: .write)]),
            .init(kind: .devices, name: "Remove", pendingOperations: [.init(identity: unresolved, action: .remove)]),
            .init(kind: .devices, name: "Deleting", deviceMembers: [member], pendingOperations: [.init(identity: member.identity, action: .remove)], isDeleting: true)
        ]
        for (index, config) in configs.enumerated() {
            let info = SceneInfo(sceneId: UInt16(index + 7), imageId: index + 3)
            info.configuration = config
            try info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        }
        // All four SDK rows are absent, including a committed projection failure.
        let records = try SceneConfigurationStore.exportRecords(scope: scope, scenes: [])
        precondition(records.map(\.number) == [7, 8, 9, 10])
        let payload: [String: Any] = ["groups": [], "scenes": try SceneConfigurationPayload.metadata(records: records),
            "spaceData": ["sceneConfigurations": try SceneConfigurationPayload.encode(records: records)]]
        let imported = try SceneConfigurationPayload.records(payload: payload)
        for _ in 0..<2 {
            precondition(SunSmartDataManager.shared.configurationTransaction {
                try SceneConfigurationStore.importRecords(imported, scope: scope)
            })
        }
        let rows = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        precondition(rows.count == 4 && rows.map(\.imageId) == [3, 4, 5, 6])
        for (index, row) in rows.enumerated() { precondition(row.configuration == configs[index], "revision, generations and unresolved identity must survive") }
        try SceneConfigurationStore().restoreSceneProjections()
        precondition(manager.scenes.map(\.number) == [7, 8, 9], "do not resurrect deletion tombstone")
        precondition(manager.scenes[1].info.configuration?.revision == configs[1].revision)
        let db = SunSmartDataManager.shared.db!
        try db.run("CREATE TRIGGER reject_scene BEFORE INSERT ON sceneInfos WHEN NEW.number = 9 BEGIN SELECT RAISE(ABORT, 'injected'); END")
        precondition(!SunSmartDataManager.shared.configurationTransaction {
            try SceneConfigurationStore.importRecords(imported, scope: scope)
        })
        let rolledBack = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        precondition(rolledBack.map(\.configuration) == configs.map(Optional.some), "partial import must roll back")
        try db.run("DROP TRIGGER reject_scene")
        node.fingerprint = String(repeating: "C", count: 64)
        let snapshot = try SceneTargetResolver.resolve(scene: manager.scenes[0])
        precondition(snapshot.targets.isEmpty && snapshot.unresolved.count == 1, "reprovisioned address never inherits relation")
        precondition(SunSmartDataManager.shared.configurationTransaction {
            try SceneConfigurationStore.removeConfirmedIdentities([node.timedSchedulerIdentity!], scope: scope)
        })
        let unchanged = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        precondition(unchanged.first!.configuration?.deviceMembers.count == 1)
        precondition(SunSmartDataManager.shared.configurationTransaction {
            try SceneConfigurationStore.removeConfirmedIdentities([member.identity], scope: scope)
        })
        let cleaned = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        precondition(cleaned[0].configuration?.deviceMembers.isEmpty == true)
        precondition(cleaned[1].configuration?.pendingOperations.isEmpty == true)
        precondition(cleaned[2].configuration?.pendingOperations.first?.identity == unresolved)
        precondition(cleaned[3].configuration?.isDeleting == true && cleaned[3].configuration?.revision == configs[3].revision)
        let zero = SceneConfigurationPayload.Record(number: 0, name: "invalid", imageId: 0, configuration: nil)
        do { _ = try SceneConfigurationPayload.encode(records: [zero]); fatalError("zero exported") } catch {}
        print("PASS: committed App rows roundtrip without SDK, idempotent import, original number/revision/generation, tombstone, transaction rollback and reprovision identity")
    }
}
