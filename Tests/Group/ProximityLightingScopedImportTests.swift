import Foundation

// SDK/storage boundary doubles. The runner compiles the actual App preflight,
// context, planner, coordinator and node task methods, not copies of their logic.
typealias Address = UInt16
extension UInt16 {
    init?(hex: String) { self.init(hex, radix: 16) }
    var hex: String { String(format: "%04X", self) }
    var isUnicast: Bool { self > 0 && self < 0x8000 }
}
extension String { var hex: String { self }; var localizedString: String { self } }
struct MeshAddress: Equatable { let address: Address }
let jsonDecoder = JSONDecoder()
struct SpaceTriggerZone: Codable, Equatable {
    struct Item: Codable, Equatable { let groupAddress: Address; let deviceAddress: Address }
    var items: [Item]
}
final class Profile {
    enum ProfileType: Int { case ordinary = 0, proximityLighting = 7, proximityLightingWithPhotocell = 8 }
    var type: ProfileType = .proximityLighting
    var proximityLightingNumber: UInt8 = 2
}
final class GroupProximityLightingSequencePath {
    struct Item { var address: Address? }
    var items: [Item]
    init(items: [Item]) { self.items = items }
}
final class GroupProximityLightingPathZone {
    var addresses: [Address]
    init(addresses: [Address]) { self.addresses = addresses }
}
final class GroupProximityLightingPathData {
    var paths: [GroupProximityLightingSequencePath]
    var zones: [GroupProximityLightingPathZone]
    init(paths: [GroupProximityLightingSequencePath], zones: [GroupProximityLightingPathZone]) {
        self.paths = paths; self.zones = zones
    }
}
final class GroupInfo {
    var profile = Profile()
    var profileLoadFailed = false, topologyLoadFailed = false
    var proximityLightingPath: GroupProximityLightingPathData?
    static var stored: [String: GroupInfo] = [:]
    static func load(meshUUID: String, address: Address, subnetworkId: String? = nil) -> GroupInfo? {
        stored[meshUUID + (subnetworkId ?? "") + address.hex]
    }
    static func unavailable(address: Address) -> GroupInfo { let x = GroupInfo(); x.profileLoadFailed = true; return x }
    @discardableResult func save(meshUUID: String, subnetworkId: String) -> Bool { true }
}
final class Group: Decodable {
    let address: MeshAddress
    var name = "Group", isVirtual = false, info = GroupInfo()
    var subNetworkId: String?
    weak var network: MeshNetwork?
    static var globalMemberReads = 0
    var nodes: [Node] { Self.globalMemberReads += 1; return MeshNetworkManager.instance.realNodes.filter { $0.group?.address == address } }
    init(_ address: Address) { self.address = .init(address: address) }
    required init(from decoder: Decoder) throws {
        let json = try JSON(from: decoder)
        address = .init(address: Address(hex: json["address"].stringValue)!)
    }
    func save() {}
    func updateGroupSyncState() {}
}
final class Element {
    let unicastAddress: Address
    var models: [Model] = []
    weak var parentNode: Node?
    init(_ address: Address) { unicastAddress = address }
}
final class Model {
    weak var parentElement: Element?
    var subscribed: [Address] = []
    var isVendor = false
    var subscriptions: [Group] { (parentElement?.parentNode?.network?.groups ?? []).filter { subscribed.contains($0.address.address) } }
}
final class Node: Decodable {
    enum GroupState: Int { case none = 0, inGroup = 1, exitFailure = 2 }
    let primaryUnicastAddress: Address
    let uuid: String
    var elements: [Element] = []
    var groupState = GroupState.inGroup
    var subNetworkId: String?
    weak var network: MeshNetwork?
    var isLocalProvisioner = false, isProvisioner = false, isConfigComplete = false
    var proximityLightingEnabled = true
    var proximityLightingRelayCount: UInt8? = 2
    var proximityLightingNeighborAddresses: [Address] = []
    var sunricherVendorModel: Model? { elements.flatMap(\.models).first { $0.isVendor } }
    var group: Group? { elements.flatMap(\.models).flatMap(\.subscriptions).first }
    required init(from decoder: Decoder) throws {
        let json = try JSON(from: decoder)
        primaryUnicastAddress = Address(hex: json["unicastAddress"].stringValue)!
        uuid = json["uuid"].stringValue
        for (index, item) in json["elements"].arrayValue.enumerated() {
            let element = Element(primaryUnicastAddress + Address(index)); element.parentNode = self
            element.models = item["models"].arrayValue.map { value in
                let model = Model(); model.parentElement = element
                model.isVendor = value["modelId"].stringValue == "0A780001"
                model.subscribed = value["subscribe"].arrayValue.compactMap { Address(hex: $0.stringValue) }
                return model
            }
            elements.append(element)
        }
    }
    func contains(elementWithAddress address: Address) -> Bool { elements.contains { $0.unicastAddress == address } }
    func clearSyncStateCache() {}
}
final class MeshNetwork {
    let uuid: UUID
    var groups: [Group] = [], nodes: [Node] = []
    static var stored: [String: MeshNetwork] = [:]
    init(_ uuid: UUID = UUID()) { self.uuid = uuid }
    static func load(meshUUID: String, subnetworkId: String) -> MeshNetwork? { stored[meshUUID + subnetworkId] }
}
final class MeshNetworkManager {
    struct Key { var networkId: String }
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
    var currentNetworkKey = Key(networkId: "")
    var realNodes: [Node] { meshNetwork?.nodes ?? [] }
    var groups: [Group] { meshNetwork?.groups ?? [] }
}
final class SpaceData {
    let id = UUID().uuidString, meshUUID: String, meshNetworkId: String
    var triggerZones: [SpaceTriggerZone] = [], triggerZonesLoadFailed = false
    var lastUpdate: Int64 = 10, dirtyCount = 0
    static var stored: [String: SpaceData] = [:]
    init(network: MeshNetwork, networkId: String) { meshUUID = network.uuid.uuidString; meshNetworkId = networkId }
    static func load(subNetworkId: String) -> SpaceData? { stored[subNetworkId] }
    func markLocalChangePendingCloudSync() { dirtyCount += 1; lastUpdate += 1 }
    @discardableResult func save() -> Bool { true }
}
enum SpaceConfigurationSafety {
    enum SafetyError: Error { case persistenceFailed }
    static func isBlocked(_ space: SpaceData) -> Bool { false }
    static func checkpoint(_ space: SpaceData) -> Bool { true }
    static func configurationAvailable(for node: Node, group: Group?) -> Bool { true }
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    func configurationTransaction(_ action: () throws -> Void) -> Bool { do { try action(); return true } catch { return false } }
}
enum NodeSyncData: Equatable {
    case proximityLightingEnabled(Bool)
    case proximityLightingRelayNumber(UInt8)
    case proximityLightingNeighbor(relayNumber: UInt8, neighborAddresses: [Address])
}

