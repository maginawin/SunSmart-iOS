import Foundation
typealias SceneNumber = UInt16
extension UInt16 { var hex: String { String(format: "%04X", self) } }
final class Element { var observedSceneRegister: Set<UInt16>? }
final class Model { let parentElement: Element? = Element() }
final class Node: NSObject {
    enum State { case normal, exitFailure }
    let uuid = UUID()
    let name: String? = "Lamp"
    let primaryUnicastAddress: UInt16
    var groupState: State = .normal
    var sceneSetupModel: Model? = Model()
    init(_ address: UInt16) { primaryUnicastAddress = address }
}
final class Scene: NSObject {
    let number: UInt16
    init(_ number: UInt16) { self.number = number }
}
struct DataItem {
    enum State { case normal, waitDelete }
    let sceneNumber: UInt16
    var state: State = .normal
}
final class Info { var sceneExecuteDatas: [DataItem] = [] }
final class Group: NSObject {
    var nodes: [Node] = []
    let info = Info()
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var realNodes: [Node] = []
    var groups: [Group] = []
}

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
        print("SceneTopologyTests passed: real topology projection, atomic preflight, empty/unknown, exit recovery")
    }
}
