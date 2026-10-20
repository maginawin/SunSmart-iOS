import Foundation

@main enum HDBDeviceSyncServiceTests {
    static func fixture(sensor: Bool = true) -> (SpaceData, MeshNetwork, Node) {
        SpaceData.siblings = []; SpaceConfigurationSafety.journal = .init()
        SiteData.hdbEnabled = true; SpaceData.failSave = false; GroupInfo.failAddress = nil; Group.failAddress = nil
        Node.PreConfiguration.failSave = false; Node.PreConfiguration.saved = nil
        let space = SpaceData(), network = MeshNetwork(), node = Node()
        node.network = network; network.nodes = [node]
        if sensor {
            let model = Model(0x1100); model.parentElement = node.elements[0]
            node.elements[0].models.append(model)
            node.presenceDetectedSensorModel = model; node.ambientLightSensorModel = model
            node.sensorModelTypes[model] = .init(id: 0x004D)
        }
        space.hdb = .init(); SpaceData.persisted = space.copy()
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        MeshNetworkManager.instance.currentNetworkKey.networkId = "network"
        MeshAPI.allocation = Array(UInt16(0xC001)...0xC100)
        return (space, network, node)
    }
    static func check(_ condition: @autoclosure () throws -> Bool) throws { let result = try condition(); precondition(result) }
    static func main() throws {
        try pendingDevicesRemainVisibleInsideReadContext()
        try sensorPropertySelection()
        try resetAndPendingZoneIntents()
        try zoneReadinessRequiresSensorSubscriptions()
        try publicationTimingRepair()
        let (space, network, node) = fixture()
        let context = try HDBDeviceSyncContext.resolve(space: space, node: node)!
        precondition(HDBDeviceSyncService.needsSync(node: node))
        try HDBDeviceSyncService.prepareIntent(context: context)
        let allocated = try HDBConfigurationStore.load(space: space)
        let address = allocated.devices[0].sensorGroupId!
        precondition(address == 0xC001 && network.groups.count == 1 && allocated.lightingZones.isEmpty)
        precondition(MeshNetworkManager.instance.groups.isEmpty)
        node.elements[0].models[0].subscriptions = [network.groups[0]]
        precondition(node.group == nil && node.configurationGroup == nil)
        node.elements[0].models[0].subscriptions = []
        let plan = try context.plan(in: allocated)
        precondition(plan.publicationTargets.count == 1 && plan.subscriptionTargets.count == 2)
        try check(HDBDeviceSyncService.makeSteps(context: context).count == HDBDeviceSyncService.pendingLinks(context: context, plan: plan).count + 1 + context.zoneOperations(in: allocated).count)
        try seedPrepared(space: space, node: node)
        precondition(!HDBDeviceSyncService.needsSync(node: node))
        let persisted = SpaceData.persisted!.copy()
        SiteData.hdbEnabled = false
        try check(HDBDeviceSyncContext.resolve(node: node) == nil)
        precondition(!HDBDeviceSyncService.needsSync(node: node))
        HDBDeviceSyncService.prepareIntents(nodes: [node])
        precondition(SpaceData.persisted!.hdb == persisted.hdb && !context.isCurrent())
        SiteData.hdbEnabled = true
        let wrong = space.copy(); wrong.meshUUID = UUID().uuidString
        do { _ = try HDBDeviceSyncContext.resolve(space: wrong, node: node); fatalError("wrong ownership accepted") } catch {}
        node.deviceKey = Data([2]); precondition(!context.isCurrent())
        let current = try HDBDeviceSyncContext.resolve(node: node)!
        UserData.currentUserId = "replacement"; precondition(!current.isCurrent()); UserData.currentUserId = "user"
        // Retire source, retain until the receiver cleanup is acknowledged.
        let peer = Node(address: 2); peer.network = network; network.nodes.append(peer)
        peer.elements[0].models[0].subscriptions = [network.groups[0]]
        network.nodes.removeAll { $0 === node }
        SpaceConfigurationSafety.journal.entries = [.init(nodeUUID: node.uuid.uuidString)]
        try HDBConfigurationStore.removeDevice(space: space, nodeUuid: node.uuid)
        try HDBConfigurationStore.finishSensorGroupCleanup(space: space)
        precondition(SpaceConfigurationSafety.journal.entries[0].sensorGroupId == address && !HDBConfigurationStore.availableLightingZoneAddresses(meshUUID: space.meshUUID).contains(address))
        guard case .devices(let peers) = HDBDeviceSyncService.deletionSyncType(datas: []) else { fatalError("cleanup missing from ordinary Sync") }
        precondition(peers.map(\.uuid) == [peer.uuid])
        let receiver = try HDBDeviceSyncContext.resolve(node: peer, allowNonLights: true)!
        try check(HDBDeviceSyncService.cleanupOperations(context: receiver, config: space.hdb!).count == 1)
        peer.elements[0].models[0].subscriptions = []
        network.nodes = [] // Last-node deletion must still permit local address reclamation.
        Group.failAddress = address
        do { try HDBConfigurationStore.finishSensorGroupCleanup(space: space); fatalError("failed delete ignored") } catch {}
        precondition(SpaceConfigurationSafety.journal.entries[0].sensorGroupId == address)
        Group.failAddress = nil
        try HDBConfigurationStore.finishSensorGroupCleanup(space: space)
        try HDBConfigurationStore.finishSensorGroupCleanup(space: space)
        precondition(SpaceConfigurationSafety.journal.entries[0].sensorGroupId == nil && network.groups.isEmpty)
        precondition(HDBConfigurationStore.availableLightingZoneAddresses(meshUUID: space.meshUUID).first == address)
        // Interrupted Group registration resumes the same reservation.
        let (second, secondNetwork, secondNode) = fixture()
        let secondContext = try HDBDeviceSyncContext.resolve(node: secondNode)!
        Group.failAddress = 0xC001
        do { try HDBDeviceSyncService.prepareIntent(context: secondContext); fatalError("failed Group save ignored") } catch {}
        var saved = try HDBConfigurationStore.load(space: second)
        precondition(saved.devices[0].sensorGroupId == nil && secondNetwork.groups.count == 1)
        Group.failAddress = nil
        try HDBDeviceSyncService.prepareIntent(context: secondContext)
        saved = try HDBConfigurationStore.load(space: second)
        precondition(saved.devices[0].sensorGroupId == 0xC001 && secondNetwork.groups.count == 1)
        try HDBConfigurationStore.restoreDevice(space: second, nodeUuid: secondNode.uuid, nodeAddress: 1, mac: "AABBCCDDEEFF")
        precondition(second.hdb!.devices[0].lightingConfiguration?.brightIntensity?.status == .pending && second.hdb!.devices[0].sensorGroupId == 0xC001)
        // Ordinary virtual Groups in another Space occupy the shared Site pool.
        let (_, sharedNetwork, sharedNode) = fixture()
        let siblingGroup = Group(0xC001); siblingGroup.isVirtual = true; siblingGroup.subNetworkId = "another-subnet"
        sharedNetwork.groups = [siblingGroup]
        try HDBDeviceSyncService.prepareIntent(context: HDBDeviceSyncContext.resolve(node: sharedNode)!)
        precondition(sharedNetwork.groups.map { $0.address.address } == [0xC001, 0xC002])
        // Group deletion followed by a Space write failure must not let old cleanup
        // touch a newly allocated Group at that address.
        let (reclaimedSpace, reclaimedNetwork, reclaimedNode) = fixture()
        try seedPrepared(space: reclaimedSpace, node: reclaimedNode)
        let reclaimedAddress = reclaimedSpace.hdb!.devices[0].sensorGroupId!
        SpaceConfigurationSafety.journal.entries = [.init(nodeUUID: reclaimedNode.uuid.uuidString)]
        reclaimedNetwork.nodes = []
        try HDBConfigurationStore.removeDevice(space: reclaimedSpace, nodeUuid: reclaimedNode.uuid)
        SpaceData.failSave = true
        do { try HDBConfigurationStore.finishSensorGroupCleanup(space: reclaimedSpace); fatalError("dirty write failure ignored") } catch {}
        SpaceData.failSave = false
        let newOwner = Node(); newOwner.network = reclaimedNetwork
        let newSensor = Model(0x1100); newSensor.parentElement = newOwner.elements[0]
        newOwner.elements[0].models.append(newSensor); newOwner.presenceDetectedSensorModel = newSensor
        newOwner.sensorModelTypes[newSensor] = .init(id: 0x004D)
        reclaimedNetwork.nodes = [newOwner]
        try seedPrepared(space: reclaimedSpace, node: newOwner)
        precondition(reclaimedSpace.hdb!.devices[0].sensorGroupId == reclaimedAddress)
        try check(HDBConfigurationStore.pendingSensorGroupAddresses(space: reclaimedSpace).isEmpty)
        try HDBConfigurationStore.finishSensorGroupCleanup(space: reclaimedSpace)
        precondition(reclaimedNetwork.groups.count == 1 && newSensor.publish?.publicationAddress.address == reclaimedAddress)
        precondition(SpaceConfigurationSafety.journal.entries[0].sensorGroupId == nil)
        // Address exhaustion remains recoverable and does not invent a destination.
        let (empty, _, noAddress) = fixture(); MeshAPI.allocation = []
        do { try HDBDeviceSyncService.prepareIntent(context: HDBDeviceSyncContext.resolve(node: noAddress)!); fatalError("exhaustion accepted") }
        catch HDBConfigurationError.addressUnavailable {}
        try check(HDBConfigurationStore.load(space: empty).devices[0].sensorGroupId == nil)
        precondition(HDBDeviceSyncService.needsSync(node: noAddress))
        let (plain, _, noSensor) = fixture(sensor: false)
        try seedPrepared(space: plain, node: noSensor)
        precondition(plain.hdb!.devices[0].sensorGroupId == nil && MeshNetworkManager.instance.meshNetwork!.groups.isEmpty)
        precondition(!HDBDeviceSyncService.needsSync(node: noSensor))
        // Only Presence publishes, even when Ambient uses another Sensor Server.
        let (dualSpace, _, dualNode) = fixture()
        let luxElement = Element(); luxElement.unicastAddress = 3
        let lux = Model(0x1100); lux.parentElement = luxElement; luxElement.models = [lux]
        dualNode.elements.append(luxElement); dualNode.ambientLightSensorModel = lux
        dualNode.sensorModelTypes[lux] = .init(id: 0x004E)
        let dualContext = try HDBDeviceSyncContext.resolve(space: dualSpace, node: dualNode)!
        try HDBDeviceSyncService.prepareIntent(context: dualContext)
        let dualPlan = try dualContext.plan(in: HDBConfigurationStore.load(space: dualSpace))
        precondition(dualPlan.publicationTargets.count == 1 && dualPlan.publicationTargets[0].elementAddress == 1 && dualPlan.sensorGroupId != nil)
        precondition(dualPlan.subscriptionTargets.count == 3)
        let (luxSpace, _, luxNode) = fixture()
        luxNode.presenceDetectedSensorModel = nil
        luxNode.sensorModelTypes[luxNode.ambientLightSensorModel!] = .init(id: 0x004E)
        let luxContext = try HDBDeviceSyncContext.resolve(space: luxSpace, node: luxNode)!
        try HDBDeviceSyncService.prepareIntent(context: luxContext)
        let luxPlan = try luxContext.plan(in: HDBConfigurationStore.load(space: luxSpace))
        precondition(luxPlan.publicationTargets.isEmpty && luxPlan.sensorGroupId != nil && luxPlan.subscriptionTargets.count == 2)
        print("PASS: actual HDB context/planner/store: Site isolation, empty Zone, sensor dedup, identity invalidation, allocation retry/exhaustion, restore, receiver cleanup and address reuse")
    }

