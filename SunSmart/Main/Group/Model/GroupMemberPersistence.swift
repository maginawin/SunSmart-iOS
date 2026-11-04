import Foundation
import NordicSigMeshSDK
import SQLite

/// Members SAVE spans the App and Mesh databases. This local receipt is never
/// exported; its commit marker shares the App transaction, not the Mesh writes.
enum GroupMemberPersistence {
    enum Failure: Error { case persistence, staleIdentity, conflictingIntent }

    struct Scope: Codable, Equatable {
        let account: String
        let region: String
        let siteID: String
        let spaceID: String
        let meshUUID: String
        let networkID: String
        let groupAddress: Address

        init(space: SpaceData, group: Group) {
            account = UserData.currentUserId
            region = String(describing: UserData.currentServerRegion)
            siteID = space.siteId; spaceID = space.id
            meshUUID = space.meshUUID; networkID = space.meshNetworkId
            groupAddress = group.address.address
        }

        func matches(_ space: SpaceData) -> Bool {
            account == UserData.currentUserId && region == String(describing: UserData.currentServerRegion)
                && siteID == space.siteId && spaceID == space.id
                && meshUUID == space.meshUUID && networkID == space.meshNetworkId
        }
    }

    struct State: Codable, Equatable {
        var groupState: Int
        var functions: [Node.RequiredFunctionType]
        var restore: Data?
        // The SDK's restore codec omits these two runtime fields. Preserve them
        // in rollback snapshots without changing the SDK or its wire format.
        var powerUpState: UInt8?
        var manualOverrideTimeout: UInt32?

        init(_ node: Node) throws {
            groupState = node.groupState.rawValue
            functions = node.requiredFunctionTypes
            restore = try node.restoreData.map { try Self.encoder.encode($0) }
            powerUpState = node.restoreData?.powerUpState.rawValue
            manualOverrideTimeout = node.restoreData?.manualOverrideTimeout
        }

        private static var encoder: JSONEncoder {
            let value = JSONEncoder(); value.outputFormatting = .sortedKeys; return value
        }

        func restoreValue() throws -> NodeRestoreData? {
            guard let restore else { return nil }
            let value = try JSONDecoder().decode(NodeRestoreData.self, from: restore)
            if let powerUpState, let state = OnPowerUp(rawValue: powerUpState) { value.powerUpState = state }
            if let manualOverrideTimeout { value.manualOverrideTimeout = manualOverrideTimeout }
            return value
        }

        mutating func setPendingGroup(_ address: Address?) throws {
            let value = try restoreValue() ?? NodeRestoreData()
            value.addGroupAddress = address
            restore = try Self.encoder.encode(value)
        }

        func apply(to node: Node) throws {
            guard let state = Node.GroupState(rawValue: groupState) else { throw Failure.persistence }
            node.groupState = state
            node.requiredFunctionTypes = functions
            node.restoreData = try restoreValue()
            node.clearSyncStateCache()
        }

        func matchesPersisted(_ node: Node) throws -> Bool {
            let saved = try State(node)
            return groupState == saved.groupState && functions == saved.functions && restore == saved.restore
        }
    }

    struct Entry: Codable {
        let identity: TimedSchedulerNodeIdentity
        let previous: State
        let desired: State
    }

    struct Receipt: Codable {
        let id: UUID
        let scope: Scope
        let entries: [Entry]
        var committed = false
    }

    static func isSelectable(_ node: Node, in group: Group) -> Bool {
        guard let network = node.network, network.uuid == group.network?.uuid,
              node.subNetworkId == group.subNetworkId,
              node.group == nil || node.group?.address.address == group.address.address else { return false }
        guard let pending = node.restoreData?.addGroupAddress, pending != group.address.address else { return true }
        // A Group can be deleted before its first subscription ACK. Only a
        // missing target may be replaced; an existing other Group keeps ownership.
        return node.group == nil && !network.groups.contains {
            $0.subNetworkId == node.subNetworkId && $0.address.address == pending
        }
    }

    static func isSelected(_ node: Node, in group: Group) -> Bool {
        node.restoreData?.addGroupAddress == group.address.address
            || (node.group?.address.address == group.address.address && node.groupState != .exitFailure)
    }

    static func pendingMembers(in group: Group, nodes: [Node]) -> [Node] {
        nodes.filter { $0.restoreData?.addGroupAddress == group.address.address && $0.group == nil }
    }

