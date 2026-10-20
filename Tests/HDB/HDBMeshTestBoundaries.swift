import Foundation

enum UserData { static var currentUserId = "user", currentServerRegion = "region" }
extension String { var hex: String { self }; var localizedString: String { self == "hdb_default_zone_name" ? "Zone %d" : self } }
struct MeshAddress: Equatable { let address: UInt16; init(_ address: UInt16) { self.address = address } }
final class GroupInfo {
    static var failAddress: UInt16?
    let address: UInt16
    init(address: UInt16) { self.address = address }
    func save(meshUUID: String, subnetworkId: String) -> Bool { address != Self.failAddress }
    func delete(meshUUID: String) -> Bool { address != Self.failAddress }
}
final class Group {
    let address: MeshAddress
    var subNetworkId: String? = "network"
    var isVirtual = false
    var name = ""
    var info: GroupInfo
    init(_ address: UInt16) { self.address = MeshAddress(address); info = GroupInfo(address: address) }
    convenience init(name: String, address: MeshAddress) throws { self.init(address.address); self.name = name }
    func save() -> Bool { address.address != Self.failAddress }
    func delete() -> Bool { address.address != Self.failAddress }
    static var failAddress: UInt16?
}
struct TestSensorProperty { let id: UInt16 }
final class Model: Hashable {
    static func == (lhs: Model, rhs: Model) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    let modelIdentifier: UInt16, companyIdentifier: UInt16?
    var relatedModels: [Model] = []
    var subscriptions: [Group] = []
    var publish: TestPublish?
    weak var parentElement: Element?
    var boundApplicationKeys = [ApplicationKey()]
    init(_ id: UInt16, company: UInt16? = nil) { modelIdentifier = id; companyIdentifier = company }
    func unsubscribeFromAll() { subscriptions.removeAll() }
}
final class Element { var unicastAddress: UInt16 = 1; var models = [Model(0x130F), Model(0x1310), Model(0x1000), Model(0x1300), Model(1, company: 0x0A78)] }
final class Node {
    enum DeviceType { case light, other }
    let uuid: UUID
    var primaryUnicastAddress: UInt16
    var deviceKey: Data? = Data([1])
    var createdTimestamp: Int64 = 1
    struct PreConfiguration {
        var hdbInitializationSignature: String?
        static var saved: PreConfiguration?, failSave = false
        func save(meshUUID: String, nodeAddress: UInt16) -> Bool { if Self.failSave { return false }; Self.saved = self; return true }
        static func load(meshUUID: String, nodeAddress: UInt16) -> PreConfiguration? { saved }
    }
    var preConfiguration = PreConfiguration()
    init(uuid: UUID = UUID(), address: UInt16 = 1) { self.uuid = uuid; primaryUnicastAddress = address; elements[0].unicastAddress = address; elements[0].models.forEach { $0.parentElement = elements[0] } }
    var name: String? = "Light", macAddress: String? = "aabbccddeeff", subNetworkId: String? = "network"
    var isProvisioner = false, isConfigComplete = false, isKeybindComplete = true
    var presenceDetectedSensorModel: Model?
    var ambientLightSensorModel: Model?
    var sensorModelTypes: [Model: TestSensorProperty] = [:]
    func knows(networkKey: MeshNetworkManager.Key) -> Bool { subNetworkId == networkKey.networkId }
    var deviceType = DeviceType.light
    var elements = [Element()]
    weak var network: MeshNetwork?
    static var failSave = false
    var saveCount = 0
    var savedSubscriptions: [Model: [Group]] = [:]
    func save() -> Bool {
        guard !Self.failSave else { return false }
        saveCount += 1
        savedSubscriptions = Dictionary(uniqueKeysWithValues: elements.flatMap(\.models).map { ($0, $0.subscriptions) })
        return true
    }
    var group: Group? { elements.flatMap(\.models).flatMap(\.subscriptions).first { !$0.isVirtual } }
}
final class MeshNetwork {
    let uuid = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    var nodes: [Node] = [], groups: [Group] = [], scenes: [Int] = []
    static var saved: MeshNetwork?
    static var loadCount = 0
    var networkKeys: [MeshNetworkManager.Key] = [.init()]
    var applicationKeys = [ApplicationKey()]
    func remove(group: Group) throws { groups.removeAll { $0 === group } }
    func add(group: Group) throws { groups.append(group); _ = group.save() }
    static func load(meshUUID: String, subnetworkId: String? = nil, allData: Bool = true) -> MeshNetwork? { loadCount += 1; return saved }
}
final class MeshNetworkManager {
    struct Key { var networkId = "network" }
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?, currentNetworkKey = Key()
    var groups: [Group] { meshNetwork?.groups.filter { !$0.isVirtual } ?? [] }
}
enum MeshAPI {
    static var allocation = Array(UInt16(0xC000)...0xC100)
    static func getAvailableGroupAddresses(meshUUID: String, subnetworkId: String? = nil) -> [UInt16] {
        allocation.filter { address in !(MeshNetwork.saved?.groups.contains {
            $0.address.address == address && (subnetworkId == nil || $0.subNetworkId == subnetworkId)
        } ?? false) }
    }
    static func createGroup(name: String?, address: UInt16, isVirtual: Bool) throws -> Group {
        let group = Group(address); MeshNetworkManager.instance.meshNetwork!.groups.append(group); return group
    }
}
protocol MeshMessage { var parameters: Data { get } }
protocol StaticMeshMessage {}
struct ConfigModelSubscriptionAdd: MeshMessage { let parameters: Data; init?(parameters: Data) { self.parameters = parameters } }
struct ConfigModelSubscriptionDelete: MeshMessage { let parameters: Data; init?(parameters: Data) { self.parameters = parameters } }
struct ConfigModelSubscriptionOverwrite: MeshMessage {
    let parameters: Data
    init?(parameters: Data) { guard [6, 8].contains(parameters.count) else { return nil }; self.parameters = parameters }
}
struct ConfigModelSubscriptionDeleteAll: MeshMessage {
    let parameters: Data
    init?(parameters: Data) { guard [4, 6].contains(parameters.count) else { return nil }; self.parameters = parameters }
}
struct ConfigModelSubscriptionStatus: StaticMeshMessage, MeshMessage {
    let parameters: Data
    let elementAddress: UInt16, address: UInt16, modelIdentifier: UInt16, companyIdentifier: UInt16?
    let isSuccess: Bool
    init(_ message: MeshMessage, success: Bool) {
        var payload = message.parameters
        if message is ConfigModelSubscriptionDeleteAll { payload.insert(contentsOf: [0, 0], at: 2) }
        parameters = Data([success ? 0 : 1]) + payload
        let b = [UInt8](payload)
        func u(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i+1]) << 8 }
        elementAddress = u(0); address = u(2); modelIdentifier = u(b.count-2); companyIdentifier = b.count == 8 ? u(4) : nil; isSuccess = success
    }
}
final class MeshMessageHandle {
    let message: MeshMessage
    let address: UInt16?
    var continuous = false
    var isSuccessful = false
    var model: Model?
    init(message: MeshMessage, address: UInt16) { self.message = message; self.address = address }
    convenience init(message: MeshMessage, model: Model) { self.init(message: message, address: model.parentElement?.unicastAddress ?? 1); self.model = model }
}
final class SyncExecutionEnvironment {
    struct Batch {
        let handles: [MeshMessageHandle]
        let success: ((MeshMessageHandle, StaticMeshMessage) -> Void)?
        let failure: ((MeshMessageHandle) -> Void)?
        let finished: (([MeshMessageHandle]) -> Void)?
    }
    static var batches: [Batch] = [], stops = 0
    static var subscriptionObserver: ((MeshMessageHandle) -> Void)?
    static var stopObserver: ((@escaping () -> Void) -> Void)?
    var stop: (@escaping () -> Void) -> Void = { done in stops += 1; if let stopObserver { stopObserver(done) } else { done() } }
    func addMessage(messageHandles: [MeshMessageHandle], successfulBack: ((MeshMessageHandle, StaticMeshMessage) -> Void)?, failedBack: ((MeshMessageHandle) -> Void)?, finishedBack: (([MeshMessageHandle]) -> Void)?) {
        Self.batches.append(.init(handles: messageHandles, success: successfulBack, failure: failedBack, finished: finishedBack))
    }
    // Emulates the SDK's same-element shared subscription-list cache mutation.
    static func applySubscription(_ handle: MeshMessageHandle) {
        subscriptionObserver?(handle)
        let status = ConfigModelSubscriptionStatus(handle.message, success: true)
        guard let network = MeshNetworkManager.instance.meshNetwork,
              let node = network.nodes.first(where: { $0.primaryUnicastAddress == handle.address }),
              let element = node.elements.first(where: { $0.unicastAddress == status.elementAddress }),
              let model = element.models.first(where: { $0.modelIdentifier == status.modelIdentifier && $0.companyIdentifier == status.companyIdentifier }) else { return }
        let group = network.groups.first { $0.address.address == status.address } ?? Group(status.address)
        for receiver in [model] + model.relatedModels.filter({ $0.parentElement === element }) {
            if handle.message is ConfigModelSubscriptionOverwrite || handle.message is ConfigModelSubscriptionDeleteAll { receiver.subscriptions = [] }
            if handle.message is ConfigModelSubscriptionDelete {
                receiver.subscriptions.removeAll { $0.address.address == status.address }
            } else if !(handle.message is ConfigModelSubscriptionDeleteAll), !receiver.subscriptions.contains(where: { $0.address.address == status.address }) {
                receiver.subscriptions.append(group)
            }
        }
    }
    static func finishFirst(failIndex: Int? = nil) {
        let b = batches.removeFirst()
        for (index, h) in b.handles.enumerated() {
            h.isSuccessful = index != failIndex
            if h.isSuccessful {
                applySubscription(h)
                b.success?(h, ConfigModelSubscriptionStatus(h.message, success: true))
            } else {
                b.failure?(h)
                if !h.continuous { break }
            }
        }
        b.finished?(b.handles)
    }
}


