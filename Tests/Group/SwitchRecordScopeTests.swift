import Foundation
import SQLite
import struct SQLite.Expression

typealias Address = UInt16
typealias SceneNumber = UInt16
protocol Copyable { func copy() -> Self }
// Only Power Switch metadata types are substitutes; the property declarations
// and overridden copy method are extracted from the production subclass.
enum PJEightKeySwitchPanelDefinition { enum PanelType { case scene8Key, brightness8Key } }
enum PJEightKeyPowerSwitchKind { case battery, ac }
enum PJEightKeySwitchMoreSettingsViewModel { struct State { static let `default` = State() } }
enum PJEightKeySwitchSyncState { case pending }
extension String { var localizedString: String { self } }
extension UInt16 {
    var hex: String { String(format: "%04X", self) }
    var isGroup: Bool { self >= 0xC000 }
    var isUnicast: Bool { self > 0 && self < 0x8000 }
}
let jsonEncoder = JSONEncoder()
let jsonDecoder = JSONDecoder()
struct NetworkID { let hex: String }
struct Key { let networkId: NetworkID }
struct GroupAddress: Equatable { let address: Address }
final class Group {
    let address: GroupAddress
    let subNetworkId: String
    var isVirtual = true
    var isUsed = false
    var deletionFails = false
    func delete() -> Bool { !deletionFails }
    init(_ address: Address, _ owner: String) { self.address = .init(address: address); subNetworkId = owner }
}
final class Scene { var number: SceneNumber = 1 }
final class Model {
    func isSubscribed(to: Group) -> Bool { false }
    func unsubscribe(from: Group) {}
}
final class Element { var models: [Model] = [] }
final class Node {
    var network: MeshNetwork?
    let uuid = UUID()
    var createdTimestamp: Int64 = 1
    var primaryUnicastAddress: Address = 10
    var subNetworkId = "A"
    var isPowerSwitch = false
    var enOceanMacAddress: String?
    var enOceanProxySwitchKeys: [Int] = []
    var elements: [Element] = []
    func savePropertys() -> Bool { true }
    func save() -> Bool { true }
    func notifyEnOceanSwitchReferencesChangedIfNeeded(_ changed: Bool) {}
}
final class Provisioner { var node: Node? }
final class MeshNetwork {
    static var store: [String: MeshNetwork] = [:]
    let uuid: UUID
    var nodes: [Node] = []
    var groups: [Group] = []
    var networkKeys: [Key] = []
    var localProvisioner: Provisioner?
    init(_ uuid: UUID) { self.uuid = uuid }
    static func load(meshUUID: String, subnetworkId: String? = nil) -> MeshNetwork? { store[subnetworkId ?? "site"] }
    func node(withAddress: Address) -> Node? { nodes.first { $0.primaryUnicastAddress == withAddress } }
    func remove(group: Group) throws { groups.removeAll { $0 === group } }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
    var currentNetworkKey = Key(networkId: .init(hex: "B"))
    var switchs: [DeviceSwitchData] = []
    var groups: [Group] { meshNetwork?.groups ?? [] }
    var virtualGroups: [Group] { groups }
    var scenes: [Scene] = []
    func getNextSwitchName() -> String { "Switch" }
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
}
final class SpaceData {
    static var saved: [String: (Int64, Int)] = [:]
    static var failSave = false
    let siteId: String
    let id: String
    let meshNetworkId: String
    var meshUUID: String { siteId }
    var lastUpdate: Int64 = 1
    var lastUploadCloudTimestamp: Int64? = 0
    var switchesCount = 1
    init(_ site: String, _ id: String) { siteId = site; self.id = id; meshNetworkId = id }
    func markLocalChangePendingCloudSync() { lastUpdate += 1 }
    func save() -> Bool {
        guard !Self.failSave else { return false }
        Self.saved[id] = (lastUpdate, switchesCount); return true
    }
    static func load(siteId: String, spaceId: String) -> [SpaceData] {
        guard let state = saved[spaceId] else { return [] }
        let copy = SpaceData(siteId, spaceId); copy.lastUpdate = state.0; copy.switchesCount = state.1
        return [copy]
    }
}
enum SpaceConfigurationSafety {
    enum SafetyError: Error { case persistenceFailed }
    static var journals: [String: SpaceDeletionJournal] = [:]
    static var failCompletion = false
    static var writable = true
    static func canDeleteDeviceRecords(_ space: SpaceData) -> Bool { writable }
    static func hasPendingImport(_ space: SpaceData) -> Bool { false }
    static func checkpoint(_ space: SpaceData) -> Bool { true }
    static func deletionJournal(_ space: SpaceData) throws -> SpaceDeletionJournal {
        journals[space.id] ?? .init(scope: .init(siteId: space.siteId, spaceId: space.id, meshUUID: space.meshUUID, networkId: space.meshNetworkId))
    }
    static func updateDeletionJournal(_ space: SpaceData, blocksOnFailure: Bool = true,
                                      _ update: (inout SpaceDeletionJournal) -> Void) -> Bool {
        var journal = try! deletionJournal(space); update(&journal)
        if failCompletion, journal.switches?.contains(where: { candidate in
            candidate.completedTimestamp != nil && !(journals[space.id]?.switches ?? []).contains {
                $0.id == candidate.id && $0.completedTimestamp == candidate.completedTimestamp
            }
        }) == true { return false }
        journals[space.id] = journal; return true
    }
}
// Node deletion has its own execution suite; virtual record tests must not enter it.
final class DevicePermanentDeletionContext {
    enum Outcome { case cleaned, notRemoved }
    var outcome = Outcome.notRemoved
    var isPrepared = false
    var canReset = false
    init(node: Node, space: SpaceData) { fatalError("Unexpected real Node deletion") }
    func cancel() {}
    func forceRemove() -> Bool { false }
}
enum MeshAPI {
    static func resetNodeWithoutWaitingForStatus(address: Address) throws { fatalError("Unexpected Mesh send") }
}

