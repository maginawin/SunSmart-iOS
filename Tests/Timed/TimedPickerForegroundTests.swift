#if os(macOS)
import Foundation

// UIKit lifecycle names and view attachment are boundary inputs. The script
// inserts each picker's production observer, refresh and cancellation bodies;
// snapshot reads run through the production reader without Scheduler updates.
private enum UIApplication {
    static let didBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
}
private enum SpaceSchedulerReadCoordinator {
    static let didUpdate = Notification.Name("SpaceSchedulerReadCoordinator.didUpdate")
}
private struct PickerFilterSession {
    func removeObserver(_ token: UUID) {}
}
private protocol PickerForegroundProbe: AnyObject {
    init(schedule: Schedule?)
    var currentSnapshot: ScheduleTargetSyncSnapshot? { get }
    var appearanceUpdates: Int { get }
    var attached: Bool { get set }
    func present()
    func dismiss()
}

// PRODUCTION_PICKER_PROBES

extension NodeSyncStatusRefreshTests {
    static func timedPickerForegroundTests() async {
        await checkPickerForeground(ScheduleDevicesForegroundProbe.self)
        await checkPickerForeground(ScheduleGroupsForegroundProbe.self)
        await checkPickerForeground(ScheduleScenesForegroundProbe.self)
        print("PASS: all three Timed pickers recover after foreground invalidation without Scheduler updates; duplicate activation, hidden/detached/add pickers, cancellation and release")
    }

    private static func checkPickerForeground<Picker: PickerForegroundProbe>(_ type: Picker.Type) async {
        let network = fixture(8), session = NSObject()
        let scene = Scene(); scene.info.groups = network.groups
        let schedule = Schedule(); schedule.selectTargetType = .scene; schedule.scene = scene
        MeshNetworkManager.instance.schedules = [schedule]
        MeshNetworkManager.instance.scenes = [scene]
        var checks = 0, needsSync = false
        schedule.syncRead = { _, _ in checks += 1; return needsSync }
        schedule.deleteRead = { _, _ in false }
        NodeSyncStatusRefresh.beginSession(owner: session)
        defer { NodeSyncStatusRefresh.endSession(owner: session) }

        func foreground() {
            NotificationCenter.default.post(name: .init("UIApplicationWillEnterForegroundNotification"), object: nil)
        }
        func activate() {
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        func isClean(_ snapshot: ScheduleTargetSyncSnapshot?) -> Bool {
            guard let snapshot else { return false }
            return snapshot.nodes.isEmpty && snapshot.groups.isEmpty && snapshot.scenes.isEmpty
        }

        var picker: Picker? = Picker(schedule: schedule)
        weak var releasedPicker = picker
        picker!.present()
        await drain { picker!.currentSnapshot != nil }
        require(isClean(picker!.currentSnapshot), "initial picker is not synchronized")
        let initialChecks = checks
        foreground()
        require(picker!.currentSnapshot == nil, "foreground did not invalidate the picker")
        let beforeActivation = picker!.appearanceUpdates
        activate()
        require(picker!.appearanceUpdates > beforeActivation, "visible picker did not request a foreground refresh")
        activate()
        await drain { picker!.currentSnapshot != nil }
        require(isClean(picker!.currentSnapshot), "foreground left synchronized targets with no valid snapshot")
        require(checks == initialChecks * 2, "duplicate activation repeated the target read")
        activate()
        require(checks == initialChecks * 2, "activation discarded a valid snapshot")

        // Recalculation must also retain real warnings and clear them on a later
        // foreground cycle, rather than simply treating an absent snapshot as clean.
        needsSync = true
        foreground(); activate()
        await drain { picker!.currentSnapshot != nil }
        require(picker!.currentSnapshot?.scenes == [ObjectIdentifier(scene)], "foreground lost an actual Scene warning")
        require(picker!.currentSnapshot?.groups.isEmpty == false, "foreground lost actual Group warnings")
        needsSync = false
        foreground(); activate()
        await drain { picker!.currentSnapshot != nil }
        require(isClean(picker!.currentSnapshot), "foreground retained obsolete warnings")

        // A detached view and a new-schedule picker must not enqueue work.
        picker!.attached = false
        foreground()
        var beforeIgnoredActivation = picker!.appearanceUpdates
        activate()
        require(picker!.appearanceUpdates == beforeIgnoredActivation, "detached picker refreshed")
        picker!.attached = true
        let adding = Picker(schedule: nil)
        adding.present(); activate()
        require(adding.appearanceUpdates == 0, "new-schedule picker requested sync status")

        // Close while a read is queued; a separate owner drains the batch so
        // this assertion does not rely on an arbitrary sleep.
        foreground(); activate()
        picker!.dismiss()
        beforeIgnoredActivation = picker!.appearanceUpdates
        activate()
        require(picker!.appearanceUpdates == beforeIgnoredActivation, "closed picker refreshed")
        let survivor = ScheduleTargetDisplayState()
        var completed = false
        survivor.refresh(schedule: schedule) { completed = true }
        await drain { completed }
        require(picker!.appearanceUpdates == beforeIgnoredActivation, "dismissed picker received a read callback")
        picker!.present()
        await drain { picker!.currentSnapshot != nil }
        require(isClean(picker!.currentSnapshot), "reopened picker failed to refresh")
        picker = nil
        require(releasedPicker == nil, "notification observers retained the picker")
        foreground(); activate()
    }
}
#endif
