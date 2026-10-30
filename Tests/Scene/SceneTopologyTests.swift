import Foundation
typealias DataItem = SceneExecuteData

@main struct SceneTopologyTests {
    static func main() throws {
        let manager = MeshNetworkManager.instance
        let a = Node(1), b = Node(2), c = Node(3)
        manager.realNodes = [a, b, c]
        let ga = Group(), gb = Group()
        ga.nodes = [a]; gb.nodes = [b]
        ga.info.sceneExecuteDatas = (1...16).map { DataItem(sceneNumber: UInt16($0)) }
        gb.info.sceneExecuteDatas = (17...32).map { DataItem(sceneNumber: UInt16($0)) }
        manager.groups = [ga, gb]
        a.sceneSetupModel?.parentElement?.observedSceneRegister = Set(1...16)
        b.sceneSetupModel?.parentElement?.observedSceneRegister = Set(17...32)
        c.sceneSetupModel?.parentElement?.observedSceneRegister = []
        try SceneCapacity.validateTopology()
        try SceneCapacity.validateTopology(group: gb, members: [b, c], addingMembers: [c])
        do {
            try SceneCapacity.validateTopology(group: gb, members: [b, a, c], addingMembers: [a, c])
            fatalError("Batch must reject the device with 32 desired scenes")
        } catch let failure as SceneCapacity.Failure {
            precondition(!failure.unknown && failure.devices == ["Lamp (0001)"])
        }
        precondition(ga.nodes == [a] && gb.nodes == [b], "Preflight must not mutate membership")
        do {
            try SceneCapacity.validateTopology(scene: Scene(33), sceneGroups: [ga, gb])
            fatalError("17th scene must reject both full devices")
        } catch let failure as SceneCapacity.Failure { precondition(failure.devices.count == 2) }
        // Removing a scene and editing the same number are allowed at capacity.
        try SceneCapacity.validateTopology(scene: Scene(16), sceneGroups: [ga])
        try SceneCapacity.validateTopology(scene: Scene(16), sceneGroups: [])
        a.sceneSetupModel?.parentElement?.observedSceneRegister = nil
        precondition(SceneCapacity.nodesRequiringRead(scene: Scene(16), sceneGroups: [ga]).isEmpty)
        precondition(SceneCapacity.nodesRequiringRead(scene: Scene(16), sceneGroups: []).isEmpty)
        precondition(SceneCapacity.nodesRequiringRead(scene: Scene(33), sceneGroups: [ga]) == [a])
        a.sceneSetupModel?.parentElement?.observedSceneRegister = Set(1...16)
        a.groupState = .exitFailure
        precondition(SceneCapacity.intendedScenes(on: a).isEmpty)
        try SceneCapacity.validateTopology(group: ga, members: [a], addingMembers: [a])
        c.sceneSetupModel?.parentElement?.observedSceneRegister = nil
        do {
            try SceneCapacity.validateTopology(group: gb, members: [b, c], addingMembers: [c])
            fatalError("Unknown is not empty")
        } catch let failure as SceneCapacity.Failure { precondition(failure.unknown) }
        c.sceneSetupModel = nil
        try SceneCapacity.validateTopology(group: gb, members: [b, c], addingMembers: [c])
        a.groupState = .normal
        ga.info.sceneExecuteDatas.removeLast()
        ga.info.sceneExecuteDatas.append(DataItem(sceneNumber: 33))
        // A pending new ID must not prevent updating an already stored ID.
        try SceneCapacity.validateStore(node: a, number: 1)
        let base: [String: Any] = ["allocatedUnicastRange": [], "allocatedGroupRange": []]
        var allocation = base
        allocation["allocatedSceneRange"] = [["firstScene": "0001", "lastScene": "0020"]]
        precondition(SceneCapacity.validSceneAllocation(allocation))
        allocation["allocatedSceneRange"] = [1, 2, 17, 18]
        precondition(SceneCapacity.validSceneAllocation(allocation))
        allocation["allocatedSceneRange"] = [0xFF00]
        precondition(!SceneCapacity.validSceneAllocation(allocation))
        let tombstone = Scene(40)
        tombstone.info.configuration = .init(kind: .groups, name: "Deleting", pendingOperations: [.init(identity: a.timedSchedulerIdentity!, action: .remove)], isDeleting: true)
        let oldRelation = DataItem(sceneNumber: 40); oldRelation.state = .waitDelete
        ga.info.sceneExecuteDatas.append(oldRelation)
        // A device that joins the old display group after deletion was committed
        // must not silently become a new cleanup target.
        c.sceneSetupModel = Model(); c.group = ga
        let frozen = try SceneTargetResolver.resolve(scene: tombstone)
        precondition(frozen.targets.isEmpty && frozen.cleanupTargets.map(\.identity) == [a.timedSchedulerIdentity!])
        tombstone.info.configuration!.pendingOperations = []
        let completed = try SceneTargetResolver.resolve(scene: tombstone)
        precondition(completed.targets.isEmpty && completed.cleanupTargets.isEmpty)
        print("SceneTopologyTests passed: real topology projection, atomic preflight, empty/unknown, exit recovery")
    }
}
