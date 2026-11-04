import Foundation
import SQLite

public typealias Address = UInt16
public enum OnPowerUp: UInt8 { case off, on, `default` }
public enum PhotosensorExceptionState: UInt8 { case off, on }
public struct DaylightSensorCalibrationData: Codable { var value: Int }
public struct NodePhaseEnergyConsumption: Codable { var value: Int }
public struct TransitionTime { public var rawValue: UInt8 }
struct UserData { static var currentUserId = "account-A"; static var currentServerRegion = "region-A" }
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
    // ACTUAL_CONFIGURATION_TRANSACTION
}
enum SpaceViewController { static func currentSpace() -> SpaceData? { SpaceData.value } }
struct SpaceConfigurationSafety {
    static var blocked = false
    static func isBlocked(_ space: SpaceData, excludingGroupMemberSaveID: UUID? = nil) -> Bool {
        blocked || GroupMemberPersistence.hasPending(meshUUID: space.meshUUID, networkID: space.meshNetworkId, excluding: excludingGroupMemberSaveID)
    }
    static func checkpoint(_ space: SpaceData) -> Bool { !blocked }
}
final class SpaceData {
    static let value = SpaceData()
    var timedSchemaVersion = 2; var triggerZones: [Int] = []; var lastUpdate = 10
    var canEditing = true
    var siteId = "site"; var id = "space"; var meshUUID = "A0000000-0000-0000-0000-000000000001"; var meshNetworkId = "subnet"
    static func load(siteId: String, spaceId: String) -> [SpaceData] { siteId == value.siteId && spaceId == value.id ? [value] : [] }
}
public final class Group {
    struct MeshAddress { var address: Address }
    struct Profile { enum Kind { case plain, proximityLightingWithPhotocell }; var type = Kind.proximityLightingWithPhotocell }
    struct Info { var profile = Profile() }
    var info = GroupInfo(); var address: MeshAddress; weak var network: MeshNetwork?
    var subNetworkId = "subnet"
    var nodes: [Node] { network?.nodes.filter { $0.subscription == address.address } ?? [] }
    func updateGroupSyncState() {}
    init(_ address: Address) { self.address = .init(address: address) }
}
final class MeshNetwork {
    static var db: Connection!
    let uuid = UUID(uuidString: SpaceData.value.meshUUID)!
    static var groupAddresses: [Address] = [0xC000, 0xC001]
    var groups: [Group] = MeshNetwork.groupAddresses.map(Group.init)
    var nodes: [Node] = []
    init() { groups.forEach { $0.network = self } }
    static func load(meshUUID: String, subnetworkId: String) -> MeshNetwork? {
        guard meshUUID == SpaceData.value.meshUUID, subnetworkId == "subnet" else { return nil }
        do {
            let network = MeshNetwork()
            for row in try db.prepare("SELECT value FROM nodes ORDER BY address") {
                let record = try JSONDecoder().decode(Node.Record.self, from: Data((row[0] as! Blob).bytes))
                let node = Node(record.address, group: record.subscription, key: record.fingerprint)
                node.network = network; node.groupState = Node.GroupState(rawValue: record.state)!
                node.requiredFunctionTypes = record.functions
                node.restoreData = try record.restore.map { try JSONDecoder().decode(NodeRestoreData.self, from: $0) }
                network.nodes.append(node)
            }
            return network
        } catch { return nil }
    }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var schedules = [FixtureSchedule()]
    var meshNetwork: MeshNetwork?
    var groups: [Group] { meshNetwork?.groups ?? [] }
}
final class Node: Equatable {
    static var ignoreWrites = false, rejectRestore = false
    enum GroupState: Int { case none, inGroup, exitFailure }
    enum RequiredFunctionType: Int, Codable { case mainNetwork, lightLCScene, lightLCScheduler }
    struct Record: Codable {
        var address: Address; var subscription: Address?; var fingerprint: String
        var state: Int; var functions: [RequiredFunctionType]; var restore: Data?
    }
    let primaryUnicastAddress: Address
    var fingerprint: String
    var subscription: Address?
    var groupState: GroupState
    var restoreData: NodeRestoreData?
    var requiredFunctionTypes: [RequiredFunctionType] = [.mainNetwork]
    weak var network: MeshNetwork?
    var subNetworkId = "subnet"
    var preConfiguration = PreConfiguration()
    var sensorCalibrationData: Calibration? = Calibration()
    var group: Group? { network?.groups.first { $0.address.address == subscription } }
    var timedSchedulerIdentity: TimedSchedulerNodeIdentity? {
        .init(nodeUUID: String(format: "B0000000-0000-0000-0000-%012X", primaryUnicastAddress),
              unicastAddress: String(format: "%04X", primaryUnicastAddress), deviceKeyFingerprint: fingerprint)
    }
    init(_ address: Address, group: Address?, key: String = String(repeating: "a", count: 64)) {
        primaryUnicastAddress = address; subscription = group; fingerprint = key; groupState = group == nil ? .none : .inGroup
    }
    func clearSyncStateCache() {}
    func save() -> Bool {
        if Self.ignoreWrites { return true }
        if Self.rejectRestore && groupState == .inGroup { return false }
        do {
            let record = Record(address: primaryUnicastAddress, subscription: subscription, fingerprint: fingerprint,
                state: groupState.rawValue, functions: requiredFunctionTypes, restore: try restoreData.map { try JSONEncoder().encode($0) })
            try MeshNetwork.db.run("INSERT OR REPLACE INTO nodes (address, value) VALUES (?, ?)", Int(primaryUnicastAddress), Blob(bytes: Array(try JSONEncoder().encode(record))))
            return true
        } catch { return false }
    }
    static func == (lhs: Node, rhs: Node) -> Bool { lhs === rhs }
}

