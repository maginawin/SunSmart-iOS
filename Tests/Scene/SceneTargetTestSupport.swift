import Foundation
typealias Address = UInt16
typealias SceneNumber = UInt16
extension UInt16 {
    var hex: String { String(format: "%04X", self) }
    static let allNodes: UInt16 = 0xFFFF
    var isSpecialScene: Bool { self >= 0xFF00 }
}
extension Int { static let sceneSetupServerModelId = 0x1204 }
final class Element {
    var observedSceneRegister: Set<UInt16>?
    weak var setupModel: Model?
    func model(withSigModelId: Int) -> Model? { setupModel }
}
final class Model {
    let parentElement: Element? = Element()
    init() { parentElement?.setupModel = self }
}
final class Network { let uuid = UUID() }
final class Node: NSObject {
    enum GroupState { case normal, exitFailure }
    let uuid: UUID
    let primaryUnicastAddress: Address
    var addressAliases = Set<UInt16>()
    var name: String? = "Lamp"
    var groupState: GroupState = .normal
    var state = true
    var isOn = false
    var lightness: UInt16 = 0
    var temperature: UInt16 = 0
    var sceneModel: Model? = Model()
    var sceneExecuteDatas: [SceneExecuteData] = []
    var propertySaves = 0
    var persistedSceneExecuteDatas: [SceneExecuteData] = []
    @discardableResult func savePropertys() -> Bool { propertySaves += 1; persistedSceneExecuteDatas = sceneExecuteDatas; return true }
    var cacheClears = 0
    func clearSyncStateCache() { cacheClears += 1 }
    var network: Network? = MeshNetworkManager.instance.meshNetwork
    var subNetworkId: String? = "0001"
    var group: Group?
    var sceneSetupModel: Model? = Model()
    var additionalSceneSetupModels: [Model] = []
    var elements: [Element] { ([sceneSetupModel] + additionalSceneSetupModels).compactMap { $0?.parentElement } }
    var onoffModel: Model? = Model()
    var lightnessModel: Model? = Model()
    var effectiveSupportCct = true
    var lightnessRange: ClosedRange<UInt16> = 0...65535
    var effectiveCctRange: ClosedRange<UInt16> = 2700...6500
    var fingerprint = String(repeating: "A", count: 64)
    var hasIdentity = true
    var timedSchedulerIdentity: TimedSchedulerNodeIdentity? {
        guard hasIdentity else { return nil }
        return .init(nodeUUID: uuid.uuidString, unicastAddress: primaryUnicastAddress.hex, deviceKeyFingerprint: fingerprint)
    }
    var schedulerSetupModels: [Model] = [Model()]
    var observedTimedSlots: Set<Int>? = []
    init(_ address: UInt16) { primaryUnicastAddress = address; uuid = UUID() }
    func clampEffectiveCct(_ value: UInt16) -> UInt16 { min(effectiveCctRange.upperBound, max(effectiveCctRange.lowerBound, value)) }
}
final class SceneExecuteData: Codable {
    enum State: String, Codable { case normal, waitDelete }
    var sceneNumber: SceneNumber
    var isOn: Bool
    var lightness: UInt16
    var cct: UInt16
    var hue: UInt16 = 0
    var saturation: UInt16 = 0
    var lightControlData: Int?
    var state: State = .normal
    init(sceneNumber: UInt16, isOn: Bool = true, lightness: UInt16 = 65535, cct: UInt16 = 4500, lightControlData: Int? = nil) {
        self.lightControlData = lightControlData; self.sceneNumber = sceneNumber; self.isOn = isOn; self.lightness = lightness; self.cct = cct
    }
    func deviceTarget(for node: Node) -> SceneExecuteData {
        .init(sceneNumber: sceneNumber, isOn: isOn, lightness: isOn ? lightness : 0,
              cct: node.effectiveSupportCct ? node.clampEffectiveCct(cct) : cct)
    }
}
final class GroupInfo { var sceneExecuteDatas: [SceneExecuteData] = []; var bindSchedules: [Schedule] = []; var saves = 0 }
final class Group: NSObject {
    struct GroupAddress: Equatable { let address: UInt16 }
    let address: GroupAddress
    let info = GroupInfo()
    var isOn = false
    var lightness: UInt16 = 0
    var cct = 0
    func clampEffectiveCct(_ value: UInt16) -> UInt16 { value }
    var nodes: [Node] {
        get { MeshNetworkManager.instance.realNodes.filter { $0.group === self } }
        set {
            nodes.forEach { $0.group = nil }
            newValue.forEach { $0.group = self }
        }
    }
    static var nextAddress: UInt16 = 0xC001
    init(_ address: UInt16? = nil) {
        self.address = .init(address: address ?? Self.nextAddress)
        Self.nextAddress += 1
    }
}
final class Scene: NSObject {
    let number: UInt16
    var addresses: [UInt16] = []
    var name = "Evening"
    var info: SceneInfo
    var network: Network? = MeshNetworkManager.instance.meshNetwork
    var subNetworkId = "0001"
    init(_ number: UInt16) { self.number = number; info = SceneInfo(sceneId: number) }
}
final class Schedule {
    var name = "Schedule"
    var testSyncNeededAddresses: Set<Address>?
    let id: Int
    var nodeAddresses: [UInt16] = []
    var groups: [Group] = []
    var scene: Scene?
    var nodes: [Node] { MeshNetworkManager.instance.realNodes.filter { nodeAddresses.contains($0.primaryUnicastAddress) } }
    var needDeleteNodes: [Node] = []
    var needDeleteGroups: [Group] = []
    var needDeleteScenes: [Scene] = []
    var nodeSlots: [TimedSchedulerNodeSlot]? = []
    var nodeSlotsLoadFailed = false
    init(_ id: Int, scene: Scene? = nil) { self.id = id; self.scene = scene }
    // ACTUAL_ACTIVE_SCENE_GROUPS
    // ACTUAL_SCHEDULE_TARGETS
    // ACTUAL_EXIST_NODES
}
enum NodeSyncReadContext {
    static let current: Context? = nil
    struct Context { func contains(_ node: Node, in group: Group) -> Bool { group.nodes.contains(node) } }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    struct Key { var networkId: UInt16 = 1 }
    var currentNetworkKey = Key()
    var meshNetwork: Network? = Network()
    var realNodes: [Node] = []
    var groups: [Group] = []
    var scenes: [Scene] = []
    var schedules: [Schedule] = []
}
final class MeshProxyMessageCommand { static let shared = MeshProxyMessageCommand(); var isBusy = false }
// ACTUAL_SCENE_INFO
// ACTUAL_SCENE_CAPACITY
// ACTUAL_TIMED_BINDINGS

enum EmergencyFireControllerSceneEventManager {
    static var blocked = Set<ObjectIdentifier>()
    static func isManualControlBlocked(for node: Node) -> Bool { blocked.contains(ObjectIdentifier(node)) }
}
