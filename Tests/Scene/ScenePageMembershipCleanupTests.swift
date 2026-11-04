import Foundation
import SQLite

// Real page preparation + Scene Store + App SQLite savepoints. Network export,
// authority/baseline, recovery files, SDK topology and cloud queue are boundaries.
enum PageBoundary {
    static var exports = 0, uploads = 0, begins = 0, finishes = 0, saves = 0
    static var failSave = false, failFinish = false, baselineOK = true
    static var pendingReference = false, pendingDeletion = false, pendingUpload = false
    static var afterExport: (() -> Void)?, afterBaseline: (() -> Void)?
    static var revision = 0
    static func save(_ space: SpaceData) -> Bool {
        saves += 1
        guard !failSave else { return false }
        do {
            try SunSmartDataManager.shared.db!.run("INSERT OR REPLACE INTO pageVersion (id, version) VALUES (1, ?)", space.lastUpdate)
            return true
        } catch { return false }
    }
    static func reset() throws {
        exports = 0; uploads = 0; begins = 0; finishes = 0; saves = 0
        failSave = false; failFinish = false; baselineOK = true
        pendingReference = false; pendingDeletion = false; pendingUpload = false
        afterExport = nil; afterBaseline = nil; revision += 1; SiteData.loads = 0
        SpaceData.value = SpaceData(); SpaceConfigurationSafety.currentConfigurationAvailable = true
        try SunSmartDataManager.shared.db!.run("CREATE TABLE pageVersion (id INTEGER PRIMARY KEY, version INTEGER)")
        try SunSmartDataManager.shared.db!.run("INSERT INTO pageVersion VALUES (1, 1)")
    }
}
struct SpacePageRevision {
    let value = PageBoundary.revision
    var isCurrent: Bool { value == PageBoundary.revision }
}
extension Node { var isLocalProvisioner: Bool { false }; var isProvisioner: Bool { false } }
enum ProximityLightingLifecycleCoordinator {
    static func topologyAddresses(for node: Node) -> Set<UInt16> { Set([node.primaryUnicastAddress] + node.addressAliases) }
}
final class SiteData {
    let id = "site"
    var spaces: [SpaceData] = []
    static var loads = 0
    static func load(siteId: String) -> SiteData? { loads += 1; return SiteData() }
}
enum SyncLevel { case slow }
extension SpaceData {
    enum ExportPurpose { case cleanupInspection }
    static func load(siteId: String, spaceId: String? = nil) -> [SpaceData] {
        let space = SpaceData()
        space.lastUpdate = (try? SunSmartDataManager.shared.db?.scalar("SELECT version FROM pageVersion WHERE id = 1")) as? Int64 ?? -1
        space.permission = value.permission
        return [space]
    }
    func export(purpose: ExportPurpose) async -> [String: Any]? {
        PageBoundary.exports += 1
        PageBoundary.afterExport?()
        return ["uuid": id]
    }
    func refreshSummaryCountsFromSpaceMesh() {}
    func enqueueSpaceSync(site: SiteData, level: SyncLevel) { PageBoundary.uploads += 1 }
}
extension SpaceConfigurationSafety {
    static func isCurrent(_ context: FixtureRecoveryState, space: SpaceData) -> Bool { context.generation == recovery.generation }
    static func canCleanSyncReferences(_ space: SpaceData) -> Bool { space.permission != .visitor && recovery.authority == .writable }
    static func hasPendingDeletionCleanup(_ space: SpaceData) -> Bool { PageBoundary.pendingDeletion }
    static func hasPendingUpload(_ space: SpaceData) -> Bool { PageBoundary.pendingUpload }
    static func hasPendingReferenceCleanup(_ space: SpaceData) -> Bool { PageBoundary.pendingReference }
    static func verifySyncCleanupBaseline(_ space: SpaceData, local: [String: Any]) async -> Bool {
        PageBoundary.afterBaseline?(); return PageBoundary.baselineOK
    }
    static func beginSyncReferenceCleanup(_ space: SpaceData, payload: [String: Any]) -> Bool {
        PageBoundary.begins += 1; PageBoundary.pendingReference = true; return true
    }
    static func finishSyncReferenceCleanup(_ space: SpaceData, changed: Bool) -> Bool {
        PageBoundary.finishes += 1
        guard !PageBoundary.failFinish else { return false }
        PageBoundary.pendingReference = false; return true
    }
}
@MainActor final class ScenePageHarness {
    final class View { var isUserInteractionEnabled = true; var window: Bool? = true }
    let space = SpaceData.value
    let collectionView = View(), footerView = View()
    var viewIfLoaded: View? = View()
    var isPageVisible = true, isSelectedPage = false
    var membershipRevision: SpacePageRevision?
    var membershipTask: _Concurrency.Task<Void, Never>?
    var membershipPreparationRequested = false
    func refreshVisibleUI() {}
    // ACTUAL_PAGE_METHODS
}
@main struct ScenePageMembershipCleanupTests {
    @MainActor static func fixture(orphan: Bool = true) throws -> Scene {
        let (scene, a, b, _) = try prepareFixture()
        if orphan { SceneDeletionFlowTests.manager.realNodes.removeAll { $0 === a || $0 === b } }
        return scene
    }
    @MainActor static func prepareFixture() throws -> (Scene, Node, Node, Node) {
        let (scene, a, b, x, _) = try SceneDeletionFlowTests.fixture()
        try PageBoundary.reset()
        return (scene, a, b, x)
    }
    @MainActor static func run(_ current: @escaping () -> Bool = { true }) async -> Bool {
        await ScenePageMembershipCleanup.prepare(space: SpaceData.value, isCurrent: current)
    }
    @MainActor static func expectRun(_ expected: Bool, current: @escaping () -> Bool = { true }) async {
        let result = await run(current); check(result == expected)
    }
    @MainActor static func main() async throws {
        var scene = try fixture(orphan: false)
        let changes = SunSmartDataManager.shared.db!.totalChanges
        await expectRun(true)
        check(PageBoundary.exports == 0 && PageBoundary.uploads == 0 && PageBoundary.saves == 0)
        check(SunSmartDataManager.shared.db!.totalChanges == changes)
        scene = try fixture()
        await expectRun(true)
        check(scene.info.configuration!.deviceMembers.isEmpty)
        check(try SceneDeletionFlowTests.persisted()!.configuration!.deviceMembers.isEmpty)
        check(PageBoundary.uploads == 1 && PageBoundary.begins == 1 && PageBoundary.finishes == 1)
        let version = SpaceData.value.lastUpdate
        await expectRun(true)
        check(SpaceData.value.lastUpdate == version && PageBoundary.uploads == 1)

        for blocked in 0..<5 {
            scene = try fixture()
            switch blocked {
            case 0: SpaceData.value.permission = .visitor
            case 1: PageBoundary.pendingUpload = true
            case 2: PageBoundary.pendingDeletion = true
            case 3: MeshProxyMessageCommand.shared.isBusy = true
            default:
                let receipt = SceneRestoreReceipt(id: UUID(), scope: SceneDeletionFlowTests.scope,
                    recoveryGeneration: SpaceConfigurationSafety.recovery.generation,
                    oldIdentity: scene.info.configuration!.deviceMembers[0].identity)
                SpaceConfigurationSafety.recovery.sceneRestoreReceipts = try JSONEncoder().encode([receipt])
            }
            await expectRun(false); check(PageBoundary.uploads == 0 && PageBoundary.begins == 0)
            check(scene.info.configuration!.deviceMembers.count == 2)
        }
        for mutation in 0..<5 {
            scene = try fixture()
            var selected = true
            PageBoundary.afterBaseline = {
                switch mutation {
                case 0: selected = false
                case 1: SpaceConfigurationSafety.recovery.generation = UUID()
                case 2: SceneDeletionFlowTests.manager.currentNetworkKey.networkId = 2
                case 3: SceneDeletionFlowTests.manager.realNodes.append(Node(8))
                default:
                    let saved = try! SceneDeletionFlowTests.persisted()!
                    saved.configuration!.name = "concurrent edit"
                    try! saved.saveConfiguration(meshUUID: SceneDeletionFlowTests.scope.meshUUID, subnetworkId: "0001")
                }
            }
            await expectRun(false, current: { selected }); check(PageBoundary.begins == 0 && PageBoundary.uploads == 0)
            check(scene.info.configuration!.deviceMembers.count == 2)
        }
        scene = try fixture(); PageBoundary.baselineOK = false
        await expectRun(false); check(PageBoundary.begins == 0)
        scene = try fixture(); PageBoundary.failSave = true
        await expectRun(false)
        check(SpaceData.value.lastUpdate == 1 && scene.info.configuration!.deviceMembers.count == 2)
        check(try SceneDeletionFlowTests.persisted()!.configuration!.deviceMembers.count == 2)
        check(PageBoundary.pendingReference && PageBoundary.uploads == 1)
        // Model the existing journal recovery completing before the next entry.
        PageBoundary.failSave = false; PageBoundary.pendingReference = false
        await expectRun(true); check(scene.info.configuration!.deviceMembers.isEmpty)
        scene = try fixture(); PageBoundary.failFinish = true
        await expectRun(false); check(PageBoundary.pendingReference && PageBoundary.uploads == 1)
        check(try SceneDeletionFlowTests.persisted()!.configuration!.deviceMembers.isEmpty)

        _ = try fixture()
        let page = ScenePageHarness()
        page.prepareMembershipIfNeeded() // preload/ordinary view appearance
        check(SiteData.loads == 0 && page.membershipTask == nil)
        page.setScenePageSelected(true)
        page.setScenePageSelected(true) // coalesced during the same run
        await page.membershipTask?.value
        let loads = SiteData.loads
        check(PageBoundary.uploads == 1)
        page.setScenePageSelected(false); page.setScenePageSelected(true)
        check(page.membershipTask == nil && SiteData.loads == loads)
        PageBoundary.revision += 1
        page.prepareMembershipIfNeeded(); await page.membershipTask?.value
        check(SiteData.loads > loads && PageBoundary.uploads == 1)
        print("PASS Scene page: no-op zero writes/exports/uploads, one upload per cleanup, authority/Restore/upload/busy gates, await invalidation, real SQLite rollback, retained recovery, preload and repeated-entry coalescing")
    }
}