@main enum GroupMemberPersistenceTests {
    enum Fault: Error { case injected }
    static let space = SpaceData.value
    static var manager: MeshNetworkManager { .instance }
    static var db: Connection { SunSmartDataManager.shared.db! }
    static var group: Group { manager.groups[0] }
    static var nodes: [Node] { manager.meshNetwork!.nodes }
    static func disk() -> MeshNetwork { MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)! }
    static func reload() { manager.meshNetwork = disk() }
    static func seed() throws {
        MeshNetwork.groupAddresses = [0xC000, 0xC001]
        try db.run("DELETE FROM appConfiguration")
        try MeshNetwork.db.run("DELETE FROM nodes")
        manager.meshNetwork = MeshNetwork()
        manager.meshNetwork!.nodes = [Node(2, group: 0xC000), Node(8, group: 0xC000), Node(17, group: nil)]
        for node in nodes { node.network = manager.meshNetwork; precondition(node.save()) }
        manager.schedules = [FixtureSchedule()]
        space.canEditing = true; SpaceConfigurationSafety.blocked = false
    }
    static func save(exiting: [Node] = [], adding: [Node] = [], body: () throws -> Void = {}) throws -> Bool {
        try GroupMemberPersistence.commit(space: space, group: group, exiting: exiting, adding: adding) { saveID in
            precondition(SpaceConfigurationSafety.isBlocked(space), "pending receipt blocks other entry points")
            precondition(!SpaceConfigurationSafety.isBlocked(space, excludingGroupMemberSaveID: saveID), "own SAVE must not block itself")
            try db.run("INSERT INTO appConfiguration VALUES (1)")
            try body()
        }
    }
    static func expectFailure(_ body: () throws -> Void) {
        do { try body(); fatalError("injected failure was accepted") } catch {}
    }
    static func members(_ network: MeshNetwork) -> [Address] {
        network.nodes.filter { $0.group?.address.address == 0xC000 && $0.groupState != .exitFailure }.map(\.primaryUnicastAddress)
    }
    static func assertCleanupAgrees() throws {
        let network = disk()
        let payload: [String: Any] = [
            "groups": network.groups.map { ["address": String(format: "%04X", $0.address.address), "profile": profile(1)] },
            "nodes": network.nodes.map { node -> [String: Any] in
                var row: [String: Any] = ["uuid": node.timedSchedulerIdentity!.nodeUUID,
                    "unicastAddress": String(format: "%04X", node.primaryUnicastAddress), "groupState": node.groupState.rawValue,
                    "elements": [["models": [["modelId": "1000", "subscribe": node.subscription.map { [String(format: "%04X", $0)] } ?? []]]]]]
                if let address = node.subscription { row["groupAddress"] = String(format: "%04X", address) }
                if let restore = node.restoreData { row["restoreData"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(restore)) }
                return row
            }, "scenes": [[String: Any]](), "schedules": [[String: Any]](),
            "spaceData": ["triggerZones": [[String: Any]]()]]
        let cleaned = try SpaceSyncCleanupPolicy.normalize(payload)
        let live = ProximityLightingTopologyReconciler.Snapshot(groups: manager.groups.map { group in
            .init(address: group.address.address, eligible: false, relayNumber: 0,
                  memberAddresses: Set(nodes.filter { $0.group?.address.address == group.address.address && $0.groupState != .exitFailure }.map(\.primaryUnicastAddress)),
                  hasTopology: false, paths: [], zones: [])
        }, spaceZones: [])
        precondition(SpaceSyncCleanupPolicy.equivalentTopology(live, cleaned.topology.snapshot),
                     "persisted export normalization and active topology must agree after actual SAVE")
        let normalized = cleaned.payload["nodes"] as! [[String: Any]]
        for node in network.nodes where node.restoreData?.addGroupAddress != nil {
            let row = normalized.first { $0["uuid"] as? String == node.timedSchedulerIdentity!.nodeUUID }!
            precondition((row["restoreData"] as? [String: Any])?["addGroupAddress"] as? Int == Int(node.restoreData!.addGroupAddress!))
        }
    }
    static func require(_ value: Bool) { precondition(value) }
    static func main() throws {
        let directory = CommandLine.arguments[1]
        SunSmartDataManager.shared.db = try Connection(directory + "/app.sqlite")
        MeshNetwork.db = try Connection(directory + "/mesh.sqlite")
        try db.run("CREATE TABLE appConfiguration (value INTEGER)")
        try MeshNetwork.db.run("CREATE TABLE nodes (address INTEGER PRIMARY KEY, value BLOB)")
        try seed()
        require(try save(exiting: [nodes[1]]))
        precondition(disk().nodes[1].groupState == .exitFailure && nodes[1].groupState == .exitFailure)
        precondition(members(disk()) == members(manager.meshNetwork!) && members(disk()) == [2])
        try assertCleanupAgrees()
        precondition(disk().nodes[1].subscription == 0xC000, "SAVE cannot pretend an unsubscribe ACK")
        reload()
        require(try save(adding: [nodes[1]]))
        precondition(members(disk()) == [2, 8] && nodes[1].groupState == .inGroup)
        require(try save(exiting: [nodes[0], nodes[1]]))
        try assertCleanupAgrees()
        precondition(members(disk()).isEmpty, "removing last members is legal")
        print("PASS Members exit/re-add/empty group: independent disk/live agree, physical subscriptions retained")

        try seed()
        let fresh = nodes[2]
        fresh.restoreData = NodeRestoreData(pwmFrequency: 1200, motionSensitivity: 7)
        fresh.restoreData!.powerUpState = .off; fresh.restoreData!.manualOverrideTimeout = 42
        precondition(fresh.save())
        require(try save(adding: [fresh]))
        precondition(fresh.groupState == .none && disk().nodes[2].restoreData?.addGroupAddress == 0xC000)
        try assertCleanupAgrees()
        precondition(fresh.restoreData?.pwmFrequency == 1200 && fresh.restoreData?.powerUpState == .off && fresh.restoreData?.manualOverrideTimeout == 42)
        reload()
        precondition(GroupMemberPersistence.isSelected(nodes[2], in: group))
        precondition(!GroupMemberPersistence.isSelectable(nodes[2], in: manager.groups[1]))
        precondition(GroupMemberPersistence.pendingMembers(in: group, nodes: nodes).count == 1)
        require(try save(exiting: [nodes[2]]))
        precondition(disk().nodes[2].restoreData?.addGroupAddress == nil && nodes[2].groupState == .none)
        precondition(disk().nodes[2].restoreData?.pwmFrequency == 1200 && disk().nodes[2].restoreData?.motionSensitivity == 7)
        print("PASS pending join/restart/cancel: durable target, other restore fields preserved, other Group excluded")
        try seed()
        nodes[2].restoreData = NodeRestoreData(addGroupAddress: 0xC000, pwmFrequency: 1800)
        precondition(nodes[2].save())
        let other = manager.groups[1]
        manager.meshNetwork!.groups.removeFirst()
        precondition(GroupMemberPersistence.isSelectable(nodes[2], in: other))
        expectFailure { _ = try GroupMemberPersistence.commit(space: space, group: other, exiting: [], adding: [nodes[2]]) { _ in } }
        precondition(disk().nodes[2].restoreData?.addGroupAddress == 0xC000, "live missing Group cannot override a target still present in Mesh DB")
        nodes[2].subNetworkId = "another-subnet"
        precondition(!GroupMemberPersistence.isSelectable(nodes[2], in: other))
        nodes[2].subNetworkId = "subnet"
        MeshNetwork.groupAddresses = [0xC001]; reload()
        precondition(GroupMemberPersistence.isSelectable(nodes[2], in: group), "deleted pending Group must not strand an ungrouped device")
        require(try save(adding: [nodes[2]]))
        precondition(disk().nodes[2].restoreData?.addGroupAddress == 0xC001 && nodes[2].restoreData?.pwmFrequency == 1800)
        print("PASS deleted pending target can be replaced; existing other Group remains protected")


        try seed()
        // First Mesh write succeeds, second fails. App rollback alone cannot undo it.
        try MeshNetwork.db.run("CREATE TRIGGER reject_second BEFORE INSERT ON nodes WHEN NEW.address = 8 BEGIN SELECT RAISE(ABORT, 'injected'); END")
        expectFailure { _ = try save(exiting: [nodes[0], nodes[1]]) }
        try MeshNetwork.db.run("DROP TRIGGER reject_second")
        precondition(members(disk()) == [2, 8] && members(manager.meshNetwork!) == [2, 8])
        require(try db.scalar("SELECT count(*) FROM appConfiguration") as? Int64 == 0)
        precondition(!SpaceConfigurationSafety.isBlocked(space))
        expectFailure { _ = try save(exiting: [nodes[1]], body: { throw Fault.injected }) }
        precondition(members(disk()) == [2, 8] && members(manager.meshNetwork!) == [2, 8])
        // Inject only the business COMMIT, after the prepared receipt is durable.
        expectFailure { _ = try save(exiting: [nodes[1]], body: {
            db.commitHook { db.commitHook(nil); throw Fault.injected }
        }) }
        precondition(members(disk()) == [2, 8] && members(manager.meshNetwork!) == [2, 8])
        require(try db.scalar("SELECT count(*) FROM appConfiguration") as? Int64 == 0)
        print("PASS partial Mesh write, App statement failure and final COMMIT failure restore both databases/live state")
        Node.ignoreWrites = true
        expectFailure { _ = try save(exiting: [nodes[1]]) }
        Node.ignoreWrites = false
        precondition(!SpaceConfigurationSafety.isBlocked(space) && members(disk()) == [2, 8])
        expectFailure { _ = try save(exiting: [nodes[1]], body: {
            Node.rejectRestore = true; throw Fault.injected
        }) }
        precondition(SpaceConfigurationSafety.isBlocked(space) && disk().nodes[1].groupState == .exitFailure)
        precondition(nodes[1].groupState == .inGroup, "failed compensation still restores App memory while the receipt blocks sync")
        Node.rejectRestore = false
        precondition(GroupMemberPersistence.recover(space) && !SpaceConfigurationSafety.isBlocked(space))
        precondition(members(disk()) == [2, 8])
        print("PASS readback detects a dropped Mesh write; failed compensation keeps receipt, restores UI and retries")


        try seed()
        let prepared = try GroupMemberPersistence.prepare(space: space, group: group, exiting: [nodes[0], nodes[1]], adding: [])
        try prepared.entries[0].desired.apply(to: nodes[0]); precondition(nodes[0].save())
        reload() // process stopped after a partial Mesh write
        precondition(SpaceConfigurationSafety.isBlocked(space))
        precondition(GroupMemberPersistence.recover(space))
        precondition(members(disk()) == [2, 8] && members(manager.meshNetwork!) == [2, 8])
        // Keep a committed receipt by failing its final deletion, then restart.
        try db.run("CREATE TRIGGER retain_receipt BEFORE DELETE ON groupMemberSaves BEGIN SELECT RAISE(ABORT, 'injected'); END")
        require(try !save(exiting: [nodes[1]]))
        require(try GroupMemberPersistence.receipt(meshUUID: space.meshUUID, networkID: space.meshNetworkId)?.committed == true)
        precondition(SpaceConfigurationSafety.isBlocked(space))
        try db.run("DROP TRIGGER retain_receipt")
        // Simulate missing final Mesh state; committed replay must complete it.
        nodes[1].groupState = .inGroup; precondition(nodes[1].save()); reload()
        precondition(GroupMemberPersistence.recover(space))
        precondition(nodes[1].groupState == .exitFailure && disk().nodes[1].groupState == .exitFailure)
        print("PASS restart: prepared rolls back, committed completes; failed receipt cleanup blocks sync")

        try seed()
        _ = try GroupMemberPersistence.prepare(space: space, group: group, exiting: [nodes[1]], adding: [])
        let failedReplacement = SunSmartDataManager.shared.configurationTransaction {
            try GroupMemberPersistence.discardForCloudReplacement(space)
            throw GroupMemberPersistence.Failure.persistence
        }
        precondition(!failedReplacement && SpaceConfigurationSafety.isBlocked(space), "failed cloud import retains old receipt")
        precondition(SunSmartDataManager.shared.configurationTransaction {
            try GroupMemberPersistence.discardForCloudReplacement(space)
        })
        nodes[1].groupState = .none; precondition(nodes[1].save()); reload()
        precondition(GroupMemberPersistence.recover(space) && !SpaceConfigurationSafety.isBlocked(space))
        precondition(nodes[1].groupState == .none, "cloud replacement cannot replay the old Group member save")
        print("PASS authoritative cloud replacement retires member receipt transactionally; rollback and restart")

        try seed()
        _ = try GroupMemberPersistence.prepare(space: space, group: group, exiting: [nodes[1]], adding: [])
        nodes[1].fingerprint = String(repeating: "b", count: 64); precondition(nodes[1].save()); reload()
        precondition(!GroupMemberPersistence.recover(space), "same address with new Device Key cannot replay")
        precondition(disk().nodes[1].groupState == .inGroup && SpaceConfigurationSafety.isBlocked(space))
        nodes[1].fingerprint = String(repeating: "a", count: 64); precondition(nodes[1].save())
        precondition(GroupMemberPersistence.recover(space))
        SpaceConfigurationSafety.blocked = true
        expectFailure { _ = try save(exiting: [nodes[0]]) }
        SpaceConfigurationSafety.blocked = false; space.canEditing = false
        expectFailure { _ = try save(exiting: [nodes[0]]) }
        precondition(members(disk()) == [2, 8])
        print("PASS identity/permission guards: replacement Node and blocked/read-only Space are not mutated")
        try seed()
        let page = MembersPage()
        page.performSave(exitNodes: [nodes[1]], addNodes: [nodes[2]], proxyRemovalPlans: [])
        precondition(page.installed != nil && !page.isSavingMembers)
        try assertCleanupAgrees()
        precondition(disk().nodes[1].groupState == .exitFailure && disk().nodes[2].restoreData?.addGroupAddress == 0xC000)
        precondition(members(disk()) == members(manager.meshNetwork!))
        reload()
        let cancel = MembersPage()
        cancel.performSave(exitNodes: [nodes[2]], addNodes: [], proxyRemovalPlans: [])
        guard case .group(_, _, let outgoing)? = cancel.installed?.type else { fatalError("cancel did not reach sync boundary") }
        precondition(outgoing.isEmpty && disk().nodes[2].restoreData?.addGroupAddress == nil)
        try seed()
        ProximityLightingLifecycleCoordinator.failFinalCommit = true
        let failedPage = MembersPage()
        failedPage.performSave(exitNodes: [nodes[1]], addNodes: [], proxyRemovalPlans: [])
        ProximityLightingLifecycleCoordinator.failFinalCommit = false
        precondition(failedPage.installed == nil && !failedPage.isSavingMembers)
        precondition(nodes[1].preConfiguration.dayProfileStartsAboveLux == 10 && manager.schedules[0].nodeSlots == [1])
        precondition(members(disk()) == [2, 8] && members(manager.meshNetwork!) == [2, 8])
        require(try db.scalar("SELECT count(*) FROM appConfiguration") as? Int64 == 0)
        print("PASS actual Members SAVE: mixed add/remove, pending cancel has no unsubscribe, outer COMMIT rolls back App memory and Mesh")

    }
}

