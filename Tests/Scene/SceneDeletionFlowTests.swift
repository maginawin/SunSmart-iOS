import Foundation

typealias SceneNumber = UInt16
extension String { var localizedString: String { self }; var hex: String { self } }
enum TestError: Error { case storage }
final class Element {
    var observedSceneRegister: Set<UInt16>?
    lazy var model = Model(self)
    func model(withSigModelId id: Int) -> Model? { model }
}
extension Int { static let sceneSetupServerModelId = 0x1204 }
final class Model { let parentElement: Element?; init(_ element: Element) { parentElement = element } }
struct Entry { var isValid = true; var sceneNumber: UInt16 = 1 }
final class Node: NSObject {
    let primaryUnicastAddress: UInt16
    var elements = [Element()]
    var sceneExecuteDatas: [SceneExecuteData] = []
    var allSchedulerModelEntrys: [Int: [Int: Entry]] = [:]
    init(_ address: UInt16) { primaryUnicastAddress = address }
    func delete(sceneId: UInt16) { sceneExecuteDatas.removeAll { $0.sceneNumber == sceneId } }
}
final class SceneExecuteData {
    enum State { case normal, waitDelete }
    let sceneNumber: UInt16
    var state: State = .normal
    init(_ number: UInt16) { sceneNumber = number }
}
struct Switch { var name = "switch"; var sceneANumber: UInt16?; var sceneBNumber: UInt16?; var sceneCNumber: UInt16?; var sceneDNumber: UInt16? }
final class Group: NSObject {
    final class Info {
        var sceneExecuteDatas = [SceneExecuteData(1)]
        var switchs: [Switch] = []
        var savesSucceed = true
        func save() -> Bool { savesSucceed }
    }
    var nodes: [Node] = []; let info = Info()
    func updateGroupSyncState() {}
}
final class Scene {
    final class Info {
        var groups: [Group] = []
        var deleted = false
        func delete(meshUUID: String) -> Bool { deleted = true; return true }
        func save(meshUUID: String, subnetworkId: String) -> Bool { deleted = false; return true }
    }
    let number: UInt16 = 1
    var network: Network?
    var addresses: [UInt16] = []
    var nodes: [Node] { addresses.compactMap { network?.node(withAddress: $0) } }
    let info = Info()
}
final class Network {
    let uuid = UUID()
    var scenes: [Scene] = []
    var nodes: [Node] = []
    var removalFails = false
    func node(withAddress address: UInt16) -> Node? { nodes.first { $0.primaryUnicastAddress == address } }
    func remove(scene number: UInt16) throws {
        if removalFails { throw TestError.storage }
        scenes.removeAll { scene in
            if scene.number == number { scene.network = nil; return true }; return false
        }
    }
}
struct Schedule { var sceneNumber: UInt16?; var needDeleteSceneNumbers: [UInt16] = []; var name = "timer" }
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: Network?
    struct Key { var networkId = "A" }
    var currentNetworkKey = Key()
    var realNodes: [Node] { meshNetwork?.nodes ?? [] }
    var groups: [Group] = []
    var schedules: [Schedule] = []
    var switchs: [Switch] = []
}
final class DB { func savepoint(_ body: () throws -> Void) throws { try body() } }
final class SunSmartDataManager { static let shared = SunSmartDataManager(); var db: DB? = DB() }
enum TimedSchedulerBindings { enum Failure: Error { case persistence } }
enum SceneCapacity { static func label(_ node: Node) -> String { String(node.primaryUnicastAddress) } }
final class SRAlertAction { init(title: String, actionHandler: (() -> Void)?) {} }
final class SRAlertView { init(message: String, actions: [SRAlertAction]) {}; func show() {} }
let spaceDataChangedNotificaitonName = "changed"
enum SpaceChangeDataType { case common }
struct SceneRegisterGet {}
struct SceneDelete { let number: UInt16; init(_ number: UInt16) { self.number = number } }
final class MeshMessageHandle {
    let message: Any; let model: Model; var isSuccessful = false
    init(message: Any, model: Model) { self.message = message; self.model = model }
}
final class MeshLibManager { static let manager = MeshLibManager(); var isMeshNetworkConnected = true }
final class MeshProxyMessageCommand {
    static let shared = MeshProxyMessageCommand()
    var isBusy = false
    var batches: [[MeshMessageHandle]] = []
    var pending: (([MeshMessageHandle]) -> Void)?
    func addMessage(messageHandles: [MeshMessageHandle], finishedBack: @escaping ([MeshMessageHandle]) -> Void) {
        precondition(pending == nil)
        batches.append(messageHandles); pending = finishedBack
    }
    func complete(successful: Set<Int>, invalidate: Bool = false) {
        let handles = batches.last!, callback = pending!; pending = nil
        for (index, handle) in handles.enumerated() {
            handle.isSuccessful = successful.contains(index)
            if handle.isSuccessful {
                if handle.message is SceneRegisterGet { handle.model.parentElement?.observedSceneRegister = [1] }
                else { handle.model.parentElement?.observedSceneRegister?.remove(1) }
            }
            if invalidate { handle.model.parentElement?.observedSceneRegister = nil }
        }
        callback(handles)
    }
}

