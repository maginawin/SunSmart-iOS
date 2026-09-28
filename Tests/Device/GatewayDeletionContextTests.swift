import Foundation

let testHomeDirectory = CommandLine.arguments[1]
enum UserData {
    static var currentUserId = "owner"
    static var currentServerRegion = "test"
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
    var currentNetworkKey = NetworkKey()
}
struct NetworkKey { var isPrimary = true }
final class MeshNetwork {
    let uuid = UUID()
    var nodes: [Node] = []
    var scenes: [Scene] = []
    var exclusions: [UInt16] = []
    var savesSucceed = true
    static var stored: [String: MeshNetwork] = [:]
    static func load(meshUUID: String, subnetworkId: String) -> MeshNetwork? { stored[meshUUID] }
    func remove(node: Node) {
        exclusions.append(node.primaryUnicastAddress)
        nodes.removeAll { $0 === node }
        _ = Node.delete(meshUUID: uuid.uuidString, address: node.primaryUnicastAddress)
        node.network = nil
    }
    func save() -> Bool { savesSucceed }
}
final class Scene {
    var addresses: [UInt16]
    init(_ addresses: [UInt16]) { self.addresses = addresses }
    func remove(address: UInt16) { addresses.removeAll { $0 == address } }
    func save() -> Bool { true }
}
final class Node {
    struct Element { var unicastAddress: UInt16? }
    var uuid = UUID()
    var primaryUnicastAddress: UInt16 = 10
    var subNetworkId = "primary"
    var network: MeshNetwork?
    var elements: [Element] = [.init(unicastAddress: 10), .init(unicastAddress: 11)]
    var productIdentifier: UInt16? = 0x2721
    var createdTimestamp: Int64 = 100
    static var records: [String: [Node]] = [:]
    static var deletesSucceed = true
    static func load(meshUUID: String, address: UInt16) -> [Node] {
        (records[meshUUID] ?? []).filter { $0.primaryUnicastAddress == address }
    }
    static func delete(meshUUID: String, address: UInt16) -> Bool {
        guard deletesSucceed else { return false }
        records[meshUUID]?.removeAll { $0.primaryUnicastAddress == address }
        return true
    }
    enum PreConfiguration {
        static var deleted: [UInt16] = []
        static func delete(meshUUID: String, nodeAddress: UInt16) -> Bool {
            deleted.append(nodeAddress); return true
        }
    }
}
final class SiteData {
    let id = UUID().uuidString
    let meshUUID: String
    var meshNetworkId = "primary"
    init(_ mesh: MeshNetwork) { meshUUID = mesh.uuid.uuidString }
}
final class GatewayModel {
    let siteId: String
    let mac = "AABBCC"
    var address: UInt16 = 10
    var serverDeletionPendingLocalReset = false
    var isServerDeletionInProgress = false
    static var records: [GatewayModel] = []
    init(_ site: SiteData) { siteId = site.id }
    static func load(siteId: String) -> [GatewayModel] { records.filter { $0.siteId == siteId } }
    static func load(siteId: String, macAddress: String) -> [GatewayModel] {
        load(siteId: siteId).filter { $0.mac.uppercased() == macAddress.uppercased() }
    }
    func delete() -> Bool { Self.records.removeAll { $0 === self }; return true }
}
final class SpaceData {
    enum Status { case bound, notBound }
    let siteId: String
    var relevanceGatewayId: String?
    var gatewayStatus = Status.bound
    var gatewayLastOnline: Int? = 100
    static var records: [SpaceData] = []
    init(_ site: SiteData, mac: String) { siteId = site.id; relevanceGatewayId = mac }
    static func load(siteId: String) -> [SpaceData] { records.filter { $0.siteId == siteId } }
    func save() -> Bool { true }
}
final class Schedule {
    var nodeAddresses: [UInt16] = [10, 11, 20]
    var needDeleteNodeAddresses: [UInt16] = [11, 21]
    static var records: [Schedule] = []
    static func load(meshUUID: String, meshNetworkId: String) -> [Schedule] { records }
    func save(meshUUID: String, meshNetworkId: String) -> Bool { true }
}
final class MeshDistributionData {
    var distributionAddress: UInt16 = 10
    static var record: MeshDistributionData?
    static func load(meshUUID: String, meshNetworkId: String, productId: UInt16) -> MeshDistributionData? { record }
    func delete(meshUUID: String, networkId: String, productId: UInt16) -> Bool { Self.record = nil; return true }
}
final class Database {
    var fails = false
    enum Failure: Error { case unavailable }
    func transaction(_ block: () throws -> Void) throws {
        if fails { throw Failure.unavailable }
        try block()
    }
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Database? = Database()
}

