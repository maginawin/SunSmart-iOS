import Foundation
enum NetworkApiError { case configurationUnavailable, configurationExportInvalid }

enum Fixture {
    static var revision: Int? = 1, dirty = false, baselineWrite = false, resumeWrite = false
    static var failReadback = false, pendingDeletion = false, current = true
    static var exports = 0, commits = 0, finishes = 0, validations = 0
    static func reset() { revision = 1; dirty = false; baselineWrite = false; resumeWrite = false; failReadback = false; pendingDeletion = false; current = true; exports = 0; commits = 0; finishes = 0; validations = 0 }
}
struct Context {}
final class ConfigurationMeshReadSnapshot {
    var revision: Int?, network: MeshNetwork?
    var currentNetwork: MeshNetwork? { revision != nil && revision == Fixture.revision ? network : nil }
}
final class SpaceData {
    let siteId = "site", id = "space", meshUUID = "mesh", meshNetworkId = "net"
    var lastUpdate = 10, deviceCount = 1, luminairesCount = 1
    var syncCloudError: NetworkApiError?
    static var instance = SpaceData()
    var storedZoneNeedsRepair = false, storedZoneUnreadable = false
    static func load(siteId: String, spaceId: String) -> [SpaceData] { [instance] }
    enum Purpose { case cleanupInspection }
    func export(purpose: Purpose = .cleanupInspection, allowsProtectedInspection: Bool = false,
                readSnapshot: ConfigurationMeshReadSnapshot? = nil) async -> [String: Any]? {
        Fixture.exports += 1
        if storedZoneUnreadable || (Fixture.failReadback && Fixture.exports == 2) { return nil }
        readSnapshot?.network = MeshNetwork.instance; readSnapshot?.revision = Fixture.revision
        return ["nodes": [["uuid": MeshNetwork.instance.nodes[0].uuid.uuidString]], "updateTimestamp": lastUpdate, "zoneNeedsRepair": storedZoneNeedsRepair]
    }
}
final class Group { let isVirtual = false; struct Address { let address: UInt16 = 0xC001 }; let address = Address() }
final class Node {
    enum DeviceType { case light }; let uuid = UUID(); let deviceType = DeviceType.light
    func clearSyncStateCache() {}
}
final class MeshNetwork {
    static let instance = MeshNetwork(); let groups = [Group()], nodes = [Node()]
    static func load(meshUUID: String, subnetworkId: String) -> MeshNetwork? { instance }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager(); var meshNetwork: MeshNetwork? = MeshNetwork.instance
    var schedules = [Int](), switchs = [Int]()
}
enum GroupInfo {
    static func obsoleteSyncExtensionCleanup(meshUUID: String, networkId: String, validAddresses: Set<UInt16>) throws -> (() throws -> Void)? { nil }
}
enum Schedule { static func load(meshUUID: String, meshNetworkId: String) -> [Int] { [] } }
enum DeviceSwitchData { static func load(meshUUID: String, meshNetworkId: String) -> [Int] { [] } }
enum ProximityLightingTopologyContext {
    static func network(for space: SpaceData) -> MeshNetwork? { MeshNetwork.instance }
    static func loadGroupInfo(network: MeshNetwork, space: SpaceData) {}
    static func realNodes(in network: MeshNetwork) -> [Node] { network.nodes }
}
enum SpaceSyncCleanupPolicy {
    struct Topology { let snapshot = 1 }
    struct Device { let uuid: String }
    struct Result {
        let didChange: Bool, topology = Topology(), repairs = [String]()
        var devices: [Device] { [.init(uuid: MeshNetwork.instance.nodes[0].uuid.uuidString)] }
    }
    static func normalize(_ payload: [String: Any]) throws -> Result { Fixture.validations += 1; return .init(didChange: Fixture.dirty || payload["zoneNeedsRepair"] as? Bool == true) }
    static func equivalentTopology(_ a: Int, _ b: Int) -> Bool { a == b }
}
enum ProximityLightingLifecycleCoordinator {
    struct Preparation { let isValid = true, sourceSnapshot = 1; let normalized = SpaceSyncCleanupPolicy.Topology() }
    struct Transaction { func prepare() -> Preparation { .init() } }
    static func begin(space: SpaceData, groups: [Group], nodes: [Node], network: MeshNetwork) -> Transaction { .init() }
    static func commit(_ preparation: Preparation, hasAdditionalLogicalChange: Bool, automaticCleanupSnapshot: Int, applyAdditionalChanges: () throws -> Void) -> Bool? {
        try! applyAdditionalChanges(); Fixture.commits += 1; Fixture.dirty = false
        Fixture.revision = Fixture.revision.map { $0 + 1 }; return true
    }
}
enum SpaceConfigurationSafety {
    static func configurationSyncError(_ space: SpaceData) -> NetworkApiError { .configurationUnavailable }
    @discardableResult
    static func recordSyncFailure(_ space: SpaceData, error: NetworkApiError, stage: String) -> Bool {
        space.syncCloudError = error; return false
    }
    static func recoverUpgradeBaselineIfNeeded(_ space: SpaceData, readLocal: () async -> [String: Any]?) async -> Bool { true }
    static func canCleanSyncReferences(_ space: SpaceData) -> Bool { true }
    static func recoveryState(_ space: SpaceData) throws -> Context { Context() }
    static func block(_ space: SpaceData, reason: String) {}
    static func verifySyncCleanupBaseline(_ space: SpaceData, local: [String: Any]) async -> Bool {
        if Fixture.baselineWrite { Fixture.revision = Fixture.revision.map { $0 + 1 } }; return true
    }
    static func isCurrent(_ context: Context, space: SpaceData) -> Bool { Fixture.current }
    static func beginSyncReferenceCleanup(_ space: SpaceData, payload: [String: Any]) -> Bool { true }
    static func hasPendingDeletionCleanup(_ space: SpaceData) -> Bool { Fixture.pendingDeletion }
    static func finishSyncReferenceCleanup(_ space: SpaceData, changed: Bool) -> Bool { Fixture.finishes += 1; return true }
    static func isBlocked(_ space: SpaceData) -> Bool { false }
}
enum DevicePermanentDeletionContext {
    static func resume(space: SpaceData) { if Fixture.resumeWrite { Fixture.revision = Fixture.revision.map { $0 + 1 } } }
}
enum SpaceConfigurationIntegrityPolicy { static func integer(_ value: Any?) -> Int? { value as? Int } }
let proximityLightingImportSyncNotificationName = "test"
struct ProximityLightingImportSyncRequest { let spaceId: String, meshUUID: String, networkId: String }

