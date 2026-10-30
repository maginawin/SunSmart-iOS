import Foundation

@main struct SceneDraftSelectionTests {
    static func main() throws {
        let scope = SceneScope(meshUUID: "mesh", networkID: "net")
        func identity(_ index: Int) -> TimedSchedulerNodeIdentity {
            .init(nodeUUID: String(format: "00000000-0000-0000-0000-%012d", index),
                  unicastAddress: String(format: "%04X", index), deviceKeyFingerprint: String(repeating: "A", count: 64))
        }
        let on = SceneParameters(isOn: true, lightness: 65535, cct: 4500)
        let off = SceneParameters(isOn: false, lightness: 0, cct: 4500)
        let a = identity(1), b = identity(2), c = identity(3)
        func session() throws -> SceneDraftSelection {
            .init(draft: try SceneDraft(scope: scope, name: "Scene", imageId: 1, kind: .devices))
        }
        let candidates: [SceneDraftSelection.Candidate] = [
            .init(identity: a, name: "Hidden lamp", category: "Room", categoryID: 1, canAdd: true, defaults: on),
            .init(identity: b, name: "Panel", category: "Room", categoryID: 1, canAdd: true, defaults: on),
            .init(identity: c, name: "Panel offline", category: "Room", categoryID: 1, canAdd: false, defaults: on)]
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            precondition(condition(), name); passed += 1; print("PASS selection: \(name)")
        }
        let filtered = try session()
        filtered.filter.submit(" panel ")
        try filtered.selectFiltered(candidates, selected: true)
        check("selectAllUsesFilteredEligibleSet", filtered.draft.deviceMembers.map(\.identity) == [b])
        try filtered.setSelected(candidates[0], selected: true)
        try filtered.selectFiltered(candidates, selected: false)
        check("hiddenSelectionsAreRetained", filtered.draft.deviceMembers.map(\.identity) == [a])
        let before = filtered.draft
        try filtered.switchKind(to: .groups, confirmed: false)
        check("switchModeCancelRetainsDraft", filtered.draft == before)
        try filtered.apply(off, identities: [a,b,c])
        check("bulkEditOnlyChangesSelectedMembers", filtered.draft.deviceMembers == [.init(identity: a, parameters: off)])
        let stored = filtered.draft
        let token = filtered.beginParameterEdit()
        try filtered.finishParameterEdit(token, parameters: on, identities: [a], apply: false)
        check("relayCancelDiscards", filtered.draft == stored)
        let applyToken = filtered.beginParameterEdit()
        try filtered.finishParameterEdit(applyToken, parameters: on, identities: [a], apply: true)
        check("relayApplyCommitsDraftOnly", filtered.draft.deviceMembers[0].parameters == on && stored.deviceMembers[0].parameters == off && filtered.draft.number == nil)
        try filtered.apply(off, identities: [a])
        try filtered.setSelected(candidates[0], selected: false)
        try filtered.setSelected(candidates[0], selected: true)
        check("reselectRetainsEditedDraftParameters", filtered.draft.deviceMembers[0].parameters == off)
        let old = filtered.beginParameterEdit()
        let latest = filtered.beginParameterEdit()
        try filtered.finishParameterEdit(latest, parameters: off, identities: [a], apply: true)
        try filtered.finishParameterEdit(old, parameters: on, identities: [a], apply: true)
        check("oldSliderCallbackCannotOverwriteNewValue", filtered.draft.deviceMembers[0].parameters == off)
        let abandoned = filtered.beginParameterEdit()
        filtered.invalidateParameterEdit()
        try filtered.finishParameterEdit(abandoned, parameters: on, identities: [a], apply: true)
        check("abandonedPopupCannotCommit", filtered.draft.deviceMembers[0].parameters == off)
        let config = SceneConfiguration(kind: .devices, name: "Old", deviceMembers: [.init(identity: c, parameters: on)])
        let existing = SceneDraftSelection(draft: try SceneDraft(number: 1, scope: scope, name: "Old", imageId: 1,
            kind: .devices, deviceMembers: config.deviceMembers, sourceConfiguration: config))
        try existing.selectFiltered(candidates, selected: false)
        check("offlineExistingMemberCanBeRemoved", existing.draft.deviceMembers.isEmpty)
        try existing.setSelected(candidates[2], selected: true)
        check("offlineRemovalCanBeUndone", existing.draft.deviceMembers == config.deviceMembers)
        try existing.setSelected(candidates[2], selected: false)
        do { try existing.switchKind(to: .groups, confirmed: true); preconditionFailure("cleanup conversion") } catch { passed += 1 }
        filtered.filter.submit(" rOoM ")
        check("categorySearchUsesProductionFilter", filtered.filtered(candidates).count == 2)
        filtered.filter.reset()
        check("selectorIncludesEmptyCategories", filtered.visibleCategoryIDs([1: "Room", 2: "Empty"], candidates: candidates, selecting: true) == [1,2])
        filtered.filter.submit("empty")
        check("emptyCategorySearchRetainsZeroCount", filtered.visibleCategoryIDs([1: "Room", 2: "Empty"], candidates: candidates, selecting: true) == [2])
        let beforeRemoval = filtered.draft
        try filtered.removeMembers([a,b], confirmed: false)
        check("categoryRemovalCancelRetainsDraft", filtered.draft == beforeRemoval)
        try filtered.removeMembers([a,b], confirmed: true)
        check("categoryRemovalOnlyChangesSelectedMembers", filtered.draft.deviceMembers.isEmpty && beforeRemoval.deviceMembers.count == 1)
        let newEmpty = try session()
        check("newEmptyDeviceSelectionCannotFinish", !newEmpty.canFinishDeviceSelection)
        check("existingLastMemberRemovalCanFinish", existing.canFinishDeviceSelection)
        let entry = SceneSelectionEntryHarness(selection: existing)
        entry.selectDevices()
        let existingPage = entry.navigationController!.topViewController!
        existingPage.selectDevices()
        check("existingEmptySelectionDonePopsSelector", entry.navigationController!.topViewController === entry)
        let newEntry = SceneSelectionEntryHarness(selection: newEmpty)
        newEntry.selectDevices()
        let page = newEntry.navigationController!.topViewController!
        check("selectorPushSharesDraft", page !== newEntry && page.selection === newEntry.selection && page.devicesView.selecting)
        newEntry.selectDevices()
        check("hiddenParentCannotPushAgain", newEntry.navigationController!.pages.count == 2)
        page.selectDevices()
        check("newEmptySelectionDoneStaysInSelector", newEntry.navigationController!.topViewController === page && page.tips == 1)
        let beforeClose = newEmpty.draft
        page.closeAction()
        check("emptySelectorClosePopsWithoutDiscard", newEntry.navigationController!.topViewController === newEntry && page.alerts == 0 && page.leaves == 0)
        check("closeRetainsEmptyDraft", newEmpty.draft == beforeClose)
        newEntry.selectDevices()
        let nextPage = newEntry.navigationController!.topViewController!
        try newEmpty.setSelected(candidates[0], selected: true)
        try newEmpty.apply(off, identities: [a])
        newEmpty.filter.submit("hidden")
        let edited = newEmpty.draft
        let lateEdit = newEmpty.beginParameterEdit()
        nextPage.closeAction()
        try newEmpty.finishParameterEdit(lateEdit, parameters: on, identities: [a], apply: true)
        check("closeRetainsMembersAndParametersAndRejectsLatePopup", newEmpty.draft == edited && nextPage.leaves == 0)
        check("popClearsSharedSearch", newEmpty.displayed(candidates).count == 3)
        newEntry.closeAction()
        check("settingsCloseStillAsksToDiscard", newEntry.alerts == 1)
        check("settingsDiscardUsesDestructiveStyle", newEntry.lastConfirmStyle == .destructive)
        newEntry.selectDevices()
        let donePage = newEntry.navigationController!.topViewController!
        donePage.selectDevices()
        check("selectionDonePopsWithoutSaving", newEntry.navigationController!.topViewController === newEntry && newEmpty.draft == edited)
        check("navigationUsesAnimations", newEntry.navigationController!.animations.allSatisfy { $0 })
        check("oneMemberCategoryHasNoLiveIdentity", SceneDeviceSettingsTarget.category([a]).liveIdentity == nil)
        check("deviceEntryRetainsLiveIdentity", SceneDeviceSettingsTarget.device(a).liveIdentity == a)
        let offlineDisplay = try session()
        offlineDisplay.filter.submit("offline")
        check("offlineRowsVisibleButNotEligible", offlineDisplay.displayed(candidates).map(\.identity) == [c] && offlineDisplay.filtered(candidates).isEmpty)
        check("offlineDeviceSearchKeepsItsCategory", offlineDisplay.visibleCategoryIDs([1: "Room"], candidates: candidates, selecting: true) == [1])
        try offlineDisplay.selectFiltered(candidates, selected: true)
        check("displayingOfflineDoesNotAuthorizeAdding", offlineDisplay.draft.deviceMembers.isEmpty)

