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

    static func normalizePersistAndReload(_ scene: Scene, references: SceneDeletionReferences) throws {
        try markDeleting(scene, references: references)
        scene.info.configuration = try scene.info.configuration?.normalized()
        try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        let persisted = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        scene.info.configuration = persisted.first { $0.sceneId == scene.number }!.configuration
    }

    // Simulate independent device responses, not just ACK flags or pre-existing cache.
    static func completeRead(_ read: SceneDeletionTask, node: Node) -> Bool {
        let deviceEntries = node.allSchedulerModelEntrys
        let registers = read.messageHandles
        for handle in registers {
            let mask = (deviceEntries[handle.model] ?? [:]).keys.reduce(UInt16(0)) { $0 | (UInt16(1) << $1) }
            read.receive(handle: handle, status: SchedulerStatus(schedules: mask))
        }
        guard read.apply(results: registers, expected: registers) else { return false }
        let details = read.followUpMessageHandles
        guard !details.isEmpty else { return true }
        for handle in details {
            let index = (handle.message as! SchedulerActionGet).index
            read.receive(handle: handle, status: SchedulerActionStatus(index: index,
                entry: deviceEntries[handle.model]?[Int(index)] ?? .init()))
        }
        return read.apply(results: details, expected: details)
    }

    static func selectiveSchedulerReadBoundaries() throws {
        for mode in ["one", "empty", "missingBitmap", "missingDetail", "wrongIndex", "becameEmpty", "stopDetails", "lateBitmap", "staleDetail"] {
            let (scene, node, _) = fixture()
            let reference = SceneReferenceRemoval(kind: .scheduler, identity: node.timedSchedulerIdentity, address: 1, name: "Read", slots: [0])
            try markDeleting(scene, references: .init(pending: [reference]))
            let old: [Int: SchedulerRegistryEntry] = [7: .init(action: .sceneRecall, sceneNumber: 9)]
            node.schedulerActions = old
            node.schedulerSetupModels.forEach { node.allSchedulerModelEntrys[$0] = old }
            let read = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .read)
            let registers = read.messageHandles
            check(registers.count == 2 && registers.allSatisfy { $0.message is SchedulerGet }, "two Models start with two bitmap reads")
            read.receive(handle: registers[0], status: SchedulerStatus(schedules: mode == "empty" ? 0 : 1))
            if mode != "missingBitmap" { read.receive(handle: registers[1], status: SchedulerStatus(schedules: 0)) }
            let accepted = read.apply(results: registers, expected: registers)
            if mode == "missingBitmap" {
                check(!accepted && node.observedTimedSlots == nil && pending(scene) == [reference], "ACK flags cannot replace a missing bitmap")
                continue
            }
            check(accepted && pending(scene) == [reference], "bitmap phase never consumes deletion dependency")
            let details = read.followUpMessageHandles
            if mode == "empty" {
                check(details.isEmpty && node.observedTimedSlots == [] && node.schedulerActions.isEmpty, "zero bitmaps authoritatively clear stale caches without detail reads")
            } else {
                check(details.count == 1 && details[0].model === node.schedulerSetupModels[0]
                    && (details[0].message as? SchedulerActionGet)?.index == 0, "only occupied slot on its owning Element is queried")
                if mode == "stopDetails" {
                    read.invalidateIncompleteSchedulerRead()
                    read.receive(handle: details[0], status: SchedulerActionStatus(index: 0, entry: .init(action: .sceneRecall, sceneNumber: 1)))
                    check(!read.apply(results: details, expected: details) && node.observedTimedSlots == nil && node.schedulerActions == old, "STOP rejects late detail and retains unknown capacity")
                    read.resetForRetry()
                    check(read.messageHandles.count == 2 && read.messageHandles.allSatisfy { $0.message is SchedulerGet }, "retry starts with fresh occupancy")
                    continue
                }
                if mode == "lateBitmap" { read.receive(handle: registers[0], status: SchedulerStatus(schedules: 0)) }
                if mode == "staleDetail" { scene.info.configuration?.revision = UUID() }
                if mode != "missingDetail" {
                    read.receive(handle: details[0], status: SchedulerActionStatus(index: mode == "wrongIndex" ? 1 : 0,
                        entry: mode == "becameEmpty" ? .init() : .init(action: .sceneRecall, sceneNumber: 1)))
                }
                let complete = read.apply(results: details, expected: details)
                if ["missingDetail", "wrongIndex", "staleDetail"].contains(mode) {
                    check(!complete && node.observedTimedSlots == nil && node.schedulerActions == old, "incomplete or stale detail cannot establish a trusted cache")
                    continue
                }
                check(complete && read.followUpMessageHandles.isEmpty, "valid details finish the same read task")
            }
            let apply = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
            let writes = apply.messageHandles
            let expectedWrites = ["empty", "becameEmpty"].contains(mode) ? 0 : 1
            check(writes.count == expectedWrites && apply.apply(results: writes, expected: writes), "cleanup writes only observed matching entry")
            if mode == "one" { check(registers.count + details.count + writes.count + 2 == 6, "single occupied slot requires six commands including two Scene Deletes") }
        }
    }

    static func main() throws {
        try selectiveSchedulerReadBoundaries()
        try preparationIsAtomicAndSelective()
        try productionFingerprintSurvivesNormalizedCascade()
        try productionFingerprintReadFailureInvalidatesCache()
        try productionFingerprintRejectsReprovisionedIdentity()
        #if SCENE_CASCADE_COVERAGE_RECOVERY
        try missingSchedulerCoverageRecoversWithoutReplacingOwnership()
        try coverageRecoveryPersistsBeforePublishing()
        #endif
        try schedulerPlansPreserveCurrentOwner()
        try legacyAndOrphanSchedulerRecovery()
        try retriesRebuildSchedulerWork()
        try incompleteSchedulerReadsStayUnknown()
        try wholeSwitchDeletionSettlesReferencesAtomically()
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

    static func productionFingerprintSurvivesNormalizedCascade() throws {
        let (scene, lamp, _) = fixture()
        let powerNode = Node(3), emergencyNode = Node(4)
        manager.realNodes += [powerNode, emergencyNode]
        for node in manager.realNodes { try node.useProductionFingerprint() }
        let rawIdentity = lamp.timedSchedulerIdentity!
        check(rawIdentity.deviceKeyFingerprint == rawIdentity.deviceKeyFingerprint.lowercased()
            && rawIdentity.deviceKeyFingerprint != rawIdentity.deviceKeyFingerprint.uppercased(),
              "production SHA256 key fingerprint supplies the real lowercase identity boundary")
        check(lamp.sceneConfigurationIdentity == (try? SceneConfiguration.identity(rawIdentity))
            && lamp.sceneConfigurationIdentity != rawIdentity,
              "production Node Scene identity canonicalizes without changing raw Timed identity")
        let timed = schedule(10, scene: 1, node: lamp, slot: 1)
        manager.schedules = [timed]
        lamp.allSchedulerModelEntrys[lamp.schedulerSetupModels[0]] = [1: .init(action: .sceneRecall, sceneNumber: 1)]
        let kinetic = DeviceSwitchData(id: "lower-kinetic", name: "Kinetic")
        kinetic.proxyNodeAddress = 2; kinetic.sceneANumber = 1
        let power = PJEightKeySwitchData(id: "lower-power", name: "Power")
        power.proxyNodeAddress = 3; power.sceneANumber = 1
        manager.switchs = [kinetic, power]
        let emergency = DeviceEmerFireData("lower-efc")
        emergency.bindNodeAddress = 4; emergency.configuration.powerLossSettings.triggerActionPreset = .sceneRecall(1)
        FixtureStore.emergency[emergency.id] = emergency
        let preparation = try SceneDeletionCascade.prepare(scene: scene, snapshot: .init(scope: scope, targets: [.init(node: lamp)]))
        check(preparation.schedules.first?.nodeSlots?.first?.identity == rawIdentity
            && timed.nodeSlots?.first?.identity == rawIdentity,
              "cascade preparation preserves raw Timed slot identity on source and deletion copy")
        try preparation.persist(); preparation.install()
        try normalizePersistAndReload(scene, references: preparation.references)
        let persistedReferences = pending(scene)
        check(persistedReferences.count == 4 && persistedReferences.allSatisfy { reference in
            manager.realNodes.first { $0.primaryUnicastAddress == reference.address }?.sceneConfigurationIdentity == reference.identity
        }, "all four persisted cleanup kinds carry the canonical Scene identity after reload")
        let section = SyncDevicesSectionModel()
        let steps = SceneDeletionCascade.appendTasks(scene: scene, to: section)
        check(section.devices.count == 4 && steps.count == 5,
              "normalized scheduler, kinetic, power and EFC references all produce executable tasks")
        for reference in persistedReferences {
            let node = manager.realNodes.first { $0.primaryUnicastAddress == reference.address }!
            if reference.kind == .scheduler {
                let read = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .read)
                let handles = read.messageHandles
                check(handles.count == 2 && completeRead(read, node: node),
                      "canonical persisted identity accepts full Scheduler read receipts")
            }
            let task = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .apply)
            let handles = task.messageHandles
            let expectedCount = reference.kind == .powerSwitch ? 4 : 1
            check(handles.count == expectedCount && task.apply(results: handles, expected: handles),
                  "canonical persisted \(reference.kind) reference generates work and accepts cleanup receipts")
        }
        check(pending(scene).isEmpty, "all normalized cleanup receipts settle after reload")
        check(FixtureStore.schedules[10]?.nodeSlots?.first?.identity == rawIdentity
            && manager.schedules[0].nodeSlots?.first?.identity == rawIdentity
            && lamp.timedSchedulerIdentity == rawIdentity,
              "Scene task normalization never rewrites persisted or live Timed slot ownership")
    }

    static func productionFingerprintReadFailureInvalidatesCache() throws {
        for termination in ["failedAck", "partial", "cancel", "retry"] {
            let (scene, node, _) = fixture()
            try node.useProductionFingerprint()
            let reference = SceneReferenceRemoval(kind: .scheduler, identity: node.timedSchedulerIdentity,
                address: 1, name: "Lowercase read")
            try normalizePersistAndReload(scene, references: .init(pending: [reference]))
            let persisted = pending(scene)[0]
            let originalActions: [Int: SchedulerRegistryEntry] = [7: .init(action: .sceneRecall, sceneNumber: 9)]
            node.allSchedulerModelEntrys = [:]; node.schedulerActions = originalActions
            let read = SceneDeletionTask(scene: scene, reference: persisted, node: node, phase: .read)
            let handles = read.messageHandles
            check(handles.count == 2, "normalized identity starts authoritative Scheduler read before \(termination)")
            node.schedulerSetupModels.forEach { node.allSchedulerModelEntrys[$0] = [:] }
            node.schedulerActions = [:]; node.savePropertys()
            switch termination {
            case "cancel": read.invalidateIncompleteSchedulerRead()
            case "retry": read.resetForRetry()
            default:
                if termination == "failedAck" { handles.first?.isSuccessful = false }
                let results = termination == "partial" ? Array(handles.dropFirst()) : handles
                check(!read.apply(results: results, expected: handles), "incomplete normalized read cannot consume dependency")
            }
            check(node.observedTimedSlots == nil && node.savedSchedulerEntries.isEmpty,
                  "canonical identity still invalidates partial read cache after \(termination)")
            check(node.schedulerActions == originalActions && node.savedSchedulerActions == originalActions
                && pending(scene) == [persisted], "failed normalized read preserves prior legacy state and durable dependency")
        }
    }

    static func productionFingerprintRejectsReprovisionedIdentity() throws {
        for mutation in ["uuid", "key"] {
            let (scene, _, node) = fixture()
            try node.useProductionFingerprint()
            let oldIdentity = node.timedSchedulerIdentity!
            let item = DeviceSwitchData(id: "lower-identity", name: "Switch")
            item.proxyNodeAddress = 2
            manager.switchs = [item]
            let reference = SceneReferenceRemoval(kind: .kinetic, identity: oldIdentity,
                address: 2, objectID: item.id, name: item.name, keys: [4])
            try normalizePersistAndReload(scene, references: .init(pending: [reference]))
            let persisted = pending(scene)[0]
            let task = SceneDeletionTask(scene: scene, reference: persisted, node: node, phase: .apply)
            let handles = task.messageHandles
            check(handles.count == 1, "normalized old provisioning identity starts valid work before \(mutation) change")
            if mutation == "uuid" { try node.useProductionFingerprint(uuid: UUID()) }
            else { try node.useProductionFingerprint(key: "FFEEDDCCBBAA99887766554433221100") }
            check(node.primaryUnicastAddress == persisted.address && node.sceneConfigurationIdentity != persisted.identity
                && !task.isCurrent && task.messageHandles.isEmpty && !task.apply(results: handles, expected: handles),
                  "same address with different \(mutation) still rejects old messages and receipts")
            check(SceneDeletionCascade.appendTasks(scene: scene, to: SyncDevicesSectionModel()).isEmpty
                && pending(scene) == [persisted], "reprovisioned \(mutation) cannot inherit canonical cleanup dependency")
        }
    }

    #if SCENE_CASCADE_COVERAGE_RECOVERY
    static func missingSchedulerCoverageRecoversWithoutReplacingOwnership() throws {
        let (_, node, _) = fixture()
        try node.useProductionFingerprint()
        let original = SceneConfiguration(schemaVersion: 2, kind: .groups, name: "Deleting",
            pendingOperations: [.init(identity: node.timedSchedulerIdentity!, action: .remove)],
            isDeleting: true, deletionReferences: .init(scheduleIDs: [10]))
        let recovered = try SceneDeletionCascade.restoringSchedulerCoverage(original, nodes: [node])
        let reference = recovered.deletionReferences?.pending.first
        check(recovered.deletionReferences?.pending.count == 1 && reference?.kind == .scheduler
            && reference?.identity == node.sceneConfigurationIdentity && reference?.address == node.primaryUnicastAddress,
              "missing Scheduler coverage recovers one canonical reference for physical pending removal")
        check(recovered.revision == original.revision && recovered.pendingOperations[0].generation == original.pendingOperations[0].generation
            && recovered.deletionReferences?.scheduleIDs == [10], "coverage recovery preserves Scene revision, generations and owned Timed IDs")
        let repeated = try SceneDeletionCascade.restoringSchedulerCoverage(recovered, nodes: [node])
        check(repeated == recovered && repeated.deletionReferences?.pending.first?.id == reference?.id,
              "recovery is idempotent and preserves existing cleanup receipt ID")
        var completed = recovered
        completed.deletionReferences?.pending = []; completed.pendingOperations = []
        let afterCompletion = try SceneDeletionCascade.restoringSchedulerCoverage(completed, nodes: [node])
        check(afterCompletion == completed,
              "confirmed physical Scene removal never recreates Scheduler cleanup")
        try node.useProductionFingerprint(key: "FFEEDDCCBBAA99887766554433221100")
        let unrelated = try SceneDeletionCascade.restoringSchedulerCoverage(original, nodes: [node])
        check(unrelated.deletionReferences?.pending.isEmpty == true,
              "same-address replacement key does not inherit missing cleanup coverage")
    }

    static func coverageRecoveryPersistsBeforePublishing() throws {
        let (scene, node, _) = fixture()
        try node.useProductionFingerprint()
        try normalizePersistAndReload(scene, references: .init())
        scene.info.configuration?.pendingOperations = [.init(identity: node.sceneConfigurationIdentity!, action: .remove)]
        try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        let original = scene.info.configuration
        let persistedInfo = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)[0]
        FixtureStore.failSceneSave = true
        do {
            try SceneConfigurationStore.restoreDeletionSchedulerCoverage(info: persistedInfo, scope: scope)
            check(false, "failed coverage persistence must throw")
        } catch {
            check(error as? SceneConfigurationStore.Failure == .persistence, "coverage persistence failure is reported")
        }
        let failedDisk = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)[0]
        check(persistedInfo.configuration == original && scene.info.configuration == original && failedDisk.configuration == original,
              "coverage save failure rolls back transient row and leaves live and persisted intent unchanged")
        FixtureStore.failSceneSave = false; MeshProxyMessageCommand.shared.isBusy = true
        do {
            try SceneConfigurationStore.restoreDeletionSchedulerCoverage(info: persistedInfo, scope: scope)
            check(false, "active transport must defer coverage migration")
        } catch {
            check(error as? SceneConfigurationStore.Failure == .unavailable && persistedInfo.configuration == original,
                  "active transport rejection preserves deletion intent")
        }
        MeshProxyMessageCommand.shared.isBusy = false
        try SceneConfigurationStore.restoreDeletionSchedulerCoverage(info: persistedInfo, scope: scope)
        let saved = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)[0]
        check(saved.configuration?.deletionReferences?.pending.count == 1
            && saved.configuration == persistedInfo.configuration && scene.info.configuration == saved.configuration,
              "successful coverage persistence publishes identical committed dependencies to live Scene")
        let referenceID = saved.configuration?.deletionReferences?.pending.first?.id
        try SceneConfigurationStore.restoreDeletionSchedulerCoverage(info: persistedInfo, scope: scope)
        check(persistedInfo.configuration?.deletionReferences?.pending.first?.id == referenceID,
              "repeated Store recovery keeps the committed cleanup identity")
    }
    #endif

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

    static func incompleteSchedulerReadsStayUnknown() throws {
        for termination in ["failedAck", "partial", "stale", "cancel", "retry"] {
            let (scene, node, _) = fixture()
            node.allSchedulerModelEntrys = [:]
            let oldActions: [Int: SchedulerRegistryEntry] = [0: .init(action: .sceneRecall, sceneNumber: 9)]
            node.schedulerActions = oldActions
            let reference = SceneReferenceRemoval(kind: .scheduler, identity: node.timedSchedulerIdentity, address: 1, name: "Read")
            try markDeleting(scene, references: .init(pending: [reference]))
            let read = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .read)
            let handles = read.messageHandles
            // SDK replies for empty slots create non-nil dictionaries before the missing slot times out.
            node.schedulerSetupModels.forEach { node.allSchedulerModelEntrys[$0] = [:] }
            node.schedulerActions = [:]; node.savePropertys()
            switch termination {
            case "cancel": read.invalidateIncompleteSchedulerRead()
            case "retry": read.resetForRetry()
            default:
                if termination == "failedAck" { handles[0].isSuccessful = false }
                if termination == "stale" { scene.info.configuration?.revision = UUID() }
                let results = termination == "partial" ? Array(handles.dropFirst()) : handles
                check(!read.apply(results: results, expected: handles), "incomplete or stale read rejects success")
            }
            check(node.observedTimedSlots == nil && node.savedSchedulerEntries.isEmpty,
                  "\(termination) invalidates partial cache in memory and persistence")
            check(node.schedulerActions == oldActions && node.savedSchedulerActions == oldActions && node.scheduleIds == [0],
                  "\(termination) preserves pre-read legacy observations")
            do {
                _ = try TimedSchedulerSlotPolicy.plan(identity: node.timedSchedulerIdentity!,
                    intents: [.init(scheduleID: 20, targetsNode: true, legacy: false, binding: nil)],
                    observedSlots: node.observedTimedSlots)
                check(false, "unknown slot 0 must not be allocated after \(termination)")
            } catch { check(error as? TimedSchedulerSlotPolicy.Failure == .unknownCapacity, "incomplete read requires capacity recovery") }
            check(pending(scene) == [reference], "incomplete read retains Scene dependency")
        }
        let (scene, node, _) = fixture()
        let reference = SceneReferenceRemoval(kind: .scheduler, identity: node.timedSchedulerIdentity, address: 1, name: "Read")
        try markDeleting(scene, references: .init(pending: [reference]))
        let read = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: .read)
        _ = read.messageHandles
        node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = [0: .init(action: .sceneRecall, sceneNumber: 9)]
        check(completeRead(read, node: node), "full read accepts complete observation")
        read.invalidateIncompleteSchedulerRead(); read.resetForRetry()
        check(node.observedTimedSlots == [0], "stop or reset after completed read preserves trusted cache")
        let plan = try TimedSchedulerSlotPolicy.plan(identity: node.timedSchedulerIdentity!,
            intents: [.init(scheduleID: 20, targetsNode: true, legacy: false, binding: nil)], observedSlots: node.observedTimedSlots)
        check(plan[20]?.slot == 1, "complete read preserves occupied slot and allows new Timed")
    }

    static func wholeSwitchDeletionSettlesReferencesAtomically() throws {
        let (scene, _, proxy) = fixture()
        let item = DeviceSwitchData(id: "deleted", name: "Switch")
        item.proxyNodeAddress = 2
        manager.switchs = [item]
        let reference = SceneReferenceRemoval(kind: .kinetic, identity: proxy.timedSchedulerIdentity,
            address: 2, objectID: item.id, name: item.name, keys: [4])
        let other = SceneReferenceRemoval(kind: .kinetic, identity: proxy.timedSchedulerIdentity,
            address: 2, objectID: "other", name: "Other", keys: [3])
        let scheduler = SceneReferenceRemoval(kind: .scheduler, identity: proxy.timedSchedulerIdentity,
            address: 2, objectID: item.id, name: "Scheduler")
        try markDeleting(scene, references: .init(pending: [reference, other, scheduler]))
        let secondScene = Scene(2)
        manager.scenes.append(secondScene)
        try markDeleting(secondScene, references: .init(pending: [reference]))
        let stale = SceneDeletionTask(scene: secondScene, reference: reference, node: proxy, phase: .apply)
        let handles = stale.messageHandles
        for failure in ["scene", "switch"] {
            FixtureStore.failSceneSave = failure == "scene"
            FixtureStore.failSwitchSave = failure == "switch"
            check(!SceneDeletionCascade.deleteSwitchRecords(item, scope: scope), "failed \(failure) save rejects whole switch deletion")
            check(FixtureStore.switches[item.id] != nil && pending(scene).count == 3 && pending(secondScene) == [reference],
                  "failed transaction preserves live objects and all dependencies")
            let persisted = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
            check(persisted.allSatisfy { $0.configuration?.deletionReferences?.pending.contains(reference) == true },
                  "failed deletion remains recoverable after restart")
        }
        FixtureStore.failSceneSave = false; FixtureStore.failSwitchSave = false
        check(SceneDeletionCascade.deleteSwitchRecords(item, scope: scope), "confirmed whole switch deletion commits")
        manager.switchs.removeAll { $0.id == item.id }
        check(FixtureStore.switches[item.id] == nil && pending(scene) == [other, scheduler] && pending(secondScene).isEmpty,
              "settle this switch across Scenes while preserving unrelated dependencies")
        check(SceneDeletionCascade.canFinish(info: secondScene.info), "Scene can finish after whole switch is removed")
        check(!stale.apply(results: handles, expected: handles), "old cleanup callback cannot reapply after deletion")
        let section = SyncDevicesSectionModel()
        check(SceneDeletionCascade.appendTasks(scene: secondScene, to: section).isEmpty, "new global plan contains no orphan switch cleanup")
        let reloaded = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID).first { $0.sceneId == 2 }!
        check(reloaded.configuration?.deletionReferences?.pending.isEmpty == true, "restart preserves settled receipt")

        // Missing data without a confirmed whole-delete transaction must not fabricate an ACK.
        try markDeleting(secondScene, references: .init(pending: [reference]))
        let missing = SceneDeletionTask(scene: secondScene, reference: reference, node: proxy, phase: .apply)
        check(missing.messageHandles.isEmpty && !missing.allowsEmpty && !missing.apply(results: [], expected: []),
              "unconfirmed missing switch remains pending")
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
        check(reads.count == 2 && reads.allSatisfy { $0.message is SchedulerGet }, "read occupancy on all scheduler models")
        check(completeRead(read, node: lamp) && pending(scene).count == 1, "read does not settle cleanup receipt")
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
        check(retryReads.count == 2 && zip(originalReads, retryReads).allSatisfy { $0 !== $1 },
              "retry regenerates all scheduler reads instead of reusing failed handle state")
        node.schedulerSetupModels.forEach { node.allSchedulerModelEntrys[$0] = [:] }
        check(completeRead(read, node: node) && pending(scene) == [reference],
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
        check(task.messageHandles.count == 2, "residual device reads every slot before physical Scene removal")
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
