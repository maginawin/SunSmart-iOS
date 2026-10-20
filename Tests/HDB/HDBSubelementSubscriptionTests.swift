import Foundation

@main enum HDBSubelementSubscriptionTests {
    static func fixture(sensor: Bool = true) throws -> (SpaceData, Node, HDBDeviceSyncContext) {
        precondition(SyncExecutionEnvironment.batches.isEmpty)
        SyncExecutionEnvironment.subscriptionObserver = nil; SyncExecutionEnvironment.stopObserver = nil
        Node.failSave = false
        SiteData.hdbEnabled = true; SpaceData.failSave = false; SpaceData.siblings = []
        SpaceConfigurationSafety.journal = .init(); Node.PreConfiguration.saved = nil
        MeshLibManager.manager.subElementGroupSubscriptionModelIDs = [0x1306, 0x130F]
        MeshAPI.allocation = Array(UInt16(0xC001)...0xC100)
        let space = SpaceData(), network = MeshNetwork(), node = Node()
        HDBSubelementFixture.configure(node, sensor: sensor)
        node.network = network; network.nodes = [node]
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        MeshNetworkManager.instance.currentNetworkKey.networkId = "network"
        space.hdb = .init(); SpaceData.persisted = space.copy()
        try seedPrepared(space: space, node: node, zonesSynced: false)
        precondition(node.isKeybindComplete)
        return (space, node, try HDBDeviceSyncContext.resolve(space: space, node: node)!)
    }

    static func acknowledge(_ task: HDBDeviceSyncTask, _ handles: [MeshMessageHandle], node: Node) {
        precondition(!handles.isEmpty, "next Zone stage must be executable")
        for handle in handles {
            handle.isSuccessful = true
            SyncExecutionEnvironment.applySubscription(handle)
            // FEFD is legitimately absent between Reset and broadcast restoration.
            task.receive(handle: handle, response: ConfigModelSubscriptionStatus(handle.message, success: true))
        }
    }

    static func main() throws {
        try testResetBarrier()
        try testInFlightCancellation()
        try testCrossElementReplayAtEveryRequest()
        try testCancellationAndLateAcknowledgements()
        try testScopedReadinessAndPartialSave()
        try testAffectedNonZoneBroadcastReceiver()
        try testSharedTargetsAndBindingGuards()
        try testOldFailureRecovery()
        try testDirectApplyFailureAndReopen()
        try testChangedBroadcastContract()
        for sensor in [true, false] {
            for zoneCount in [0, 1, 2, 8] {
                let (space, node, context) = try fixture(sensor: sensor)
                for id in 1...8 { _ = try HDBConfigurationStore.createZone(space: space, zoneId: id, name: "Zone \(id)") }
                try HDBConfigurationStore.update(space: space) {
                    $0.devices[0].lightingZones = (0..<zoneCount).map { .init(zoneId: $0 + 1) }
                }
                let config = try HDBConfigurationStore.load(space: space)
                let operations = try context.zoneOperations(in: config)
                precondition(operations.first?.stage == .reset)
                precondition(operations[0].subscriptions.count == 5)
                precondition(operations[0].subscriptions.allSatisfy { $0.command == .deleteAll && $0.address == 0 })
                if sensor {
                    precondition(operations[2].stage == .sensor && operations[2].subscriptions.allSatisfy { $0.command == .add })
                }
                for operation in operations {
                    let task = HDBDeviceSyncTask(context: context, operation: .zone(operation))
                    let handles = task.makeHandles()
                    acknowledge(task, handles, node: node)
                    precondition(task.persist(result: handles))
                }
                var expected = Set<UInt16>([0xFEFD])
                if let address = config.devices[0].sensorGroupId { expected.insert(address) }
                expected.formUnion(config.lightingZones.prefix(zoneCount).map(\.groupAddress))
                precondition(node.elements[2].models.allSatisfy { Set($0.subscriptions.map { $0.address.address }) == expected })
                precondition(node.elements[1].models[0].subscriptions.map { $0.address.address } == [0xFEFD])
                let sensorServers = node.elements.flatMap(\.models).filter { $0.modelIdentifier == 0x1100 && $0.companyIdentifier == nil }
                precondition(sensorServers.allSatisfy {
                    $0.subscriptions.map { $0.address.address } == [config.devices[0].sensorGroupId!]
                }, "Zone writes must preserve every Sensor Server's private group subscription")
                precondition(!HDBDeviceSyncService.needsSync(node: node))
            }
        }
        print("PASS: DeleteAll barrier; separate device/cache convergence after every request interruption; scoped SDK readiness; partial-save/cancel/late ACK; Sensor/no Sensor and 0/1/2/8 Zones")
    }

