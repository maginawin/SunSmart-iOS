import Foundation

enum UserData { static var currentUserId = "test", currentServerRegion = "region" }
final class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    enum Operation { case syncSpace(space: SpaceData) }
    enum Level { case normal }
    func cancelSynchronizationHandle(space: SpaceData) {}
    func addSynchronizationHandle(operation: Operation, level: Level) {}
}

extension ScopedImportTests {
    static func testSiteDeviceOwnership() throws {
        typealias P = SiteDeviceOwnershipPolicy
        require(P.normalizedMAC("aa:bb:cc:dd:ee:ff") == "AABBCCDDEEFF", "normalize MAC separators and case")
        for mac in ["", "000000000000", "FFFFFFFFFFFF", "not-a-mac"] {
            require(P.normalizedMAC(mac) == nil, "invalid identity cannot cause deletion")
        }
        let old = P.Instance(siteId: "S", spaceId: "A", networkId: "A", uuid: "same", address: 2, created: 10, mac: "AABBCCDDEEFF")
        let latest = P.Instance(siteId: "S", spaceId: "B", networkId: "B", uuid: "same", address: 70, created: 20, mac: old.mac)
        let otherSite = P.Instance(siteId: "OTHER", spaceId: "C", networkId: "C", uuid: "same", address: 2, created: 1, mac: old.mac)
        require(P.removals([latest, otherSite, old]).map(\.old) == [old], "latest owns only this Site's MAC")
        let tie = P.Instance(siteId: "S", spaceId: "B", networkId: "B", uuid: "same", address: 70, created: 10, mac: old.mac)
        require(P.removals([old, tie]).isEmpty, "timestamp ties need explicit provisioning evidence")
        require(P.removals([old, tie], preferred: tie).map(\.old) == [old], "local provisioning breaks a same-second tie")

        let prior = try fixture(networkId: "OWNERSHIP-OLD")
        let unrelated = try fixture(networkId: "OWNERSHIP-OTHER")
        prior.nodes[0].macAddress = "AA:BB:CC:DD:EE:FF"
        prior.nodes[0].createdTimestamp = 10
        let extra = Element(3); extra.parentNode = prior.nodes[0]; prior.nodes[0].elements.append(extra)
        prior.network.scenes = [Scene([2, 3, 5])]
        let scheduler = Schedule(); scheduler.nodeAddresses = [2, 3, 5]; scheduler.needDeleteNodeAddresses = [3, 5]
        Schedule.stored[prior.space.meshUUID + prior.space.meshNetworkId] = [scheduler]
        unrelated.nodes[0].macAddress = prior.nodes[0].macAddress

        let network = MeshNetwork(prior.network.uuid)
        let space = SpaceData(network: network, networkId: "OWNERSHIP-NEW")
        let data: [String: Any] = ["uuid": prior.nodes[0].uuid, "unicastAddress": "0046", "elements": [["models": []]]]
        let winner = try jsonDecoder.decode(Node.self, from: JSONSerialization.data(withJSONObject: data))
        winner.network = network; winner.subNetworkId = space.meshNetworkId; winner.macAddress = "aabbccddeeff"; winner.createdTimestamp = 10
        network.nodes = [winner]
        MeshNetwork.stored[space.meshUUID + space.meshNetworkId] = network
        SpaceData.stored[space.meshUUID + space.meshNetworkId] = space
        MeshNetworkManager.instance.meshNetwork = network
        MeshNetworkManager.instance.currentNetworkKey = .init(networkId: space.meshNetworkId)

        prior.nodes[0].deletionFails = true
        let first = SiteDeviceOwnershipReconciler.reconcile(siteId: prior.space.siteId,
            preferred: SiteDeviceOwnershipReconciler.instance(winner, space: space))
        require(first.isEmpty && prior.network.nodes.count == 2, "failed storage removal remains retryable")
        require(SpaceConfigurationSafety.hasPendingDeletionCleanup(prior.space), "persist replacement evidence before removal")
        prior.nodes[0].deletionFails = false
        let changed = SiteDeviceOwnershipReconciler.reconcile(siteId: prior.space.siteId)
        require(changed == [prior.space.id], "background cleanup targets old Space")
        require(prior.network.nodes.count == 1 && network.nodes.count == 1 && unrelated.network.nodes.count == 2, "keep winner, peer and other Site")
        require(MeshNetworkManager.instance.meshNetwork === network, "never switch active network")
        require(prior.network.scenes[0].addresses == [5], "Scene primary and secondary elements removed")
        require(scheduler.nodeAddresses == [5] && scheduler.needDeleteNodeAddresses == [5], "Scheduler active and pending elements removed")
        require(prior.group.info.proximityLightingPath!.paths[0].items[0].address == nil, "Sequence slot cleared")
        require(prior.group.info.proximityLightingPath!.zones[1].addresses == [5], "Group Trigger Zone cleaned")
        require(prior.space.triggerZones[1].items.map(\.deviceAddress) == [5], "Space Trigger Zone cleaned")
        require(prior.network.groups.count == 1 && prior.space.luminairesCount == 1, "retain group and update counts")
        let journal = try SpaceConfigurationSafety.deletionJournal(prior.space)
        require(journal.entries.count == 1 && journal.entries[0].stage == .cleaned && journal.entries[0].replacement?.spaceId == space.id, "retain cloud receipt")
        require(SiteDeviceOwnershipReconciler.reconcile(siteId: prior.space.siteId).isEmpty, "repeated reconciliation is idempotent")
        let thirdNetwork = MeshNetwork(prior.network.uuid)
        let thirdSpace = SpaceData(network: thirdNetwork, networkId: "OWNERSHIP-THIRD")
        var thirdData = data; thirdData["unicastAddress"] = "0049"
        let thirdNode = try jsonDecoder.decode(Node.self, from: JSONSerialization.data(withJSONObject: thirdData))
        thirdNode.network = thirdNetwork; thirdNode.subNetworkId = thirdSpace.meshNetworkId
        thirdNode.macAddress = winner.macAddress; thirdNode.createdTimestamp = 5
        thirdNetwork.nodes = [thirdNode]
        MeshNetwork.stored[thirdSpace.meshUUID + thirdSpace.meshNetworkId] = thirdNetwork
        SpaceData.stored[thirdSpace.meshUUID + thirdSpace.meshNetworkId] = thirdSpace
        MeshNetworkManager.instance.meshNetwork = thirdNetwork
        MeshNetworkManager.instance.currentNetworkKey = .init(networkId: thirdSpace.meshNetworkId)
        SiteDeviceOwnershipReconciler.provisioned(thirdNode, space: thirdSpace)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        require(thirdNode.createdTimestamp == 11 && network.nodes.isEmpty && thirdNetwork.nodes.count == 1,
                "explicit re-provisioning keeps the new instance even after a clock rollback")
        print("PASS: Site MAC ownership, background cleanup, storage retry, Scene/Scheduler/Path/Zone references and Site isolation")
    }
}
