import Foundation

@main enum HDBIntegrationTests {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "condition failed", file: StaticString = #file, line: UInt = #line) rethrows {
        let value = try condition(); precondition(value, message, file: file, line: line)
    }
    static func fixture(sensor: Bool = false) throws -> (SpaceData, MeshNetwork, Node, HDBLightingZoneService) {
        precondition(SyncExecutionEnvironment.batches.isEmpty)
        SpaceData.failSave = false; Node.failSave = false; SpaceData.siblings = []
        SpaceConfigurationSafety.journal = .init(); SiteData.hdbEnabled = true
        MeshAPI.allocation = Array(UInt16(0xC001)...0xC100)
        let space = SpaceData(), network = MeshNetwork(), node = Node()
        node.network = network; network.nodes = [node]
        if sensor {
            let element = node.elements[0]
            let sensorModel = Model(0x1100); sensorModel.parentElement = element
            element.models.append(sensorModel); node.presenceDetectedSensorModel = sensorModel
            node.sensorModelTypes[sensorModel] = .init(id: 0x004D)
            // LC, LC Setup and OnOff share this element's subscription table.
            let shared = Array(element.models.prefix(3))
            for model in shared { model.relatedModels = shared.filter { $0 !== model } }
            // Related models in a different element do not share its subscription table.
            let secondary = Element(); secondary.unicastAddress = 2; secondary.models = [Model(0x1000)]
            secondary.models[0].parentElement = secondary
            element.models[0].relatedModels.append(secondary.models[0]); node.elements.append(secondary)
        }
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        MeshNetworkManager.instance.currentNetworkKey.networkId = "network"
        space.hdb = .init(); SpaceData.persisted = space.copy()
        _ = try HDBConfigurationStore.createZone(space: space, zoneId: 1, name: "One")
        _ = try HDBConfigurationStore.createZone(space: space, zoneId: 2, name: "Two")
        try seedPrepared(space: space, node: node)
        return (space, network, node, HDBLightingZoneService(site: SiteData(), space: space))
    }
    static func main() throws {
        try testModelMetadataLifecycle()
        try testWholeDeviceReplay()
        try testSensorFirstAndSharedLists()
        try testEmptyTargetAndPersistence()
        try testInvalidatedReceipts()
        try testPreparationAndAllocation()
        print("PASS: production Store/Service/Executor full replay, shared Sensor lists, empty target, strict ACK, durable failures and late replies")
    }
    static func testModelMetadataLifecycle() throws {
        let (space, network, node, _) = try fixture(sensor: true)
        let secondary = node.elements[1]
        let vendor = Model(1, company: 0x0A78), lc = Model(0x130F), setup = Model(0x1310)
        secondary.models += [vendor, lc, setup]
        for model in secondary.models { model.parentElement = secondary }
        let shared = [secondary.models[0], lc, setup]
        for model in shared {
            model.relatedModels = shared.filter { $0 !== model }
            model.subscriptions = [Group(0xFEFD)]
        }
        let context = try HDBDeviceSyncContext.resolve(space: space, node: node)!
        let before = try HDBConfigurationStore.load(space: space)
        let metadata = try HDBConfigurationStore.deviceConfiguration(node: node)
        check(!metadata.zoneModels.contains { $0.elementAddress == 2 && [0x1000, 0x0A780001].contains($0.modelId) })
        check(Set(metadata.sensorGroupModels.filter { $0.elementAddress == 2 }.map(\.modelId)) == [0x1000, 0x130F, 0x1310])
        check(Set(metadata.broadcastModels.map(\.modelId)) == [0x1000, 0x130F, 0x1310])
        SpaceData.failSave = true
        do { try HDBDeviceSyncService.prepareIntent(context: context); fatalError("metadata save failure accepted") } catch HDBConfigurationError.persistenceFailed {}
        SpaceData.failSave = false
        try check(HDBConfigurationStore.load(space: space) == before)
        try HDBDeviceSyncService.prepareIntent(context: context)
        let config = try HDBConfigurationStore.load(space: space)
        check(config.devices[0].hasSameModels(as: metadata) && config.devices[0].lightingZonesStatus == .pending)
        try HDBConfigurationStore.validateModels(config, nodes: network.nodes)
        let persisted = try JSONDecoder().decode(HDBConfiguration.self, from: JSONEncoder().encode(config))
        check(persisted == config)
        let plan = try context.plan(in: config)
        check(plan.baseTargets.contains { $0.model.elementAddress == 2 && $0.model.modelId == 0x0A780001 && $0.value != nil },
              "Preparation retains the secondary Vendor with its fixed initialization values")
        var invalid = config; invalid.devices[0].broadcastModels.removeLast()
        do { try HDBConfigurationStore.validateModels(invalid, nodes: network.nodes); fatalError("incomplete export/import target list accepted") } catch HDBConfigurationError.invalidData {}
        let oldPlan = try context.zoneOperations(in: config)[0].plan
        node.primaryUnicastAddress += 10
        for element in node.elements { element.unicastAddress += 10 }
        let restoredContext = try HDBDeviceSyncContext.resolve(space: space, node: node)!
        try HDBDeviceSyncService.prepareIntent(context: restoredContext)
        let restored = try HDBConfigurationStore.load(space: space)
        check(restored.devices[0].nodeAddress == 11)
        check((restored.devices[0].zoneModels + restored.devices[0].sensorGroupModels + restored.devices[0].broadcastModels).allSatisfy { $0.elementAddress >= 11 })
        check(!HDBLightingZonePolicy.matches(oldPlan, in: restored))
        try HDBConfigurationStore.validateModels(restored, nodes: network.nodes)
        let exported = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored.devices[0])) as! [String: Any]
        let lighting = exported["lightingConfiguration"] as! [String: Any]
        let maps = lighting["lightingControl"] as! [String: Any]
        check(maps["Auto"] as? String == "000B" && maps["Force_On"] as? String == "000B")
        check((lighting["brightIntensity"] as! [String: Any])["elementAddress"] as? String == "000B",
              "Restored command metadata must follow the new Composition addresses")
    }

    static func testWholeDeviceReplay() throws {
        let (space, network, node, service) = try fixture()
        let uploads = CloudSynchronizationManager.shared.submissions
        let empty = try service.getLightingZones(nodeUuid: node.uuid)
        check(empty.lightingZones.isEmpty && SyncExecutionEnvironment.batches.isEmpty)
        check(CloudSynchronizationManager.shared.submissions == uploads)
        // Even a previously synced device saves pending intent before the first message.
        try service.setLightingZones(nodeUuid: node.uuid, zoneIds: [2, 1])
        try check(service.getLightingZones(nodeUuid: node.uuid).lightingZonesStatus == .pending)
        var handles = SyncExecutionEnvironment.batches[0].handles
        check(handles.count == 5 && handles.allSatisfy { $0.address == 1 && $0.message is ConfigModelSubscriptionDeleteAll })
        SyncExecutionEnvironment.finishFirst()
        handles = SyncExecutionEnvironment.batches[0].handles
        check(handles.count == 10 && handles.allSatisfy { $0.message is ConfigModelSubscriptionAdd })
        SyncExecutionEnvironment.finishFirst(failIndex: 2)
        check(!service.isRunning && service.lastError != nil)
        let partial = try service.getLightingZones(nodeUuid: node.uuid)
        check(partial.lightingZones.map(\.zoneId) == [1, 2] && partial.lightingZonesStatus == .pending)
        MeshNetworkManager.instance.meshNetwork = nil
        try check(service.getLightingZones(nodeUuid: node.uuid) == partial)
        MeshNetworkManager.instance.meshNetwork = network
        let reopened = HDBLightingZoneService(site: SiteData(), space: space.copy())
        try reopened.retry(nodeUuid: node.uuid)
        check(SyncExecutionEnvironment.batches[0].handles.allSatisfy { $0.message is ConfigModelSubscriptionDeleteAll })
        finishAll(reopened)
        try check(reopened.getLightingZones(nodeUuid: node.uuid).lightingZonesStatus == .synced)
        let targetAddresses: Set<UInt16> = [0xC001, 0xC002]
        check(node.elements.flatMap(\.models).allSatisfy { Set($0.subscriptions.map { $0.address.address }) == targetAddresses })
        // Manual Apply of the same synced target still starts from DeleteAll.
        try reopened.setLightingZones(nodeUuid: node.uuid, zoneIds: [1, 2])
        check(SyncExecutionEnvironment.batches[0].handles.allSatisfy { $0.message is ConfigModelSubscriptionDeleteAll })
        SyncExecutionEnvironment.finishFirst(failIndex: 0)
        check(SyncExecutionEnvironment.batches.isEmpty, "reset failure must prevent every Add")
        try reopened.retry(nodeUuid: node.uuid); finishAll(reopened)
        try reopened.setLightingZones(nodeUuid: node.uuid, zoneIds: [2])
        SyncExecutionEnvironment.finishFirst(failIndex: 0)
        try check(reopened.getLightingZones(nodeUuid: node.uuid).lightingZones.map(\.zoneId) == [2], "saved array is only the new target")
        try reopened.retry(nodeUuid: node.uuid); finishAll(reopened)
        check(node.elements.flatMap(\.models).allSatisfy { $0.subscriptions.map { $0.address.address } == [0xC002] })
    }
    static func testSensorFirstAndSharedLists() throws {
        for empty in [false, true] {
            let (space, _, node, service) = try fixture(sensor: true)
            let sensorAddress = space.hdb!.devices[0].sensorGroupId!
            let shared = Array(node.elements[0].models.prefix(3))
            shared.forEach { $0.subscriptions = [Group(0xC099)] }
            try service.setLightingZones(nodeUuid: node.uuid, zoneIds: empty ? [] : [1, 2])
            let reset = SyncExecutionEnvironment.batches[0].handles
            check(reset.count == 5 && reset.allSatisfy { $0.message is ConfigModelSubscriptionDeleteAll })
            SyncExecutionEnvironment.finishFirst(failIndex: 4)
            check(shared.allSatisfy { $0.subscriptions.isEmpty })
            try check(service.getLightingZones(nodeUuid: node.uuid).lightingZonesStatus == .pending)
            try service.retry(nodeUuid: node.uuid)
            SyncExecutionEnvironment.finishFirst()
            let sensor = SyncExecutionEnvironment.batches[0].handles
            check(sensor.count == 3 && sensor.allSatisfy {
                $0.message is ConfigModelSubscriptionAdd && ConfigModelSubscriptionStatus($0.message, success: true).address == sensorAddress
            })
            SyncExecutionEnvironment.finishFirst()
            check(shared.allSatisfy { $0.subscriptions.map { $0.address.address } == [sensorAddress] })
            if !empty {
                check(SyncExecutionEnvironment.batches[0].handles.count == 10, "every Zone is added to every target")
                SyncExecutionEnvironment.finishFirst(failIndex: 4)
                check(shared.allSatisfy { $0.subscriptions.contains { $0.address.address == sensorAddress } })
                try service.retry(nodeUuid: node.uuid); finishAll(service)
            }
            try check(service.getLightingZones(nodeUuid: node.uuid).lightingZonesStatus == .synced)
            let expected: Set<UInt16> = empty ? [sensorAddress] : [sensorAddress, 0xC001, 0xC002]
            check(shared.allSatisfy { Set($0.subscriptions.map { $0.address.address }) == expected })
            check(node.elements[1].models[0].subscriptions.isEmpty, "secondary OnOff without LC is never a Zone target")
            check(node.presenceDetectedSensorModel!.publish?.publicationAddress.address == sensorAddress)
            check(!HDBDeviceSyncService.needsSync(node: node))
        }
    }
    static func testEmptyTargetAndPersistence() throws {
        let (space, network, node, service) = try fixture()
        try service.setLightingZones(nodeUuid: node.uuid, zoneIds: [1]); finishAll(service)
        try service.setLightingZones(nodeUuid: node.uuid, zoneIds: [])
        let handles = SyncExecutionEnvironment.batches[0].handles
        check(handles.count == 5 && handles.allSatisfy { $0.message is ConfigModelSubscriptionDeleteAll })
        check(handles.map { $0.message.parameters.count }.sorted() == [4, 4, 4, 4, 6])
        SyncExecutionEnvironment.finishFirst(failIndex: 2)
        let reopened = HDBLightingZoneService(site: SiteData(), space: space.copy())
        let pending = try reopened.getLightingZones(nodeUuid: node.uuid)
        check(pending.lightingZones.isEmpty && pending.lightingZonesStatus == .pending && HDBDeviceSyncService.needsSync(node: node))
        // A success status for a nonzero address must not count as DeleteAll's ACK.
        try reopened.retry(nodeUuid: node.uuid)
        let batch = SyncExecutionEnvironment.batches.removeFirst()
        for handle in batch.handles {
            var data = handle.message.parameters; data.insert(contentsOf: [1, 0xC0], at: 2)
            batch.success?(handle, ConfigModelSubscriptionStatus(ConfigModelSubscriptionAdd(parameters: data)!, success: true))
        }
        batch.finished?(batch.handles)
        try check(reopened.getLightingZones(nodeUuid: node.uuid).lightingZonesStatus == .pending)
        for failNode in [true, false] {
            try reopened.retry(nodeUuid: node.uuid)
            if failNode { Node.failSave = true } else { SpaceData.failSave = true }
            SyncExecutionEnvironment.finishFirst()
            Node.failSave = false; SpaceData.failSave = false
            try check(reopened.getLightingZones(nodeUuid: node.uuid).lightingZonesStatus == .pending)
        }
        try reopened.retry(nodeUuid: node.uuid); finishAll(reopened)
        check(node.elements.flatMap(\.models).allSatisfy { $0.subscriptions.isEmpty })
        check(!HDBDeviceSyncService.needsSync(node: node))
        let directory = space.hdb!.lightingZones
        try HDBConfigurationStore.removeDevice(space: space, nodeUuid: node.uuid)
        check(space.hdb!.devices.isEmpty && space.hdb!.lightingZones == directory && network.groups.count == 2)
    }
    static func testInvalidatedReceipts() throws {
        for change in 0..<8 {
            let (space, network, node, service) = try fixture()
            try service.setLightingZones(nodeUuid: node.uuid, zoneIds: [1])
            switch change {
            case 0: node.primaryUnicastAddress = 2; node.elements[0].unicastAddress = 2
            case 1: node.deviceKey = Data([9])
            case 2: network.nodes = [Node(uuid: node.uuid)]
            case 3:
                let replacement = MeshNetwork(); replacement.nodes = [Node(uuid: node.uuid, address: 2)]; MeshNetwork.saved = replacement
            case 4:
                try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingZones = [.init(zoneId: 2)] }
                try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingZones = [.init(zoneId: 1)] }
            case 5: node.elements[0].models.removeLast()
            case 6: service.cancel()
            default: SpaceData.persisted!.canEditing = false
            }
            SyncExecutionEnvironment.finishFirst()
            check(!service.isRunning)
            try check(service.getLightingZones(nodeUuid: node.uuid).lightingZonesStatus == .pending, "late ACK cannot complete changed/cancelled intent")
            SpaceData.persisted!.canEditing = true
        }
    }
    static func testPreparationAndAllocation() throws {
        let (space, network, node, service) = try fixture()
        node.preConfiguration.hdbInitializationSignature = nil
        let sends = MeshNetworkManager.preparationSends
        do { try service.setLightingZones(nodeUuid: node.uuid, zoneIds: [1]); fatalError("unprepared Apply accepted") }
        catch HDBLightingError.notPrepared {}
        try service.setLightingZones(nodeUuid: node.uuid, zoneIds: []); finishAll(service)
        check(MeshNetworkManager.preparationSends == sends, "Zone Apply never owns initialization")
        try seedPrepared(space: space, node: node)
        SpaceData.failSave = true
        do { try service.setLightingZones(nodeUuid: node.uuid, zoneIds: [1]); fatalError("failed intent save accepted") } catch {}
        check(SyncExecutionEnvironment.batches.isEmpty)
        do { _ = try HDBConfigurationStore.createZone(space: space, zoneId: 3, name: "Failed"); fatalError("allocation save failure accepted") } catch {}
        SpaceData.failSave = false
        check(network.groups.count == 3 && space.hdb!.lightingZones.count == 2)
        let zone = try HDBConfigurationStore.createZone(space: space, zoneId: 3, name: "Three")
        check(zone.groupAddress == 0xC004)
        let (sensorSpace, _, sensorNode, sensorService) = try fixture(sensor: true)
        try HDBConfigurationStore.update(space: sensorSpace) { $0.devices[0].sensorGroupId = nil }
        try sensorService.setLightingZones(nodeUuid: sensorNode.uuid, zoneIds: [])
        check(SyncExecutionEnvironment.batches.count == 1)
        check(SyncExecutionEnvironment.batches[0].handles.allSatisfy { $0.message is ConfigModelSubscriptionDeleteAll })
        SyncExecutionEnvironment.finishFirst()
        check(SyncExecutionEnvironment.batches.isEmpty && !sensorService.isRunning && sensorService.lastError == nil,
              "null Sensor Group skips that stage, even when Composition has a Sensor Server")
    }
}

func finishAll(_ service: HDBLightingZoneService) {
    while service.isRunning {
        precondition(!SyncExecutionEnvironment.batches.isEmpty, "running plan must have an active batch")
        SyncExecutionEnvironment.finishFirst()
    }
}