    static func testResetBarrier() throws {
        let (space, _, context) = try fixture()
        let operations = try context.zoneOperations(in: HDBConfigurationStore.load(space: space))
        precondition(operations.first?.stage == .reset, "all elements must be cleared before any Add")
        precondition(operations[0].subscriptions.count == 5)
        precondition(operations[0].subscriptions.allSatisfy { $0.command == .deleteAll })
        precondition(operations.dropFirst().flatMap(\.subscriptions).allSatisfy { $0.command == .add })
    }

    static func testInFlightCancellation() throws {
        let (space, node, _) = try fixture()
        let service = HDBLightingZoneService(site: SiteData(), space: space)
        try service.retry(nodeUuid: node.uuid)
        let batch = SyncExecutionEnvironment.batches.removeFirst(), handle = batch.handles[0]
        var stopped: (() -> Void)?
        SyncExecutionEnvironment.stopObserver = { stopped = $0 }
        service.cancel()
        // wait:true STOP still delivers the already in-flight request's ACK.
        handle.isSuccessful = true; SyncExecutionEnvironment.applySubscription(handle)
        batch.success?(handle, ConfigModelSubscriptionStatus(handle.message, success: true))
        precondition(node.elements[2].models.allSatisfy { $0.subscriptions.isEmpty }, "in-flight DeleteAll ACK during STOP must clear cross-element cache")
        stopped?()
        precondition(!service.isRunning && service.lastError == nil)
        precondition(node.elements[2].models.allSatisfy { node.savedSubscriptions[$0]?.isEmpty == true })
        let pending = try service.getLightingZones(nodeUuid: node.uuid)
        precondition(pending.lightingZonesStatus == .pending)
        SyncExecutionEnvironment.stopObserver = nil
        try service.retry(nodeUuid: node.uuid)
        finishAll(node: node)
        batch.success?(handle, ConfigModelSubscriptionStatus(handle.message, success: true))
        precondition(node.isKeybindComplete, "ACKs after STOP settlement are no longer accepted")
    }

    // Device state is independent of the SDK cache: destructive operations walk
    // the full extension graph, while an Add only updates the addressed element.
    final class DeviceSubscriptions {
        let node: Node
        var values: [Model: Set<UInt16>]
        init(_ node: Node) {
            self.node = node
            values = Dictionary(uniqueKeysWithValues: node.elements.flatMap(\.models).map {
                ($0, Set($0.subscriptions.map { $0.address.address }))
            })
        }
        func apply(_ handle: MeshMessageHandle) {
            let status = ConfigModelSubscriptionStatus(handle.message, success: true)
            let element = node.elements.first { $0.unicastAddress == status.elementAddress }!
            let model = element.models.first { $0.modelIdentifier == status.modelIdentifier && $0.companyIdentifier == status.companyIdentifier }!
            if handle.message is ConfigModelSubscriptionDeleteAll || handle.message is ConfigModelSubscriptionOverwrite {
                for item in Set([model] + model.relatedModels) { values[item] = [] }
            }
            if !(handle.message is ConfigModelSubscriptionDeleteAll) {
                for item in [model] + model.relatedModels.filter({ $0.parentElement === element }) {
                    values[item, default: []].insert(status.address)
                }
            }
        }
        func checkCache() {
            for model in node.elements.flatMap(\.models) {
                precondition(values[model] == Set(model.subscriptions.map { $0.address.address }), "device/cache mismatch")
            }
        }
    }

