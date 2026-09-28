import Foundation

// SDK, membership and checkpoint boundaries only. The script inserts the real
// preparation, operation guard, device permissions and protection-file readers.
enum MeshOperate { case add, edit, delete, control }
enum Permission { case owner, editor, visitor }
enum SpaceState { case normal }
enum UserData {
    static var currentUserId = "account"
    static var currentServerRegion = "region"
}
extension String { var hex: String { self } }
final class MeshNetwork {
    let uuid = UUID()
    var nodes: [Node] = []
}
final class Node {
    let uuid = UUID()
    let createdTimestamp: Int64 = 1
    var primaryUnicastAddress: UInt16 = 1
    let macAddress: String? = nil
    let productIdentifier: UInt16? = nil
    var network: MeshNetwork?
    var subNetworkId = "net"
}
final class MeshNetworkManager {
    struct Key { var networkId = "net" }
    static var instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
    var currentNetworkKey = Key()
}
enum ProximityLightingLifecycleCoordinator {
    static func topologyAddresses(for node: Node) -> Set<UInt16> { [node.primaryUnicastAddress] }
}
enum SpaceMembershipCoordinator {
    static var leaving = false
    static var configurationAllowed = true
    static func isLeaving(_ space: SpaceData) -> Bool { leaving }
    static func allowsConfiguration(_ space: SpaceData) -> Bool { configurationAllowed }
}
final class SpaceData {
    var meshUUID = ""
    let meshNetworkId = "net"
    var permission = Permission.owner
    var disableEditorPermission = false
    var meshOTADistribution = false
    var lastUploadCloudTimestamp: Int64? = 1
    var requiresPasswordVerification = false
    var state = SpaceState.normal
    static func load(siteId: String) -> [SpaceData] { [] }
    // DEVICE_OPERATES
}
enum SpaceConfigurationSafety {
    static var recoveryRoot = URL(fileURLWithPath: "/unused")
    static let testDefaults = UserDefaults(suiteName: "LightsDeletionContextTests-" + UUID().uuidString)!
    static func key(meshUUID: String, networkId: String) -> String { meshUUID + networkId }
    static func identity(_ space: SpaceData) -> SpaceRecoveryState.Identity {
        .init(account: UserData.currentUserId, region: UserData.currentServerRegion,
              space: .init(siteId: "site", spaceId: "space", meshUUID: space.meshUUID, networkId: space.meshNetworkId))
    }
    static func stateURL(_ space: SpaceData) -> URL {
        recoveryRoot.appendingPathComponent(key(meshUUID: space.meshUUID, networkId: space.meshNetworkId) + ".json")
    }
    static func recoveryState(_ space: SpaceData) throws -> SpaceRecoveryState {
        if let state = try SpaceRecoveryState.read(from: stateURL(space), identity: identity(space)) { return state }
        let state = SpaceRecoveryState(identity: identity(space))
        try state.write(to: stateURL(space))
        return state
    }
    static func directory(_ space: SpaceData) throws -> URL {
        let state = try recoveryState(space)
        guard state.phase == .active else { throw CocoaError(.fileReadCorruptFile) }
        let url = recoveryRoot.appendingPathComponent(key(meshUUID: space.meshUUID, networkId: space.meshNetworkId))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func deletionJournal(_ space: SpaceData) throws -> SpaceDeletionJournal {
        try .read(from: directory(space).appendingPathComponent("device-deletions.json"), scope: identity(space).space)
    }
    static func updateDeletionJournal(_ space: SpaceData, _ update: (inout SpaceDeletionJournal) -> Void) -> Bool {
        do {
            var journal = try deletionJournal(space)
            update(&journal)
            try journal.write(to: directory(space).appendingPathComponent("device-deletions.json"))
            return true
        } catch { return false }
    }
    static func checkpoint(_ space: SpaceData, refresh: Bool) -> Bool { true }
    // SAFETY_METHODS
}
final class OperationHarness {
    let space: SpaceData
    let manager: MeshNetworkManager
    let network: MeshNetwork
    let account = UserData.currentUserId
    let region = UserData.currentServerRegion
    var recoveryContext: SpaceRecoveryState?
    var cancelled = false
    var contexts: [String: DevicePermanentDeletionContext] = [:]
    init(space: SpaceData, network: MeshNetwork) throws {
        self.space = space; self.network = network; manager = MeshNetworkManager.instance
        recoveryContext = try SpaceConfigurationSafety.recoveryState(space)
    }
    // OPERATION_CURRENT
}

@main
struct LightsBatchDeletionContextTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        SpaceConfigurationSafety.recoveryRoot = root
        let space = SpaceData(), network = MeshNetwork(), node = Node()
        space.meshUUID = network.uuid.uuidString; node.network = network; network.nodes = [node]
        MeshNetworkManager.instance.meshNetwork = network
        let operation = try OperationHarness(space: space, network: network)
        expect(operation.isCurrent, "fresh authorized operation may begin")

        let context = DevicePermanentDeletionContext(node: node, space: space)
        expect(context.isPrepared, "production prepare must persist the intent")
        operation.contexts[node.uuid.uuidString] = context
        expect(tryJournal(space).entries.first?.stage == .prepared, "real prepared record exists on disk")
        expect(!space.deviceOperates.contains(.delete), "other callers stay blocked by this operation")
        expect(operation.isCurrent, "own prepared intent must not prevent sending or forced local deletion")