    private static func database() throws -> Connection {
        guard let db = SunSmartDataManager.shared.db else { throw Failure.persistence }
        return db
    }

    private static func createTable(_ db: Connection) throws {
        try db.run("""
            CREATE TABLE IF NOT EXISTS groupMemberSaves (
                account TEXT NOT NULL, region TEXT NOT NULL, meshUUID TEXT NOT NULL,
                networkID TEXT NOT NULL, value BLOB NOT NULL,
                PRIMARY KEY (account, region, meshUUID, networkID))
            """)
    }

    static func receipt(meshUUID: String, networkID: String) throws -> Receipt? {
        let db = try database()
        guard try db.scalar("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'groupMemberSaves'") as? Int64 == 1 else { return nil }
        guard let value = try db.scalar("SELECT value FROM groupMemberSaves WHERE account = ? AND region = ? AND meshUUID = ? AND networkID = ?",
            UserData.currentUserId, String(describing: UserData.currentServerRegion), meshUUID, networkID) else { return nil }
        guard let blob = value as? Blob else { throw Failure.persistence }
        return try JSONDecoder().decode(Receipt.self, from: Data(blob.bytes))
    }

    static func hasPending(meshUUID: String, networkID: String, excluding saveID: UUID? = nil) -> Bool {
        do {
            guard let value = try receipt(meshUUID: meshUUID, networkID: networkID) else { return false }
            return value.id != saveID || value.committed
        } catch { return true }
    }

    private static func write(_ receipt: Receipt, inserting: Bool = false) throws {
        let data = try JSONEncoder().encode(receipt)
        let scope = receipt.scope
        let verb = inserting ? "INSERT" : "INSERT OR REPLACE"
        try database().run("\(verb) INTO groupMemberSaves (account, region, meshUUID, networkID, value) VALUES (?, ?, ?, ?, ?)",
            scope.account, scope.region, scope.meshUUID, scope.networkID, Blob(bytes: Array(data)))
    }

    private static func remove(_ receipt: Receipt) throws {
        let scope = receipt.scope
        try database().run("DELETE FROM groupMemberSaves WHERE account = ? AND region = ? AND meshUUID = ? AND networkID = ?",
            scope.account, scope.region, scope.meshUUID, scope.networkID)
    }

    /// Called inside the authoritative import's App transaction. A replaced
    /// Group must never replay an older local member-save receipt after restart.
    static func discardForCloudReplacement(_ space: SpaceData) throws {
        let db = try database()
        guard try db.scalar("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'groupMemberSaves'") as? Int64 == 1 else { return }
        try db.run("DELETE FROM groupMemberSaves WHERE account = ? AND region = ? AND meshUUID = ? AND networkID = ?",
            UserData.currentUserId, String(describing: UserData.currentServerRegion), space.meshUUID, space.meshNetworkId)
    }

    static func prepare(space: SpaceData, group: Group, exiting: [Node], adding: [Node]) throws -> Receipt {
        precondition(Thread.isMainThread)
        guard space.canEditing, !SpaceConfigurationSafety.isBlocked(space),
              group.network?.uuid.uuidString == space.meshUUID, group.subNetworkId == space.meshNetworkId,
              let network = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              network.groups.contains(where: { $0.address.address == group.address.address }),
              SpaceConfigurationSafety.checkpoint(space) else { throw Failure.staleIdentity }
        let scope = Scope(space: space, group: group)
        var entries: [Entry] = []
        for node in exiting + adding {
            guard node.network?.uuid.uuidString == scope.meshUUID, node.subNetworkId == scope.networkID,
                  let identity = node.timedSchedulerIdentity, identity.isValid,
                  !entries.contains(where: { $0.identity == identity }),
                  let saved = network.nodes.first(where: { $0.timedSchedulerIdentity == identity }) else {
                throw Failure.staleIdentity
            }
            guard isSelectable(node, in: group), isSelectable(saved, in: group) else { throw Failure.conflictingIntent }
            let previous = try State(node)
            guard try previous.matchesPersisted(saved) else { throw Failure.persistence }
            var desired = previous
            if exiting.contains(node) {
                // A pending add without any subscription is cancellation, not an unsubscribe.
                desired.groupState = node.group == nil ? Node.GroupState.none.rawValue : Node.GroupState.exitFailure.rawValue
                if node.restoreData?.addGroupAddress == group.address.address { try desired.setPendingGroup(nil) }
            } else {
                if node.group == nil {
                    desired.groupState = Node.GroupState.none.rawValue
                    try desired.setPendingGroup(group.address.address)
                } else {
                    desired.groupState = Node.GroupState.inGroup.rawValue
                }
                if group.info.profile.type == .proximityLightingWithPhotocell, !desired.functions.contains(.lightLCScene) {
                    desired.functions.append(.lightLCScene)
                }
            }
            entries.append(.init(identity: identity, previous: previous, desired: desired))
        }
        guard !entries.isEmpty else { throw Failure.persistence }
        let value = Receipt(id: UUID(), scope: scope, entries: entries)
        try createTable(database())
        try write(value, inserting: true)
        return value
    }

