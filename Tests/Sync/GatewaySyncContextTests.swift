import Foundation

typealias Address = UInt16
extension String { var localizedString: String { self }; var hex: String { self } }
enum UserData { static var currentUserId = "account", currentServerRegion = "region" }
struct Key: Codable { var index: UInt16; var boundNetworkKeyIndex: UInt16 = 0; var networkId = "primary"; var isPrimary = true; var key = "test" }
final class MeshNetwork { var uuid = UUID(); var nodes: [Node] = []; var networkKeys = [Key(index: 0), Key(index: 1)]; var applicationKeys = [Key(index: 0), Key(index: 1, boundNetworkKeyIndex: 1)] }
final class MeshNetworkManager { static let instance = MeshNetworkManager(); var meshNetwork: MeshNetwork? = MeshNetwork(); var currentNetworkKey = Key(index: 0) }
final class Node {
    enum DeviceType { case gateway, light }
    var network: MeshNetwork?; var uuid = UUID(); var primaryUnicastAddress: Address = 1
    var deviceKey: Data? = Data([1]); var macAddress: String? = "AABB"; var deviceType = DeviceType.gateway
    var networkKeys = [Key(index: 0)]
    init() { network = MeshNetworkManager.instance.meshNetwork }
}
struct Space { enum Operation { case edit }; var id = "space"; var canEditing = true; var deviceOperates: [Operation] = [.edit] }
final class SiteData {
    enum State { case normal, waitDeleted }; enum Permission { case owner, editor, visitor }
    var region = "region", id = "site", meshNetworkId = "primary"
    var meshUUID = MeshNetworkManager.instance.meshNetwork!.uuid.uuidString
    var state = State.normal, permission = Permission.owner; var spaces = [Space()]
    static var stored: SiteData?
    static func load(siteId: String) -> SiteData? { stored }
    // PRODUCTION_PERMISSION
}
final class Association { var spaceId = "space"; var appKeyIndex: UInt16 = 1 }
// Like the SDK type, supports == without declaring Equatable conformance.
struct MQTT { var value: String; static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value } }
final class GatewayModel {
    var siteId = "site", mac = "AABB"; var address: Address = 1
    var isCurrentPersistenceContext = true, isServerDeletionInProgress = false, serverDeletionPendingLocalReset = false
    var lastUpdate: Int64 = 1
    var activate = true; var apn: String?; var mqttServerInfo: MQTT?; var associatedSpaces = [Association()]
    static var stored: GatewayModel?
    static func load(siteId: String, macAddress: String) -> [GatewayModel] { stored.map { [$0] } ?? [] }
    static func normalizedMac(_ value: String) -> String { value.uppercased() }
    func update(gatewayModel: GatewayModel) { activate = gatewayModel.activate; apn = gatewayModel.apn; mqttServerInfo = gatewayModel.mqttServerInfo; associatedSpaces = gatewayModel.associatedSpaces }
    func copy() -> GatewayModel { let result = GatewayModel(); result.update(gatewayModel: self); result.lastUpdate = lastUpdate; return result }
}
enum GatewayDeletionContext { static var pending = false; static func hasPendingDeletion(siteId: String, mac: String) -> Bool { pending } }
enum SyncDevicesViewController { enum SyncType { case devices([Node]), gatewayRecovery(Node, GatewayModel, Int), gatewayServerRecovery(Node, GatewayModel), scene } }
// PRODUCTION_CONTEXT

