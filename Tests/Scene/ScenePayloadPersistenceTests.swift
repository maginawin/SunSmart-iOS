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
            info.displayOrder = [30, 40, 20, 10][index]
            info.configuration = config
            try info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        }
        // All four SDK rows are absent, including a committed projection failure.
        let records = try SceneConfigurationStore.exportRecords(scope: scope, scenes: [])
        precondition(records.map(\.number) == [7, 8, 9, 10])
        precondition(SceneDisplayOrder.payload(records: records) == ["000A", "0009", "0007", "0008"], "export must include order of unprojected rows and tombstones")
        let payload: [String: Any] = ["groups": [], "scenes": try SceneConfigurationPayload.metadata(records: records),
            "spaceData": ["sceneConfigurations": try SceneConfigurationPayload.encode(records: records),
                          SceneDisplayOrder.payloadKey: SceneDisplayOrder.payload(records: records)]]
        let imported = try SceneConfigurationPayload.records(payload: payload)
        for _ in 0..<2 {
            precondition(SunSmartDataManager.shared.configurationTransaction {
                try SceneConfigurationStore.importRecords(imported, scope: scope)
            })
        }
        let rows = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        precondition(rows.count == 4 && rows.map(\.imageId) == [3, 4, 5, 6])
        precondition(rows.map(\.displayOrder) == [3, 4, 2, 1])
        for (index, row) in rows.enumerated() { precondition(row.configuration == configs[index], "revision, generations and unresolved identity must survive") }
        try SceneConfigurationStore().restoreSceneProjections()
        precondition(manager.scenes.map(\.number) == [7, 8, 9, 10], "pending deletion remains visible on ordinary re-entry")
        precondition(Scene.sortedForDisplay(manager.scenes).map(\.number) == [10, 9, 7, 8], "projection recovery must retain imported display order")
        precondition(manager.scenes[1].info.configuration?.revision == configs[1].revision)
        let db = SunSmartDataManager.shared.db!
        try db.run("CREATE TRIGGER reject_scene BEFORE INSERT ON sceneInfos WHEN NEW.number = 9 BEGIN SELECT RAISE(ABORT, 'injected'); END")
        precondition(!SunSmartDataManager.shared.configurationTransaction {
            try SceneConfigurationStore.importRecords(imported, scope: scope)
        })
        let rolledBack = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        precondition(rolledBack.map(\.configuration) == configs.map(Optional.some), "partial import must roll back")
        precondition(rolledBack.map(\.displayOrder) == [3, 4, 2, 1], "partial import must roll back order with configuration")
        try db.run("DROP TRIGGER reject_scene")
        node.fingerprint = String(repeating: "C", count: 64)
        let snapshot = try SceneTargetResolver.resolve(scene: manager.scenes[0])
        precondition(snapshot.targets.isEmpty && snapshot.unresolved.count == 1, "reprovisioned address never inherits relation")
        precondition(SunSmartDataManager.shared.configurationTransaction {
            try SceneConfigurationStore.removeConfirmedIdentities([node.timedSchedulerIdentity!], scope: scope)
        })
        let unchanged = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        precondition(unchanged.first!.configuration?.deviceMembers.count == 1)
        precondition(unchanged.map(\.displayOrder) == [3, 4, 2, 1])
        precondition(SunSmartDataManager.shared.configurationTransaction {
            try SceneConfigurationStore.removeConfirmedIdentities([member.identity], scope: scope)
        })
        let cleaned = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        precondition(cleaned[0].configuration?.deviceMembers.isEmpty == true)
        precondition(cleaned[1].configuration?.pendingOperations.isEmpty == true)
        precondition(cleaned[2].configuration?.pendingOperations.first?.identity == unresolved)
        precondition(cleaned[3].configuration?.isDeleting == true && cleaned[3].configuration?.revision == configs[3].revision)
        precondition(cleaned.map(\.displayOrder) == [3, 4, 2, 1], "identity cleanup must not reset display metadata")
        let zero = SceneConfigurationPayload.Record(number: 0, name: "invalid", imageId: 0, configuration: nil)
        do { _ = try SceneConfigurationPayload.encode(records: [zero]); fatalError("zero exported") } catch {}
        try displayOrderPayloadCompatibility(records: records, scope: scope)
        try displayOrderIdentityRecovery(path: CommandLine.arguments[1] + ".restore-order")
        try siteRefreshPendingDeletion(path: CommandLine.arguments[1] + ".site-refresh")
        print("PASS: committed App rows roundtrip without SDK, idempotent import, original number/revision/generation, tombstone, transaction rollback and reprovision identity")
    }
}