// Only authorization, HTTP and time are substituted for the batch request path.
@MainActor
enum BatchRequestClock { static var now: TimeInterval = 100 }
@MainActor
final class GatewayServerAuthorizationService {
    static let shared = GatewayServerAuthorizationService()
    var duringWait: (() -> Void)?
    func waitForInFlightAuthorizationToFinish(gateway: GatewayModel) async {
        await Task.yield()
        duringWait?()
    }
}
@MainActor
final class NetworkRequest {
    enum API { case gatewayDelete(gatewayId: String) }
    enum Failure: Error { case unavailable }
    static let shared = NetworkRequest()
    var succeeded = true
    var durations: [TimeInterval] = []
    var beforeRequest: (() -> Void)?
    func request(_ api: API, maximumDuration: TimeInterval) async -> Result<Void, Failure> {
        beforeRequest?()
        durations.append(maximumDuration)
        return succeeded ? .success(()) : .failure(.unavailable)
    }
}
@MainActor
final class BatchGatewayRequestHarness {
    var isCurrent = true
    func deleteServer(context: GatewayDeletionContext, gateway: GatewayModel, deadline: TimeInterval) async -> Bool {
        // BATCH_DELETE_SERVER
    }
}

@main
struct GatewayDeletionContextTests {
    struct Fixture {
        let mesh: MeshNetwork
        let site: SiteData
        let node: Node
        let gateway: GatewayModel
        init(product: UInt16 = 0x2721, spaceCount: Int = 0) {
            UserData.currentUserId = "owner"
            UserData.currentServerRegion = "test"
            Node.deletesSucceed = true
            SunSmartDataManager.shared.db = Database()
            mesh = MeshNetwork(); site = SiteData(mesh); node = Node(); gateway = GatewayModel(site)
            node.productIdentifier = product; node.network = mesh
            mesh.nodes = [node]
            mesh.scenes = [Scene([10, 11, 20])]
            MeshNetwork.stored[site.meshUUID] = mesh
            Node.records[site.meshUUID] = [node]
            MeshNetworkManager.instance.meshNetwork = mesh
            MeshNetworkManager.instance.currentNetworkKey = NetworkKey()
            GatewayModel.records = [gateway]
            SpaceData.records = (0..<spaceCount).map { _ in SpaceData(site, mac: gateway.mac) }
            Schedule.records = [Schedule()]
            MeshDistributionData.record = MeshDistributionData()
        }
        func context() -> GatewayDeletionContext {
            GatewayDeletionContext(site: site, gateway: gateway, node: node)!
        }
    }
    @MainActor
    static func main() async {
        for product: UInt16 in [0x2721, 0x2701, 0x2702, 0x2703] {
            for count in [0, 1, 3] {
                let f = Fixture(product: product, spaceCount: count)
                let context = f.context()
                check(context.prepare() && context.recordServerDeletion(), "Site Gateway prepares without a Space context")
                // SDK Reset success removes the node and clears its network reference.
                f.mesh.remove(node: f.node)
                check(context.finish(resetConfirmed: true), "SDK removal is idempotent at local completion")
                check(GatewayModel.records.isEmpty && Node.load(meshUUID: f.site.meshUUID, address: 10).isEmpty, "both stores cleared")
                check(SpaceData.records.count == count && SpaceData.records.allSatisfy { $0.relevanceGatewayId == nil && $0.gatewayStatus == .notBound && $0.gatewayLastOnline == nil }, "all associations cleared, Spaces retained")
                check(f.mesh.scenes[0].addresses == [20] && Schedule.records[0].nodeAddresses == [20]
                    && Schedule.records[0].needDeleteNodeAddresses == [21], "primary and secondary element references cleared")
                check(MeshDistributionData.record == nil && Node.PreConfiguration.deleted.contains(10), "gateway extensions cleared")
                check(GatewayDeletionContext.blocksImport(siteId: f.site.id, mac: f.gateway.mac, node: f.node, createdTimestamp: 100), "old snapshot blocked")
            }
        }
        let offline = Fixture()
        let direct = offline.context()
        check(direct.prepare() && direct.recordServerDeletion() && direct.finish(resetConfirmed: false), "unreachable Gateway still completes local removal")
        check(offline.mesh.exclusions.contains(10), "unreset device address enters exclusions")

        let failed = Fixture()
        let operation = failed.context()
        check(operation.prepare(), "prepare")
        check(GatewayDeletionContext.blocksRegistration(gateway: failed.gateway, node: failed.node), "different caller cannot register while deleting")
        operation.cancelPreparation(); operation.release()
        check(!GatewayDeletionContext.blocksRegistration(gateway: failed.gateway, node: failed.node) && failed.mesh.nodes.count == 1, "server failure preserves local instance and releases registration")

        let interrupted = Fixture(spaceCount: 1)
        var first: GatewayDeletionContext? = interrupted.context()
        check(first!.prepare() && first!.recordServerDeletion(), "persist confirmation")
        var contender: GatewayDeletionContext? = interrupted.context()
        check(!contender!.prepare(), "one active delete per Gateway")
        contender = nil
        check(!GatewayDeletionContext.resume(site: interrupted.site) && !GatewayModel.records.isEmpty, "failed contender cannot release the active Reset protection")
        first = nil
        check(GatewayDeletionContext.resume(site: interrupted.site) && GatewayModel.records.isEmpty, "confirmed interrupted operation resumes locally")

        let prepared = Fixture()
        var preflight: GatewayDeletionContext? = prepared.context()
        check(preflight!.prepare(), "durable preparation")
        preflight = nil
        check(!GatewayDeletionContext.resume(site: prepared.site) && !GatewayModel.records.isEmpty
            && !GatewayDeletionContext.hasPendingDeletion(siteId: prepared.site.id, mac: prepared.gateway.mac), "unconfirmed interruption releases only preparation")

        let ambiguous = Fixture()
        var request: GatewayDeletionContext? = ambiguous.context()
        check(request!.prepare() && request!.recordServerRequest(), "HTTP must have durable intent")
        request = nil
        check(!GatewayDeletionContext.resume(site: ambiguous.site)
            && GatewayDeletionContext.blocksRegistration(gateway: ambiguous.gateway, node: ambiguous.node),
            "unknown HTTP outcome survives restart and cannot register again")

        let confirmedFlag = Fixture()
        var beforeConfirmation: GatewayDeletionContext? = confirmedFlag.context()
        check(beforeConfirmation!.prepare() && beforeConfirmation!.recordServerRequest(), "prepare pending flag recovery")
        confirmedFlag.gateway.serverDeletionPendingLocalReset = true
        beforeConfirmation = nil
        let manualRetry = confirmedFlag.context()
        check(manualRetry.prepare() && manualRetry.finish(resetConfirmed: false),
            "durable pending flag upgrades prepared receipt when retrying directly from Space")

        let fromSpace = Fixture(spaceCount: 2)
        let spaceRoute = MeshNetwork()
        MeshNetworkManager.instance.meshNetwork = spaceRoute
        MeshNetworkManager.instance.currentNetworkKey.isPrimary = false
        check(GatewayDeletionContext(site: fromSpace.site, gateway: fromSpace.gateway, node: fromSpace.node) == nil,
            "legacy initializer cannot silently use the wrong route")
        let explicitSite = GatewayDeletionContext(site: fromSpace.site, gateway: fromSpace.gateway,
            node: fromSpace.node, siteNetwork: fromSpace.mesh)!
        check(explicitSite.prepare() && explicitSite.recordServerRequest()
            && explicitSite.recordServerDeletion() && explicitSite.finish(resetConfirmed: false),
            "explicit Site snapshot supports server and local stages from Space")
        check(MeshNetworkManager.instance.meshNetwork === spaceRoute && spaceRoute.nodes.isEmpty,
            "Gateway cleanup never switches or removes the active Space route")

        let disk = Fixture()
        var retry: GatewayDeletionContext? = disk.context()
        check(retry!.prepare() && retry!.recordServerDeletion(), "prepare failed cleanup")
        SunSmartDataManager.shared.db!.fails = true
        check(!retry!.finish(resetConfirmed: true), "local persistence failure is not success")
        retry = nil; SunSmartDataManager.shared.db!.fails = false
        check(!GatewayDeletionContext.resume(site: disk.site) && GatewayModel.records.isEmpty, "retry keeps the successful Reset receipt and completes remaining app data")

        let reused = Fixture()
        let old = reused.context()
        check(old.prepare() && old.recordServerDeletion(), "prepare identity guard")
        let newNode = Node(); newNode.network = reused.mesh; newNode.createdTimestamp = 200
        Node.records[reused.site.meshUUID] = [newNode]; reused.mesh.nodes = [newNode]
        check(!old.finish(resetConfirmed: false) && reused.mesh.nodes.first === newNode, "late cleanup cannot erase a reused address")

        let addedAgain = Fixture()
        let deletion = addedAgain.context()
        check(deletion.prepare() && deletion.recordServerDeletion() && deletion.finish(resetConfirmed: false), "first provisioning deleted")
        let newer = Node(); newer.uuid = addedAgain.node.uuid; newer.createdTimestamp = 200
        Node.records[addedAgain.site.meshUUID] = [newer]
        let newGateway = GatewayModel(addedAgain.site); GatewayModel.records = [newGateway]
        check(!GatewayDeletionContext.blocksSave(newGateway)
            && !GatewayDeletionContext.blocksRegistration(gateway: newGateway, node: newer), "same physical device with newer provisioning can be saved and registered")
        check(!GatewayDeletionContext.serverDeletionConfirmed(siteId: addedAgain.site.id, mac: newGateway.mac), "old snapshot cannot clear the newly provisioned Gateway associations")

        let legacy = Fixture(spaceCount: 1)
        legacy.gateway.serverDeletionPendingLocalReset = true
        check(GatewayDeletionContext.resume(site: legacy.site) && GatewayModel.records.isEmpty,
              "legacy confirmed deletion adopts a receipt and finishes without a Space checkpoint")
        let legacyMissingNode = Fixture()
        legacyMissingNode.gateway.serverDeletionPendingLocalReset = true
        legacyMissingNode.mesh.remove(node: legacyMissingNode.node)
        check(GatewayDeletionContext.resume(site: legacyMissingNode.site) && GatewayModel.records.isEmpty,
              "legacy pending Gateway can finish when SDK already removed its Node")

        UserData.currentUserId = "editor"
        check(!deletion.isCurrent && !GatewayDeletionContext.hasPendingDeletion(siteId: reused.site.id, mac: reused.gateway.mac), "account scope isolated")
        await testBatchServerRequestStart()
        print("GatewayDeletionContextTests passed")
    }