    static func sensorPropertySelection() throws {
        for property: UInt16? in [nil, 0, 0x004E, 0x0072] {
            let (space, network, node) = fixture()
            let sensor = node.presenceDetectedSensorModel!
            // A stale convenience getter must not substitute for the property map.
            node.sensorModelTypes = property.map { [sensor: TestSensorProperty(id: $0)] } ?? [:]
            let context = try HDBDeviceSyncContext.resolve(node: node)!
            try HDBDeviceSyncService.prepareIntent(context: context)
            let config = try HDBConfigurationStore.load(space: space)
            let plan = try context.plan(in: config)
            precondition(plan.sensorGroupId != nil && network.groups.count == 1)
            precondition(plan.publicationTargets.isEmpty && plan.subscriptionTargets.count == 2)
            precondition(HDBDeviceSyncService.pendingLinks(context: context, plan: plan).allSatisfy {
                if case .subscription = $0 { return true }; return false
            })
            try seedPrepared(space: space, node: node)
            try check(HDBDeviceSyncService.isPrepared(context: context, config: HDBConfigurationStore.load(space: space)))
            precondition(!HDBDeviceSyncService.needsSync(node: node), "unknown properties must not add an HDB pending publication")
            precondition(sensor.publish == nil)
            // Preserve the SDK's separate standard provisioning checks.
            precondition(node.isKeybindComplete == (property != nil))
        }

        let (space, _, node) = fixture()
        let presence = node.presenceDetectedSensorModel!
        let secondary = Element(); secondary.unicastAddress = 2
        let unknown = Model(0x1100); unknown.parentElement = secondary; secondary.models = [unknown]
        node.elements.append(secondary)
        let context = try HDBDeviceSyncContext.resolve(node: node)!
        try HDBDeviceSyncService.prepareIntent(context: context)
        try check(context.plan(in: HDBConfigurationStore.load(space: space)).publicationTargets.isEmpty)
        try seedPrepared(space: space, node: node)
        precondition(!HDBDeviceSyncService.needsSync(node: node))

        // Fresh property evidence selects its element, not a stale cached Presence model.
        node.sensorModelTypes[presence] = .init(id: 0x004E)
        node.sensorModelTypes[unknown] = .init(id: 0x004D)
        let selected = try context.plan(in: HDBConfigurationStore.load(space: space))
        precondition(selected.publicationTargets.count == 1 && selected.publicationTargets[0].elementAddress == 2)
        node.sensorModelTypes[presence] = .init(id: 0x004D)
        do {
            _ = try context.plan(in: HDBConfigurationStore.load(space: space))
            fatalError("ambiguous Presence instances must not select an arbitrary element")
        } catch HDBConfigurationError.unsupportedModels {}

        let (vendorSpace, vendorNetwork, vendorNode) = fixture(sensor: false)
        let vendor = Model(0x1100, company: 0x0A78); vendor.parentElement = vendorNode.elements[0]
        vendorNode.elements[0].models.append(vendor)
        let vendorContext = try HDBDeviceSyncContext.resolve(node: vendorNode)!
        try HDBDeviceSyncService.prepareIntent(context: vendorContext)
        let vendorPlan = try vendorContext.plan(in: HDBConfigurationStore.load(space: vendorSpace))
        precondition(vendorPlan.sensorGroupId == nil && vendorNetwork.groups.isEmpty && vendorPlan.publicationTargets.isEmpty)
    }

