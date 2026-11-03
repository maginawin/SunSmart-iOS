import Foundation

@main struct SceneDeletionCascadeTests {
    static let manager = MeshNetworkManager.instance
    static var passed = 0
    static var failed = 0
    static var scope: SceneScope { .init(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: manager.currentNetworkKey.networkId.hex) }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passed += 1 } else { failed += 1; print("FAIL cascade: \(message)") }
    }
    static func fixture() -> (Scene, Node, Node) {
        FixtureStore.reset()
        manager.meshNetwork = Network(); manager.currentNetworkKey.networkId = 1; manager.currentApplicationKey.index = 0
        manager.schedules = []; manager.switchs = []
        let scene = Scene(), lamp = Node(1), proxy = Node(2)
        lamp.schedulerSetupModels = [Model(), Model()]
        lamp.schedulerSetupModels.forEach { lamp.allSchedulerModelEntrys[$0] = [:] }
        manager.realNodes = [lamp, proxy]; manager.scenes = [scene]
        return (scene, lamp, proxy)
    }
    static func schedule(_ id: Int, scene: UInt16, node: Node, slot: Int) -> Schedule {
        let item = Schedule(id, scene: scene)
        item.nodeAddresses = [node.primaryUnicastAddress]
        item.nodeSlots = [.init(identity: node.timedSchedulerIdentity!, slot: slot, state: .assigned)]
        return item
    }
    static func markDeleting(_ scene: Scene, references: SceneDeletionReferences) throws {
        for item in manager.switchs where FixtureStore.switches[item.id] == nil { _ = item.save(meshUUID: scope.meshUUID, networkId: scope.networkID) }
        for item in manager.schedules where FixtureStore.schedules[item.id] == nil { _ = item.save(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID) }
        scene.info.configuration = .init(schemaVersion: 2, kind: .groups, name: "Scene 1",
            isDeleting: true, deletionReferences: references)
        try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
    }
    static func pending(_ scene: Scene) -> [SceneReferenceRemoval] { scene.info.configuration?.deletionReferences?.pending ?? [] }

    static func main() throws {
        try preparationIsAtomicAndSelective()
        try schedulerPlansPreserveCurrentOwner()
        try legacyAndOrphanSchedulerRecovery()
        try retriesRebuildSchedulerWork()
        try changedSchedulerSlotRejectsLateReceipt()
        try kineticCleanupAndReceiptLifetime()
        try duplicateObservedKeysAreCanonical()
        try kineticWithoutGroupPreservesUnknownCleanup()
        try registeredResidualRequiresSchedulerRead()
        try persistedEditRejectsOldReceiptAndUsesLatestAction()
        try unresolvedAndStaleOperations()
        try powerAndEmergencyCleanup()
        try powerWithoutGroupCleansOnlyCapturedKeys()
        try changedPowerAndEmergencyConfigurationRejectLateReceipts()
        try finalizationAndAdmission()
        print("cascade: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }

    static func preparationIsAtomicAndSelective() throws {
        let (scene, lamp, proxy) = fixture()
        let first = schedule(10, scene: 1, node: lamp, slot: 1)
        let second = schedule(11, scene: 1, node: lamp, slot: 3)
        let changed = schedule(12, scene: 2, node: lamp, slot: 5)
        changed.needDeleteSceneNumbers = [1]
        manager.schedules = [first, second, changed]
        for item in manager.schedules { _ = item.save(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID) }
        let kinetic = DeviceSwitchData(id: "switch", name: "Wall switch")
        kinetic.sceneANumber = 1; kinetic.sceneBNumber = 2; kinetic.sceneCNumber = 1; kinetic.sceneDNumber = 3
        kinetic.proxyNodeAddress = proxy.primaryUnicastAddress
        kinetic.longPress = .cctDown(0xC002)
        let unrelated = DeviceSwitchData(id: "unrelated", name: "Other switch")
        unrelated.sceneANumber = 2
        manager.switchs = [kinetic, unrelated]
        _ = kinetic.save(meshUUID: scope.meshUUID, networkId: scope.networkID)
        let preparation = try SceneDeletionCascade.prepare(scene: scene, snapshot: .init(scope: scope, targets: [.init(node: lamp)]))
        check(preparation.references.scheduleIDs == [10, 11], "delete only Timed still targeting this Scene")
        check(preparation.schedules.count == 2 && preparation.schedules.allSatisfy { $0.action == .noAction && $0.sceneNumber == nil }, "direct Timed becomes durable deletion")
        check(preparation.schedules.allSatisfy { $0.nodeSlots?.allSatisfy { $0.state == .pendingRemoval } == true }, "keep slots pending until receipts")
        check(changed.sceneNumber == 2 && changed.action == .sceneRecall, "new Timed target remains active")
        check(first.sceneNumber == 1 && kinetic.sceneANumber == 1, "prepare does not mutate live models")
        let updated = preparation.switches[0]
        check(preparation.switches.count == 1 && updated.sceneANumber == nil && updated.sceneCNumber == nil,
              "clear matching switch actions only")
        check(updated.sceneBNumber == 2 && updated.sceneDNumber == 3 && updated.longPress == kinetic.longPress,
              "retain other scenes and long press")
        let scheduler = preparation.references.pending.first { $0.kind == .scheduler }!
        check(scheduler.slots == [1, 3], "changed Timed slot is not queued for unconditional deletion")
        FixtureStore.failSwitchSave = true
        let saved = SunSmartDataManager.shared.configurationTransaction { try preparation.persist() }
        check(!saved && FixtureStore.schedules[10]?.sceneNumber == 1 && FixtureStore.switches[kinetic.id]?.sceneANumber == 1,
              "partial preparation persistence rolls back all business writes")
        FixtureStore.failSwitchSave = false
        check(SunSmartDataManager.shared.configurationTransaction { try preparation.persist() }, "prepared business changes persist")
        preparation.install()
        check(manager.schedules.first { $0.id == 10 }?.sceneNumber == nil && manager.switchs.first { $0.id == kinetic.id }?.sceneANumber == nil,
              "install publishes committed copies")
        check(manager.schedules.first { $0.id == 12 } === changed && manager.switchs.last === unrelated,
              "unrelated objects are preserved")
    }

    static func schedulerPlansPreserveCurrentOwner() throws {
        let (scene, lamp, _) = fixture()
        let ordinary = lamp.schedulerSetupModels[0], secondary = lamp.schedulerSetupModels[1]
        let deleting = schedule(10, scene: 1, node: lamp, slot: 1)
        deleting.sceneNumber = nil; deleting.action = .noAction; deleting.nodeAddresses = []
        let changed = schedule(12, scene: 2, node: lamp, slot: 5)
        manager.schedules = [deleting, changed]
        lamp.allSchedulerModelEntrys[ordinary] = [1: .init(action: .sceneRecall, sceneNumber: 1),
            2: .init(action: .sceneRecall, sceneNumber: 9), 5: .init(action: .sceneRecall, sceneNumber: 1)]
        lamp.allSchedulerModelEntrys[secondary] = [5: .init(action: .sceneRecall, sceneNumber: 1),
            7: .init(action: .sceneRecall, sceneNumber: 1)]
        let reference = SceneReferenceRemoval(kind: .scheduler, identity: lamp.timedSchedulerIdentity, address: 1, name: "Scheduler", slots: [1])
        try markDeleting(scene, references: .init(scheduleIDs: [10], pending: [reference]))
        let read = SceneDeletionTask(scene: scene, reference: reference, node: lamp, phase: .read)
        let reads = read.messageHandles
        check(reads.count == 32 && reads.allSatisfy { $0.message is SchedulerActionGet }, "read every slot on all scheduler models")
        check(read.apply(results: reads, expected: reads) && pending(scene).count == 1, "read does not settle cleanup receipt")
        let task = SceneDeletionTask(scene: scene, reference: reference, node: lamp, phase: .apply)
        let writes = task.messageHandles
        check(writes.count == 4, "clear matching entries plus captured deleting slots only")
        check(!writes.contains { ($0.message as? SchedulerActionSet)?.index == 2 }, "unrelated slot is untouched")
        let newOwner = writes.first { $0.model === ordinary && ($0.message as? SchedulerActionSet)?.index == 5 }
        check((newOwner?.message as? SchedulerActionSet)?.entry == changed.schedulerEntry, "old scene is replaced by current owner configuration")
        let cleanup = writes.filter { !($0.model === ordinary && ($0.message as? SchedulerActionSet)?.index == 5) }
        check(cleanup.allSatisfy { ($0.message as? SchedulerActionSet)?.entry.isValid == false }, "other old scene entries are cleared")
        writes.forEach { handle in
            let message = handle.message as! SchedulerActionSet
            if message.entry.isValid { lamp.allSchedulerModelEntrys[handle.model]?[Int(message.index)] = message.entry }
            else { lamp.allSchedulerModelEntrys[handle.model]?[Int(message.index)] = nil }
        }
        check(task.apply(results: writes, expected: writes), "matched scheduler receipts settle cleanup")
        check(SceneDeletionCascade.canFinish(info: scene.info), "cleared references permit finalization without deleting new owner")
        try markDeleting(scene, references: .init(pending: [reference]))
        lamp.allSchedulerModelEntrys[secondary] = nil
        let unknown = SceneDeletionTask(scene: scene, reference: reference, node: lamp, phase: .apply)
        check(unknown.messageHandles.isEmpty && !unknown.allowsEmpty && !unknown.apply(results: [], expected: []),
              "unknown model state cannot become successful empty cleanup")
    }

    static func kineticCleanupAndReceiptLifetime() throws {
        let (scene, _, proxy) = fixture()
        let item = DeviceSwitchData(id: "switch", name: "Switch")
        item.proxyNodeAddress = 2; item.sceneANumber = nil; item.sceneBNumber = 2; item.longPress = .cctDown(0xC002)
        manager.switchs = [item]
        let reference = SceneReferenceRemoval(kind: .kinetic, identity: proxy.timedSchedulerIdentity, address: 2,
            objectID: item.id, name: item.name, keys: [4])
        try markDeleting(scene, references: .init(pending: [reference]))
        let task = SceneDeletionTask(scene: scene, reference: reference, node: proxy, phase: .apply)
        let handles = task.messageHandles
        check(handles.count == 1, "only matched switch key is rewritten")
        if let message = handles.first?.message as? SunricherVendorSet, case .enOceanSwitchKeySet(let key, _) = message.function {
            check(key.key == 4 && key.shortPressAction == .sceneRecall(nil, address: 0xFFFF) && key.longPressAction == .cctDown(0xC002),
                  "cleared short press retains key direction and long press")
        } else { check(false, "kinetic key configuration missing") }
        handles[0].isSuccessful = false
        check(!task.apply(results: handles, expected: handles) && pending(scene).count == 1, "failed ACK preserves receipt")
        handles[0].isSuccessful = true; FixtureStore.failSceneSave = true
        check(!task.apply(results: handles, expected: handles) && pending(scene).count == 1, "receipt persistence failure restores in-memory intent")
        let persisted = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)[0]
        check(persisted.configuration?.deletionReferences?.pending == [reference], "restart after failed receipt save keeps dependency")
        FixtureStore.failSceneSave = false
        check(task.apply(results: handles, expected: handles) && pending(scene).isEmpty, "retry settles the same operation")
        check(!task.apply(results: handles, expected: handles), "duplicate late receipt cannot settle a second time")
    }

    static func legacyAndOrphanSchedulerRecovery() throws {
        let (scene, node, _) = fixture()
        let legacy = Schedule(6, scene: 1)
        legacy.nodeSlots = nil; legacy.testExistAddresses = [1]
        manager.schedules = [legacy]
        node.allSchedulerModelEntrys[node.schedulerSetupModels[1]] = [9: .init(action: .sceneRecall, sceneNumber: 1)]
        let preparation = try SceneDeletionCascade.prepare(scene: scene, snapshot: .init(scope: scope))
        check(preparation.schedules[0].nodeSlots?.first?.slot == 6
            && preparation.schedules[0].nodeSlots?.first?.state == .pendingRemoval,
              "legacy logical slot is captured before clearing targets")
        let reference = preparation.references.pending[0]
        check(reference.slots == [6], "orphan observation captures target without inventing ownership")
        preparation.install(); try markDeleting(scene, references: preparation.references)
        let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
        let handles = task.messageHandles
        check(handles.count == 1 && (handles[0].message as? SchedulerActionSet)?.index == 9,
              "orphan scene entry is cleaned even with no business owner at that slot")
        check(task.apply(results: handles, expected: handles) && pending(scene).isEmpty, "orphan cleanup settles after matched result")

        try markDeleting(scene, references: .init(pending: [reference]))
        let empty = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
        check(empty.messageHandles.isEmpty && empty.allowsEmpty && empty.apply(results: [], expected: []),
              "confirmed empty scheduler models allow cleanup without fabricated radio work")
    }

    static func unresolvedAndStaleOperations() throws {
        let (scene, _, proxy) = fixture()
        let item = DeviceSwitchData(id: "switch", name: "Switch"); item.proxyNodeAddress = 2
        manager.switchs = [item]
        let unknown = SceneReferenceRemoval(kind: .kinetic, identity: nil, address: 2, objectID: item.id, name: item.name, keys: [4])
        try markDeleting(scene, references: .init(pending: [unknown]))
        let section = SyncDevicesSectionModel()
        check(SceneDeletionCascade.appendTasks(scene: scene, to: section).isEmpty && section.devices.isEmpty
            && !SceneDeletionCascade.canFinish(info: scene.info), "unknown identity is retained without executable tasks")
        let reference = SceneReferenceRemoval(kind: .kinetic, identity: proxy.timedSchedulerIdentity, address: 2, objectID: item.id, name: item.name, keys: [4])
        for mutation in 0..<6 {
            try markDeleting(scene, references: .init(pending: [reference]))
            let task = SceneDeletionTask(scene: scene, reference: reference, node: proxy, phase: .apply)
            let handles = task.messageHandles
            check(!handles.isEmpty, "stale-operation fixture starts with executable work")
            let identity = proxy.timedSchedulerIdentity
            switch mutation {
            case 0: scene.info.configuration?.revision = UUID()
            case 1: proxy.timedSchedulerIdentity = .init(nodeUUID: identity!.nodeUUID, unicastAddress: "0002", deviceKeyFingerprint: String(repeating: "B", count: 64))
            case 2: item.sceneANumber = 2
            case 3: manager.currentNetworkKey.networkId = 2
            case 4: item.enOceanMacAddress = "changed-mac"
            default: manager.currentApplicationKey.index = 2
            }
            check(!task.apply(results: handles, expected: handles) && pending(scene).count == 1,
                  "stale revision, identity, business configuration or network must reject late receipt")
            proxy.timedSchedulerIdentity = identity; item.sceneANumber = nil; manager.currentNetworkKey.networkId = 1
            item.enOceanMacAddress = "fixture-mac"; manager.currentApplicationKey.index = 0
        }
    }

    static func retriesRebuildSchedulerWork() throws {
        let (scene, node, _) = fixture()
        let reference = SceneReferenceRemoval(kind: .scheduler, identity: node.timedSchedulerIdentity, address: 1, name: "Scheduler")
        try markDeleting(scene, references: .init(pending: [reference]))
        let read = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .read)
        let originalReads = read.messageHandles
        originalReads[0].isSuccessful = false
        check(!read.apply(results: originalReads, expected: originalReads), "failed scheduler read retains dependency")
        read.resetForRetry()
        let retryReads = read.messageHandles
        check(retryReads.count == 32 && zip(originalReads, retryReads).allSatisfy { $0 !== $1 },
              "retry regenerates all scheduler reads instead of reusing failed handle state")
        check(read.apply(results: retryReads, expected: retryReads) && pending(scene) == [reference],
              "successful repeated read still waits for cleanup phase")
        let apply = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
        node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = nil
        check(apply.messageHandles.isEmpty && !apply.allowsEmpty, "incomplete read blocks cleanup preparation")
        node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = [8: .init(action: .sceneRecall, sceneNumber: 1)]
        apply.resetForRetry()
        let retryWrites = apply.messageHandles
        check(retryWrites.count == 1 && (retryWrites[0].message as? SchedulerActionSet)?.index == 8,
              "retry rebuilds cleanup plan from freshly read scheduler state")
        check(apply.apply(results: retryWrites, expected: retryWrites), "retried scheduler plan settles only after new receipts")
    }

    static func duplicateObservedKeysAreCanonical() throws {
        let (scene, _, proxy) = fixture()
        let item = DeviceSwitchData(id: "same-key", name: "Switch")
        item.proxyNodeAddress = 2; item.sceneANumber = 1
        proxy.enOceanMacAddress = item.enOceanMacAddress
        proxy.enOceanProxySwitchKeys = [item.switchKeys[0], item.switchKeys[0]]
        manager.switchs = [item]
        let preparation = try SceneDeletionCascade.prepare(scene: scene, snapshot: .init(scope: scope))
        let reference = preparation.references.pending.first { $0.kind == .kinetic }!
        check(reference.keys == [4], "same desired and observed key becomes one durable cleanup key")
        let configuration = SceneConfiguration(schemaVersion: 2, kind: .groups, name: "Scene", isDeleting: true,
            deletionReferences: preparation.references)
        check((try? configuration.normalized()) != nil, "deduplicated observed cleanup passes persistence validation")
    }

    static func changedSchedulerSlotRejectsLateReceipt() throws {
        let (scene, node, _) = fixture()
        let current = schedule(12, scene: 2, node: node, slot: 5)
        manager.schedules = [current]
        node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = [5: .init(action: .sceneRecall, sceneNumber: 1)]
        let reference = SceneReferenceRemoval(kind: .scheduler, identity: node.timedSchedulerIdentity, address: 1, name: "Scheduler")
        try markDeleting(scene, references: .init(pending: [reference]))
        let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
        let handles = task.messageHandles
        check(handles.count == 1, "slot protection fixture plans restoration of current owner")
        let old = current.nodeSlots![0]
        current.nodeSlots = [.init(identity: old.identity, slot: 6, state: old.state, generation: old.generation)]
        check(!task.apply(results: handles, expected: handles) && pending(scene) == [reference],
              "changing only current owner slot rejects previously captured cleanup receipt")
    }

    static func powerWithoutGroupCleansOnlyCapturedKeys() throws {
        let (scene, _, node) = fixture()
        let power = PJEightKeySwitchData(id: "orphan-power", name: "Battery switch")
        power.proxyNodeAddress = 2; power.linkGroupAddress = nil; power.sceneANumber = 1; power.sceneBNumber = 2
        manager.switchs = [power]
        let preparation = try SceneDeletionCascade.prepare(scene: scene, snapshot: .init(scope: scope))
        try preparation.persist(); preparation.install(); try markDeleting(scene, references: preparation.references)
        let reference = pending(scene).first { $0.kind == .powerSwitch }!
        let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
        let handles = task.messageHandles
        check(handles.count == 1 && !task.allowsEmpty, "missing Group still generates captured power key cleanup")
        if handles.count == 1, let message = handles[0].message as? SunricherVendorSet,
           case .batteryPowerSwitchKeyConfig(let value) = message.function {
            check(value.button == 0 && value.type == .disabled && value.address == .unassigned,
                  "missing Group disables only the captured Scene key at unassigned address")
        } else { check(false, "missing Group power cleanup message missing") }
        let live = manager.switchs[0] as! PJEightKeySwitchData
        check(task.apply(results: handles, expected: handles) && pending(scene).isEmpty, "partial power key cleanup can settle Scene dependency")
        check(live.appliedConfigHash == "old" && FixtureStore.powerHashes[live.id] == "old" && live.needsBatteryPowerSwitchSync,
              "partial power cleanup does not acknowledge unrelated complete desired configuration")
    }

    static func changedPowerAndEmergencyConfigurationRejectLateReceipts() throws {
        for mutation in 0..<2 {
            let (scene, _, node) = fixture()
            let power = PJEightKeySwitchData(id: "power", name: "Battery switch")
            power.proxyNodeAddress = 2
            manager.switchs = [power]
            let reference = SceneReferenceRemoval(kind: .powerSwitch, identity: node.timedSchedulerIdentity,
                address: 2, objectID: power.id, name: power.name, keys: [0])
            try markDeleting(scene, references: .init(pending: [reference]))
            let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
            let handles = task.messageHandles
            if mutation == 0 { power.desiredConfigVersion += 1 } else { power.desiredConfigHash = "replacement" }
            check(!task.apply(results: handles, expected: handles) && pending(scene) == [reference],
                  "new power desired version or hash rejects old cleanup receipts")
        }
        for mutation in 0..<3 {
            let (scene, _, node) = fixture()
            let emergency = DeviceEmerFireData("efc")
            emergency.bindNodeAddress = 2; emergency.configuration.powerLossSettings.triggerActionPreset = .invalid
            FixtureStore.emergency[emergency.id] = emergency
            let reference = SceneReferenceRemoval(kind: .emergency, identity: node.timedSchedulerIdentity,
                address: 2, objectID: emergency.id, name: emergency.name, keys: [0])
            try markDeleting(scene, references: .init(pending: [reference]))
            let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
            let handles = task.messageHandles
            switch mutation {
            case 0: emergency.bindNodeAddress = 3
            case 1: emergency.publishGroupAddress = 0xC020
            default: manager.currentApplicationKey.index = 2
            }
            check(!task.apply(results: handles, expected: handles) && pending(scene) == [reference],
                  "changed EFC binding, publication or application key rejects old cleanup receipts")
        }
    }

    static func powerAndEmergencyCleanup() throws {
        let (scene, _, node) = fixture()
        let power = PJEightKeySwitchData(id: "power", name: "Battery switch")
        power.proxyNodeAddress = 2; power.sceneANumber = 1; power.sceneBNumber = 2
        manager.switchs = [power]
        let emergency = DeviceEmerFireData("efc")
        emergency.bindNodeAddress = 2
        emergency.configuration.powerLossSettings.triggerActionPreset = .sceneRecall(1)
        emergency.configuration.fireAlarmSettings.triggerActionPreset = .sceneRecall(2)
        FixtureStore.emergency[emergency.id] = emergency
        let preparation = try SceneDeletionCascade.prepare(scene: scene, snapshot: .init(scope: scope))
        check(preparation.emergency[0].configuration.powerLossSettings.triggerActionPreset == .invalid
            && preparation.emergency[0].configuration.fireAlarmSettings.triggerActionPreset == .sceneRecall(2),
              "EFC clears exact recall to invalid without altering other trigger")
        try preparation.persist(); preparation.install()
        try markDeleting(scene, references: preparation.references)
        let reference = pending(scene).first { $0.kind == .powerSwitch }!
        let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
        check(task.activationSwitch != nil, "battery cleanup retains activation requirement")
        let handles = task.messageHandles
        check(handles.count == 4 && handles.allSatisfy { !$0.continuous }, "power switch rewrites key configuration through existing transport shape")
        let live = manager.switchs[0] as! PJEightKeySwitchData
        FixtureStore.failSceneSave = true
        check(!task.apply(results: handles, expected: handles) && live.appliedConfigHash == "old"
            && FixtureStore.powerHashes[live.id] == "old", "power hash and cleanup receipt rollback together")
        FixtureStore.failSceneSave = false
        FixtureStore.failPowerSave = true
        check(!task.apply(results: handles, expected: handles) && pending(scene).contains(reference),
              "failed conditional power metadata write cannot consume cleanup receipt")
        FixtureStore.failPowerSave = false
        check(task.apply(results: handles, expected: handles) && live.appliedConfigHash == live.desiredConfigHash,
              "successful key cleanup persists applied hash")
        let efcReference = pending(scene).first { $0.kind == .emergency }!
        let efcTask = SceneDeletionTask(scene: scene, reference: efcReference, node: node, phase: .apply)
        let efcHandles = efcTask.messageHandles
        if efcHandles.count == 1, let message = efcHandles[0].message as? SunricherVendorSet,
           case .emergencyActionConfig(let configuration) = message.function {
            check(configuration.state == 0 && configuration.action == .invalid, "EFC sends only matching action disable, not brightness fallback")
        } else { check(false, "EFC action task missing") }
        check(efcTask.apply(results: efcHandles, expected: efcHandles) && pending(scene).isEmpty,
              "confirmed EFC action cleanup persists its dependency removal")
    }

    static func persistedEditRejectsOldReceiptAndUsesLatestAction() throws {
        let (scene, _, node) = fixture()
        let item = DeviceSwitchData(id: "edited-copy", name: "Switch")
        item.proxyNodeAddress = node.primaryUnicastAddress
        manager.switchs = [item]
        let reference = SceneReferenceRemoval(kind: .kinetic, identity: node.timedSchedulerIdentity,
            address: node.primaryUnicastAddress, objectID: item.id, name: item.name, keys: [4])
        try markDeleting(scene, references: .init(pending: [reference]))
        let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
        let handles = task.messageHandles
        let editedCopy = item.copy(); editedCopy.sceneANumber = 2
        _ = editedCopy.save(meshUUID: scope.meshUUID, networkId: scope.networkID)
        check(!task.apply(results: handles, expected: handles) && pending(scene) == [reference],
              "persisted edit on a separate object rejects old cleanup receipt")
        task.resetForRetry()
        let updated = task.messageHandles
        if let message = updated.first?.message as? SunricherVendorSet,
           case .enOceanSwitchKeySet(let key, _) = message.function,
           case .sceneRecall(let number, _) = key.shortPressAction {
            check(number == 2, "retry preserves latest persisted action even if manager still holds another copy")
        } else { check(false, "latest persisted key message missing") }
        check(task.apply(results: updated, expected: updated), "latest persisted configuration can complete cleanup")
    }

    static func registeredResidualRequiresSchedulerRead() throws {
        let (scene, node, _) = fixture()
        node.allSchedulerModelEntrys = [:]
        let preparation = try SceneDeletionCascade.prepare(scene: scene, snapshot: .init(scope: scope), additionalNodes: [node])
        let reference = preparation.references.pending.first
        check(reference?.kind == .scheduler && reference?.identity == node.timedSchedulerIdentity,
              "registered residual outside members retains Scheduler dependency even with unknown cache")
        try markDeleting(scene, references: preparation.references)
        let task = SceneDeletionTask(scene: scene, reference: reference!, node: node, phase: .read)
        check(task.messageHandles.count == 32, "residual device reads every slot before physical Scene removal")
    }

    static func kineticWithoutGroupPreservesUnknownCleanup() throws {
        let (scene, _, node) = fixture()
        let item = DeviceSwitchData(id: "offline-kinetic", name: "Offline switch")
        item.proxyNodeAddress = node.primaryUnicastAddress
        item.sceneANumber = 1; item.linkGroupAddress = nil
        manager.switchs = [item]
        let preparation = try SceneDeletionCascade.prepare(scene: scene, snapshot: .init(scope: scope))
        check(preparation.references.pending.first?.keys == [4], "saved panel mapping retains the Scene key after group removal")
        try preparation.persist(); preparation.install(); try markDeleting(scene, references: preparation.references)
        let reference = pending(scene)[0]
        let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
        check(task.messageHandles.isEmpty && !task.allowsEmpty && !task.apply(results: [], expected: []),
              "missing observed long-press configuration cannot be falsely acknowledged as empty cleanup")
        check(pending(scene) == [reference], "unknown kinetic configuration retains durable cleanup")
    }

    static func finalizationAndAdmission() throws {
        let (scene, lamp, _) = fixture()
        let removed = schedule(10, scene: 1, node: lamp, slot: 1)
        removed.action = .noAction; removed.sceneNumber = nil; removed.nodeAddresses = []
        let kept = schedule(12, scene: 2, node: lamp, slot: 2); kept.needDeleteSceneNumbers = [1]
        FixtureStore.schedules = [10: removed, 12: kept]
        try markDeleting(scene, references: .init(scheduleIDs: [10]))
        check(!SceneDeletionCascade.permitsReferences([1], meshUUID: scope.meshUUID, networkID: scope.networkID)
            && SceneDeletionCascade.permitsReferences([2], meshUUID: scope.meshUUID, networkID: scope.networkID),
              "stale editor cannot recreate deleting Scene reference")
        manager.scenes = []
        check(SceneDeletionCascade.owns(scheduleID: 10, meshUUID: scope.meshUUID, networkID: scope.networkID)
            && !SceneDeletionCascade.owns(scheduleID: 12, meshUUID: scope.meshUUID, networkID: scope.networkID),
              "database tombstone reserves direct Timed ID after SDK Scene removal")
        try SceneDeletionCascade.finalizeReferences(info: scene.info, scope: scope)
        check(FixtureStore.schedules[10] == nil && FixtureStore.schedules[12]?.sceneNumber == 2
            && FixtureStore.schedules[12]?.needDeleteSceneNumbers.isEmpty == true,
              "finalization deletes direct Timed and only releases stale reference from changed Timed")
    }
}