    @MainActor
    static func testBatchServerRequestStart() async {
        enum Scenario: CaseIterable { case cancelled, deadlineReached, deadlineExceeded, success, requestFailed }
        for scenario in Scenario.allCases {
            let f = Fixture(), context = f.context(), operation = BatchGatewayRequestHarness()
            let request = NetworkRequest.shared
            BatchRequestClock.now = 100
            request.durations = []
            request.succeeded = scenario != .requestFailed
            request.beforeRequest = {
                // Once HTTP begins, cancellation must retain uncertainty protection.
                context.cancelPreparation()
                check(GatewayDeletionContext.hasPendingDeletion(siteId: f.site.id, mac: f.gateway.mac),
                      "request intent must be durable before invoking HTTP")
            }
            GatewayServerAuthorizationService.shared.duringWait = {
                check(GatewayDeletionContext.hasPendingDeletion(siteId: f.site.id, mac: f.gateway.mac),
                      "preparation must protect the Gateway during authorization")
                switch scenario {
                case .cancelled: operation.isCurrent = false
                case .deadlineReached: BatchRequestClock.now = 130
                case .deadlineExceeded: BatchRequestClock.now = 131
                case .success, .requestFailed: BatchRequestClock.now = 105
                }
            }
            let result = await GatewayDeletionCoordinator().delete(using: .init(
                isOnline: { true }, isCurrent: { operation.isCurrent && context.isCurrent },
                serverAlreadyDeleted: { context.serverAlreadyDeleted }, permission: { .allowed },
                prepare: { context.prepare() },
                deleteServer: { await operation.deleteServer(context: context, gateway: f.gateway, deadline: 130) },
                recordServerDeletion: { context.recordServerDeletion() },
                canReset: { false }, reset: { false },
                finishLocal: { context.finish(resetConfirmed: $0) },
                cancelPreparation: { context.cancelPreparation() }))
            context.release()
            switch scenario {
            case .cancelled, .deadlineReached, .deadlineExceeded:
                check(result == .failed(.server) && request.durations.isEmpty,
                      "cancelled or expired preflight must not call HTTP")
                if scenario != .cancelled {
                    check(!GatewayDeletionContext.hasPendingDeletion(siteId: f.site.id, mac: f.gateway.mac),
                          "expired preflight releases its preparation immediately")
                }
                _ = GatewayDeletionContext.resume(site: f.site)
                check(!GatewayDeletionContext.hasPendingDeletion(siteId: f.site.id, mac: f.gateway.mac)
                    && !GatewayDeletionContext.blocksSave(f.gateway)
                    && !GatewayDeletionContext.blocksRegistration(gateway: f.gateway, node: f.node),
                    "unsent request must not leave persistent save or registration protection")
                check(f.mesh.nodes.contains { $0 === f.node } && GatewayModel.records.contains { $0 === f.gateway },
                      "unsent request preserves the local Gateway and node")
            case .success:
                check(result == .deleted(resetConfirmed: false) && request.durations == [25],
                      "valid preflight sends once with remaining duration and completes deletion")
            case .requestFailed:
                _ = GatewayDeletionContext.resume(site: f.site)
                check(result == .failed(.server) && request.durations == [25]
                    && GatewayDeletionContext.blocksRegistration(gateway: f.gateway, node: f.node),
                    "an actual request with unknown outcome retains protection across recovery")
            }
            request.beforeRequest = nil
            GatewayServerAuthorizationService.shared.duringWait = nil
        }
    }
    static func check(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
}