    /// Always load fresh Nodes before writing: membership replay must not restore
    /// stale subscriptions, Scene/Scheduler observations or other Mesh properties.
    private static func apply(_ receipt: Receipt, desired: Bool, space: SpaceData) throws {
        let scope = receipt.scope
        guard scope.matches(space),
              let storedSpace = SpaceData.load(siteId: scope.siteID, spaceId: scope.spaceID).first,
              scope.matches(storedSpace),
              let network = MeshNetwork.load(meshUUID: scope.meshUUID, subnetworkId: scope.networkID),
              network.groups.contains(where: { $0.address.address == scope.groupAddress }) else { throw Failure.staleIdentity }
        // Validate the complete set before changing any Node, including a reused address.
        let nodes = try receipt.entries.map { entry -> Node in
            guard let node = network.nodes.first(where: { $0.timedSchedulerIdentity == entry.identity }) else { throw Failure.staleIdentity }
            return node
        }
        for (entry, node) in zip(receipt.entries, nodes) {
            let state = desired ? entry.desired : entry.previous
            if try !state.matchesPersisted(node) {
                try state.apply(to: node)
                guard node.save() else { throw Failure.persistence }
            }
        }
        guard let readback = MeshNetwork.load(meshUUID: scope.meshUUID, subnetworkId: scope.networkID) else { throw Failure.persistence }
        for entry in receipt.entries {
            let state = desired ? entry.desired : entry.previous
            guard let saved = readback.nodes.first(where: { $0.timedSchedulerIdentity == entry.identity }),
                  try state.matchesPersisted(saved) else { throw Failure.persistence }
        }
        try publish(receipt, desired: desired, space: space)
    }

    private static func publish(_ receipt: Receipt, desired: Bool, space: SpaceData) throws {
        let scope = receipt.scope
        guard scope.matches(space) else { throw Failure.staleIdentity }
        let manager = MeshNetworkManager.instance
        if let live = manager.meshNetwork, live.uuid.uuidString == scope.meshUUID {
            for entry in receipt.entries {
                if let node = live.nodes.first(where: { $0.subNetworkId == scope.networkID && $0.timedSchedulerIdentity == entry.identity }) {
                    try (desired ? entry.desired : entry.previous).apply(to: node)
                }
            }
        }
    }

    @discardableResult
    static func recoverCurrentSpace() -> Bool {
        guard let space = SpaceViewController.currentSpace() else { return false }
        return recover(space)
    }

    @discardableResult
    static func recover(_ space: SpaceData) -> Bool {
        precondition(Thread.isMainThread)
        do {
            guard let value = try receipt(meshUUID: space.meshUUID, networkID: space.meshNetworkId) else { return true }
            try apply(value, desired: value.committed, space: space)
            try remove(value)
            return true
        } catch {
            #if DEBUG
            print("[GroupMemberSave] stage=recoveryFailed")
            #endif
            return false
        }
    }

    /// A false result means App commit succeeded but receipt cleanup needs retry;
    /// callers must keep the committed App memory and must not start device sync.
    static func commit(space: SpaceData, group: Group, exiting: [Node], adding: [Node],
                       applying changes: (UUID) throws -> Void) throws -> Bool {
        let value = try prepare(space: space, group: group, exiting: exiting, adding: adding)
        var failure: Error?
        let saved = SunSmartDataManager.shared.configurationTransaction {
            do {
                try apply(value, desired: true, space: space)
                try changes(value.id)
                var committed = value; committed.committed = true
                try write(committed)
            } catch { failure = error; throw error }
        }
        if saved { return recover(space) }
        // Prepared receipt survives the failed App transaction. Leave it in place
        // if rollback/readback fails, so all ordinary editors/sync remain blocked.
        _ = recover(space)
        try? publish(value, desired: false, space: space)
        throw failure ?? Failure.persistence
    }
}
