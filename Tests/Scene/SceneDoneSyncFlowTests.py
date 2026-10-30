"""Execute Settings DONE/commit/navigation methods with deterministic UI/transport boundaries."""
from pathlib import Path
import tempfile
import subprocess
ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift').read_text()
sync_source = (ROOT / 'SunSmart/Main/Space/Controller/SyncDevicesViewController.swift').read_text()
def block(marker):
    start = source.index(marker)
    opening = source.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('@objc ', '').replace('private func', 'func')
swift = r'''
import Foundation
extension String { var localizedString: String { self } }
enum Kind { case groups, devices }
struct Draft { var kind: Kind = .groups; var revision = UUID(); var number: Int? = 1; var scope = 1 }
final class Scene {
    struct Configuration { var pendingOperations: [Int] = [] }
    struct Info { var configuration: Configuration? = Configuration() }
    var needSync = false
    var info = Info()
}
final class SceneDraftSelection { var draft: Draft; init(draft: Draft) { self.draft = draft } }
typealias TimedSchedulerNodeIdentity = Int
typealias SceneTargetSnapshot = Snapshot
extension Int { var node: Int { self }; var state: Bool { self > 0 }; var identity: Int { self } }
struct Snapshot { typealias Comparison = Int; var comparison = 1; var targets: [Int] = [1]; var hasConfiguredMembers = true }
enum SceneTargetResolver { static var snapshot = Snapshot(); static func resolve(draft: Draft) throws -> Snapshot { snapshot } }
struct SceneConfigurationStore {
    enum Failure: Error { case noNumber, staleDraft }
    static var allowed = true
    static var unchanged: Scene?
    static func validateAccess(_ scope: Int) throws { if !allowed { throw Failure.staleDraft } }
    func editingDraft(for scene: Scene) throws -> Draft { Draft() }
    func sceneIfUnchanged(draft: Draft) throws -> Scene? {
        try Self.validateAccess(draft.scope)
        return Self.unchanged
    }
}
enum SceneCapacity {
    static func nodesRequiringRead(sceneSnapshot: Snapshot) -> [Int] { [] }
    static func readUnknownState(nodes: [Int], completion: (Bool) -> Void) { completion(true) }
}
enum TimedSchedulerBindings {
    static var unknown = false
    static func nodesRequiringTopologyRead(sceneSnapshot: Snapshot) throws -> [Int] { unknown ? [1] : [] }
    static func prepareTopology(sceneSnapshot: Snapshot) throws -> Bool { true }
}
enum ScheduleServer {
    static var completion: ((Bool) -> Void)?
    static func readUnknownSchedulerState(nodes: [Int], completion: @escaping (Bool) -> Void) { Self.completion = completion }
}
enum XWHUDManager { static func hide() {}; static func showCustomHUD(withMessage: String, isWindow: Bool) {} }
enum DispatchQueue { struct Queue { func async(_ action: () -> Void) { action() } }; static let main = Queue() }
enum SpaceChangeDataType { case common }
let spaceDataChangedNotificaitonName = "space", sceneDataUpdateNotificationName = "scene", scenesRefreshNotificationName = "scenes"
final class DevicesView { var selecting = false; var previewPhase: SceneDevicePreviewState.Phase = .recommended }
final class ToastStatusView {
    enum Kind { case success, failure }; enum Appearance { case siteUpdate }
    static var shown: [Kind] = []
    var removed = false
    func removeFromSuperview() { removed = true }
    static func show(in view: Int, message: String, type: Kind, appearance: Appearance, duration: Int) -> ToastStatusView { shown.append(type); return .init() }
}
typealias SceneSaveCoordinator = Coordinator
final class Coordinator {
    enum Purpose { case preview, beforeSave }
    enum TargetResult { case successful, failed, offline }
    struct Report { var revision: UUID; var results: [Int: TargetResult] }
    var cancellations = 0
    func cancel() { cancellations += 1 }
    enum Result { case ready(Scene), projectionPending(Int) }
    var committedNumber: Int?, sends = 0, saves = 0, pending = false, throwsError = false
    func send(draft: Draft, purpose: Purpose) throws {
        if throwsError { throw SceneConfigurationStore.Failure.staleDraft }
        sends += 1
    }
    func confirm(revision: UUID) throws -> Result { saves += 1; return .ready(Scene()) }
    func saveForSync(draft: Draft) throws -> Result {
        if throwsError { throw SceneConfigurationStore.Failure.staleDraft }
        saves += 1; committedNumber = 1; return pending ? .projectionPending(1) : .ready(Scene())
    }
}
final class SyncDevicesViewController {
    enum Kind { case scene(Scene) }
    enum SyncState { case syncSuccess, syncFailure }
    struct Initialization { var isKeybindComplete = false }
    var hdbAwaitingInitialization: [Initialization] = []
    var hasLeftSyncPage = false
    var backActionCallback: (([Int]) -> Void)?
    var syncSuccessCallback: ((Kind) -> Void)?
    let type: Kind
    init(type: Kind) { self.type = type }
    func rebuildTaskPlan(resume: Bool) {}
    func complete(_ state: SyncState) {
        let callback: (SyncState) -> Void = // COMPLETION_CALLBACK
        callback(state)
    }
}
final class SyncDevicesProgressView {
    static func current() -> SyncDevicesProgressView? { nil }
    func hide() {}
    func reload() {}
}
final class Navigation {
    var pushed: [SyncDevicesViewController] = []
    var viewControllers: [AnyObject] = []
    var pops = 0
    func pushViewController(_ page: SyncDevicesViewController, animated: Bool) { pushed.append(page); viewControllers.append(page) }
    func popToViewController(_ page: AnyObject, animated: Bool) { pops += 1; viewControllers = Array(viewControllers.prefix { $0 !== page }) + [page] }
}
final class Settings {
    var busy = false, active = true, lifecycle = UUID(), savePurpose = false, emptySave = false
    var syncPagePresented = false
    var selection: SceneDraftSelection? = .init(draft: Draft()), scene: Scene? = Scene()
    var initialError: Error?, coordinator = Coordinator()
    var devicesView: DevicesView! = DevicesView()
    var devicePreview = SceneDevicePreviewState()
    var previewComparison: Int?, previewOnline = Set<Int>()
    var previewReport: Coordinator.Report?, previewToast: ToastStatusView?
    var view = 1, resultDialogs = 0
    func showPreviewResults(_ report: Coordinator.Report) { resultDialogs += 1 }
    var navigationController: Navigation? = Navigation()
    var alerts = 0, errors = 0, stopped = 0, finished = 0, callbacks = 0
    var finishesCreation = false
    var sceneUpdateCallback: ((Scene) -> Void)?
    var tips: [String] = []
    init() { navigationController?.viewControllers = [NSObject(), self]; sceneUpdateCallback = { [weak self] _ in self?.callbacks += 1 } }
    func setupEditor(_ selection: SceneDraftSelection) {}
    func selectDevices() { devicesView.selecting = false }
    func tip(_ text: String) { tips.append(text) }
    func failed(_ error: Error) { errors += 1; interruptDevicePreview(); busy = false }
    func setBusy(_ value: Bool) { busy = value }
    func stopDeviceLiveControl() {}
    func stopGroupPreview() { stopped += 1 }
    func accepts(_ token: UUID, revision: UUID) -> Bool { active && token == lifecycle && selection?.draft.revision == revision }
    func showAlert(title: String, message: String, cancel: String, confirm: String, action: @escaping () -> Void) { alerts += 1 }
    func requestAddresses(revision: UUID) {}
    func finishCreation() { finished += 1 }
    func leave() {
        active = false
        if finishesCreation { finishCreation() }
        else if let previous = navigationController?.viewControllers.first { navigationController?.popToViewController(previous, animated: true) }
    }
    // METHODS
}
func check(_ condition: Bool, _ message: String) { if !condition { print("FAIL: \(message)"); exit(1) }; print("PASS: \(message)") }
@main enum Tests {
    static func main() {
        let unchanged = Settings(), existing = Scene()
        SceneConfigurationStore.unchanged = existing
        unchanged.doneAction(); unchanged.doneAction()
        check(unchanged.coordinator.saves == 0 && unchanged.navigationController!.pushed.isEmpty && unchanged.navigationController!.pops == 1,
              "unchanged synced Settings closes once without save or Sync page")
        for residual in [false, true] {
            let retry = Settings()
            existing.needSync = !residual
            existing.info.configuration?.pendingOperations = residual ? [1] : []
            retry.doneAction()
            check(retry.coordinator.saves == 0 && retry.navigationController!.pushed.count == 1,
                  "unchanged Settings retries existing work without regenerating it: residual=\(residual)")
        }
        existing.needSync = false; existing.info.configuration?.pendingOperations = []
        let emptyCreated = Settings(); emptyCreated.finishesCreation = true; emptyCreated.doneAction()
        check(emptyCreated.finished == 1 && emptyCreated.coordinator.saves == 0 && emptyCreated.navigationController!.pushed.isEmpty,
              "unchanged precreated scene completes creation without empty Sync page")
        let revoked = Settings(); SceneConfigurationStore.allowed = false; revoked.doneAction()
        check(revoked.errors == 1 && revoked.navigationController!.pops == 0, "unchanged shortcut still validates access")
        SceneConfigurationStore.allowed = true; SceneConfigurationStore.unchanged = nil
        let page = Settings()
        page.doneAction()
        check(page.alerts == 0, "DONE has no send/confirm dialog")
        check(page.coordinator.sends == 0 && page.coordinator.saves == 1, "DONE commits without preview send")
        check(page.navigationController!.pushed.count == 1 && page.stopped == 1, "DONE opens one sync page and stops live control")
        page.doneAction()
        check(page.navigationController!.pushed.count == 1, "repeated DONE cannot push twice")
        let sync = page.navigationController!.pushed[0]
        sync.backActionCallback?([])
        check(page.navigationController!.viewControllers.count == 1, "sync back skips committed editor")
        sync.complete(.syncSuccess)
        check(page.navigationController!.pops == 1, "late success after manual return cannot navigate twice")
        let auto = Settings(); auto.doneAction()
        let autoSync = auto.navigationController!.pushed[0]
        autoSync.complete(.syncFailure)
        check(auto.navigationController!.viewControllers.last === autoSync, "failure or stopped run stays on Sync")
        autoSync.complete(.syncSuccess)
        check(auto.navigationController!.viewControllers.count == 1 && auto.navigationController!.pops == 1, "successful retry automatically skips committed Settings")
        autoSync.complete(.syncSuccess); autoSync.backActionCallback?([])
        check(auto.navigationController!.pops == 1, "success and back share exactly one navigation")
        let left = Settings(); left.doneAction()
        let leftSync = left.navigationController!.pushed[0]; leftSync.hasLeftSyncPage = true
        leftSync.complete(.syncSuccess)
        check(left.navigationController!.pops == 0, "completion from a departed page cannot navigate")
        let pending = Settings(); pending.coordinator.pending = true; pending.doneAction()
        check(pending.navigationController!.pushed.isEmpty && !pending.busy, "projection pending cannot open sync")
        pending.coordinator.pending = false; pending.doneAction()
        check(pending.navigationController!.pushed.count == 1, "projection retry hands off once ready")
        let failed = Settings(); failed.coordinator.throwsError = true; failed.doneAction()
        check(failed.errors == 1 && failed.navigationController!.pushed.isEmpty, "failed commit cannot open sync")
        let preview = Settings(); preview.startSend(saving: false)
        check(preview.coordinator.sends == 1 && preview.coordinator.saves == 0 && preview.navigationController!.pushed.isEmpty, "Preview remains parameter-only")

        let device = Settings(); device.selection!.draft.kind = .devices
        device.refreshDevicePreviewContext()
        check(device.devicesView.previewPhase == .recommended, "new device draft recommends preview")
        device.previewAction(); device.previewAction(); device.doneAction()
        check(device.coordinator.sends == 1 && device.coordinator.saves == 0 && device.busy && device.devicesView.previewPhase == .applying, "device preview is single-flight and blocks DONE only while running")
        let revision = device.selection!.draft.revision
        device.received(.init(revision: revision, results: [1: .successful]))
        check(!device.busy && device.devicesView.previewPhase == .applied && ToastStatusView.shown.last == .success && device.resultDialogs == 0, "success removes banner and shows nonblocking toast")
        let toast = device.previewToast!
        device.refreshDevicePreviewContext()
        check(device.devicesView.previewPhase == .applied && !toast.removed, "unchanged draft retains applied feedback")
        device.selection!.draft.revision = UUID(); device.refreshDevicePreviewContext()
        check(device.devicesView.previewPhase == .recommended && toast.removed && device.previewReport == nil, "changed draft invalidates success and removes its toast")
        device.previewAction()
        device.received(.init(revision: revision, results: [1: .successful]))
        check(device.busy && device.devicesView.previewPhase == .applying, "old revision cannot finish a new preview")
        device.received(.init(revision: device.selection!.draft.revision, results: [1: .successful, 2: .failed, 3: .offline]))
        check(device.devicesView.previewPhase == .incomplete(successful: 1, failed: 1, offline: 1) && ToastStatusView.shown.last == .failure && device.previewReport != nil, "partial result keeps accurate counts and detail data")
        device.doneAction()
        check(device.coordinator.saves == 1 && device.navigationController!.pushed.count == 1, "preview failure does not block formal DONE")
        for results: [Int: Coordinator.TargetResult] in [[:], [1: .offline], [1: .failed]] {
            let unsuccessful = Settings(); unsuccessful.selection!.draft.kind = .devices
            unsuccessful.previewAction(); unsuccessful.received(.init(revision: unsuccessful.selection!.draft.revision, results: results))
            check(!unsuccessful.busy && unsuccessful.devicesView.previewPhase != .applied && ToastStatusView.shown.last == .failure, "empty, offline and failed results cannot claim success")
        }
        let interrupted = Settings(); interrupted.selection!.draft.kind = .devices
        interrupted.previewAction(); let oldAttempt = interrupted.devicePreview.attempt!
        interrupted.interruptDevicePreview()
        interrupted.received(.init(revision: interrupted.selection!.draft.revision, results: [1: .successful]))
        check(!interrupted.busy && interrupted.devicesView.previewPhase == .interrupted && interrupted.previewReport == nil, "cancelled preview ignores late report and unlocks editing")
        interrupted.previewAction()
        check(interrupted.devicePreview.attempt != oldAttempt && interrupted.busy, "KEEP EDITING can retry with a new attempt")
        check(!interrupted.devicePreview.complete(attempt: oldAttempt, revision: interrupted.selection!.draft.revision, successful: 1, failed: 0, offline: 0), "old attempt cannot overwrite retry state")
        interrupted.active = false
        interrupted.received(.init(revision: interrupted.selection!.draft.revision, results: [1: .successful]))
        check(interrupted.previewReport == nil, "inactive editor rejects reports")
        let preparation = Settings(); preparation.selection!.draft.kind = .devices
        TimedSchedulerBindings.unknown = true; preparation.previewAction()
        check(preparation.devicesView.previewPhase == .preparing && preparation.coordinator.sends == 0, "topology read remains in preparing state")
        let readCompletion = ScheduleServer.completion!
        preparation.interruptDevicePreview(); TimedSchedulerBindings.unknown = false; readCompletion(true)
        check(preparation.coordinator.sends == 0 && !preparation.busy, "late topology read cannot start cancelled preview")
        let readFailed = Settings(); readFailed.selection!.draft.kind = .devices
        TimedSchedulerBindings.unknown = true; readFailed.previewAction(); ScheduleServer.completion?(false)
        check(!readFailed.busy && readFailed.devicesView.previewPhase == .interrupted, "failed preparation restores retry")
        TimedSchedulerBindings.unknown = false
        let sendFailed = Settings(); sendFailed.selection!.draft.kind = .devices; sendFailed.coordinator.throwsError = true
        sendFailed.previewAction()
        check(!sendFailed.busy && sendFailed.devicesView.previewPhase == .interrupted, "send error does not leave applying banner")
        let changedTargets = Settings(); changedTargets.selection!.draft.kind = .devices; changedTargets.previewAction()
        SceneTargetResolver.snapshot.comparison += 1; changedTargets.refreshDevicePreviewContext()
        check(!changedTargets.busy && changedTargets.devicesView.previewPhase == .recommended && changedTargets.coordinator.cancellations > 0, "changed targets cancel in-flight preview and require fresh check")
        SceneTargetResolver.snapshot.comparison = 1
        let selector = Settings(); selector.devicesView.selecting = true; selector.previewAction(); selector.doneAction()
        check(selector.coordinator.sends == 0 && selector.coordinator.saves == 0 && !selector.devicesView.selecting, "selector DONE only returns and selector cannot preview")
        preview.received(.init(revision: preview.selection!.draft.revision, results: [1: .successful]))
        check(preview.resultDialogs == 1, "Groups retains its existing result dialog")

        let create = Settings(); create.scene = nil; create.doneAction()
        create.navigationController!.pushed[0].backActionCallback?([])
        check(create.finished == 1 && create.callbacks == 1, "new draft completes creation on sync exit")
        let custom = Settings(); custom.finishesCreation = true; custom.doneAction()
        custom.navigationController!.pushed[0].backActionCallback?([])
        check(custom.finished == 1, "already-created empty scene completes creation on sync exit")
        for isNew in [true, false] {
            let created = Settings(); created.scene = isNew ? nil : Scene(); created.finishesCreation = !isNew
            created.doneAction()
            let createdSync = created.navigationController!.pushed[0]
            createdSync.complete(.syncSuccess); createdSync.backActionCallback?([]); createdSync.complete(.syncSuccess)
            check(created.finished == 1 && created.callbacks == 1, "successful creation completes existing flow exactly once: new=\(isNew)")
        }
        let selecting = Settings(); selecting.devicesView.selecting = true; selecting.doneAction()
        check(!selecting.devicesView.selecting && selecting.coordinator.saves == 0, "selection DONE only finishes device selection")
        let empty = Settings(); SceneTargetResolver.snapshot.targets = []; empty.doneAction()
        check(empty.navigationController!.pushed.count == 1, "legal empty target still opens sync for cleanup")
        let waiting = Settings(); TimedSchedulerBindings.unknown = true; waiting.doneAction()
        waiting.active = false; waiting.lifecycle = UUID(); TimedSchedulerBindings.unknown = false
        ScheduleServer.completion?(true)
        check(waiting.coordinator.saves == 0 && waiting.navigationController!.pushed.isEmpty, "late topology read cannot save after exit")
    }
}
'''
markers = ['    @objc private func doneAction()', '    private func startSend(saving:', '    private func commit(revision:']
if '    private func openSyncPage(' in source:
    markers += ['    private func openSyncPage(']
markers += ['    private func clearPreviewToast()', '    private func beginDevicePreview()', '    private func interruptDevicePreview()', '    private func refreshDevicePreviewContext()', '    @objc private func previewAction()', '    private func received(']
state_source = (ROOT / 'SunSmart/Main/Scene/Model/SceneDraftSelection.swift').read_text()
swift += '\n' + state_source[state_source.index('struct SceneDevicePreviewState {'):]
swift = swift.replace('// METHODS', '\n'.join(block(m) for m in markers))
start = sync_source.index('        executionSession.onCompleted = ')
opening = sync_source.index('{', start)
end, depth = opening + 1, 1
while depth:
    depth += (sync_source[end] == '{') - (sync_source[end] == '}')
    end += 1
swift = swift.replace('// COMPLETION_CALLBACK', sync_source[opening:end])
with tempfile.TemporaryDirectory(prefix='scene-done-flow-') as directory:
    path = Path(directory); (path / 'Tests.swift').write_text(swift)
    subprocess.run(['swiftc', '-parse-as-library', str(path / 'Tests.swift'), '-o', str(path / 'Tests')], check=True)
    subprocess.run([str(path / 'Tests')], check=True)
