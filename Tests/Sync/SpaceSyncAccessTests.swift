import Foundation

// SDK, storage and UI discovery boundaries. Access decisions and cleanup-result
// handling below are extracted unchanged from production.
enum Thread { static var isMainThread = true }
enum NetworkApiError: Error, Equatable { case configurationUnavailable, spacePasswordOverdue, noSpacePermission, userUnauthorized, configurationReviewRequired }
enum UserData { static var currentUserId = "A", currentServerRegion = "region" }
struct Key { var networkId = Identifier(); struct Identifier { var hex = "0001" } }
final class Mesh { let uuid = UUID() }
final class MeshNetworkManager { static let instance = MeshNetworkManager(); var meshNetwork: Mesh? = Mesh(); var currentNetworkKey = Key() }
final class SpaceData {
    enum Permission { case owner, editor, visitor }
    enum State { case normal, waitDeleted }
    let id: String; var meshUUID: String; var meshNetworkId = "0001"
    var permission = Permission.editor, state = State.normal
    var requiresPasswordVerification = false, disableEditorPermission = false, meshOTADistribution = false
    var syncCloudError: NetworkApiError?
    init(_ id: String = "space") { self.id = id; meshUUID = MeshNetworkManager.instance.meshNetwork!.uuid.uuidString }
    static var stored = SpaceData()
    static func load(subNetworkId: String) -> SpaceData? { stored.meshNetworkId == subNetworkId ? stored : nil }
}
enum SpaceViewController { static var active: SpaceData? = SpaceData(); static func currentSpace() -> SpaceData? { active } }
enum SpaceMembershipCoordinator {
    static var allowed = true, leaving = false
    static func isLeaving(_ space: SpaceData) -> Bool { leaving }
    static func allowsConfiguration(_ space: SpaceData) -> Bool { allowed }
}
enum SpaceConfigurationSafety {
    struct Recovery {
        enum Phase { case active, retired }
        enum Authority { case writable, readOnly, waitingForAuthorization, revoked }
        var phase = Phase.active, authority = Authority.writable, generation = UUID()
        var unbindRequested: Bool?, requiresRemoteImport: Bool?
    }
    static var recovery = Recovery(), blocked = false, currentConfigurationAvailable = true, pending = false, unreadable = false
    static func recoveryState(_ space: SpaceData) throws -> Recovery {
        if unreadable { throw NetworkApiError.configurationUnavailable }; return recovery
    }
    static func isBlocked(_ space: SpaceData) -> Bool { blocked }
    static func configurationSyncError(_ space: SpaceData) -> NetworkApiError { .configurationReviewRequired }
    static func isCurrent(_ context: Recovery, space: SpaceData) -> Bool { !SpaceMembershipCoordinator.leaving && context.generation == recovery.generation }
    static func hasPendingUpload(_ space: SpaceData) -> Bool { pending }
}
enum SpaceSyncCleanupCoordinator {
    static var ready = true, failure: NetworkApiError?, calls = 0
    static func prepare(_ space: SpaceData) async -> Bool { calls += 1; space.syncCloudError = failure; return ready }
    // PRODUCTION_CLEANUP
}
// PRODUCTION_ACCESS

@main struct SpaceSyncAccessTests {
    static func reset() {
        SpaceData.stored = SpaceData(); SpaceViewController.active = SpaceData()
        SpaceMembershipCoordinator.allowed = true; SpaceMembershipCoordinator.leaving = false
        SpaceConfigurationSafety.recovery = .init(); SpaceConfigurationSafety.blocked = false
        SpaceConfigurationSafety.currentConfigurationAvailable = true; SpaceConfigurationSafety.pending = false
        SpaceConfigurationSafety.unreadable = false
        SpaceSyncCleanupCoordinator.ready = true; SpaceSyncCleanupCoordinator.failure = nil
    }
    static func main() async {
        for role in [SpaceData.Permission.owner, .editor] {
            reset(); SpaceData.stored.permission = role; SpaceViewController.active!.permission = role
            precondition(SpaceSyncAccess.error() == nil)
        }
        for whereChanged in ["stored", "active"] {
            reset(); let space = whereChanged == "stored" ? SpaceData.stored : SpaceViewController.active!
            space.permission = .visitor; precondition(SpaceSyncAccess.error() == .noSpacePermission)
            space.permission = .editor; space.requiresPasswordVerification = true
            precondition(SpaceSyncAccess.error() == .spacePasswordOverdue)
            space.requiresPasswordVerification = false; space.disableEditorPermission = true
            precondition(SpaceSyncAccess.error() == .noSpacePermission)
            space.disableEditorPermission = false; space.meshOTADistribution = true
            precondition(SpaceSyncAccess.error() == .noSpacePermission)
        }
        for authority in [SpaceConfigurationSafety.Recovery.Authority.readOnly, .revoked, .waitingForAuthorization] {
            reset(); SpaceConfigurationSafety.recovery.authority = authority
            precondition(SpaceSyncAccess.error() == (authority == .waitingForAuthorization ? .userUnauthorized : .noSpacePermission))
        }
        reset(); SpaceMembershipCoordinator.allowed = false
        precondition(SpaceSyncAccess.error() == .configurationUnavailable)
        reset(); SpaceConfigurationSafety.recovery.requiresRemoteImport = true
        precondition(SpaceSyncAccess.error() == .configurationReviewRequired)
        reset(); SpaceConfigurationSafety.blocked = true
        precondition(SpaceSyncAccess.error() == .configurationReviewRequired)
        precondition(SpaceSyncAccess.error(checkingConfiguration: false) == nil, "allow authorized reference recovery")
        reset(); SpaceConfigurationSafety.unreadable = true
        precondition(SpaceSyncAccess.error() == .configurationUnavailable)
        reset(); let identity = SpaceSyncAccess.captureIdentity(), recovery = SpaceSyncAccess.captureRecovery()
        SpaceConfigurationSafety.recovery.generation = UUID()
        precondition(identity() && !recovery(), "new recovery requires a fresh preparation")
        UserData.currentUserId = "B"; precondition(!identity()); UserData.currentUserId = "A"
        SpaceViewController.active = SpaceData("other"); precondition(!identity())
        reset(); let expected = SpaceData("other")
        precondition(SpaceSyncAccess.error(expectedSpace: expected) == .configurationUnavailable)
        SpaceViewController.active = nil; precondition(SpaceSyncAccess.error() == .configurationUnavailable)
        reset(); Thread.isMainThread = false
        precondition(SpaceSyncAccess.error() == .configurationUnavailable); Thread.isMainThread = true
        reset()
        let ready = await SpaceSyncCleanupCoordinator.prepareForDeviceSync(); precondition(ready == nil)
        SpaceSyncCleanupCoordinator.ready = false; SpaceConfigurationSafety.pending = true
        let deferred = await SpaceSyncCleanupCoordinator.prepareForDeviceSync(); precondition(deferred == nil)
        SpaceConfigurationSafety.pending = false; SpaceSyncCleanupCoordinator.failure = .configurationReviewRequired
        let failed = await SpaceSyncCleanupCoordinator.prepareForDeviceSync(); precondition(failed == .configurationReviewRequired)
        SpaceConfigurationSafety.pending = true; SpaceConfigurationSafety.recovery.authority = .readOnly
        let revoked = await SpaceSyncCleanupCoordinator.prepareForDeviceSync(); precondition(revoked == .noSpacePermission)
        print("PASS shared sync access: Owner/Editor, Visitor, stored/active mismatch, password/recovery, identity, cleanup failure and pending-upload deferral")
    }
}
