import Foundation
@main enum HDBDeviceAddCompletionTests {
    static func main() throws {
        let space = SpaceData(), network = MeshNetwork(), first = Node(), second = Node(address: 2)
        network.nodes = [first, second]; network.nodes.forEach { $0.network = network }
        MeshNetwork.saved = network; MeshNetworkManager.instance.meshNetwork = network
        space.hdb = .init(); SpaceData.persisted = space.copy()
        var completions: [Set<UUID>] = []
        let coordinator = HDBDeviceAddCompletion()
        precondition(HDBDeviceAddCompletion.currentBatchNodes(addresses: [second.primaryUnicastAddress],
            nodes: [first, second]).map(\.uuid) == [second.uuid], "previous batch nodes must not be prepared again")
        let scanned = try HDBDeviceAddCompletion.provisioningMAC("aa-bb-cc-dd-ee-ff", siteId: space.siteId)
        precondition(scanned == "AABBCCDDEEFF")
        do { _ = try HDBDeviceAddCompletion.provisioningMAC(nil, siteId: space.siteId); fatalError("HDB random MAC fallback allowed") }
        catch HDBConfigurationError.invalidMAC {}
        SiteData.hdbEnabled = false
        let ordinaryMAC = try HDBDeviceAddCompletion.provisioningMAC(nil, siteId: space.siteId)
        precondition(ordinaryMAC == nil)
        let ordinaryScanned = try HDBDeviceAddCompletion.provisioningMAC("112233445566", siteId: space.siteId)
        precondition(ordinaryScanned == nil, "ordinary callbacks keep using their latest scanner value")
        coordinator.run(space: space, nodes: [first, second], standardIncomplete: [first.uuid]) { completions.append($0) }
        precondition(completions == [[first.uuid]] && SyncExecutionSession.started.isEmpty && space.hdb!.devices.isEmpty)
        SiteData.hdbEnabled = true; completions = []
        coordinator.run(space: space, nodes: [first, second], standardIncomplete: [first.uuid]) { completions.append($0) }
        precondition(completions.isEmpty && coordinator.isRunning)
        precondition(space.hdb!.devices.map(\.nodeUuid) == [second.uuid], "standard failure must not prepare")
        try seedPrepared(space: space, node: second)
        let active = SyncExecutionSession.started.last!
        precondition(!active.publishesCloudChange)
        let lateCompletion = active.onSettled!
        active.onSettled?(.syncSuccess)
        precondition(completions == [[first.uuid]] && !coordinator.isRunning)
        lateCompletion(.syncSuccess)
        precondition(completions.count == 1)
        completions = []
        coordinator.run(space: space, nodes: [first], standardIncomplete: []) { completions.append($0) }
        precondition(completions.isEmpty && coordinator.isRunning)
        lateCompletion(.syncSuccess)
        precondition(completions.isEmpty && coordinator.isRunning, "old batch callback cannot end the new batch")
        let cancelled = SyncExecutionSession.started.last!.onSettled!
        coordinator.cancel(); cancelled(.syncSuccess)
        precondition(completions == [[first.uuid]] && HDBDeviceSyncService.needsSync(node: first))
        // No handles/transport success cannot disguise a missing durable receipt.
        completions = []
        coordinator.run(space: space, nodes: [first], standardIncomplete: []) { completions.append($0) }
        SyncExecutionSession.started.last!.onSettled?(.syncSuccess)
        precondition(completions == [[first.uuid]])
        // Intent persistence failure is a partial add, never another provisioning attempt.
        completions = []; SpaceData.failSave = true
        let third = Node(address: 3); third.network = network; network.nodes.append(third)
        coordinator.run(space: space, nodes: [third], standardIncomplete: []) { completions.append($0) }
        precondition(completions == [[third.uuid]] && !coordinator.isRunning)
        SpaceData.failSave = false
        // Missing MAC cannot persist a half HDB record, and supplying it makes retry possible.
        completions = []
        third.macAddress = nil
        let beforeMissing = space.hdb
        let taskCount = SyncExecutionSession.started.count
        coordinator.run(space: space, nodes: [third], standardIncomplete: []) { completions.append($0) }
        precondition(completions == [[third.uuid]] && !coordinator.isRunning)
        precondition(space.hdb == beforeMissing && SyncExecutionSession.started.count == taskCount)
        third.macAddress = "112233445566"
        completions = []
        coordinator.run(space: space, nodes: [third], standardIncomplete: []) { completions.append($0) }
        precondition(coordinator.isRunning && completions.isEmpty)
        precondition(space.hdb?.devices.first { $0.nodeUuid == third.uuid }?.mac == "11:22:33:44:55:66")
        try seedPrepared(space: space, node: third)
        SyncExecutionSession.started.last!.onSettled?(.syncSuccess)
        precondition(completions == [[]] && !coordinator.isRunning)
        third.macAddress = "112233445577"
        try HDBConfigurationStore.restoreDevice(space: space, nodeUuid: third.uuid, nodeAddress: 3, mac: third.macAddress)
        precondition(space.hdb?.devices.first { $0.nodeUuid == third.uuid }?.mac == "11:22:33:44:55:77")
        var detached: HDBDeviceAddCompletion? = HDBDeviceAddCompletion()
        weak var lifetime = detached
        var detachedFinished = false
        detached?.run(space: space, nodes: [third], standardIncomplete: []) { _ in detachedFinished = true }
        detached = nil
        precondition(lifetime != nil && !detachedFinished, "controller release must not drop stop/settlement ownership")
        SyncExecutionSession.started.last!.onStopped?()
        precondition(lifetime == nil && detachedFinished)
        print("PASS: actual add-completion coordinator with transport boundary: standard bypass, dependency failure, deferred final callback, partial success, cancel, late callback and durable-readiness gate")
    }
}
