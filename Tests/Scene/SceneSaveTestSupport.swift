import Foundation
import SQLite
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
    // ACTUAL_TRANSACTION
}

struct FixtureRecoveryState { enum Authority { case writable, waitingForAuthorization, readOnly, revoked }; enum Phase { case active, leaving }; var authority: Authority = .writable; var phase: Phase = .active; var generation = UUID(); var sceneRestoreReceipts: Data? }
typealias MeshNetwork = Network
enum SpaceConfigurationSafety { static var currentConfigurationAvailable = true
    static var recovery = FixtureRecoveryState()
    static func isBlocked(_ space: SpaceData) -> Bool { !currentConfigurationAvailable }
    static func reconcileAuthority(_ space: SpaceData, remote: [String: Any]) {
        if space.requiresPasswordVerification { recovery.authority = .waitingForAuthorization }
        else if space.permission == .visitor { recovery.authority = .readOnly }
    }
    static var failReceiptWrite = false
    static var failAppliedReceiptWrite = false
    static func recoveryState(_ space: SpaceData) throws -> FixtureRecoveryState { recovery }
    static func saveSceneRestoreReceipts(_ data: Data, context: FixtureRecoveryState, space: SpaceData) throws {
        guard !failReceiptWrite, context.generation == recovery.generation else { throw SceneConfigurationStore.Failure.persistence }
        if failAppliedReceiptWrite,
           try JSONDecoder().decode([SceneRestoreReceipt].self, from: data).contains(where: { $0.stage == .applied }) {
            throw SceneConfigurationStore.Failure.persistence
        }
        recovery.sceneRestoreReceipts = data
    }
    static func needsTimedUpgradeBaseline(_ space: SpaceData) -> Bool { false } }
final class SpaceData {
    enum Permission { case owner, editor, visitor; static var viewer: Permission { .visitor } }
    enum State { case normal, waitDeleted }
    var state: State = .normal
    let id = "space"
    var requiresPasswordVerification = false
    var disableEditorPermission = false
    var meshOTADistribution = false
    var vistorPasswordEnable = false
    var lastUploadCloudTimestamp: Int64? = 1
    var meshNetworkId: String { MeshNetworkManager.instance.currentNetworkKey.networkId.hex }
    // ACTUAL_SCENE_AUTHORITY

    var permission: Permission = .owner
    var timedSchemaVersion = 2
    func save() -> Bool { true }
    var meshUUID: String { MeshNetworkManager.instance.meshNetwork!.uuid.uuidString }
    static var value = SpaceData()
    static func load(subNetworkId: String) -> SpaceData? { value }
}
extension Network {
    struct Range { let firstScene: UInt16 = 1; let lastScene: UInt16 = 100 }
    struct Provisioner { let allocatedSceneRange = [Range()] }
    var localProvisioner: Provisioner? { Provisioner() }
    static var removalFails = false
    static var didRemove: (() -> Void)?
    var nodes: [Node] { MeshNetworkManager.instance.realNodes }
    static func load(meshUUID: String, subnetworkId: String) -> Network? { MeshNetworkManager.instance.meshNetwork }
    var scenes: [Scene] { MeshNetworkManager.instance.scenes }
    func node(withAddress address: UInt16) -> Node? { MeshNetworkManager.instance.realNodes.first { $0.primaryUnicastAddress == address || $0.addressAliases.contains(address) } }
    func remove(scene number: UInt16) throws {
        if Self.removalFails { throw SceneConfigurationStore.Failure.persistence }
        MeshNetworkManager.instance.scenes.removeAll { scene in
            if scene.number == number { scene.network = nil; return true }; return false
        }
        Scene.diskNumbers.remove(number)
        Self.didRemove?()
    }
    func add(scene: Scene) { MeshNetworkManager.instance.scenes.append(scene) }
}
extension Scene {
    static var sdkSaveFails = false
    static var diskNumbers: Set<UInt16> = []
    static func loadAddresses(meshUUID: String) -> [UInt16] { Array(diskNumbers) }
    convenience init(_ number: UInt16, name: String) { self.init(number); self.name = name }
    func save() -> Bool {
        guard !Self.sdkSaveFails else { return false }
        Self.diskNumbers.insert(number); return true
    }
}
extension GroupInfo {
    static var savingSucceeds = true
    func save(meshUUID: String? = nil, subnetworkId: String? = nil) -> Bool {
        saves += 1
        guard Self.savingSucceeds, let db = SunSmartDataManager.shared.db else { return false }
        do {
            try db.run("CREATE TABLE IF NOT EXISTS fixture_group_scene (id INTEGER PRIMARY KEY, value BLOB)")
            let address = MeshNetworkManager.instance.groups.first { $0.info === self }?.address.address ?? 0
            let data = try JSONEncoder().encode(sceneExecuteDatas)
            try db.run("INSERT OR REPLACE INTO fixture_group_scene VALUES (?, ?)", Int(address), Blob(bytes: Array(data)))
            return true
        } catch { return false }
    }
}
extension TimedSchedulerBindings {
    // ACTUAL_TIMED_COMMIT
}

extension Schedule {
    func save(meshUUID: String, meshNetworkId: String) -> Bool {
        do {
            let db = SunSmartDataManager.shared.db!
            try db.run("CREATE TABLE IF NOT EXISTS fixture_slots (id INTEGER PRIMARY KEY, value BLOB)")
            let data = try JSONEncoder().encode(nodeSlots)
            try db.run("INSERT OR REPLACE INTO fixture_slots VALUES (?, ?)", id, Blob(bytes: Array(data)))
            return true
        } catch { return false }
    }
}

extension Group {
    // ACTUAL_UPDATE_GROUP
}

struct FixtureSwitch { var name = "switch"; var sceneANumber: UInt16?; var sceneBNumber: UInt16?; var sceneCNumber: UInt16?; var sceneDNumber: UInt16? }
enum FixtureReferences { static var switches: [FixtureSwitch] = []; static var observed: [ObjectIdentifier: [Int: [Int: FixtureEntry]]] = [:] }
struct FixtureEntry { var isValid = true; var sceneNumber: UInt16 }
extension MeshNetworkManager { var switchs: [FixtureSwitch] { FixtureReferences.switches } }
extension GroupInfo { var switchs: [FixtureSwitch] { [] } }
extension Node { var allSchedulerModelEntrys: [Int: [Int: FixtureEntry]] { FixtureReferences.observed[ObjectIdentifier(self)] ?? [:] } }
extension Schedule { var sceneNumber: UInt16? { scene?.number }; var needDeleteSceneNumbers: [UInt16] { needDeleteScenes.map(\.number) } }

enum MeshOperate { case add, edit, delete, control }
enum SpaceMembershipCoordinator {
    static var allowed = true
    static func allowsConfiguration(_ space: SpaceData) -> Bool { allowed }
    static func isLeaving(_ space: SpaceData) -> Bool { !allowed }
}
enum SpaceViewController {
    static var available = true
    static var active: SpaceData?
    static func currentSpace() -> SpaceData? { available ? (active ?? SpaceData.value) : nil }
}