@main struct SpaceSyncReadbackReuseTests {
    @MainActor static func main() async {
        let space = SpaceData.instance
        Fixture.reset()
        var success = await SpaceSyncCleanupCoordinator.run(space, scope: .init())
        precondition(success && Fixture.exports == 2 && Fixture.finishes == 1 && Fixture.validations == 2,
                     "unchanged read must validate the reloaded persisted Space")
        Fixture.reset(); Fixture.dirty = true
        success = await SpaceSyncCleanupCoordinator.run(space, scope: .init())
        precondition(success && Fixture.exports == 2 && Fixture.commits == 1 && Fixture.finishes == 1,
                     "changed cleanup must read back committed state")
        Fixture.reset(); Fixture.baselineWrite = true
        success = await SpaceSyncCleanupCoordinator.run(space, scope: .init())
        precondition(success && Fixture.exports == 2, "baseline await invalidation must force readback")
        Fixture.reset(); Fixture.resumeWrite = true
        success = await SpaceSyncCleanupCoordinator.run(space, scope: .init())
        precondition(success && Fixture.exports == 2, "deletion recovery write must force readback")
        Fixture.reset(); Fixture.revision = nil
        success = await SpaceSyncCleanupCoordinator.run(space, scope: .init())
        precondition(success && Fixture.exports == 2, "unknown revision must never reuse")
        Fixture.reset(); Fixture.dirty = true; Fixture.failReadback = true
        success = await SpaceSyncCleanupCoordinator.run(space, scope: .init())
        precondition(!success && Fixture.finishes == 0, "failed readback must not finish recovery")
        Fixture.reset(); Fixture.current = false
        success = await SpaceSyncCleanupCoordinator.run(space, scope: .init())
        precondition(!success && Fixture.finishes == 0, "stale authority context must not finish")
        Fixture.reset(); Fixture.pendingDeletion = true
        success = await SpaceSyncCleanupCoordinator.run(space, scope: .init())
        precondition(!success && Fixture.finishes == 0, "pending deletion must not be skipped")
        for unreadable in [false, true] {
            Fixture.reset()
            let caller = SpaceData()
            SpaceData.instance = SpaceData()
            SpaceData.instance.storedZoneNeedsRepair = !unreadable
            SpaceData.instance.storedZoneUnreadable = unreadable
            precondition(caller !== SpaceData.instance && caller.lastUpdate == SpaceData.instance.lastUpdate)
            success = await SpaceSyncCleanupCoordinator.run(caller, scope: .init())
            precondition(!success && Fixture.exports == 2 && Fixture.finishes == 0,
                         "same-timestamp stale caller must not hide persisted Zone repairs or decode failure")
        }
        print("PASS: persisted Space readback; unchanged/mutating/unknown revision export=2; same-timestamp stale/damaged Zones and recovery protections")
    }
}