    static func resetAndPendingZoneIntents() throws {
        for sensor in [false, true] {
            let (space, _, node) = fixture(sensor: sensor)
            let context = try HDBDeviceSyncContext.resolve(node: node)!
            // A signature write failure must not erase the persisted empty reset baseline.
            Node.PreConfiguration.failSave = true
            do {
                try HDBDeviceSyncService.prepareIntent(context: context, subscriptionsWereReset: true)
                preconditionFailure("signature save failure ignored")
            } catch HDBConfigurationError.persistenceFailed {}
            Node.PreConfiguration.failSave = false
            try check(HDBConfigurationStore.load(space: space).devices[0].lightingZonesStatus == .synced)
            let reopened = try HDBDeviceSyncContext.resolve(space: space.copy(), node: node)!
            try HDBDeviceSyncService.prepareIntent(context: reopened)
            var config = try HDBConfigurationStore.load(space: space)
            precondition(config.devices[0].lightingZones.isEmpty)
            try check(context.zoneOperations(in: config).isEmpty)
            // An ordinary signature refresh must preserve a real user-requested clear.
            try HDBConfigurationStore.update(space: space) { $0.devices[0].lightingZonesStatus = .pending }
            node.preConfiguration.hdbInitializationSignature = nil
            try HDBDeviceSyncService.prepareIntent(context: context)
            config = try HDBConfigurationStore.load(space: space)
            precondition(config.devices[0].lightingZonesStatus == .pending)
            try check(!context.zoneOperations(in: config).isEmpty)
            // Reprovisioning an existing device restores its saved nonempty Zone target.
            _ = try HDBConfigurationStore.createZone(space: space, zoneId: 1, name: "One")
            try HDBConfigurationStore.update(space: space) {
                $0.devices[0].lightingZones = [.init(zoneId: 1)]
                $0.devices[0].lightingZonesStatus = .synced
            }
            try HDBDeviceSyncService.prepareIntent(context: context, subscriptionsWereReset: true)
            config = try HDBConfigurationStore.load(space: space)
            precondition(config.devices[0].lightingZones.map(\.zoneId) == [1] && config.devices[0].lightingZonesStatus == .pending)
            try check(!context.zoneOperations(in: config).isEmpty)
        }
    }

