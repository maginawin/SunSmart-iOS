import Foundation

/// Production add coordinator, Store, task planning and ACK persistence run together.
/// The test drives Session/radio callbacks; full Session lifecycle has its own suite.
@main enum HDBDeviceAddExecutionTests {
    static func fixture() -> (SpaceData, Node) {
        SiteData.hdbEnabled = true; SpaceData.failSave = false
        SpaceData.siblings = []; SpaceConfigurationSafety.journal = .init()
        Node.PreConfiguration.failSave = false; Node.PreConfiguration.saved = nil
        SyncExecutionSession.started = []; CloudSynchronizationManager.shared.snapshots = []
        let space = SpaceData(), network = MeshNetwork(), node = Node()
        HDBSubelementFixture.configure(node)
        let energy = Model(0x1100); energy.parentElement = node.elements[2]
        node.elements[2].models.append(energy); node.sensorModelTypes[energy] = .init(id: 0x0072)
        network.nodes = [node]; node.network = network; network.scenes = [1, 2]
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        MeshNetworkManager.instance.currentNetworkKey.networkId = "network"
        space.hdb = .init(); space.sceneCount = 9; space.scheheduleCount = 9; space.switchesCount = 9
        SpaceData.persisted = space.copy()
        return (space, node)
    }

    static func acknowledge(_ task: HDBDeviceSyncTask, handles: [MeshMessageHandle]) {
        for handle in handles {
            handle.isSuccessful = true
            if handle.message is ConfigModelSubscriptionAdd || handle.message is ConfigModelSubscriptionOverwrite || handle.message is ConfigModelSubscriptionDeleteAll {
                SyncExecutionEnvironment.applySubscription(handle)
                task.receive(handle: handle, response: ConfigModelSubscriptionStatus(handle.message, success: true))
            } else if let request = handle.message as? ConfigModelPublicationSet {
                request.model.publish = request.publication
                task.receive(handle: handle, response: ConfigModelPublicationStatus(request, success: true))
            } else { task.receive(handle: handle, response: handle.message) }
        }
    }

