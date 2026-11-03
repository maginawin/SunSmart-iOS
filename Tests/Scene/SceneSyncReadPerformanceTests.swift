import Foundation

/// Uses the production resolver, incremental preparation and node Scene difference.
/// The real identity's crypto/formatting cost and BLE are intentionally not simulated.
@main struct SceneSyncReadPerformanceTests {
    static func require(_ value: Bool, _ message: String) {
        if !value { fatalError(message) }
    }

    static func main() throws {
        let manager = MeshNetworkManager.instance
        for count in [53, 500] {
            manager.meshNetwork = Network()
            let group = Group(0xC001), other = Group(0xC002)
            manager.groups = [group, other]
            manager.realNodes = (1...count).map { Node(UInt16($0)) }
            manager.realNodes.forEach { $0.group = group }
            let scenes = [Scene(1), Scene(2)]
            manager.scenes = scenes
            group.info.sceneExecuteDatas = scenes.map { .init(sceneNumber: $0.number) }
            group.info.sceneExecuteDatas[0].hue = 123
            group.info.sceneExecuteDatas[0].lightControlData = 7
            // Share identities across two Group Scenes and one fixed-device Scene.
            let devices = Scene(3)
            devices.info.configuration = .init(kind: .devices, name: "Devices", deviceMembers:
                manager.realNodes.map { .init(identity: $0.sceneConfigurationIdentity!,
                    parameters: .init(isOn: true, lightness: 12000, cct: 3000)) })
            manager.scenes.append(devices)
            Node.identityReads = 0
            let baseline = try manager.scenes.map { try SceneTargetResolver.resolve(scene: $0) }
            require(Node.identityReads == count * 3, "fresh resolution must generate each identity only once")
            for node in manager.realNodes {
                node.sceneExecuteDatas = zip(manager.scenes, baseline).compactMap { $1.writeData(scene: $0, node: node) }
            }

            var resolutions = 0, indexes = 0
            AppPerformance.observe { sample in
                if sample.name == "SyncSceneResolve" { resolutions += 1 }
                if sample.name == "SyncSceneIdentityIndex" { indexes += 1 }
            }
            defer { AppPerformance.observe(nil); NodeSyncReadContext.current = nil }
            let context = NodeSyncReadContext()
            NodeSyncReadContext.current = context
            Node.identityReads = 0
            require(!context.sceneReads.advance(until: 0), "expired preparation must yield")
            require(Node.identityReads == 0, "expired slice computed identities")
            var slices = 0
            while !context.sceneReads.advance(until: ProcessInfo.processInfo.systemUptime + 0.001) {
                slices += 1
                require(slices < 10000, "Scene preparation failed to finish")
            }
            require(Node.identityReads == count && indexes == 1 && resolutions == 3,
                    "Scene count multiplied identity builds or nodes multiplied Scene resolution")
            for (scene, expected) in zip(manager.scenes, baseline) {
                require(try SceneTargetResolver.resolveForSyncRead(scene: scene).comparison == expected.comparison,
                        "incremental resolution changed targets/auxiliary parameters")
            }
            for _ in 0..<5 {
                for node in manager.realNodes {
                    require(node.getNodeSyncSceneDatas().isEmpty, "matching device unexpectedly pending")
                    require(node.getNodeSyncSceneDatas(group: group).isEmpty, "explicit Group changed equality")
                }
            }
            require(Node.identityReads == count && resolutions == 3, "node checks recomputed identities or Scene snapshots")
            let first = manager.realNodes[0]
            let identity = first.sceneSyncReadIdentity!
            let snapshot = try context.sceneReads.snapshot(scenes[0])
            let target = snapshot.writeData(scene: scenes[0], node: first, identity: identity)
            require(target?.hue == 123 && target?.lightControlData == 7, "Group auxiliary fields were lost")

            // A new generation owns new reads. Nil vs explicit Group and per-Scene
            // differences must remain distinct, including cached empty results.
            first.sceneExecuteDatas = []
            let replacement = NodeSyncReadContext()
            NodeSyncReadContext.current = replacement
            require(replacement.sceneReads.advance(until: .infinity), "replacement preparation incomplete")
            require(first.getNodeSyncSceneDatas().count == 3, "new cache did not observe missing device data")
            require(first.getNodeSyncSceneDatas(group: other).map(\.scene.number) == [3], "explicit Group leaked into direct targets")
            require(first.getNodeSyncSceneDatas(scene: scenes[0]).count == 1, "per-Scene difference reused all-Scene result")
            first.fingerprint = String(repeating: "B", count: 64)
            // Fresh validation must ignore an installed display snapshot.
            let fresh = try SceneTargetResolver.resolve(scene: devices)
            require(fresh.unresolved.count == 1 && !fresh.targets.contains { $0.node === first }, "execution reused stale display identity")
            NodeSyncReadContext.current = nil
            print("PASS: \(count) nodes, 3 Scenes, \(count) shared identity reads, 3 resolutions; repeated differences, Group parameters and fresh execution")
        }

        let node = manager.realNodes[0]
        let duplicate = Node(node.primaryUnicastAddress)
        duplicate.uuid = node.uuid; duplicate.fingerprint = node.fingerprint
        manager.realNodes.append(duplicate)
        let duplicateScene = Scene(8)
        duplicateScene.info.configuration = .init(kind: .devices, name: "Duplicate", deviceMembers: [
            .init(identity: node.sceneConfigurationIdentity!, parameters: .init(isOn: true, lightness: 1000, cct: 3000))])
        let rejected = try SceneTargetResolver.resolve(scene: duplicateScene)
        require(rejected.targets.isEmpty && rejected.unresolved.count == 1, "identity collision selected an arbitrary Node")

        let broken = Scene(9); broken.info.loadConfiguration(Data("{}".utf8))
        manager.scenes = [broken]
        let failed = SceneSyncReadPreparation()
        require(failed.advance(until: .infinity), "invalid Scene did not settle")
        for _ in 0..<5 {
            do { _ = try failed.snapshot(broken); fatalError("invalid Scene became an empty success") }
            catch { }
        }
        let index = SceneTargetResolver.IdentityIndex()
        require(index.advance(until: .infinity), "index incomplete")
        let resolution = try SceneTargetResolver.resolution(scene: duplicateScene, index: index)
        require(try resolution.advance(until: 0) == nil, "expired target slice must yield")
        require(try resolution.advance(until: .infinity)?.unresolved.count == 1, "resumed target resolution changed")
        print("PASS: duplicate identity rejection, cached parse failure and target deadline/resume")
    }
}