// UIKit/BLE and topology adapters are boundaries here. Execute the actual
// Members controller save through the production two-database coordinator.
extension String { var localizedString: String { self } }
final class Button { var isEnabled = true }
final class NavigationItem { var rightBarButtonItem: Button? = Button() }
enum XWHUDManager {
    static var failures = 0
    static func showTipHUD(_ message: String, isLineFeed: Bool) { failures += 1 }
    static func showErrorTipHUD(_ message: String) { failures += 1 }
}
struct MeshLibManager {
    static var manager = MeshLibManager()
    var isMeshNetworkConnected = true
}
final class GroupInfo {
    var profile = Group.Profile()
    static func load(meshUUID: String, address: Address, subnetworkId: String) -> GroupInfo? { GroupInfo() }
}
final class PreConfiguration {
    var dayProfileStartsAboveLux: Int? = 10, nightProfileStartsBelowLux: Int? = 20
    var dayProfileLightData: Int? = 30, nightProfileLightData: Int? = 40
    var resetDaylightCalibration = false
    func save(meshUUID: String, nodeAddress: Address) -> Bool { true }
}
struct Calibration { var isCalibration = true }
final class FixtureSchedule { var nodeSlots: [Int]? = [1] }
struct TimedSchedulerBindings {
    enum Failure: Error { case persistence }
    struct Plan { let count: Int }
    static func prepareTopology(group: Group, members: [Node], addingMembers: [Node]) throws -> Plan { .init(count: members.count) }
    static func commit(_ plan: Plan, applying changes: () throws -> Void) throws {
        let db = SunSmartDataManager.shared.db!
        try db.savepoint {
            MeshNetworkManager.instance.schedules[0].nodeSlots = [plan.count]
            try changes()
        }
    }
    static func showFailure(_ error: Error) { XWHUDManager.failures += 1 }
}
final class FixtureSwitch {
    var deleteProxyNodeAddress: Address?
    func save() -> Bool { true }
}
struct GroupMemberProxyRemovalPlan {
    enum Decision { case markPendingRemoval }
    let decision = Decision.markPendingRemoval
    let node: Node; let switchData: FixtureSwitch
}
struct ProximityLightingLifecycleCoordinator {
    struct Transaction {
        mutating func updateMembers(group: Group, members: [Node]) {}
        func prepare() -> Preparation { Preparation() }
    }
    struct Preparation { var isValid = true, doesNotIntroduceHardErrors = true }
    struct Result { var syncDatas: [Int] = [] }
    static var failFinalCommit = false
    static func begin(space: SpaceData) -> Transaction { Transaction() }
    static func commit(_ preparation: Preparation, allowExistingHardErrors: Bool,
                       hasAdditionalLogicalChange: Bool, groupMemberSaveID: UUID?, applyAdditionalChanges: () throws -> Void) -> Result? {
        guard !SpaceConfigurationSafety.isBlocked(SpaceData.value, excludingGroupMemberSaveID: groupMemberSaveID) else { return nil }
        let saved = SunSmartDataManager.shared.configurationTransaction {
            try applyAdditionalChanges()
            try SunSmartDataManager.shared.db!.run("INSERT INTO appConfiguration VALUES (2)")
            if failFinalCommit {
                SunSmartDataManager.shared.db!.commitHook {
                    SunSmartDataManager.shared.db!.commitHook(nil)
                    throw GroupMemberPersistenceTests.Fault.injected
                }
            }
        }
        return saved ? Result() : nil
    }
    static func preview(_ preparation: Preparation, allowExistingHardErrors: Bool) -> Result? { Result() }
}
final class SyncDevicesViewController {
    enum Kind { case group(Group, inNodes: [Node], outNodes: [Node]) }
    let type: Kind
    var supplementaryProximityLightingSyncDatas: [Int] = []
    init(type: Kind) { self.type = type }
}
final class MembersPage {
    let space = SpaceData.value
    var group: Group { MeshNetworkManager.instance.groups[0] }
    let navigationItem = NavigationItem()
    var isSavingMembers = false
    var installed: SyncDevicesViewController?
    // ACTUAL_MEMBER_SAVE
}