@main struct SceneDeletionFlowTests {
    static func drain(until done: () -> Bool) {
        let end = Date().addingTimeInterval(2)
        while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
        precondition(done(), "Expected callback did not arrive")
    }
    static func fixture() -> (Scene, Group, Network) {
        let manager = MeshNetworkManager.instance, network = Network(), scene = Scene(), group = Group()
        network.nodes = [Node(1), Node(2)]
        network.nodes.forEach { $0.elements[0].observedSceneRegister = [1] }
        scene.network = network; network.scenes = [scene]
        scene.info.groups = [group]; group.nodes = network.nodes; scene.addresses = [1, 2]
        manager.meshNetwork = network; manager.groups = [group]; manager.schedules = []; manager.switchs = []
        let transport = MeshProxyMessageCommand.shared
        transport.batches = []; transport.pending = nil
        return (scene, group, network)
    }
    static func main() {
        let transport = MeshProxyMessageCommand.shared
        var succeeded = 0, failed = 0
        let success: (Scene) -> Void = { _ in succeeded += 1 }, failure: (Scene) -> Void = { _ in failed += 1 }
        var (scene, group, network) = fixture()
        SceneServer.deleteScene(scene: scene, success: success, failed: failure)
        precondition(group.info.sceneExecuteDatas[0].state == .waitDelete)
        transport.complete(successful: [0])
        drain { failed == 1 }
        precondition(network.scenes.count == 1 && !scene.info.deleted && group.info.sceneExecuteDatas.count == 1)
        SceneServer.deleteScene(scene: scene, success: success, failed: failure)
        precondition(transport.batches.last?.count == 1, "Retry must target only the remaining device")
        transport.complete(successful: [0]); drain { succeeded == 1 }
        precondition(network.scenes.isEmpty && group.info.sceneExecuteDatas.isEmpty && scene.info.deleted)

        (scene, group, network) = fixture()
        network.nodes[0].elements[0].observedSceneRegister = nil
        SceneServer.deleteScene(scene: scene, success: success, failed: failure)
        precondition(transport.batches.last?.first?.message is SceneRegisterGet)
        transport.complete(successful: []); drain { failed == 2 }
        precondition(group.info.sceneExecuteDatas[0].state == .normal && network.scenes.count == 1)
        SceneServer.deleteScene(scene: scene, success: success, failed: failure)
        transport.complete(successful: [0]); drain { transport.batches.count == 3 }
        transport.complete(successful: [0, 1], invalidate: true); drain { failed == 3 }
        precondition(network.scenes.count == 1, "Lost observation cannot release the ID")

        (scene, group, network) = fixture()
        SceneServer.deleteScene(scene: scene, success: success, failed: failure)
        MeshNetworkManager.instance.meshNetwork = Network()
        transport.complete(successful: [0, 1]); drain { failed == 4 }
        precondition(network.scenes.count == 1 && !scene.info.deleted, "Late replies cannot commit in another Space")

        (scene, group, network) = fixture()
        MeshNetworkManager.instance.schedules = [Schedule(sceneNumber: 1)]
        SceneServer.deleteScene(scene: scene, success: success, failed: failure)
        precondition(failed == 5 && transport.batches.isEmpty && network.scenes.count == 1)
        MeshNetworkManager.instance.schedules = []
        group.info.savesSucceed = false
        SceneServer.deleteScene(scene: scene, success: success, failed: failure)
        precondition(failed == 6 && transport.batches.isEmpty && group.info.sceneExecuteDatas[0].state == .normal)

        (scene, group, network) = fixture()
        let residual = Node(3); residual.elements[0].observedSceneRegister = [1]; network.nodes.append(residual)
        SceneServer.deleteScene(scene: scene, success: success, failed: failure)
        precondition(transport.batches.last?.count == 3, "Observed residual outside Group must be removed")
        network.removalFails = true
        transport.complete(successful: [0, 1, 2]); drain { failed == 7 }
        precondition(network.scenes.count == 1 && !scene.info.deleted && group.info.sceneExecuteDatas.count == 1)
        print("SceneDeletionFlowTests passed: partial failure/retry, unknown, disconnect, late reply, references, persistence failure, residual targets")
    }
}