struct ApplicationKey { var boundNetworkKey = MeshNetworkManager.Key(); var index: UInt16 = 0 }
protocol AcknowledgedMeshMessage: MeshMessage {}
struct LightLCModeSet: AcknowledgedMeshMessage { var parameters = Data([3]) }
struct PreparationMessage: AcknowledgedMeshMessage { var parameters = Data([1]) }
enum HDBLightingMessages {
    static var preparationTargets: [HDBPreparationTarget] = []
    static func preparation(_ targets: [HDBPreparationTarget]) throws -> [(HDBModelTarget, AcknowledgedMeshMessage)] {
        preparationTargets = targets
        return targets.map { ($0.model, PreparationMessage() as AcknowledgedMeshMessage) } + targets.filter { $0.model.modelId == 0x130F }.map { ($0.model, LightLCModeSet() as AcknowledgedMeshMessage) }
    }
    static func model(_ target: HDBModelTarget, node: Node, key: ApplicationKey) throws -> Model {
        node.elements.first(where: { $0.unicastAddress == target.elementAddress })!.models.first(where: { $0.modelIdentifier == target.modelIdentifier && $0.companyIdentifier == target.companyIdentifier })!
    }
    static func matches(_ request: MeshMessage, response: MeshMessage) -> Bool { request.parameters == response.parameters }
}
extension MeshNetworkManager {
    static var preparationObserver: ((AcknowledgedMeshMessage, Model) -> Void)?
    static var preparationSends = 0
    static var preparationFailure = false
    static var pausePreparation = false
    static var preparationReply: (MeshMessage, CheckedContinuation<MeshMessage, Error>)?
    func send(_ message: AcknowledgedMeshMessage, to model: Model) async throws -> MeshMessage {
        try Task.checkCancellation()
        Self.preparationSends += 1
        Self.preparationObserver?(message, model)
        if Self.preparationFailure { throw HDBConfigurationError.unavailable }
        if Self.pausePreparation {
            return try await withCheckedThrowingContinuation { Self.preparationReply = (message, $0) }
        }
        return message
    }
}

struct TestPublish {
    enum Timing { case disabled, periodic }
    // Inject SDK Retransmit here.
    let publicationAddress: MeshAddress
    var index: UInt16 = 0
    var ttl: UInt8 = SensorPublicationPolicy.ttl
    var period = Timing.disabled
    var retransmit = Retransmit.disabled
}
typealias Publish = TestPublish
// Inject SensorPublicationPolicy here.
enum ProximityLightingTopologyContext {
    static func network(for space: SpaceData) -> MeshNetwork? { MeshNetwork.saved }
    static func realNodes(in network: MeshNetwork) -> [Node] { network.nodes.filter { !$0.isProvisioner && !$0.isConfigComplete } }
}
enum Schedule { static func load(meshUUID: String, meshNetworkId: String) -> [Int] { [] } }
enum DeviceSwitchData { static func load(meshUUID: String, meshNetworkId: String) -> [Int] { [] } }
final class NodeSyncReadContext {
    static var current: NodeSyncReadContext?
    var networkID = "network"
    func memoized<T>(_ key: String, read: () -> T) -> T { read() }
}