    static func testCrossElementReplayAtEveryRequest() throws {
        var cases = 0
        for zones in [0, 1, 2, 8] {
            for interruptedAfter in 0...(12 + zones * 6) {
                let (space, node, context) = try fixture()
                for id in 1...8 { _ = try HDBConfigurationStore.createZone(space: space, zoneId: id, name: "Z\(id)") }
                try HDBConfigurationStore.update(space: space) {
                    $0.devices[0].lightingZones = (0..<zones).map { .init(zoneId: $0 + 1) }
                }
                let actual = DeviceSubscriptions(node)
                // Reproduce the reported initial divergence: App has FEFD/Sensor,
                // the device LC is empty, and an old primary Zone must be removed.
                for model in node.elements[2].models { actual.values[model] = [] }
                actual.values[node.elements[0].models[0], default: []].insert(0xC099)
                SyncExecutionEnvironment.subscriptionObserver = actual.apply
                let operations = try context.zoneOperations(in: HDBConfigurationStore.load(space: space))
                var remaining = interruptedAfter
                for operation in operations where remaining > 0 {
                    let task = HDBDeviceSyncTask(context: context, operation: .zone(operation))
                    let handles = task.makeHandles()
                    precondition(!handles.isEmpty)
                    let prefix = Array(handles.prefix(remaining))
                    acknowledge(task, prefix, node: node)
                    precondition(task.flushAcknowledgedZoneCache())
                    remaining -= prefix.count
                }
                // Reopen from acknowledged, persisted subscriptions. No stage progress
                // is trusted: replacing the target still causes a complete replay.
                for (model, groups) in node.savedSubscriptions { model.subscriptions = groups }
                try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingZonesStatus = .pending }
                for operation in try context.zoneOperations(in: HDBConfigurationStore.load(space: space)) {
                    let task = HDBDeviceSyncTask(context: context, operation: .zone(operation))
                    let handles = task.makeHandles(); acknowledge(task, handles, node: node)
                    precondition(task.persist(result: handles))
                }
                actual.checkCache()
                let config = try HDBConfigurationStore.load(space: space)
                let wanted = Set([UInt16(0xFEFD), config.devices[0].sensorGroupId!] + config.lightingZones.prefix(zones).map(\.groupAddress))
                precondition(node.elements[2].models.allSatisfy { actual.values[$0] == wanted })
                precondition(node.isKeybindComplete && config.devices[0].lightingZonesStatus == .synced)
                cases += 1
            }
        }
        SyncExecutionEnvironment.subscriptionObserver = nil
        precondition(cases == 118)
    }

    static func testCancellationAndLateAcknowledgements() throws {
        for count in [1, 6] { try cancellationAndLateAcknowledgements(acknowledgedCount: count) }
    }

    static func cancellationAndLateAcknowledgements(acknowledgedCount: Int) throws {
        let (space, node, _) = try fixture()
        let service = HDBLightingZoneService(site: SiteData(), space: space)
        try service.retry(nodeUuid: node.uuid)
        let old = SyncExecutionEnvironment.batches.removeFirst(), handle = old.handles[0]
        for accepted in old.handles.prefix(acknowledgedCount) {
            accepted.isSuccessful = true; SyncExecutionEnvironment.applySubscription(accepted)
            old.success?(accepted, ConfigModelSubscriptionStatus(accepted.message, success: true))
        }
        precondition(node.elements[2].models.allSatisfy { $0.subscriptions.isEmpty }, "primary reset clears LC cache immediately")
        let saves = node.saveCount
        var stopped: (() -> Void)?
        SyncExecutionEnvironment.stopObserver = { stopped = $0 }
        service.cancel()
        precondition(service.isRunning && node.saveCount == saves, "remain busy until stop and flush settle")
        do { try service.retry(nodeUuid: node.uuid); fatalError("retry during stop accepted") }
        catch HDBConfigurationError.busy {}
        // Already accepted ACKs remain saveable when the desired intent changes.
        _ = try HDBConfigurationStore.createZone(space: space, zoneId: 1, name: "Next")
        stopped?()
        precondition(!service.isRunning && node.saveCount == saves + 1 && service.lastError == nil)
        precondition(node.elements[2].models.allSatisfy { node.savedSubscriptions[$0]?.isEmpty == true })
        SyncExecutionEnvironment.stopObserver = nil
        try service.retry(nodeUuid: node.uuid)
        SyncExecutionEnvironment.finishFirst(); SyncExecutionEnvironment.finishFirst()
        precondition(node.isKeybindComplete)
        // A late ACK from the same plan's previous attempt must not clear restored FEFD.
        old.success?(handle, ConfigModelSubscriptionStatus(handle.message, success: true))
        old.finished?(old.handles)
        precondition(node.isKeybindComplete)
        finishAll(node: node)
    }

    static func testScopedReadinessAndPartialSave() throws {
        let (space, node, context) = try fixture()
        let operations = try context.zoneOperations(in: HDBConfigurationStore.load(space: space))
        let reset = HDBDeviceSyncTask(context: context, operation: .zone(operations[0]))
        let handles = reset.makeHandles()
        // Simulate an ACK received by the shared session after cancellation.
        handles[0].isSuccessful = true
        SyncExecutionEnvironment.applySubscription(handles[0])
        reset.receive(handle: handles[0], response: ConfigModelSubscriptionStatus(handles[0].message, success: true), cacheOnly: true)
        precondition(!node.isKeybindComplete && reset.hasPendingZoneCacheSave)
        Node.failSave = true
        precondition(!reset.flushAcknowledgedZoneCache() && reset.hasPendingZoneCacheSave)
        Node.failSave = false
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingZonesStatus = .pending }
        precondition(reset.flushAcknowledgedZoneCache(), "changed intent does not discard already accepted cache changes")
        let broadcast = HDBDeviceSyncTask(context: context, operation: .zone(operations[1]))
        precondition(!broadcast.makeHandles().isEmpty, "FEFD restoration must remain executable")
        let receivers = node.elements[2].models
        precondition(node.isKeybindComplete(restoringSubelementSubscriptionsFor: receivers))
        precondition(!node.isKeybindComplete(restoringSubelementSubscriptionsFor: [Model(0x130F)]), "foreign model cannot grant exemption")
        node.elements[1].models[0].subscriptions = []
        precondition(broadcast.makeHandles().isEmpty, "unrelated FEFD loss must remain blocked")
        node.elements[1].models[0].subscriptions = [Group(0xFEFD)]
        receivers[1].boundApplicationKeys = []
        precondition(broadcast.makeHandles().isEmpty, "missing bindings are never exempt")
        receivers[1].boundApplicationKeys = [ApplicationKey()]
        MeshLibManager.testPublishModelIDs = [0x130F]
        precondition(broadcast.makeHandles().isEmpty, "publication requirements are never exempt")
        MeshLibManager.testPublishModelIDs = []
        node.sensorModelTypes.removeAll()
        precondition(broadcast.makeHandles().isEmpty, "sensor metadata requirements are never exempt")
    }

    static func testAffectedNonZoneBroadcastReceiver() throws {
        let (space, node, context) = try fixture()
        let temperature = node.elements[1].models[0]
        let chain = [node.elements[0].models[0]] + node.elements[0].models[0].relatedModels + [temperature]
        for model in Set(chain) { model.relatedModels = Array(Set(chain).subtracting([model])) }
        let metadata = try HDBConfigurationStore.deviceConfiguration(node: node)
        try HDBConfigurationStore.update(space: space) { $0.devices[0].copyModels(from: metadata) }
        _ = try HDBConfigurationStore.createZone(space: space, zoneId: 1, name: "One")
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingZones = [.init(zoneId: 1)] }
        let operations = try context.zoneOperations(in: HDBConfigurationStore.load(space: space))
        precondition(operations[1].subscriptions.contains { $0.target.modelIdentifier == 0x1306 })
        precondition(!operations.last!.subscriptions.contains { $0.target.modelIdentifier == 0x1306 })
        for operation in operations {
            let task = HDBDeviceSyncTask(context: context, operation: .zone(operation))
            let handles = task.makeHandles(); acknowledge(task, handles, node: node)
            precondition(task.persist(result: handles))
        }
        precondition(temperature.subscriptions.map { $0.address.address } == [0xFEFD])
        precondition(node.isKeybindComplete)
    }

    static func testSharedTargetsAndBindingGuards() throws {
        let (space, node, context) = try fixture()
        let lcTargets = try context.zoneBroadcastTargets()
        precondition(lcTargets.count == 3 && lcTargets.allSatisfy { $0.elementAddress == 4 })
        // A required receiver outside the five Zone types can still share a table
        // with a Zone target. Derive protection before intersecting Zone models.
        let temperature = node.elements[1], otherOnOff = Model(0x1000)
        otherOnOff.parentElement = temperature; temperature.models.append(otherOnOff)
        temperature.models[0].relatedModels = [otherOnOff]
        otherOnOff.relatedModels = [temperature.models[0]]
        precondition(try! context.zoneBroadcastTargets().count == 3, "excluded secondary OnOff alone does not create a reset dependency")
        let lightness = Model(0x1300); lightness.parentElement = temperature; temperature.models.append(lightness)
        let shared = temperature.models
        for model in shared { model.relatedModels = shared.filter { $0 !== model } }
        // A primary LC has no fixed FEFD requirement, even in a multi-element node.
        let primaryLC = Model(0x130F); primaryLC.parentElement = node.elements[0]
        node.elements[0].models.append(primaryLC)
        let protected = try context.zoneBroadcastTargets()
        precondition(protected.count == 5 && !protected.contains { $0.elementAddress == 2 })
        precondition(protected.contains { $0.elementAddress == 3 && $0.modelIdentifier == 0x1000 })
        let metadata = try HDBConfigurationStore.deviceConfiguration(node: node)
        try HDBConfigurationStore.update(space: space) { $0.devices[0].copyModels(from: metadata) }
        let operations = try context.zoneOperations(in: HDBConfigurationStore.load(space: space))
        let sensorStage = operations.first { $0.stage == .sensor }!
        precondition(sensorStage.subscriptions.contains { $0.target.elementAddress == 2 && $0.command == .add })
        precondition(sensorStage.subscriptions.filter { $0.target.elementAddress == 4 }.allSatisfy { $0.command == .add })
        // Real binding failures must remain blocked; FEFD preservation is no bypass.
        for keys: [ApplicationKey] in [[], [.init(index: 7)]] {
            primaryLC.boundApplicationKeys = keys
            precondition(!node.isKeybindComplete)
            let task = HDBDeviceSyncTask(context: context, operation: .zone(operations[0]))
            precondition(task.makeHandles().isEmpty)
        }
    }

    static func testOldFailureRecovery() throws {
        for directApply in [false, true] {
            let (space, node, context) = try fixture()
            for model in node.elements[2].models { model.subscriptions.removeAll { $0.address.address == 0xFEFD } }
            precondition(!node.isKeybindComplete && node.getStandardNeedSync())
            let operations = try context.zoneOperations(in: HDBConfigurationStore.load(space: space))
            precondition(!HDBDeviceSyncTask(context: context, operation: .zone(operations[0])).makeHandles().isEmpty)
            if directApply {
                let service = HDBLightingZoneService(site: SiteData(), space: space)
                try service.retry(nodeUuid: node.uuid)
                finishAll(node: node)
                precondition(service.lastError == nil)
            } else {
                // Emulate the existing ordinary initialization's FEFD Add ACK.
                // The real SDK getter and all subsequent HDB tasks execute below.
                let repair = HDBZoneSubscription(target: .init(elementAddress: 4, modelIdentifier: 0x130F, companyIdentifier: nil), command: .add, address: 0xFEFD)
                SyncExecutionEnvironment.applySubscription(.init(message: ConfigModelSubscriptionAdd(parameters: repair.parameters)!, address: 2))
                precondition(node.isKeybindComplete)
                for step in try HDBDeviceSyncService.makeSteps(context: context) {
                    guard case .configuration(_, .hdb(let task)) = step.tasks[0].operationType else { fatalError() }
                    let handles = task.makeHandles(); acknowledge(task, handles, node: node)
                    precondition(task.persist(result: handles))
                }
            }
            precondition(node.isKeybindComplete && !HDBDeviceSyncService.needsSync(node: node))
        }
    }

    static func finishAll(node: Node) {
        while !SyncExecutionEnvironment.batches.isEmpty {
            SyncExecutionEnvironment.finishFirst()
        }
        precondition(node.isKeybindComplete)
    }

    static func testDirectApplyFailureAndReopen() throws {
        // Fail each destructive/protected phase and the final Zone Add in turn.
        for scenario in 0..<8 {
            let failStage = scenario / 2, failIndex = scenario % 2
            let (space, node, _) = try fixture()
            _ = try HDBConfigurationStore.createZone(space: space, zoneId: 1, name: "One")
            let service = HDBLightingZoneService(site: SiteData(), space: space)
            try service.setLightingZones(nodeUuid: node.uuid, zoneIds: [1])
            for _ in 0..<failStage { SyncExecutionEnvironment.finishFirst() }
            let saves = node.saveCount
            SyncExecutionEnvironment.finishFirst(failIndex: failIndex)
            if failIndex == 1 {
                precondition(node.saveCount == saves + 1, "partially successful stages must persist their ACKs")
                for model in node.elements.flatMap(\.models) {
                    precondition(node.savedSubscriptions[model]?.map { $0.address.address } == model.subscriptions.map { $0.address.address })
                }
            }
            precondition(!service.isRunning && service.lastError != nil && SyncExecutionEnvironment.batches.isEmpty)
            let pending = try service.getLightingZones(nodeUuid: node.uuid)
            precondition(pending.lightingZonesStatus == .pending && pending.lightingZones.map(\.zoneId) == [1])
            if (1..<3).contains(failStage) && failIndex == 0 {
                let sensor = pending.sensorGroupId!
                precondition(node.elements[2].models.allSatisfy { !$0.subscriptions.contains { $0.address.address == sensor } },
                             "failed first Sensor Add leaves Sensor temporarily absent, but retry must remain possible")
            }
            let reopened = HDBLightingZoneService(site: SiteData(), space: space.copy())
            try reopened.retry(nodeUuid: node.uuid)
            let first = SyncExecutionEnvironment.batches[0].handles
            precondition(first.count == 5 && first.allSatisfy {
                $0.message is ConfigModelSubscriptionDeleteAll && ConfigModelSubscriptionStatus($0.message, success: true).address == 0
            })
            finishAll(node: node)
            let saved = try reopened.getLightingZones(nodeUuid: node.uuid)
            precondition(saved.lightingZonesStatus == .synced && !HDBDeviceSyncService.needsSync(node: node))
            let zone = try HDBConfigurationStore.load(space: space).lightingZones[0].groupAddress
            precondition(node.elements[2].models.allSatisfy { Set($0.subscriptions.map { $0.address.address }) == [0xFEFD, saved.sensorGroupId!, zone] })
        }
    }

    static func testChangedBroadcastContract() throws {
        let (space, node, context) = try fixture()
        let savedModels = try HDBConfigurationStore.deviceConfiguration(node: node)
        MeshLibManager.manager.subElementGroupSubscriptionModelIDs = []
        precondition(try! HDBConfigurationStore.deviceConfiguration(node: node) == savedModels,
                     "exported targets derive from Composition, not the currently open Site's global SDK settings")
        MeshLibManager.manager.subElementGroupSubscriptionModelIDs = [0x1306, 0x130F]
        let operation = try context.zoneOperations(in: HDBConfigurationStore.load(space: space))[0]
        let task = HDBDeviceSyncTask(context: context, operation: .zone(operation))
        let handles = task.makeHandles()
        try HDBConfigurationStore.update(space: space) { $0.devices[0].broadcastModels.removeLast() }
        acknowledge(task, handles, node: node)
        precondition(!task.persist(result: handles), "changed persisted broadcast targets reject old ACKs")
        let service = HDBLightingZoneService(site: SiteData(), space: space)
        try service.retry(nodeUuid: node.uuid)
        try HDBConfigurationStore.update(space: space) { $0.devices[0].broadcastModels.removeLast() }
        SyncExecutionEnvironment.finishFirst()
        precondition(!service.isRunning && SyncExecutionEnvironment.batches.isEmpty)
        let saved = try service.getLightingZones(nodeUuid: node.uuid)
        precondition(saved.lightingZonesStatus == .pending)
    }
}
