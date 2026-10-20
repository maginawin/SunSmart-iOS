import Foundation
final class SpaceData {
    static var persisted: SpaceData?
    static var siblings: [SpaceData] = []
    static var failSave = false
    static var saveCount = 0
    var siteId = "site", id = "space", meshNetworkId = "network", meshUUID = "11111111-1111-4111-8111-111111111111"
    var hdbGroupAddresses: Set<UInt16> { hdb?.allGroupAddresses ?? [] }
    static func load(subNetworkId: String) -> SpaceData? { persisted?.copy() }
    var hdb: HDBConfiguration?, hdbLoadFailed = false
    var canEditing = true
    var hdbPersistenceBaseline: HDBConfiguration?
    var groupCount = 0, deviceCount = 0, luminairesCount = 0, sceneCount = 0, scheheduleCount = 0, switchesCount = 0
    enum Operate { case edit }
    var groupOperates: [Operate] { canEditing ? [.edit] : [] }
    var lastUpdate: Int64 = 1, lastUploadCloudTimestamp: Int64? = 1
    static func load(siteId: String, spaceId: String? = nil) -> [SpaceData] {
        ((persisted.map { [$0.copy()] } ?? []) + siblings.map { $0.copy() }).filter { spaceId == nil || $0.id == spaceId }
    }
    func copy() -> SpaceData { let s = SpaceData(); s.applyConfigurationState(from: self); return s }
    func applyConfigurationState(from s: SpaceData) {
        siteId = s.siteId; id = s.id; meshNetworkId = s.meshNetworkId; meshUUID = s.meshUUID
        hdb = s.hdb; hdbLoadFailed = s.hdbLoadFailed; canEditing = s.canEditing
        lastUpdate = s.lastUpdate; lastUploadCloudTimestamp = s.lastUploadCloudTimestamp
        groupCount = s.groupCount; deviceCount = s.deviceCount; luminairesCount = s.luminairesCount
        sceneCount = s.sceneCount; scheheduleCount = s.scheheduleCount; switchesCount = s.switchesCount
    }
    func refreshSummaryCountsFromSpaceMesh() {}
    func enqueueSpaceSync(site: SiteData, level: CloudSynchronizationManager.Level) { CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: self), level: level) }
    func save() -> Bool { Self.saveCount += 1; if Self.failSave { return false }; Self.persisted = copy(); return true }
}
enum SpaceMembershipCoordinator { static func allowsConfiguration(_ space: SpaceData) -> Bool { true } }
struct TestDeletionJournal {
    struct Entry { enum Stage { case removed, cleaned }; var nodeUUID: String; var stage: Stage = .cleaned; var sensorGroupId: UInt16? }
    var entries: [Entry] = []
}
enum SpaceConfigurationSafety {
    static var journal = TestDeletionJournal()
    static func isBlocked(_ space: SpaceData) -> Bool { false }
    static func deletionJournal(_ space: SpaceData) throws -> TestDeletionJournal { journal }
    static func updateDeletionJournal(_ space: SpaceData, _ mutate: (inout TestDeletionJournal) -> Void) -> Bool { mutate(&journal); return true }
}
final class CloudSynchronizationManager {
    enum Operation { case syncSpace(space: SpaceData) }
    enum Level { case promptly }
    static let shared = CloudSynchronizationManager()
    var submissions = 0
    var snapshots: [SpaceData] = []
    func addSynchronizationHandle(operation: Operation, level: Level) {
        submissions += 1
        if case .syncSpace(let space) = operation { snapshots.append(space.copy()) }
    }
}


final class SiteData { static var hdbEnabled = true, failTypeRead = false; func loadIsHdbSite() throws -> Bool { if Self.failTypeRead { throw HDBConfigurationError.persistenceFailed }; return Self.hdbEnabled }; var id = "site"; var spaces: [SpaceData] = []; static func load(siteId: String) -> SiteData? { SiteData() } }
