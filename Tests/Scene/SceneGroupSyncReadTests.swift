import Foundation

final class SceneExecuteData {
    enum State { case normal, waitDelete }
    let sceneNumber: UInt16
    var isOn: Bool
    var lightness: UInt16, cct: UInt16
    var hue: UInt16 = 0, saturation: UInt16 = 0, state = State.normal
    let lightControlData: [String: Int]?
    init(sceneNumber: UInt16, isOn: Bool, lightness: UInt16, cct: UInt16, lightControlData: [String: Int]? = nil) {
        self.sceneNumber = sceneNumber; self.isOn = isOn; self.lightness = lightness; self.cct = cct
        self.lightControlData = lightControlData
    }
    // PRODUCTION_SCENE_COMPARISON
}

extension Node {
    func clampEffectiveCct(_ value: UInt16) -> UInt16 {
        min(effectiveCctRange.upperBound, max(effectiveCctRange.lowerBound, value))
    }
}

extension NodeSyncStatusRefreshTests {
    /// Runs the production Scene reader, batching/cancellation and protection
    /// file reader. SDK Scene differences are fixture inputs, not BLE evidence.
    static func sceneGroupSyncReadTests() async {
        let network = fixture(490), session = NSObject()
        network.groups = (0..<17).map { index in
            let group = Group(Address(0xCD60 + index)); group.network = network
            group.info.profile.type = .ordinary
            return group
        }
        for (index, node) in network.nodes.enumerated() {
            node.sunricherVendorModel?.subscribe = [network.groups[index % 17].address.address]
        }
        let scene = Scene(), other = Scene()
        scene.info.groups = network.groups; other.info.groups = network.groups
        MeshNetworkManager.instance.scenes = [scene, other]
        NodeSyncStatusRefresh.beginSession(owner: session)
        defer {
            NodeSyncStatusRefresh.endSession(owner: session)
            Node.onSceneCheck = nil
            AppPerformance.observe(nil)
        }
        let owners = (0..<17).map { _ in NSObject() }
        var fileReads = 0, completed = 0
        AppPerformance.observe { sample in
            if sample.name == "ProtectionFileRead" { fileReads += 1 }
        }
        // Force several main-queue slices so overlapping consumers exercise
        // shared partial progress, rather than only a completed cache hit.
        Node.onSceneCheck = { node in
            if node.primaryUnicastAddress <= 10 { Thread.sleep(forTimeInterval: 0.001) }
        }
        // Seventeen concurrent consumers (including the Scene list) must share
        // partial progress as well as the final group result.
        for owner in owners {
            NodeSyncStatusRefresh.requestSceneGroups(scene: scene, owner: owner) { snapshot in
                require(snapshot?.groups.count == 17 && snapshot?.needsSync.isEmpty == true,
                        "synchronized Scene lost a group or marked it pending")
                completed += 1
            }
        }
        await drain { completed == owners.count }
        Node.onSceneCheck = nil
        require(network.nodes.reduce(0, { $0 + $1.sceneChecks }) == 490,
                "Scene members were checked again for each card/owner")
        require(fileReads == 2, "Scene card/node count multiplied protection file reads")
        var listDone = false
        NodeSyncStatusRefresh.request(scene: scene, owner: owners[0]) { value in
            require(!value, "Scene list disagrees with detail"); listDone = true
        }
        await drain { listDone }
        require(network.nodes.reduce(0, { $0 + $1.sceneChecks }) == 490 && fileReads == 2,
                "Scene list failed to reuse the group result")

        let badNode = network.nodes[31], badGroup = network.groups[31 % 17]
        scene.unsynced = [badNode.primaryUnicastAddress]
        NodeSyncStatusGeneration.invalidate()
        completed = 0
        NodeSyncStatusRefresh.requestSceneGroups(scene: scene, owner: owners[0]) { snapshot in
            require(snapshot?.needsSync == [ObjectIdentifier(badGroup)], "one Scene mismatch affected other groups")
            completed += 1
        }
        NodeSyncStatusRefresh.requestSceneGroups(scene: other, owner: owners[1]) { snapshot in
            require(snapshot?.needsSync.isEmpty == true, "another Scene reused the first Scene's result")
            completed += 1
        }
        await drain { completed == 2 }

        let offNode = network.nodes[7]
        let cachedOff = SceneExecuteData(sceneNumber: 14, isOn: false, lightness: 20000, cct: 6000)
        let targetOff = SceneExecuteData(sceneNumber: 14, isOn: false, lightness: 0, cct: 4500)
        other.comparisons[offNode.primaryUnicastAddress] = (cachedOff, targetOff)
        NodeSyncStatusGeneration.invalidate()
        var offDone = false
        NodeSyncStatusRefresh.requestSceneGroups(scene: other, owner: owners[0]) { snapshot in
            require(snapshot?.needsSync.isEmpty == true, "OFF Scene compared unsent lightness/CCT")
            offDone = true
        }
        await drain { offDone }
        cachedOff.isOn = true
        NodeSyncStatusGeneration.invalidate()
        offDone = false
        NodeSyncStatusRefresh.requestSceneGroups(scene: other, owner: owners[0]) { snapshot in
            require(snapshot?.needsSync == [ObjectIdentifier(network.groups[7 % 17])], "OFF Scene missed ON mismatch")
            offDone = true
        }
        await drain { offDone }
        cachedOff.isOn = false
        NodeSyncStatusGeneration.invalidate()

        // An empty Scene group remains represented and needs no node operation.
        let empty = Group(0xCD80); empty.network = network; empty.info.profile.type = .ordinary
        network.groups.append(empty); scene.info.groups.append(empty)
        ConfigurationSnapshotRevision.value = 1
        var emptyDone = false
        NodeSyncStatusRefresh.requestSceneGroups(scene: scene, owner: owners[0]) { snapshot in
            require(snapshot?.groups.count == 18 && snapshot?.needsSync.contains(ObjectIdentifier(empty)) == false,
                    "empty group was lost or marked unsynchronized")
            emptyDone = true
        }
        await drain { emptyDone }

        // Invalidation during a slice must restart the shared reader before
        // publishing; both owners see the replacement generation.
        var changed = false
        scene.unsynced = []
        NodeSyncStatusGeneration.invalidate()
        Node.onSceneCheck = { _ in
            guard !changed else { return }; changed = true
            scene.unsynced = [network.nodes[0].primaryUnicastAddress]
            NodeSyncStatusGeneration.invalidate()
        }
        var changedDone = false
        NodeSyncStatusRefresh.requestSceneGroups(scene: scene, owner: owners[0]) { snapshot in
            require(snapshot?.needsSync == [ObjectIdentifier(network.groups[0])], "stale Scene result published")
            changedDone = true
        }
        await drain { changedDone }
        Node.onSceneCheck = nil

        // Pending/corrupt protection never looks synchronized, including the
        // bool adapter used by the existing Scene list.
        let protection = SpaceConfigurationSafety.syncReadRequest(meshUUID: network.uuid.uuidString, networkId: "net")
        try! FileManager.default.createDirectory(at: protection.root, withIntermediateDirectories: true)
        let stateURL = protection.root.appendingPathComponent(protection.scope.storageKey + ".json")
        try! Data("broken".utf8).write(to: stateURL)
        SpaceProtectionReadGeneration.invalidate()
        completed = 0
        NodeSyncStatusRefresh.requestSceneGroups(scene: scene, owner: owners[0]) { snapshot in
            require(snapshot == nil, "corrupt protection published a Scene snapshot"); completed += 1
        }
        NodeSyncStatusRefresh.request(scene: scene, owner: owners[1]) { value in
            require(value, "corrupt protection appeared synchronized in list"); completed += 1
        }
        await drain { completed == 2 }
        try! FileManager.default.removeItem(at: stateURL)
        SpaceProtectionReadGeneration.invalidate()

        let blockedKey = "spaceConfigurationBlocked." + protection.scope.storageKey
        protection.defaults.set("fixturePendingImport", forKey: blockedKey)
        SpaceProtectionReadGeneration.invalidate()
        var blockedDone = false
        NodeSyncStatusRefresh.requestSceneGroups(scene: scene, owner: owners[0]) { snapshot in
            require(snapshot == nil, "blocked configuration appeared synchronized"); blockedDone = true
        }
        await drain { blockedDone }
        protection.defaults.removeObject(forKey: blockedKey)
        SpaceProtectionReadGeneration.invalidate()

        let display = SceneGroupDisplayState()
        var displayUpdates = 0
        display.refresh(scene: scene) { displayUpdates += 1 }
        display.cancel()
        display.refresh(scene: other) { displayUpdates += 1 }
        await drain { displayUpdates == 1 }
        require(display.currentSnapshot?.needsSync.isEmpty == true, "cancelled/old Scene updated the reused page")
        let checks = network.nodes.reduce(0, { $0 + $1.sceneChecks })
        display.refresh(scene: other) { preconditionFailure("unchanged page repeated its request") }
        require(network.nodes.reduce(0, { $0 + $1.sceneChecks }) == checks, "unchanged page repeated checks")
        NodeSyncStatusGeneration.invalidate()
        require(display.currentSnapshot == nil, "page retained a stale synchronized snapshot")

        var deallocating: SceneGroupDisplayState? = SceneGroupDisplayState()
        deallocating?.refresh(scene: scene) { preconditionFailure("deallocated page received a Scene result") }
        deallocating = nil
        var finalDone = false
        NodeSyncStatusRefresh.requestSceneGroups(scene: other, owner: owners[0]) { _ in finalDone = true }
        await drain { finalDone }

        // The appearance batch reuses membership but reads live on/off and CCT.
        let reads = Model.subscriptionReads
        let node = network.nodes[0], group = network.groups[0]
        node.isOn = true; node.effectiveSupportCct = true; node.effectiveCctRange = 2200...7000
        var appearance = NodeSyncStatusRefresh.sceneGroupAppearances(network.groups)
        require(appearance[ObjectIdentifier(group)]?.isOn == true
                && appearance[ObjectIdentifier(group)]?.cctRange == 2200...7000, "live appearance lost ON/CCT")
        node.isOn = false; node.effectiveCctRange = 3000...5000
        appearance = NodeSyncStatusRefresh.sceneGroupAppearances(network.groups)
        require(appearance[ObjectIdentifier(group)]?.isOn == false
                && appearance[ObjectIdentifier(group)]?.cctRange == 3000...5000, "appearance froze live fields")
        require(Model.subscriptionReads == reads, "appearance reread membership per card")
        print("PASS: Scene 17 groups/490 nodes, shared reads, per-Scene group status, OFF, empty/corrupt/invalidation/cancel/reuse, live appearance")
    }
}