@main enum SwitchRecordScopeTests {
    static func main() throws {
        let db = try Connection(.inMemory)
        SunSmartDataManager.shared.db = db
        DeviceSwitchData.initDatabase()
        try db.run("CREATE TABLE pjEightKeySwitchs (meshUUID TEXT, subNetworkKey TEXT, switchId TEXT)")
        let site = UUID()
        let space = SpaceData(site.uuidString, "A")
        _ = space.save()
        let target = MeshNetwork(site), other = MeshNetwork(site), all = MeshNetwork(site)
        other.networkKeys = [Key(networkId: .init(hex: "B"))]
        MeshNetwork.store = ["A": target, "B": other, "site": all]
        MeshNetworkManager.instance.meshNetwork = other
        func insert(_ id: String, _ scope: String) -> DeviceSwitchData {
            let row = DeviceSwitchData(id: id, enabled: true, name: "Switch " + scope)
            row.recordScope = .init(meshUUID: site.uuidString, networkId: scope)
            precondition(row.save())
            try! db.run("INSERT INTO pjEightKeySwitchs VALUES (?, ?, ?)", site.uuidString, scope, id)
            return DeviceSwitchData.load(meshUUID: site.uuidString, meshNetworkId: scope, id: id).first!
        }
        let selected = insert("same-id", "A")
        _ = insert("same-id", "B")
        precondition(selected.recordScope?.matches(MeshNetworkManager.instance) == false)
        let wrongProxy = Node(); wrongProxy.subNetworkId = "B"
        other.nodes = [wrongProxy]
        selected.proxyNodeAddress = 10
        precondition(selected.proxyNode == nil, "Wrong Space proxy must never resolve")
        selected.proxyNodeAddress = nil
        precondition(SwitchRecordDeletion.remove(selected, space: space, force: true))
        precondition(DeviceSwitchData.load(meshUUID: site.uuidString, meshNetworkId: "A").isEmpty)
        precondition(DeviceSwitchData.load(meshUUID: site.uuidString, meshNetworkId: "B").count == 1)
        precondition(try! db.scalar("SELECT count(*) FROM pjEightKeySwitchs WHERE subNetworkKey = 'B'") as! Int64 == 1)
        precondition(try! SpaceConfigurationSafety.deletionJournal(space).hasReceipts)
        precondition(!(try! SpaceConfigurationSafety.deletionJournal(space).needsCleanup))

        let retry = insert("retry", "A")
        SpaceData.failSave = true
        precondition(!SwitchRecordDeletion.remove(retry, space: space, force: true))
        precondition(DeviceSwitchData.load(meshUUID: site.uuidString, meshNetworkId: "A").count == 1)
        precondition(!PJEightKeySwitchRepository.shared.recordIsAbsent(switchId: "retry", meshUUID: site.uuidString, networkId: "A"))
        SpaceData.failSave = false
        SwitchRecordDeletion.resume(space: space)
        precondition(DeviceSwitchData.load(meshUUID: site.uuidString, meshNetworkId: "A").isEmpty)

        let interrupted = insert("interrupt", "A")
        SpaceConfigurationSafety.failCompletion = true
        precondition(!SwitchRecordDeletion.remove(interrupted, space: space, force: true))
        precondition(try! SpaceConfigurationSafety.deletionJournal(space).needsCleanup)
        SpaceConfigurationSafety.failCompletion = false
        SwitchRecordDeletion.resume(space: space)
        precondition(!(try! SpaceConfigurationSafety.deletionJournal(space).needsCleanup))

        let changed = insert("changed", "A")
        SpaceData.failSave = true
        precondition(!SwitchRecordDeletion.remove(changed, space: space, force: true))
        SpaceData.failSave = false
        changed.name = "Replacement"; precondition(changed.save())
        SwitchRecordDeletion.resume(space: space)
        precondition(DeviceSwitchData.load(meshUUID: site.uuidString, meshNetworkId: "A", id: "changed").first?.name == "Replacement")
        SpaceConfigurationSafety.writable = false
        precondition(!SwitchRecordDeletion.remove(changed, space: space, force: true))
        SpaceConfigurationSafety.writable = true
        precondition(SwitchRecordDeletion.remove(changed, space: space, force: true), "A fresh explicit confirmation may replace a stale intent")

        let proxyRow = insert("proxy", "A")
        let ownProxy = Node(); ownProxy.enOceanMacAddress = "AA"; ownProxy.enOceanProxySwitchKeys = [1]
        target.nodes = [ownProxy]; all.nodes = [ownProxy]
        proxyRow.proxyNodeAddress = 10; proxyRow.enOceanMacAddress = "AA"
        proxyRow.linkGroupAddress = 0xC001; precondition(proxyRow.save())
        let privateGroup = Group(0xC001, "A"), peerGroup = Group(0xC002, "B")
        target.groups = [privateGroup]; other.groups = [peerGroup]; all.groups = [privateGroup, peerGroup]
        precondition(SwitchRecordDeletion.remove(proxyRow, space: space, force: true))
        precondition(ownProxy.enOceanMacAddress == nil && ownProxy.enOceanProxySwitchKeys.isEmpty)
        precondition(target.nodes.count == 1, "A lighting proxy must not be deleted")
        precondition(target.groups.isEmpty && other.groups.count == 1)
        let normal = insert("normal", "A")
        target.networkKeys = [Key(networkId: .init(hex: "A"))]
        MeshNetworkManager.instance.meshNetwork = target
        MeshNetworkManager.instance.currentNetworkKey = target.networkKeys[0]
        precondition(normal.recordScope?.matches(MeshNetworkManager.instance) == true)
        precondition(SwitchRecordDeletion.remove(normal, space: space, force: false))

        let manager = MeshNetworkManager.instance
        let bound = insert("normal-bound", "A")
        bound.proxyNodeAddress = ownProxy.primaryUnicastAddress
        bound.enOceanMacAddress = "AA"; bound.enOceanSecurityKey = "test-key"
        precondition(bound.save())
        manager.switchs = [bound]
        let listed = DeviceSwitchData.loadForDisplay(meshUUID: site.uuidString, networkId: "A", reuseMeshCache: true).first!
        precondition(listed === bound, "normal Mesh list must share the unbind callback's instance")
        let staleSelection = listed.copy()
        ownProxy.network = target
        ownProxy.commitSuccessfulEnOceanSwitchUnbind(enOceanMacAddress: "AA")
        precondition(listed.proxyNodeAddress == nil && listed.enOceanMacAddress == nil && listed.enOceanSecurityKey == nil)
        precondition(!SwitchRecordDeletion.remove(staleSelection, space: space, force: false), "fingerprint protection remains required")
        precondition(SwitchRecordDeletion.remove(listed, space: space, force: false), "successful Mesh unbind must complete record deletion")

        let fresh = insert("cache-refresh", "A")
        manager.switchs = [fresh.copy()]
        fresh.name = "Persisted edit"; precondition(fresh.save())
        let refreshed = DeviceSwitchData.loadForDisplay(meshUUID: site.uuidString, networkId: "A", reuseMeshCache: true).first!
        precondition(refreshed.name == fresh.name && manager.switchs.first === refreshed)
        manager.switchs = [DeviceSwitchData.load(meshUUID: site.uuidString, meshNetworkId: "B").first!]
        let peerCache = manager.switchs[0]
        manager.currentNetworkKey = other.networkKeys[0]
        let isolated = DeviceSwitchData.loadForDisplay(meshUUID: site.uuidString, networkId: "A", reuseMeshCache: true).first!
        precondition(isolated.recordScope == fresh.recordScope && manager.switchs.first === peerCache)
        manager.currentNetworkKey = target.networkKeys[0]
        _ = DeviceSwitchData.loadForDisplay(meshUUID: site.uuidString, networkId: "A", reuseMeshCache: false)
        precondition(manager.switchs.first === peerCache, "blocked Mesh browsing must not publish into the active cache")
        let uncached = DeviceSwitchData.loadForDisplay(meshUUID: site.uuidString, networkId: "A", reuseMeshCache: true).first!
        precondition(uncached !== peerCache && manager.switchs.first === uncached)
        precondition(SwitchRecordDeletion.remove(uncached, space: space, force: true))

        for kind in [PJEightKeyPowerSwitchKind.battery, .ac] {
            let persisted = insert("power-edit", "A")
            let source = PJEightKeySwitchData(id: persisted.id, enabled: true, name: persisted.name)
            source.update(switchData: persisted)
            source.powerSwitchKind = kind
            source.desiredConfigHash = "edited-config"
            let edited = source.copy()
            precondition(edited !== source && edited.recordScope == persisted.recordScope)
            precondition(edited.powerSwitchKind == kind && edited.desiredConfigHash == source.desiredConfigHash)
            edited.name = "Saved Power Switch"; precondition(edited.save())
            let wrongSpace = SpaceData(site.uuidString, "B")
            precondition(!SwitchRecordDeletion.remove(edited, space: wrongSpace, force: true))
            precondition(SwitchRecordDeletion.remove(edited, space: space, force: true), "editor copy returned to monitor must remain deletable")
        }
        print("PASS Switch lifecycle: production unbind and scoped list identity, stale fingerprints/cache, cross-Space browse, battery/AC edit copy and Force Delete")

        // Offline luminaires retain SDK model subscriptions after Force Delete.
        // The row/side table and count must commit while group cleanup survives
        // both a restart and cloud acknowledgment, without a Mesh barrier.
        let offline = insert("offline", "A")
        offline.linkGroupAddress = 0xC010; offline.subLinkGroupAddress = 0xC011
        precondition(offline.save())
        let usedGroup = Group(0xC010, "A"), failedGroup = Group(0xC011, "A")
        usedGroup.isUsed = true; failedGroup.deletionFails = true
        target.groups = [usedGroup, failedGroup]; all.groups = target.groups + other.groups
        precondition(SwitchRecordDeletion.remove(offline, space: space, force: true))
        precondition(DeviceSwitchData.load(meshUUID: site.uuidString, meshNetworkId: "A").isEmpty)
        precondition(PJEightKeySwitchRepository.shared.recordIsAbsent(switchId: offline.id, meshUUID: site.uuidString, networkId: "A"))
        precondition(space.switchesCount == 0 && MeshNetworkManager.instance.switchs.isEmpty)
        var deferred = try SpaceConfigurationSafety.deletionJournal(space)
        precondition(!deferred.needsCleanup && deferred.pendingVirtualGroupAddresses == [0xC010, 0xC011])
        deferred.confirmUpload(timestamp: space.lastUpdate)
        precondition(!deferred.hasReceipts && deferred.pendingVirtualGroupAddresses?.count == 2)
        SpaceConfigurationSafety.journals[space.id] = try JSONDecoder().decode(SpaceDeletionJournal.self, from: JSONEncoder().encode(deferred))
        SwitchRecordDeletion.resume(space: space)
        precondition(target.groups.count == 2 && !(try! SpaceConfigurationSafety.deletionJournal(space).needsCleanup))
        // A new row sharing an address must retain that group's subscription.
        let newOwner = insert("new-owner", "A")
        newOwner.linkGroupAddress = 0xC010; precondition(newOwner.save())
        usedGroup.isUsed = false; failedGroup.deletionFails = false
        SwitchRecordDeletion.resume(space: space)
        precondition(target.groups.count == 1 && target.groups[0] === usedGroup)
        precondition(SwitchRecordDeletion.remove(newOwner, space: space, force: true))
        precondition(target.groups.isEmpty && (try! SpaceConfigurationSafety.deletionJournal(space).pendingVirtualGroupAddresses?.isEmpty == true))

        let shared = insert("cross-space-group", "A")
        shared.linkGroupAddress = 0xC020; precondition(shared.save())
        let ownGroup = Group(0xC020, "A"), otherOwner = Group(0xC020, "B")
        target.groups = [ownGroup]; all.groups = [ownGroup, otherOwner]
        precondition(SwitchRecordDeletion.remove(shared, space: space, force: true))
        precondition(target.groups.count == 1, "cross-Space address ownership must retain the group")

        // An interruption after the DB deletion still needs to remove the active
        // Group cache, even when the upload has already removed Switch receipts.
        let activeNetwork = MeshNetwork(site)
        activeNetwork.networkKeys = target.networkKeys
        let staleGroup = Group(0xC030, "A")
        activeNetwork.groups = [staleGroup]
        MeshNetworkManager.instance.meshNetwork = activeNetwork
        SpaceConfigurationSafety.journals[space.id] = .init(scope: deferred.scope, pendingVirtualGroupAddresses: [0xC030])
        SwitchRecordDeletion.resume(space: space)
        precondition(activeNetwork.groups.isEmpty && (try! SpaceConfigurationSafety.deletionJournal(space).pendingVirtualGroupAddresses?.isEmpty == true))

        let scope = try SpaceConfigurationSafety.deletionJournal(space).scope
        let legacy = try JSONEncoder().encode(SpaceDeletionJournal(scope: scope))
        let decoded = try JSONDecoder().decode(SpaceDeletionJournal.self, from: legacy)
        precondition(decoded.switches == nil)
        SunSmartDataManager.shared.db = nil
        precondition(!selected.delete(meshUUID: site.uuidString, networkId: "A"))
        print("PASS Switch scope: missing Key browse, cross-Space isolation, side-table rollback, replay, changed-record rejection, permissions, legacy journal, missing database")
        print("PASS Switch Force Delete: residual subscriptions, deferred delete failure, cloud/restart replay, new/shared owners and interrupted active-cache cleanup")
    }
}