private func siteRefreshPendingDeletion(path: String) throws {
    let manager = MeshNetworkManager.instance
    manager.meshNetwork = Network(); manager.currentNetworkKey.networkId = 1
    manager.scenes = []; manager.groups = []; manager.schedules = []
    Scene.sdkSaveFails = false; Scene.diskNumbers = []
    SunSmartDataManager.shared.db = try Connection(path)
    let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
    let node = Node(0x13); node.name = "L2"; node.state = false
    manager.realNodes = [node]
    let member = SceneDeviceMember(identity: node.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 1234, cct: 4500))
    let store = SceneConfigurationStore()
    var records = (1...10).map { number in
        SceneConfigurationPayload.Record(number: UInt16(number), name: "Scene \(number)", imageId: 1,
            configuration: .init(kind: .groups, name: "Scene \(number)"), displayOrder: Int64(number))
    }
    for number in 11...12 {
        let configuration = SceneConfiguration(schemaVersion: 2, kind: .devices, name: "Pending \(number)",
            deviceMembers: [member], pendingOperations: [.init(identity: member.identity, action: .remove)],
            isDeleting: true, deletionReferences: .init(pending: [
                .init(kind: .scheduler, identity: member.identity, address: 0x13, name: "L2")
            ]))
        records.append(.init(number: UInt16(number), name: configuration.name, imageId: 2,
                             configuration: configuration, displayOrder: Int64(number)))
        node.sceneExecuteDatas.append(.init(sceneNumber: UInt16(number)))
    }
    for count in [11, 12] {
        let selected = Array(records.prefix(count))
        let payload: [String: Any] = ["groups": [], "scenes": try SceneConfigurationPayload.metadata(records: selected),
            "updateTimestamp": 100, "spaceData": ["sceneConfigurations": try SceneConfigurationPayload.encode(records: selected),
                                                  SceneDisplayOrder.payloadKey: SceneDisplayOrder.payload(records: selected)]]
        // Real JSON and App SQLite boundaries; the SDK fixture substitutes its
        // Scene persistence/transport. Repeated imports use the identical bytes.
        let json = try JSONSerialization.data(withJSONObject: payload)
        for permission in [SpaceData.Permission.owner, .visitor, .editor] {
            SpaceData.value.permission = permission
            SpaceConfigurationSafety.recovery.authority = permission == .visitor ? .readOnly : .writable
            for _ in 0..<2 {
                let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
                let imported = try SceneConfigurationPayload.records(payload: decoded)
                manager.scenes = []; Scene.diskNumbers = [] // complete import replaces SDK projections
                precondition(SunSmartDataManager.shared.configurationTransaction {
                    try SceneConfigurationStore.importRecords(imported, scope: scope)
                })
                let scenes = SceneConfigurationStore.projectImportedRecords(imported, scope: scope,
                    network: manager.meshNetwork!, nodes: manager.realNodes)
                precondition(scenes.count == count && Scene.listedScenes(manager.scenes).count == count,
                             "complete import must retain pending Scenes and the Site count")
                precondition(Scene.diskNumbers == Set(selected.map(\.number)), "import must save every SDK Scene")
                precondition(scenes.filter { $0.number > 10 }.allSatisfy {
                    $0.info.configuration?.isDeleting == true && $0.addresses == [0x13]
                        && !SceneCommandBuilder.isSelectable(scene: $0)
                }, "pending Scenes remain visible but cannot Recall or become new references")
                manager.scenes = []
                SunSmartDataManager.shared.db = try Connection(path)
                try store.restoreSceneProjections()
                try store.restoreSceneProjections()
                precondition(Scene.listedScenes(manager.scenes).count == count,
                             "ordinary re-entry must restore each Scene once without explicit sync")
                let reloaded = try SceneConfigurationStore.exportRecords(scope: scope, scenes: manager.scenes)
                precondition(reloaded.map(\.configuration) == selected.map(\.configuration),
                             "re-entry must preserve original revision, identity, generations and Scheduler work")
            }
        }
    }
    let events = DeviceEmerFireData.reservedSceneNumbers.map { Scene($0) }
    precondition(Scene.listedScenes(manager.scenes + events).count == 12,
                 "Site summaries and management exclude the same EFC events")
    // A completed device cleanup with a remaining App row stays read-only on
    // passive load. Only an authorized cleanup may release the number.
    let info = try SceneInfo.loadAll(meshUUID: scope.meshUUID).first { $0.sceneId == 11 }!
    info.configuration!.pendingOperations = []; info.configuration!.deletionReferences = .init()
    try info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
    manager.scenes = []; Scene.diskNumbers = []
    SpaceData.value.permission = .visitor; SpaceConfigurationSafety.recovery.authority = .readOnly
    try store.restoreSceneProjections()
    precondition(Scene.listedScenes(manager.scenes).count == 12 && SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 11) != nil)
    SpaceData.value.permission = .owner; SpaceConfigurationSafety.recovery.authority = .writable
    try store.prepareDeletionRetries()
    precondition(Scene.listedScenes(manager.scenes).count == 11 && SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 11) == nil)
    precondition(manager.scenes.first { $0.number == 12 }?.info.configuration == records[11].configuration,
                 "finishing one Scene must preserve the other pending cleanup")
    print("PASS Site refresh: 11/12 Scenes, JSON/import/SQLite re-entry, repeated same payload, owner/editor/visitor, original pending generations, EFC count and authorized finalization")
}