        let saved = SceneDraftSelection(draft: try SceneDraft(number: 2, scope: scope, name: "Saved", imageId: 1,
            kind: .devices, deviceMembers: [.init(identity: a, parameters: on)]))
        let header = SceneEditorHeaderHarness(selection: saved)
        header.updateEditorHeader()
        check("savedDraftHidesBannerButKeepsPreviewButton", !saved.hasUnsavedChanges && header.previewBanner.isHidden && header.previewButton.isEnabled)
        let savedPage = SceneSelectionEntryHarness(selection: saved)
        savedPage.closeAction()
        check("unchangedSettingsClosesWithoutDiscard", savedPage.leaves == 1 && savedPage.alerts == 0 && savedPage.previewInterruptions == 1)
        saved.filter.submit("hidden")
        let cancelledEdit = saved.beginParameterEdit()
        try saved.finishParameterEdit(cancelledEdit, parameters: off, identities: [a], apply: false)
        check("searchAndCancelledEditAreNotUnsavedChanges", !saved.hasUnsavedChanges)
        let enteredRevision = saved.draft.revision
        for value in [off, SceneParameters(isOn: true, lightness: 32000, cct: 4500), SceneParameters(isOn: true, lightness: 65535, cct: 3000)] {
            try saved.apply(value, identities: [a])
            header.previewPhase = .recommended; header.updateEditorHeader()
            check("parameterEditShowsRecommendation", saved.hasUnsavedChanges && !header.previewBanner.isHidden)
            try saved.apply(on, identities: [a])
            header.updateEditorHeader()
            check("revertingParametersHidesRecommendation", !saved.hasUnsavedChanges && header.previewBanner.isHidden)
        }
        check("revertedDraftIgnoresChangedRevision", saved.draft.revision != enteredRevision && !saved.hasUnsavedChanges)
        try saved.setSelected(candidates[1], selected: true)
        check("addedMemberNeedsSave", saved.hasUnsavedChanges)
        try saved.setSelected(candidates[1], selected: false)
        check("undoAdditionRestoresCleanDraft", !saved.hasUnsavedChanges)
        try saved.removeMembers([a], confirmed: true)
        header.updateEditorHeader()
        let removedPage = SceneSelectionEntryHarness(selection: saved)
        removedPage.closeAction()
        check("removingLastMemberNeedsDiscardWithoutPreview", saved.hasUnsavedChanges && header.previewBanner.isHidden && removedPage.alerts == 1 && removedPage.leaves == 0)
        try saved.setSelected(candidates[0], selected: true)
        check("readdingOriginalMemberRestoresCleanDraft", !saved.hasUnsavedChanges)
        savedPage.selectDevices()
        let child = savedPage.navigationController!.topViewController!
        try saved.apply(off, identities: [a]); child.closeAction()
        header.updateEditorHeader()
        check("childReturnRetainsParentBaselineAndChange", saved.hasUnsavedChanges && !header.previewBanner.isHidden && child.leaves == 0)
        for phase: SceneDevicePreviewState.Phase in [.preparing, .applying, .incomplete(successful: 0, failed: 1, offline: 0), .interrupted] {
            header.previewPhase = phase; header.updateEditorHeader()
            check("dirtyDraftRetainsPreviewProgressAndFailure", !header.previewBanner.isHidden)
        }
        header.previewPhase = .applied; header.updateEditorHeader()
        let appliedPage = SceneSelectionEntryHarness(selection: saved)
        appliedPage.closeAction()
        check("previewSuccessHidesBannerButStillRequiresDiscard", header.previewBanner.isHidden && appliedPage.alerts == 1)
        header.selecting = true; header.previewPhase = .recommended; header.updateEditorHeader()
        check("selectorNeverShowsPreviewBanner", header.previewBanner.isHidden)
        header.selecting = false; header.editingEnabled = false; header.updateEditorHeader()
        check("previewControlsRemainDisabledWhileBusy", !header.previewButton.isEnabled && !header.editButton.isEnabled)
        try saved.apply(on, identities: [a])
        for phase: SceneDevicePreviewState.Phase in [.recommended, .preparing, .applying, .interrupted] {
            header.previewPhase = phase; header.updateEditorHeader()
            check("manualPreviewDoesNotCreateDraftWarning", header.previewBanner.isHidden && !saved.hasUnsavedChanges)
        }
        let revertedPage = SceneSelectionEntryHarness(selection: saved)
        revertedPage.closeAction()
        check("revertedSettingsClosesDirectly", revertedPage.leaves == 1 && revertedPage.alerts == 0)
        var pendingConfig = config
        pendingConfig.pendingOperations = [.init(identity: c, action: .write), .init(identity: b, action: .remove)]
        pendingConfig = try pendingConfig.normalized()
        let pending = SceneDraftSelection(draft: try SceneDraft(number: 3, scope: scope, name: "Pending", imageId: 1,
            kind: .devices, deviceMembers: pendingConfig.deviceMembers, sourceConfiguration: pendingConfig))
        let pendingPage = SceneSelectionEntryHarness(selection: pending)
        pendingPage.closeAction()
        check("historicalWriteAndRemoveDoNotRequireDiscard", !pending.hasUnsavedChanges && pendingPage.leaves == 1 && pendingPage.alerts == 0 && pending.draft.sourceConfiguration == pendingConfig)
        let groups = SceneDraftSelection(draft: try SceneDraft(number: 4, scope: scope, name: "Groups", imageId: 1,
            kind: .groups, groupParameters: [0xC000: on]))
        let groupsPage = SceneSelectionEntryHarness(selection: groups)
        groupsPage.closeAction()
        check("legacyGroupsWithoutEditsCloseDirectly", groupsPage.leaves == 1 && groupsPage.alerts == 0)
        try groups.setGroupParameters([0xC000: off]); groupsPage.closeAction()
        check("groupEditRequiresDiscard", groups.hasUnsavedChanges && groupsPage.alerts == 1)
        try groups.setGroupParameters([0xC000: on])
        check("revertedGroupsBecomeClean", !groups.hasUnsavedChanges)
        let empty = SceneDraftSelection(draft: try SceneDraft(number: 5, scope: scope, name: "Empty", imageId: 1, kind: .groups))
        check("precreatedEmptySceneIsClean", !empty.hasUnsavedChanges)
        try empty.switchKind(to: .devices, confirmed: true)
        check("emptyKindChangeNeedsSave", empty.hasUnsavedChanges)
        try empty.switchKind(to: .groups, confirmed: true)
        check("revertingKindRestoresCleanDraft", !empty.hasUnsavedChanges)
        check("unsavedTemplateStillNeedsSave", newEmpty.hasUnsavedChanges)
        let committedPage = SceneSelectionEntryHarness(selection: newEmpty)
        committedPage.coordinator.committedNumber = 6; committedPage.closeAction()
        check("committedDraftDoesNotAskToDiscard", committedPage.leaves == 1 && committedPage.alerts == 0)
        let failedPage = SceneSelectionEntryHarness(selection: saved)
        failedPage.selection = nil; failedPage.closeAction()
        check("failedDraftLoadStillAllowsClose", failedPage.leaves == 1 && failedPage.alerts == 0)
        let busyPage = SceneSelectionEntryHarness(selection: newEmpty)
        busyPage.busy = true; let busyLifecycle = busyPage.lifecycle; busyPage.closeAction()
        check("dirtyBusyCloseCancelsBeforeConfirmation", busyPage.alerts == 1 && !busyPage.busy && busyPage.lifecycle != busyLifecycle && busyPage.coordinator.cancellations == 1)
        print("selection: \(passed) passed")
    }
}