@main struct GatewaySyncContextTests {
    static func setup() -> GatewaySyncContext {
        UserData.currentUserId = "account"; UserData.currentServerRegion = "region"
        MeshNetworkManager.instance.meshNetwork = MeshNetwork(); MeshNetworkManager.instance.currentNetworkKey = Key(index: 0)
        GatewayDeletionContext.pending = false
        let site = SiteData(), gateway = GatewayModel(), node = Node()
        SiteData.stored = SiteData(); GatewayModel.stored = GatewayModel()
        MeshNetworkManager.instance.meshNetwork!.nodes = [node]
        return GatewaySyncContext(site: site, gateway: gateway, node: node)
    }
    static func main() {
        var c = setup()
        precondition(c.error() == nil && c.prepare(for: .devices([c.node])) == nil)
        precondition(!c.accepts(.devices([c.node, Node()])) && !c.accepts(.scene))
        precondition(!c.accepts(.gatewayRecovery(Node(), c.gateway, 0)))
        for empty in [false, true] {
            c = setup(); c.site.permission = .editor; SiteData.stored!.permission = .editor
            if empty { c.gateway.associatedSpaces = []; GatewayModel.stored!.associatedSpaces = [] }
            precondition(c.error() == nil, "editable Site gateway does not require an active Space")
            SiteData.stored!.spaces[0].canEditing = false
            precondition(c.error() == "no_permission")
            SiteData.stored!.spaces[0].canEditing = true
            precondition(c.prepare(for: .gatewayServerRecovery(c.node, c.gateway)) == nil)
        }
        for mutation in 0..<12 {
            c = setup(); let plan = c.capturePlan(for: .gatewayRecovery(c.node, c.gateway, 0))
            precondition(plan())
            switch mutation {
            case 0: UserData.currentUserId = "other"
            case 1: UserData.currentServerRegion = "other"
            case 2: MeshNetworkManager.instance.currentNetworkKey.isPrimary = false
            case 3: MeshNetworkManager.instance.meshNetwork!.nodes = [Node()]
            case 4: c.node.deviceKey = Data([2])
            case 5: GatewayDeletionContext.pending = true
            case 6: GatewayModel.stored = nil
            case 7: SiteData.stored!.state = .waitDeleted
            case 8: GatewayModel.stored!.associatedSpaces[0].appKeyIndex = 2
            case 9: MeshNetworkManager.instance.meshNetwork!.networkKeys[1].key = "changed"
            case 10: c.gateway.isServerDeletionInProgress = true
            default: c.gateway.isCurrentPersistenceContext = false
            }
            precondition(!plan(), "changed authority/identity/configuration must invalidate plan")
        }
        c = setup(); let recovery = c.capturePlan(for: .gatewayServerRecovery(c.node, c.gateway))
        c.gateway.mqttServerInfo = MQTT(value: "authorized"); GatewayModel.stored!.mqttServerInfo = MQTT(value: "authorized")
        c.node.networkKeys.append(Key(index: 1))
        precondition(recovery(), "own authorization and successful key binding must not invalidate plan")
        let save = c.capturePlan(for: .devices([c.node]))
        GatewayModel.stored!.mqttServerInfo = MQTT(value: "external-change")
        precondition(!save(), "Save uses captured MQTT values")
        c = setup(); let associationPlan = c.capturePlan(for: .gatewayRecovery(c.node, c.gateway, 0))
        c.gateway.associatedSpaces[0].appKeyIndex = 2
        precondition(!associationPlan(), "in-place associated Space edits must not mutate the captured desired snapshot")
        c = setup(); GatewayModel.stored!.apn = "updated"
        precondition(c.prepare(for: .gatewayRecovery(c.node, c.gateway, 0)) == nil && c.gateway.apn == "updated")
        c = setup(); GatewayModel.stored!.associatedSpaces = []
        precondition(c.prepare(for: .devices([c.node])) != nil, "SAVE must reject an externally replaced target instead of adopting it")
        precondition(c.gateway.associatedSpaces.count == 1, "rejected preparation preserves the saved binding intent")
        c = setup(); let generationPlan = c.capturePlan(for: .devices([c.node]))
        GatewayModel.stored!.lastUpdate += 1
        precondition(!generationPlan() && c.prepare(for: .devices([c.node])) != nil, "new generation must invalidate SAVE even with equal associations")
        print("PASS Site gateway context: Owner/Editor, empty associations, permissions, identity, deletion, keys, refresh and authorization writeback")
    }
}