    static func zoneReadinessRequiresSensorSubscriptions() throws {
        let (space, _, node) = fixture()
        try seedPrepared(space: space, node: node)
        let context = try HDBDeviceSyncContext.resolve(node: node)!
        let config = try HDBConfigurationStore.load(space: space)
        let sensor = node.presenceDetectedSensorModel!
        let subscriptions = sensor.subscriptions
        sensor.subscriptions = []
        try check(!HDBDeviceSyncService.isPrepared(context: context, config: config))
        try check(!HDBDeviceSyncService.canSetZones(context: context, config: config))
        sensor.subscriptions = subscriptions
        let lc = node.elements.flatMap(\.models).first { $0.modelIdentifier == 0x130F }!
        lc.subscriptions = []
        try check(!HDBDeviceSyncService.isPrepared(context: context, config: config))
        try check(HDBDeviceSyncService.canSetZones(context: context, config: config))
    }

    static func publicationTimingRepair() throws {
        let (space, network, node) = fixture()
        // Other devices in the Space are not members of this device's private sensor group.
        for address: UInt16 in 2...5 {
            let other = Node(address: address); other.network = network; network.nodes.append(other)
        }
        try seedPrepared(space: space, node: node)
        let context = try HDBDeviceSyncContext.resolve(node: node)!
        let config = try HDBConfigurationStore.load(space: space)
        let plan = try context.plan(in: config)
        let sensor = node.presenceDetectedSensorModel!
        let expected = sensor.publish!
        let signature = node.preConfiguration.hdbInitializationSignature
        precondition(expected.period == .disabled && expected.retransmit.count == 2 && expected.retransmit.interval == 100)
        for retransmit in [Publish.Retransmit.disabled, .init(1, timesWithInterval: 0.1), .init(2, timesWithInterval: 0.05)] {
            var old = expected; old.retransmit = retransmit; sensor.publish = old
            precondition(HDBDeviceSyncService.pendingLinks(context: context, plan: plan) == [.publication(plan.publicationTargets[0])])
            precondition(HDBDeviceSyncService.needsSync(node: node))
            try check(!HDBDeviceSyncService.canSetZones(context: context, config: config))
            try HDBDeviceSyncService.prepareIntent(context: context)
            let steps = try HDBDeviceSyncService.makeSteps(context: context)
            precondition(steps.count == 1 && node.preConfiguration.hdbInitializationSignature == signature,
                         "repairing publication timing must not reinitialize LC or rebuild empty Zones")
        }
        var periodic = expected; periodic.period = .periodic; sensor.publish = periodic
        precondition(HDBDeviceSyncService.pendingLinks(context: context, plan: plan) == [.publication(plan.publicationTargets[0])])
        sensor.publish = expected
        precondition(!HDBDeviceSyncService.needsSync(node: node))
        try check(HDBDeviceSyncService.makeSteps(context: context).isEmpty)
    }