    static func main() throws {
        let (space, node) = fixture()
        let completion = HDBDeviceAddCompletion()
        var results: [Set<UUID>] = []
        completion.run(space: space, nodes: [node], standardIncomplete: []) { results.append($0) }
        let session = SyncExecutionSession.started.last!
        precondition(results.isEmpty && session.sections.count == 6,
                     "LC plus three Sensor subscriptions, Presence publication and initialization must precede completion")
        precondition(space.hdb!.devices[0].lightingZonesStatus == .synced)
        var completedSteps = Set<ObjectIdentifier>()
        for (index, step) in session.sections.enumerated() {
            precondition(step.relevanceStepModels.allSatisfy { completedSteps.contains(ObjectIdentifier($0)) })
            guard case .configuration(_, .hdb(let task)) = step.tasks[0].operationType else { fatalError() }
            precondition(!task.isLightingZoneOperation, "freshly provisioned empty Zones must not be rebuilt")
            let handles = task.makeHandles()
            precondition(!handles.isEmpty)
            precondition(handles.allSatisfy {
                $0.message is ConfigModelSubscriptionAdd || $0.message is ConfigModelPublicationSet
                    || $0.message is LightLCModeSet || $0.message is PreparationMessage || $0.message is LightingTestMessage
            }, "adding a device must only write preparation values, without subscription resets or readbacks")
            if index == 0 {
                // Release an upload's local cleanup while the first ACK is in flight.
                // Real cleanup advances the Space revision when its summary is stale.
                let upload = CloudSynchronizationManager.shared.snapshots.last!
                if upload.deviceCount != 1 || upload.luminairesCount != 1 {
                    SpaceData.persisted!.deviceCount = 1; SpaceData.persisted!.luminairesCount = 1
                    SpaceData.persisted!.lastUpdate += 1
                }
            }
            acknowledge(task, handles: handles)
            precondition(task.persist(result: handles), "own upload cleanup must not invalidate a successful preparation ACK")
            completedSteps.insert(ObjectIdentifier(step))
        }
        session.onSettled?(.syncSuccess)
        precondition(results == [Set<UUID>()] && !completion.isRunning)
        precondition(!HDBDeviceSyncService.needsSync(node: node))
        precondition(node.presenceDetectedSensorModel?.publish?.publicationAddress.address == space.hdb?.devices[0].sensorGroupId)
        precondition(node.ambientLightSensorModel?.publish == nil, "HDB add must not configure Ambient publication")
        let sensors = node.elements.flatMap(\.models).filter { $0.modelIdentifier == 0x1100 && $0.companyIdentifier == nil }
        let sensorGroupId = space.hdb!.devices[0].sensorGroupId!
        precondition(sensors.count == 3 && sensors.allSatisfy { $0.subscriptions.map { $0.address.address } == [sensorGroupId] })
        precondition(sensors.filter { $0 !== node.presenceDetectedSensorModel }.allSatisfy { $0.publish == nil })
        precondition(CloudSynchronizationManager.shared.snapshots.allSatisfy { $0.deviceCount == 1 && $0.luminairesCount == 1 },
                     "every HDB upload must carry current counts, including the first intent")
        precondition(CloudSynchronizationManager.shared.snapshots.allSatisfy { $0.sceneCount == 2 && $0.scheheduleCount == 0 && $0.switchesCount == 0 })
        precondition(SpaceData.persisted!.deviceCount == 1 && SpaceData.persisted!.luminairesCount == 1)
        // The current persisted identity must remain ready after a new read context.
        NodeSyncReadContext.current = NodeSyncReadContext()
        precondition(!HDBDeviceSyncService.needsSync(node: node))
        NodeSyncReadContext.current = nil
        let zoneService = HDBLightingZoneService(site: SiteData(), space: space)
        _ = try HDBConfigurationStore.createZone(space: space, zoneId: 1, name: "One")
        let previousSubscriptions = sensors[1].subscriptions
        sensors[1].subscriptions = []
        do {
            try zoneService.setLightingZones(nodeUuid: node.uuid, zoneIds: [1])
            preconditionFailure("Zone Apply must not bypass an incomplete Sensor subscription")
        } catch HDBLightingError.notPrepared {}
        precondition(SyncExecutionEnvironment.batches.isEmpty && space.hdb!.devices[0].lightingZones.isEmpty)
        sensors[1].subscriptions = previousSubscriptions
        try zoneService.setLightingZones(nodeUuid: node.uuid, zoneIds: [1])
        finishZones()
        let device = try zoneService.getLightingZones(nodeUuid: node.uuid)
        precondition(device.lightingZones.map(\.zoneId) == [1] && device.lightingZonesStatus == .synced)
        precondition(sensors.allSatisfy { $0.subscriptions.map { $0.address.address } == [sensorGroupId] })
        try zoneService.setLightingZones(nodeUuid: node.uuid, zoneIds: [])
        precondition(!SyncExecutionEnvironment.batches.isEmpty, "a user-requested clear must still rebuild subscriptions")
        finishZones()
        let cleared = try zoneService.getLightingZones(nodeUuid: node.uuid)
        precondition(cleared.lightingZones.isEmpty && cleared.lightingZonesStatus == .synced)
        precondition(sensors.allSatisfy { $0.subscriptions.map { $0.address.address } == [sensorGroupId] })
        precondition(node.isKeybindComplete && !HDBDeviceSyncService.needsSync(node: node))

        // A genuine external revision change must still invalidate the same ACK,
        // whether it happens before receive or between receive and persistence.
        for beforeReceive in [true, false] {
            let (changedSpace, changedNode) = fixture()
            results = []
            completion.run(space: changedSpace, nodes: [changedNode], standardIncomplete: []) { results.append($0) }
            let active = SyncExecutionSession.started.last!
            guard case .configuration(_, .hdb(let task)) = active.sections[0].tasks[0].operationType else { fatalError() }
            let handles = task.makeHandles()
            let originalConfig = SpaceData.persisted!.hdb
            if beforeReceive { SpaceData.persisted!.lastUpdate += 1 }
            acknowledge(task, handles: handles)
            if !beforeReceive { SpaceData.persisted!.lastUpdate += 1 }
            precondition(!task.persist(result: handles), "external revision changes must reject stale preparation ACKs")
            precondition(SpaceData.persisted!.hdb == originalConfig)
            active.onSettled?(.syncFailure)
            precondition(results == [[changedNode.uuid]] && HDBDeviceSyncService.needsSync(node: changedNode))
        }

        // Failure before the first intent must keep the new node available for Sync.
        let (failedSpace, failedNode) = fixture()
        SpaceData.failSave = true; results = []
        completion.run(space: failedSpace, nodes: [failedNode], standardIncomplete: []) { results.append($0) }
        precondition(results == [[failedNode.uuid]] && !completion.isRunning)
        precondition(SyncExecutionSession.started.isEmpty && CloudSynchronizationManager.shared.snapshots.isEmpty)
        precondition(failedSpace.hdb!.devices.isEmpty && HDBDeviceSyncService.needsSync(node: failedNode))
        SpaceData.failSave = false
        print("PASS: add completion persists counts before every upload; subscription/publications/initialization enable Zone Apply; external revisions still reject ACKs; summary-save failure remains repairable")
    }

    static func finishZones() {
        while !SyncExecutionEnvironment.batches.isEmpty {
            precondition(SyncExecutionEnvironment.batches[0].handles.allSatisfy {
                $0.message is ConfigModelSubscriptionAdd || $0.message is ConfigModelSubscriptionOverwrite
                    || $0.message is ConfigModelSubscriptionDeleteAll
            }, "Zone completion must not enqueue readbacks")
            SyncExecutionEnvironment.finishFirst()
        }
    }
}