final class SceneSelectionEntryHarness {
    enum Mode { case settings, deviceSelection }
    var mode = Mode.settings
    let space = 0
    var onDeviceLiveControl: (() -> Void)?
    var navigationController: Navigation?
    final class Navigation {
        var pages: [SceneSelectionEntryHarness] = []
        var animations: [Bool] = []
        var transitionCoordinator: Int?
        var topViewController: SceneSelectionEntryHarness? { pages.last }
        func pushViewController(_ page: SceneSelectionEntryHarness, animated: Bool) {
            page.navigationController = self; pages.append(page); animations.append(animated)
        }
        func popViewController(animated: Bool) { pages.removeLast(); animations.append(animated) }
    }
    final class Devices { var selecting = false }
    var busy = false
    var selection: SceneDraftSelection?
    let devicesView: Devices! = Devices()
    final class View { func endEditing(_ value: Bool) {} }
    final class Popup { func cancel() {}; func removeFromSuperview() {} }
    final class Coordinator { var committedNumber: Int?; var cancellations = 0; func cancel() { cancellations += 1 } }
    let view = View(), coordinator = Coordinator()
    var lifecycle = UUID(), picker: Popup?, alert: Popup?
    var tips = 0, alerts = 0, leaves = 0, previewInterruptions = 0
    func clearPreviewToast() {}
    func stopGroupPreview() {}
    func stopDeviceLiveControl() {}
    func invalidatePreviewAfterLiveControl() {}
    func interruptDevicePreview() { previewInterruptions += 1 }
    func setBusy(_ value: Bool) { busy = value }
    func leave() { leaves += 1 }
    enum AlertStyle { case `default`, destructive }
    var lastConfirmStyle: AlertStyle?
    func showAlert(title: String, message: String, cancel: String, confirm: String, confirmStyle: AlertStyle = .default, action: () -> Void) {
        alerts += 1; lastConfirmStyle = confirmStyle
    }
    init(selection: SceneDraftSelection) {
        self.selection = selection; navigationController = Navigation(); navigationController!.pages = [self]
    }
    init(space: Int, selection: SceneDraftSelection) {
        self.selection = selection; mode = .deviceSelection; devicesView.selecting = true
    }
    func tip(_ key: String) { tips += 1 }
    func reload() {}
    // PRODUCTION_SELECT_DEVICES
}

