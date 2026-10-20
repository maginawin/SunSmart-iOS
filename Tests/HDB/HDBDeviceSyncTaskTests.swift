import Foundation

@main enum HDBDeviceSyncTaskTests {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "condition failed") rethrows {
        let value = try condition(); precondition(value, message)
    }
    static func fixture() throws -> (SpaceData, Node, HDBDeviceSyncContext) {
        SiteData.hdbEnabled = true; SpaceData.failSave = false
        SpaceConfigurationSafety.journal = .init()
        Node.PreConfiguration.failSave = false; Node.PreConfiguration.saved = nil
        let space = SpaceData(), network = MeshNetwork(), node = Node()
        node.network = network; network.nodes = [node]
        let secondary = Element(); secondary.unicastAddress = 2; secondary.models = [Model(0x1310)]
        node.elements.append(secondary)
        for element in node.elements { element.models.forEach { $0.parentElement = element } }
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        space.hdb = .init(); SpaceData.persisted = space.copy()
        let context = try HDBDeviceSyncContext.resolve(space: space, node: node)!
        try HDBDeviceSyncService.prepareIntent(context: context)
        return (space, node, context)
    }
    static func initialization(_ context: HDBDeviceSyncContext) throws -> HDBDeviceSyncTask {
        let config = try HDBConfigurationStore.load(space: context.space)
        return .init(context: context, operation: .initialization(try context.plan(in: config), config.devices[0].lightingConfiguration!))
    }
    static func acknowledge(_ task: HDBDeviceSyncTask, _ handles: [MeshMessageHandle], omit: ((MeshMessageHandle) -> Bool) = { _ in false }) {
        for handle in handles where !omit(handle) {
            handle.isSuccessful = true
            if handle.message is ConfigModelSubscriptionOverwrite || handle.message is ConfigModelSubscriptionDeleteAll || handle.message is ConfigModelSubscriptionAdd {
                SyncExecutionEnvironment.applySubscription(handle)
                task.receive(handle: handle, response: ConfigModelSubscriptionStatus(handle.message, success: true))
            } else { task.receive(handle: handle, response: handle.message) }
        }
    }
    static func testZoneStages() throws {
        let (space, node, context) = try fixture()
        try seedPrepared(space: space, node: node)
        _ = try HDBConfigurationStore.createZone(space: space, zoneId: 1, name: "One")
        _ = try HDBConfigurationStore.createZone(space: space, zoneId: 2, name: "Two")
        try HDBConfigurationStore.update(space: space) {
            $0.devices[0].lightingZones = [.init(zoneId: 1), .init(zoneId: 2)]
            $0.devices[0].lightingZonesStatus = .pending
        }
        let operations = try context.zoneOperations(in: HDBConfigurationStore.load(space: space))
        check(operations.map(\.stage) == [.reset, .add])
        let reset = HDBDeviceSyncTask(context: context, operation: .zone(operations[0]))
        let resetHandles = reset.makeHandles()
        check(resetHandles.count == 6, "every model instance is required")
        acknowledge(reset, resetHandles); check(reset.persist(result: resetHandles))
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingZonesStatus == .pending)
        // Transport success is insufficient when ACK element/address/model/company differs.
        for byte in [0, 2, 4, 6] {
            let add = HDBDeviceSyncTask(context: context, operation: .zone(operations[1]))
            let handles = add.makeHandles()
            for handle in handles {
                handle.isSuccessful = true
                var parameters = handle.message.parameters
                if byte < parameters.count { parameters[byte] ^= 1 }
                add.receive(handle: handle, response: ConfigModelSubscriptionStatus(ConfigModelSubscriptionAdd(parameters: parameters)!, success: true))
            }
            check(!add.persist(result: handles))
            try check(HDBConfigurationStore.load(space: space).devices[0].lightingZonesStatus == .pending)
        }
        // Rebuilt ordinary Sync also starts again at DeleteAll and completes only the final Add.
        let steps = try HDBDeviceSyncService.makeSteps(context: context)
        check(steps.count == 2 && steps[1].relevanceStepModels.first === steps[0])
        for step in steps {
            guard case .configuration(_, .hdb(let task)) = step.tasks[0].operationType else { fatalError() }
            let handles = task.makeHandles(); acknowledge(task, handles)
            check(task.persist(result: handles))
        }
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingZonesStatus == .synced)
        check(!HDBDeviceSyncService.needsSync(node: node))
    }

    static func main() throws {
        try testPresencePublicationElement()
        try testZoneStages()
        let (space, node, context) = try fixture()
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingConfiguration?.merge(.init(brightIntensity: 90), status: .pending) }
        let initial = try initialization(context), handles = initial.makeHandles()
        check(!handles.isEmpty)
        let modeIndex = handles.firstIndex { $0.message is LightLCModeSet }!
        let autoIndex = handles.firstIndex { ($0.message as? LightingTestMessage)?.write == .auto }!
        check(modeIndex < autoIndex && handles[..<modeIndex].contains { ($0.message as? LightingTestMessage)?.write?.fieldName == "holdTime" })
        // One of two LC Setup instances times out: only that field stays pending.
        acknowledge(initial, handles, omit: { ($0.message as? LightingTestMessage)?.write?.fieldName == "brightIntensity" && $0.address == 2 })
        check(!initial.persist(result: handles))
        var saved = try HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration!
        check(saved.brightIntensity?.status == .pending && saved.brightIntensity?.value == 90)
        check(saved.dimIntensity?.status == .synced && saved.holdTime?.status == .synced && saved.lightingControl?.status == .synced)
        check(node.preConfiguration.hdbInitializationSignature?.hasPrefix("pending:") == true && HDBDeviceSyncService.needsSync(node: node))
        // A retry preserves the user's value and sends no already-ACKed parameter.
        let retry = try initialization(context), retryHandles = retry.makeHandles()
        let retriedFields = retryHandles.compactMap { ($0.message as? LightingTestMessage)?.write?.fieldName }
        check(retriedFields == ["brightIntensity", "brightIntensity", "lightingControl"])
        acknowledge(retry, retryHandles)
        check(retry.persist(result: retryHandles))
        check(HDBDeviceSyncService.needsSync(node: node), "empty target is pending until DeleteAll succeeds")
        for operation in try context.zoneOperations(in: HDBConfigurationStore.load(space: space)) {
            let task = HDBDeviceSyncTask(context: context, operation: .zone(operation)), handles = task.makeHandles()
            check(task.isLightingZoneOperation && handles.allSatisfy { $0.message is ConfigModelSubscriptionDeleteAll })
            acknowledge(task, handles); check(task.persist(result: handles))
        }
        check(!HDBDeviceSyncService.needsSync(node: node))
        check(Node.PreConfiguration.saved?.hdbInitializationSignature == node.preConfiguration.hdbInitializationSignature)
        // Reprovisioning keeps custom values but invalidates hardware completion.
        node.deviceKey = Data([2]); node.createdTimestamp += 1
        try HDBConfigurationStore.restoreDevice(space: space, nodeUuid: node.uuid, nodeAddress: 1, mac: "AABBCCDDEEFF")
        let restored = try HDBDeviceSyncContext.resolve(space: space, node: node)!
        saved = try HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration!
        check(saved.brightIntensity?.value == 90 && saved.brightIntensity?.status == .pending)
        check(saved.lightingControl?.value == .auto && saved.lightingControl?.status == .pending)
        check(HDBDeviceSyncService.needsSync(node: node))
        try HDBDeviceSyncService.prepareIntent(context: restored)
        let restoredTask = try initialization(restored), restoredHandles = restoredTask.makeHandles()
        let writes = restoredHandles.compactMap { ($0.message as? LightingTestMessage)?.write }
        check(writes.last == .auto && writes.contains(.property(0x002E, UInt32(Double(90) / 100 * 65535))))
        acknowledge(restoredTask, restoredHandles)
        Node.PreConfiguration.failSave = true
        check(!restoredTask.persist(result: restoredHandles), "receipt persistence is required for add success")
        check(HDBDeviceSyncService.needsSync(node: node))
        Node.PreConfiguration.failSave = false
        let receiptRetry = try initialization(restored), receiptHandles = receiptRetry.makeHandles()
        check(receiptHandles.compactMap { ($0.message as? LightingTestMessage)?.write } == [.auto])
        acknowledge(receiptRetry, receiptHandles); check(receiptRetry.persist(result: receiptHandles))
        // Ordinary parameter Sync never replays a saved Force command or forces Auto.
        try HDBConfigurationStore.update(space: space) {
            $0.devices[0].lightingConfiguration?.merge(.init(lightingControl: .forceOn), status: .synced)
            $0.devices[0].lightingConfiguration?.merge(.init(holdTime: 120), status: .pending)
        }
        let config = try HDBConfigurationStore.load(space: space)
        check(HDBDeviceSyncService.restorationCommands(config.devices[0]) == [.timeDelay])
        let parameters = HDBDeviceSyncTask(context: restored, operation: .configuration(.timeDelay, config.devices[0].lightingConfiguration!))
        let parameterHandles = parameters.makeHandles()
        check(parameterHandles.allSatisfy { ($0.message as? LightingTestMessage)?.write == .property(0x003C, 120000) })
        // A value changed away and back is still a newer intent: ignore old callbacks.
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingConfiguration?.merge(.init(holdTime: 130), status: .pending) }
        try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingConfiguration?.merge(.init(holdTime: 120), status: .pending) }
        acknowledge(parameters, parameterHandles); check(!parameters.persist(result: parameterHandles))
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.holdTime?.status == .pending)
        // A transport-successful response with wrong content is not an ACK.
        let mismatch = HDBDeviceSyncTask(context: restored, operation: .configuration(.timeDelay, config.devices[0].lightingConfiguration!))
        let mismatchHandles = mismatch.makeHandles()
        for handle in mismatchHandles { handle.isSuccessful = true; mismatch.receive(handle: handle, response: LightingTestMessage(write: .property(0x003C, 999))) }
        check(!mismatch.persist(result: mismatchHandles))
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.holdTime?.status == .pending)
        // Failed restore persistence is repaired by the ordinary Sync preparation.
        node.deviceKey = Data([3]); node.createdTimestamp += 1
        SpaceData.failSave = true
        do { try HDBConfigurationStore.restoreDevice(space: space, nodeUuid: node.uuid, nodeAddress: 1, mac: "AABBCCDDEEFF"); preconditionFailure("restore failure ignored") } catch {}
        HDBDeviceSyncService.prepareIntents(nodes: [node])
        SpaceData.failSave = false
        let recovery = try HDBDeviceSyncContext.resolve(space: space, node: node)!
        do { _ = try HDBDeviceSyncService.makeSteps(context: recovery); preconditionFailure("failed preparation was bypassed by planner") }
        catch HDBConfigurationError.persistenceFailed {}
        try check(initialization(recovery).makeHandles().isEmpty, "direct task must also reject an unestablished identity")
        try HDBDeviceSyncService.prepareIntent(context: recovery)
        let recoveryTask = try initialization(recovery), recoveryHandles = recoveryTask.makeHandles()
        let recoveryWrites = recoveryHandles.compactMap { ($0.message as? LightingTestMessage)?.write }
        check(recoveryWrites.contains(.property(0x002E, UInt32(Double(90) / 100 * 65535))) && recoveryWrites.contains(.property(0x003C, 120000)) && recoveryWrites.last == .auto)
        // An Auto ACK cannot hide a missing Mode ACK, even if the transport continues.
        acknowledge(recoveryTask, recoveryHandles, omit: { $0.message is LightLCModeSet })
        check(!recoveryTask.persist(result: recoveryHandles))
        try check(HDBConfigurationStore.load(space: space).devices[0].lightingConfiguration?.lightingControl?.status == .pending)
        try HDBDeviceSyncService.prepareIntent(context: recovery)
        let activationRetry = try initialization(recovery), activationHandles = activationRetry.makeHandles()
        check(activationHandles.compactMap { ($0.message as? LightingTestMessage)?.write } == [.auto])
        acknowledge(activationRetry, activationHandles); check(activationRetry.persist(result: activationHandles))
        node.primaryUnicastAddress = 3; node.elements[0].unicastAddress = 3; node.elements[1].unicastAddress = 4
        node.deviceKey = Data([4])
        let moved = try HDBDeviceSyncContext.resolve(space: space, node: node)!
        try HDBDeviceSyncService.prepareIntent(context: moved)
        try check(HDBConfigurationStore.load(space: space).devices[0].nodeAddress == 3)
        try check(!initialization(moved).makeHandles().isEmpty)
        print("PASS: production Sync task partial multi-model ACK, field retry, defaults/custom restore, receipt failure, no Force replay and stale/mismatched ACK rejection")
    }

    static func testPresencePublicationElement() throws {
        for presenceAddress: UInt16 in [1, 3] {
            let (space, node, context) = try fixture()
            let third = Element(); third.unicastAddress = 3; third.models = []
            node.elements.append(third)
            for element in node.elements {
                let sensor = Model(0x1100); sensor.parentElement = element; element.models.append(sensor)
                node.sensorModelTypes[sensor] = .init(id: element.unicastAddress == presenceAddress ? 0x004D
                    : element.unicastAddress == 2 ? 0x0072 : 0x004E)
            }
            try HDBDeviceSyncService.prepareIntent(context: context)
            let plan = try context.plan(in: HDBConfigurationStore.load(space: space))
            check(plan.publicationTargets.count == 1 && plan.publicationTargets[0].elementAddress == presenceAddress)
            let sensorTargets = plan.subscriptionTargets.filter { $0.modelIdentifier == 0x1100 }
            check(sensorTargets.map(\.elementAddress) == [1, 2, 3])
            for (index, sensorTarget) in sensorTargets.enumerated() {
                let subscription = HDBDeviceSyncTask(context: context, operation: .preparation(plan, .subscription(sensorTarget)))
                let subscriptionHandles = subscription.makeHandles()
                check(subscriptionHandles.count == 1 && subscriptionHandles[0].address == node.primaryUnicastAddress)
                check(subscriptionHandles[0].message is ConfigModelSubscriptionAdd)
                let encoded = ConfigModelSubscriptionStatus(subscriptionHandles[0].message, success: true)
                check(encoded.elementAddress == sensorTarget.elementAddress && encoded.address == plan.sensorGroupId
                      && encoded.modelIdentifier == 0x1100 && encoded.companyIdentifier == nil)
                if index == 1 {
                    // Partial preparation must retain the failed element for ordinary Sync.
                    check(!subscription.persist(result: subscriptionHandles))
                } else if index == 2 {
                    // A transport success or another element's ACK cannot satisfy this target.
                    subscriptionHandles[0].isSuccessful = true
                    var wrongElement = subscriptionHandles[0].message.parameters
                    wrongElement[0] = 1
                    subscription.receive(handle: subscriptionHandles[0], response: ConfigModelSubscriptionStatus(
                        ConfigModelSubscriptionAdd(parameters: wrongElement)!, success: true))
                    check(!subscription.persist(result: subscriptionHandles))
                } else {
                    acknowledge(subscription, subscriptionHandles)
                    check(subscription.persist(result: subscriptionHandles))
                }
            }
            let pendingSensors = HDBDeviceSyncService.pendingLinks(context: context, plan: plan).compactMap { step -> HDBModelTarget? in
                if case .subscription(let target) = step, target.modelIdentifier == 0x1100 { return target }
                return nil
            }
            check(pendingSensors.map(\.elementAddress) == [2, 3])
            for sensorTarget in pendingSensors {
                let retry = HDBDeviceSyncTask(context: context, operation: .preparation(plan, .subscription(sensorTarget)))
                let retryHandles = retry.makeHandles()
                acknowledge(retry, retryHandles)
                check(retry.persist(result: retryHandles))
            }
            check(node.elements.allSatisfy { element in
                element.models.first { $0.modelIdentifier == 0x1100 }!.subscriptions.map { $0.address.address } == [plan.sensorGroupId!]
            })
            let target = plan.publicationTargets[0]
            let task = HDBDeviceSyncTask(context: context, operation: .preparation(plan, .publication(target)))
            let handles = task.makeHandles()
            check(handles.count == 1 && handles[0].address == node.primaryUnicastAddress)
            let request = handles[0].message as! ConfigModelPublicationSet
            check(request.model.parentElement?.unicastAddress == presenceAddress)
            check(request.publication.publicationAddress.address == plan.sensorGroupId)
            check(request.publication.period == .disabled && request.publication.retransmit.count == 2
                  && request.publication.retransmit.interval == 100 && request.publication.ttl == 0xFF)
            // An ACK for another Sensor element must not complete this task.
            let other = node.elements.first { $0.unicastAddress != presenceAddress }!.models.first { $0.modelIdentifier == 0x1100 }!
            handles[0].isSuccessful = true
            task.receive(handle: handles[0], response: ConfigModelPublicationStatus(ConfigModelPublicationSet(request.publication, to: other)!, success: true))
            check(!task.persist(result: handles) && request.model.publish == nil)

            let wrongTiming = HDBDeviceSyncTask(context: context, operation: .preparation(plan, .publication(target)))
            let wrongTimingHandles = wrongTiming.makeHandles()
            var oldPublication = request.publication
            oldPublication.retransmit = .init(1, timesWithInterval: 0.1)
            wrongTimingHandles[0].isSuccessful = true
            wrongTiming.receive(handle: wrongTimingHandles[0], response: ConfigModelPublicationStatus(
                ConfigModelPublicationSet(oldPublication, to: request.model)!, success: true))
            check(!wrongTiming.persist(result: wrongTimingHandles) && request.model.publish == nil,
                  "an ACK carrying the old retransmit count must not complete the repair")

            let retry = HDBDeviceSyncTask(context: context, operation: .preparation(plan, .publication(target)))
            let retryHandles = retry.makeHandles()
            retryHandles[0].isSuccessful = true
            retry.receive(handle: retryHandles[0], response: ConfigModelPublicationStatus(retryHandles[0].message as! ConfigModelPublicationSet, success: true))
            check(retry.persist(result: retryHandles))
            check(request.model.publish?.publicationAddress.address == plan.sensorGroupId)
            check(request.model.publish?.retransmit.count == 2 && request.model.publish?.retransmit.interval == 100)
            check(!HDBDeviceSyncService.pendingLinks(context: context, plan: plan).contains(.publication(target)))
            check(node.sensorModelTypes.keys.filter { $0 !== request.model }.allSatisfy { $0.publish == nil })
        }
    }
}