    static func pendingDevicesRemainVisibleInsideReadContext() throws {
        let (space, network, first) = fixture()
        let nodes = [first] + (2...4).map { Node(address: UInt16($0)) }
        network.nodes = nodes
        nodes.forEach { $0.network = network }
        HDBDeviceSyncService.prepareIntents(nodes: nodes)
        precondition(nodes.allSatisfy { HDBDeviceSyncService.needsSync(node: $0) })
        NodeSyncReadContext.current = NodeSyncReadContext()
        defer { NodeSyncReadContext.current = nil }
        precondition(nodes.allSatisfy { HDBDeviceSyncService.needsSync(node: $0) },
                     "Lights read context must retain all four pending HDB devices")
        NodeSyncReadContext.current = nil
        for node in nodes { try seedPrepared(space: space, node: node) }
        // A new refresh must discard the old pending snapshot after completion.
        NodeSyncReadContext.current = NodeSyncReadContext()
        precondition(nodes.allSatisfy { !HDBDeviceSyncService.needsSync(node: $0) })
        SiteData.hdbEnabled = false
        NodeSyncReadContext.current = NodeSyncReadContext()
        precondition(nodes.allSatisfy { !HDBDeviceSyncService.needsSync(node: $0) }, "ordinary Sites must stay unchanged")
    }
}