@main struct ScopedImportTests {
    typealias R = ProximityLightingTopologyReconciler
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { print("FAIL: " + message); exit(1) }
    }
    static func payload() -> [String: Any] {
        var paths = Array(repeating: ["items": [0,0,0]], count: 32); paths[0] = ["items": [2,5,0]]
        var zones = Array(repeating: ["addresses": [Int]()], count: 32); zones[1] = ["addresses": [2,5]]
        var spaceZones = Array(repeating: ["items": [[String: Int]]()], count: 32)
        spaceZones[1] = ["items": [["groupAddress": 49152, "deviceAddress": 2], ["groupAddress": 49152, "deviceAddress": 5]]]
        return ["groups": [["address": "C000", "name": "Group 1", "profile": ["type": 7, "proximityLightingNumber": 2],
                            "proximityLightingPath": ["paths": paths, "zones": zones]]],
                "spaceData": ["proximityLightingSchemaVersion": 1, "triggerZones": spaceZones],
                "nodes": [2,5].map { address -> [String: Any] in
                    ["uuid": "device-" + String(address), "unicastAddress": Address(address).hex, "groupAddress": "C000", "groupState": 1,
                     "elements": [["models": [["modelId": "0A780001", "subscribe": ["C000"]]]]]]
                }]
    }
    private static func preflight(_ payload: [String: Any]) -> ProximityLightingImportPreflight? {
        ProximityLightingImportPreflight.parse(spaceJsonData: payload, nodeDicts: payload["nodes"] as! [[String: Any]],
            groupDicts: payload["groups"] as! [[String: Any]], initialize: true)
    }
    struct Fixture { let network: MeshNetwork; let space: SpaceData; let group: Group; let nodes: [Node] }
    static func fixture(networkId: String = "AA", uuid: UUID = UUID()) throws -> Fixture {
        let network = MeshNetwork(uuid), group = Group(0xC000)
        let space = SpaceData(network: network, networkId: networkId)
        let p = payload(), expected = preflight(p)!.reconciliation!.snapshot
        group.subNetworkId = networkId; group.network = network; network.groups = [group]
        group.info.proximityLightingPath = .init(paths: expected.groups[0].paths.map { .init(items: $0.map { .init(address: $0) }) },
                                                zones: expected.groups[0].zones.map { .init(addresses: $0) })
        space.triggerZones = preflight(p)!.triggerZones!
        let nodes = try (p["nodes"] as! [[String: Any]]).map { try jsonDecoder.decode(Node.self, from: JSONSerialization.data(withJSONObject: $0)) }
        for node in nodes { node.network = network; node.subNetworkId = networkId; node.proximityLightingNeighborAddresses = [node.primaryUnicastAddress == 2 ? 5 : 2] }
        network.nodes = nodes
        MeshNetwork.stored[space.meshUUID + networkId] = network; SpaceData.stored[networkId] = space
        GroupInfo.stored[space.meshUUID + networkId + group.address.address.hex] = group.info
        return .init(network: network, space: space, group: group, nodes: nodes)
    }
    static func main() throws {
        let target = try fixture(), other = try fixture(networkId: "BB"), sameSite = try fixture(networkId: "CC", uuid: target.network.uuid)
        let expected = preflight(payload())!.reconciliation!.snapshot
        require(target.nodes.map(\.uuid) == other.nodes.map(\.uuid), "fixture must reuse L1/L2 identities across Sites")
        for current in [nil, MeshNetwork(), other.network, sameSite.network, target.network] {
            MeshNetworkManager.instance.meshNetwork = current
            MeshNetworkManager.instance.currentNetworkKey.networkId = current === target.network ? "AA" : "BB"
            let prepared = ProximityLightingLifecycleCoordinator.begin(space: target.space, groups: [target.group], nodes: target.nodes).prepare()
            require(prepared.normalized.snapshot == expected, "explicit import must preserve all 32/32/32 entries independently of current network")
            let imported = ProximityLightingLifecycleCoordinator.commit(prepared, isImportApplication: true)
            require(imported != nil && imported!.syncDatas.isEmpty && target.space.dirtyCount == 0, "authoritative import must not create cloud edits or device tasks")
            let offline = ProximityLightingLifecycleCoordinator.begin(space: target.space).prepare()
            require(offline.normalized.snapshot == expected, "noncurrent Space snapshot must resolve its own stored network")
            let plan = ProximityLightingTopologyPlanner.makePlan(space: target.space)
            require(target.nodes.allSatisfy { $0.getNodeSyncProximityLighting(topologyPlan: plan) == nil }, "valid topology must produce no tasks")
        }
        require(Group.globalMemberReads == 0, "scoped paths must never call SDK global group.nodes")
        // Exact same addresses from another Site must not supply missing target nodes.
        let mixed = ProximityLightingLifecycleCoordinator.begin(space: target.space, groups: [target.group], nodes: other.nodes).prepare()
        require(ProximityLightingLifecycleCoordinator.commit(mixed, isImportApplication: true) == nil, "mixed-site input must be rejected")
        let damaged = ProximityLightingLifecycleCoordinator.begin(space: target.space, groups: [target.group], nodes: [target.nodes[0]]).prepare()
        require(ProximityLightingLifecycleCoordinator.commit(damaged, isImportApplication: true) == nil, "import must not persist destructive membership repairs")
        var invalid = payload(); var invalidNodes = invalid["nodes"] as! [[String: Any]]
        invalidNodes[0]["groupAddress"] = "C001"; invalid["nodes"] = invalidNodes
        require(preflight(invalid)!.hasValidationIssues, "declared membership must agree with subscriptions")
        invalid = payload(); invalidNodes = invalid["nodes"] as! [[String: Any]]
        invalidNodes.removeLast(); invalid["nodes"] = invalidNodes
        require(preflight(invalid)!.hasValidationIssues, "dangling references must not silently become repairs")
        var legacy = payload(); var legacyExtension = legacy["spaceData"] as! [String: Any]
        legacyExtension.removeValue(forKey: "proximityLightingSchemaVersion"); legacy["spaceData"] = legacyExtension
        require(preflight(legacy)?.hasValidationIssues == false, "legacy payload must retain valid topology")
        var ordinary = payload(); var ordinaryGroups = ordinary["groups"] as! [[String: Any]]
        ordinaryGroups[0]["profile"] = ["type": 0]; ordinaryGroups[0].removeValue(forKey: "proximityLightingPath")
        ordinary["groups"] = ordinaryGroups; ordinary["spaceData"] = ["proximityLightingSchemaVersion": 1, "triggerZones": [[String: Any]]()]
        require(preflight(ordinary)?.hasValidationIssues == false, "non-proximity profile is a valid import")
        require(preflight(ordinary)?.reconciliation?.snapshot.groups.first?.relayNumber == 2, "preflight must match the runtime default for an omitted Relay")
        var missing = payload(); missing["spaceData"] = ["proximityLightingSchemaVersion": 1]
        require(preflight(missing) == nil, "schema 1 must not silently accept missing zones")
        missing["spaceData"] = ["proximityLightingSchemaVersion": 2, "triggerZones": []]
        require(preflight(missing) == nil, "unknown schema must remain protected")
        var duplicate = payload(); var duplicateGroups = duplicate["groups"] as! [[String: Any]]
        var duplicatePath = duplicateGroups[0]["proximityLightingPath"] as! [String: Any]
        var duplicateZones = duplicatePath["zones"] as! [[String: Any]]
        duplicateZones[1]["addresses"] = [2,5,2]; duplicatePath["zones"] = duplicateZones
        duplicateGroups[0]["proximityLightingPath"] = duplicatePath; duplicate["groups"] = duplicateGroups
        require(preflight(duplicate)?.hasValidationIssues == false, "equivalent duplicate membership can normalize without destructive repair")
        require(preflight(duplicate)?.reconciliation?.snapshot == expected, "duplicate normalization must preserve the rest of the layout")
        let duplicateFixture = try fixture(networkId: "FF")
        duplicateFixture.group.info.proximityLightingPath!.zones[1].addresses.append(2)
        let duplicateImport = ProximityLightingLifecycleCoordinator.begin(space: duplicateFixture.space,
            groups: [duplicateFixture.group], nodes: duplicateFixture.nodes).prepare()
        require(ProximityLightingLifecycleCoordinator.commit(duplicateImport, isImportApplication: true) != nil,
                "equivalent duplicate import must apply")
        require(duplicateFixture.space.dirtyCount == 0 && duplicateFixture.group.info.proximityLightingPath!.zones[1].addresses == [2,5],
                "normalizing duplicates must not create a cloud edit")
                let unknown = try fixture(networkId: "EE")
        SpaceData.stored.removeValue(forKey: "EE")
        require(unknown.nodes[0].getNodeSyncProximityLighting() == nil, "missing Space must not generate a Group-only or Disable fallback")
                // Legitimate member deletion still cleans peers, while equivalent logical edits still upload.
        var deletion = ProximityLightingLifecycleCoordinator.begin(space: target.space, groups: [target.group], nodes: target.nodes)
        deletion.updateMembers(group: target.group, members: [target.nodes[0]])
        require(ProximityLightingLifecycleCoordinator.commit(deletion.prepare()) != nil, "explicit member removal must still commit")
        require(target.space.dirtyCount == 1, "explicit deletion must mark cloud dirty")
        let clean = try fixture(networkId: "DD")
        var edit = ProximityLightingLifecycleCoordinator.begin(space: clean.space, groups: [clean.group], nodes: clean.nodes)
        let noPaths = GroupProximityLightingPathData(paths: Array(repeating: [Address?](repeating: nil, count: 3), count: 32).map { .init(items: $0.map { .init(address: $0) }) }, zones: clean.group.info.proximityLightingPath!.zones)
        edit.replaceGroupTopology(group: clean.group, path: noPaths)
        let changed = ProximityLightingLifecycleCoordinator.commit(edit.prepare())!
        require(changed.didChange && changed.syncDatas.isEmpty && clean.space.dirtyCount == 1, "same neighbors must not suppress logical edits")
        if CommandLine.arguments.count == 2 {
            let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
            let inspected = preflight(root["data"] as! [String: Any])
            require(inspected?.hasValidationIssues == false, "provided server snapshot must pass actual import preflight")
            print("PASS: provided server snapshot preflight")
        }
        print("PASS: scoped import/planner/coordinator execution, colliding Sites/Spaces, no cloud side effects, destructive import guard, explicit deletion and equivalent logical edits")
    }
}