private func displayOrderPayloadCompatibility(records: [SceneConfigurationPayload.Record], scope: SceneScope) throws {
    let foreign = SceneInfo(sceneId: 90)
    foreign.displayOrder = 900; foreign.configuration = .init(kind: .groups, name: "Other Space")
    try foreign.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: "other")
    let cases: [(String, Any?, [String])] = [
        ("new", ["000A", "0009", "0007", "0008"], ["000A", "0009", "0007", "0008"]),
        ("old missing", nil, ["0007", "0008", "0009", "000A"]),
        ("empty", [], ["0007", "0008", "0009", "000A"]),
        ("partial", ["0008"], ["0008", "0007", "0009", "000A"]),
        ("duplicates and obsolete", ["0009", "0009", "0001", "FFFF", "broken", 4] as [Any], ["0009", "0007", "0008", "000A"]),
        ("wrong outer type", "0008", ["0007", "0008", "0009", "000A"]),
        ("null", NSNull(), ["0007", "0008", "0009", "000A"])
    ]
    SpaceData.value.permission = .viewer
    for (label, raw, expected) in cases {
        var extensionData: [String: Any] = ["sceneConfigurations": try SceneConfigurationPayload.encode(records: records)]
        if let raw { extensionData[SceneDisplayOrder.payloadKey] = raw }
        let payload: [String: Any] = ["groups": [], "scenes": try SceneConfigurationPayload.metadata(records: records), "spaceData": extensionData]
        let parsed = try SceneConfigurationPayload.records(payload: payload)
        precondition(SceneDisplayOrder.payload(records: parsed) == expected, label)
        precondition(SunSmartDataManager.shared.configurationTransaction {
            try SceneConfigurationStore.importRecords(parsed, scope: scope)
        }, "display import must remain available to a read-only recipient")
        let persisted = try SceneConfigurationStore.exportRecords(scope: scope, scenes: MeshNetworkManager.instance.scenes)
        precondition(SceneDisplayOrder.payload(records: persisted) == expected, "SQLite roundtrip: \(label)")
        precondition(persisted.map(\.configuration) == records.map(\.configuration), "display normalization must not alter scene intent")
        precondition(SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 90)?.displayOrder == 900)
    }
    // An authoritative old payload uses its number fallback. It must not inherit
    // previous local order merely because the new instance reused a Mesh number.
    let empty: [String: Any] = ["groups": [], "scenes": [], "spaceData": [SceneDisplayOrder.payloadKey: ["0007", "000A"]]]
    let emptyRecords = try SceneConfigurationPayload.records(payload: empty)
    precondition(emptyRecords.isEmpty && SceneDisplayOrder.payload(records: emptyRecords).isEmpty)
    precondition(SunSmartDataManager.shared.configurationTransaction {
        try SceneConfigurationStore.importRecords(emptyRecords, scope: scope)
    })
    let emptyRows = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
    precondition(emptyRows.isEmpty && SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 90)?.displayOrder == 900)
    SpaceData.value.permission = .owner
    print("PASS display payload: new/old/empty/partial/duplicate/obsolete lists, read-only import, no local-number inheritance and Space isolation")
}

private func displayOrderIdentityRecovery(path: String) throws {
    SunSmartDataManager.shared.db = try Connection(path)
    let manager = MeshNetworkManager.instance
    manager.meshNetwork = Network(); manager.scenes = []; manager.groups = []; manager.schedules = []
    Scene.diskNumbers = []; Scene.sdkSaveFails = false
    SpaceData.value = SpaceData(); SpaceViewController.active = nil
    SpaceConfigurationSafety.recovery = FixtureRecoveryState()
    let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
    let node = Node(1); manager.realNodes = [node]
    let oldIdentity = node.sceneConfigurationIdentity!
    let scene = Scene(5); scene.name = "Restored"
    scene.info.displayOrder = 27
    scene.info.configuration = .init(kind: .devices, name: scene.name,
        deviceMembers: [.init(identity: oldIdentity, parameters: .init(isOn: true, lightness: 1234, cct: 4500))])
    manager.scenes = [scene]
    try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
    let store = SceneConfigurationStore()
    let receipt = try store.prepareRestore(oldNode: node)!
    node.fingerprint = String(repeating: "B", count: 64)
    try store.verifyRestore(receiptID: receipt, newNode: node)
    let restored = SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 5)!
    precondition(restored.displayOrder == 27 && scene.info.displayOrder == 27)
    precondition(restored.configuration?.deviceMembers.first?.identity == node.sceneConfigurationIdentity)
    precondition(restored.configuration?.deviceMembers.first?.identity != oldIdentity)
    let configuration = restored.configuration
    _ = try store.resumeVerifiedRestores()
    precondition(SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 5)?.displayOrder == 27)
    precondition(SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 5)?.configuration == configuration, "replayed identity receipt must preserve both intent and order")
    print("PASS display order identity recovery: verified migration and repeated recovery preserve position")
}