enum XWHUDManager { static func hide() {} }

typealias SceneSettingsViewController = SceneSelectionEntryHarness

// Execute the actual header update; UIKit layout/visual acceptance remains separate.
extension String { var localizedString: String { self } }
struct CGAffineTransform {
    init(rotationAngle: Double) {}
    static let identity = CGAffineTransform(rotationAngle: 0)
}
final class SceneEditorHeaderHarness {
    final class Constraints {
        var top: Constraints { self }; var bottom: Int { 0 }
        @discardableResult func equalTo(_ value: Int) -> Constraints { self }
        func offset(_ value: Int) {}
        func updateConstraints(_ action: (Constraints) -> Void) { action(self) }
    }
    class Control {
        var isHidden = false, isEnabled = true, alpha = 1.0
        var text: String?, transform = CGAffineTransform.identity
        let snp = Constraints()
    }
    final class Banner: Control { func update(_ phase: SceneDevicePreviewState.Phase) {} }
    let selection: SceneDraftSelection
    var editorStyle = true, selecting = false, editingEnabled = true
    var previewPhase = SceneDevicePreviewState.Phase.recommended
    let searchToolbar = Control(), selectedToolbar = Control(), selectedHeading = Control()
    let previewButton = Control(), editButton = Control(), collapseButton = Control(), searchCollapseButton = Control()
    let previewBanner = Banner(), editorHeader = Control(), tableViewport = Control()
    var categories: [Int] = [], collapsed = Set<Int>()
    init(selection: SceneDraftSelection) { self.selection = selection }
    // PRODUCTION_EDITOR_HEADER
}