        let second = Node(); second.network = network; second.primaryUnicastAddress = 2
        network.nodes.append(second)
        let secondContext = DevicePermanentDeletionContext(node: second, space: space)
        expect(secondContext.isPrepared, "second device intent is prepared")
        expect(!operation.isCurrent, "unowned intent blocks until assigned to this task")
        operation.contexts[second.uuid.uuidString] = secondContext
        expect(operation.isCurrent, "all intents owned by this batch permit continuation")

        for stage in [SpaceDeletionJournal.Entry.Stage.removed, .cleaned, .prepared] {
            expect(SpaceConfigurationSafety.updateDeletionJournal(space) { $0.entries[0].stage = stage }, "stage persisted")
            expect(operation.isCurrent, "own deletion remains current through cleanup and force retry")
        }
        let foreign = SpaceDeletionJournal.Entry(id: UUID(), nodeUUID: node.uuid.uuidString,
            primaryAddress: 1, elementAddresses: [1], macAddress: nil, productId: nil)
        expect(SpaceConfigurationSafety.updateDeletionJournal(space) { $0.entries.append(foreign) }, "foreign intent persisted")
        expect(!operation.isCurrent, "another intent blocks even when it targets the same device")
        expect(SpaceConfigurationSafety.updateDeletionJournal(space) { $0.entries.removeAll { $0.id == foreign.id } }, "foreign intent removed")
        expect(operation.isCurrent, "own intent alone permits continuation")

        for marker in ["pending-import.json", "pending-reference-cleanup.json"] {
            let url = try SpaceConfigurationSafety.directory(space).appendingPathComponent(marker)
            try Data("{}".utf8).write(to: url)
            expect(!operation.isCurrent, "external \(marker) blocks the task")
            try FileManager.default.removeItem(at: url)
        }
        let blockKey = "spaceConfigurationBlocked." + SpaceConfigurationSafety.key(meshUUID: space.meshUUID, networkId: space.meshNetworkId)
        SpaceConfigurationSafety.testDefaults.set("deletionCleanupPending", forKey: blockKey)
        expect(!operation.isCurrent, "explicit cleanup failure cannot be bypassed by owning an intent")
        SpaceConfigurationSafety.testDefaults.removeObject(forKey: blockKey)

        space.permission = .visitor
        expect(!operation.isCurrent, "permission loss blocks the task")
        space.permission = .editor
        expect(operation.isCurrent, "authorized editor can continue")
        space.disableEditorPermission = true
        expect(!operation.isCurrent, "editor permission disabled blocks")
        space.disableEditorPermission = false; space.meshOTADistribution = true
        expect(!operation.isCurrent, "OTA blocks")
        space.meshOTADistribution = false; SpaceMembershipCoordinator.leaving = true
        expect(!operation.isCurrent, "leaving Space blocks")
        SpaceMembershipCoordinator.leaving = false; SpaceMembershipCoordinator.configurationAllowed = false
        expect(!operation.isCurrent, "membership not ready blocks")
        SpaceMembershipCoordinator.configurationAllowed = true

        UserData.currentUserId = "another"
        expect(!operation.isCurrent, "account change blocks")
        UserData.currentUserId = "account"; UserData.currentServerRegion = "another"
        expect(!operation.isCurrent, "region change blocks")
        UserData.currentServerRegion = "region"; operation.cancelled = true
        expect(!operation.isCurrent, "background cancellation blocks")
        operation.cancelled = false
        operation.manager.meshNetwork = MeshNetwork()
        expect(!operation.isCurrent, "network replacement blocks")
        operation.manager.meshNetwork = network; operation.manager.currentNetworkKey.networkId = "other"
        expect(!operation.isCurrent, "subnet change blocks")
        operation.manager.currentNetworkKey.networkId = "net"
        MeshNetworkManager.instance = MeshNetworkManager()
        expect(!operation.isCurrent, "manager replacement blocks")
        MeshNetworkManager.instance = operation.manager

        let state = try SpaceConfigurationSafety.recoveryState(space)
        var changed = state; changed.generation = UUID()
        try changed.write(to: SpaceConfigurationSafety.stateURL(space))
        expect(!operation.isCurrent, "recovery generation change blocks")
        changed = state; changed.phase = .removing
        try changed.write(to: SpaceConfigurationSafety.stateURL(space))
        expect(!operation.isCurrent, "inactive recovery blocks")
        changed = state; changed.unbindRequested = true
        try changed.write(to: SpaceConfigurationSafety.stateURL(space))
        expect(!operation.isCurrent, "unbind request blocks")
        try state.write(to: SpaceConfigurationSafety.stateURL(space))
        operation.recoveryContext = nil
        expect(!operation.isCurrent, "missing recovery context blocks")
        operation.recoveryContext = state
        expect(operation.isCurrent, "unchanged task remains allowed")
        try Data("invalid".utf8).write(to: SpaceConfigurationSafety.directory(space).appendingPathComponent("device-deletions.json"))
        expect(!operation.isCurrent, "corrupt journal must fail closed even for the owner")
        print("LightsBatchDeletionContextTests passed")
    }
    static func tryJournal(_ space: SpaceData) -> SpaceDeletionJournal { try! SpaceConfigurationSafety.deletionJournal(space) }
}
