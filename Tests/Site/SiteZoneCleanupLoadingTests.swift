import Foundation

// The production classifier and JSON cleanup run unchanged. Mesh storage and
// topology preparation are doubled to count reads and model unavailable data.
final class SiteData {
    let id = "site", meshUUID = "mesh"
    var spaces: [SpaceData] = []
}
final class SpaceData {
    let id: String
    var siteId = "site", meshUUID = "mesh", canEditing = true, blocked = false
    init(_ id: String) { self.id = id }
}
struct MeshAddress { let address: UInt16 }
final class Group {
    struct Profile { var type = 1 }
    struct Info { var profile = Profile() }
    let address = MeshAddress(address: 0xC001)
    var isVirtual = false, info = Info()
}
final class Node {
    enum State { case normal, exitFailure }
    let uuid = UUID(), primaryUnicastAddress: UInt16 = 16
    var groupState = State.normal, group: Group?
    var elements = [0, 1]
}
final class MeshNetwork {
    var nodes: [Node] = [], groups: [Group] = []
    var valid = true, destructive = false
}
enum SpaceConfigurationSafety {
    static func isBlocked(_ space: SpaceData) -> Bool { space.blocked }
}
enum ProximityLightingTopologyContext {
    static var networks: [String: MeshNetwork] = [:], loads: [String: Int] = [:]
    static func network(for space: SpaceData) -> MeshNetwork? {
        loads[space.id, default: 0] += 1
        return networks[space.id]
    }
    static func loadGroupInfo(network: MeshNetwork, space: SpaceData) {}
    static func realNodes(in network: MeshNetwork) -> [Node] { network.nodes }
}
enum ProximityLightingTopologyPlanner {
    struct Target { var enabled = true }
    struct Plan { func target(for address: UInt16) -> Target { .init() } }
    static func normalizedAddress(for node: Node) -> UInt16 { node.primaryUnicastAddress }
}
enum ProximityLightingLifecycleCoordinator {
    struct Preparation {
        struct Normalized { let hasDestructiveRepairs: Bool }
        let network: MeshNetwork
        var isValid: Bool { network.valid }
        var normalized: Normalized { .init(hasDestructiveRepairs: network.destructive) }
    }
    struct Session {
        let network: MeshNetwork
        func prepare() -> Preparation { .init(network: network) }
    }
    struct Preview { let plan = ProximityLightingTopologyPlanner.Plan() }
    static func begin(space: SpaceData, groups: [Group], nodes: [Node], network: MeshNetwork) -> Session { .init(network: network) }
    static func preview(_ preparation: Preparation) -> Preview? { .init() }
    static func isEligible(_ type: Int) -> Bool { type == 1 }
}

@main
enum SiteZoneCleanupLoadingTests {
    static func main() {
        let site = SiteData()
        site.spaces = (0..<300).map { SpaceData("space-\($0)") }
        let network = MeshNetwork(), group = Group(), node = Node()
        node.group = group; network.nodes = [node]; network.groups = [group]
        ProximityLightingTopologyContext.networks = ["space-0": network]
        let classify = SiteTriggerZoneTopologyReader.cleanupClassifier(site: site)
        var empty = SiteExtensionData()
        empty.replaceZones((0..<100).map { _ in SiteTriggerZone() })
        precondition(SiteTriggerZoneReferenceCleanup.clean(empty, classify: classify) == empty)
        precondition(ProximityLightingTopologyContext.loads.isEmpty, "300 Spaces and 100 empty Zones must cause zero Mesh reads")
        precondition(classify(.null) == .unknown && ProximityLightingTopologyContext.loads.isEmpty,
                     "Malformed members must not trigger Mesh reads")

        func member(_ space: String, uuid: UUID = node.uuid) -> SiteJSONValue {
            .object(SiteTriggerZoneMember(identity: .init(spaceID: space, nodeUUID: uuid),
                groupAddress: 0xC001, primaryAddress: 16, deviceAddress: 16).fields)
        }
        precondition(classify(member("space-0")) == .valid)
        precondition(classify(member("space-0", uuid: UUID())) == .obsolete)
        precondition(classify(member("space-0")) == .valid)
        precondition(ProximityLightingTopologyContext.loads == ["space-0": 1], "Referenced Space must load only once")
        precondition(classify(member("space-1")) == .unknown && classify(member("space-1")) == .unknown)
        precondition(ProximityLightingTopologyContext.loads["space-1"] == 1, "Unavailable Space must stay unknown without repeated reads")
        site.spaces[2].blocked = true
        site.spaces[3].canEditing = false
        site.spaces[4].siteId = "other-site"
        for id in ["space-2", "space-3", "space-4", "missing"] {
            precondition(classify(member(id)) == .unknown && ProximityLightingTopologyContext.loads[id] == nil,
                         "Blocked, unauthorized and foreign Spaces must not load or become obsolete")
        }
        var zone = SiteTriggerZone()
        zone.fields["members"] = .array([member("space-0"), member("space-0", uuid: UUID()), member("space-1")])
        let cleaned = SiteTriggerZoneReferenceCleanup.clean(zone, classify: classify)
        precondition(cleaned.fields["members"] == .array([member("space-0"), member("space-1")]),
                     "Keep valid and unknown members; remove only confirmed obsolete members")
        // Each new cleanup sees fresh storage; no cross-operation snapshot cache.
        let fresh = SiteTriggerZoneTopologyReader.cleanupClassifier(site: site)
        precondition(fresh(member("space-0")) == .valid && ProximityLightingTopologyContext.loads["space-0"] == 2)
        network.destructive = true
        let unsafe = SiteTriggerZoneTopologyReader.cleanupClassifier(site: site)
        precondition(unsafe(member("space-0")) == .unknown, "Unsafe topology must not authorize deletion")
        print("PASS: lazy Zone inventories, zero reads for empty/malformed Zones, one read per referenced Space, failed-read caching and conservative cleanup")
    }
}
