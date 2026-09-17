import UIKit
import NordicSigMeshSDK

final class SiteTriggerZoneViewController: UIViewController {
    private let coordinator: SiteTriggerZoneCoordinator
    private let account = UserData.currentUserId
    private let region = UserData.currentServerRegion
    private var content: SiteTriggerZoneContentView!
    private var addPanel: GroupPathSequenceDeviceAddView!
    private var presentation = SiteTriggerZonePresentationState()
    private var selectedID: UUID? { presentation.selectedID }
    private var addBarButton: UIBarButtonItem!
    private var siteTasksBarButton: UIBarButtonItem!
    private var candidateSpaces: [SiteTriggerZoneCandidates.Space] = []
    private var candidateSelection = SiteTriggerZoneCandidates.Selection()
    private var candidateLoadState = SiteTriggerZoneCandidates.LoadState()
    private var candidateListIncomplete = false
    private var candidateRequestID = UUID()
    private var candidatePageVisible = false
    private var allowPanelAnimations = false
    private var isChangingViewSize = false
    private lazy var meshConnection = SiteTriggerZoneMeshConnection(
        primaryMeshUUID: coordinator.site.meshUUID, primaryNetworkID: coordinator.site.meshNetworkId)
    private var quickConnectionActive = false
    private var quickState: QuickAddState = .stop
    private var memberDraft: SiteTriggerZoneDraft?
    private var staleMemberDraft: SiteTriggerZoneDraft?
    private var selectedCandidateID: String?
    private var triggerCandidates: [SiteTriggerZoneCandidates.Identity] = []
    private var messageObserverID: UUID?
    private var messageScopeID = UUID()
    private var observedContext: String?
    private var isForeground = true
    #if DEBUG
    private var previewBarButton: UIBarButtonItem!
    private var diagnosticMessageObserverID: UUID?
    private var diagnosticMessageScopeID = UUID()
    private var preview = SiteTriggerZonePreviewState()
    private var previewItems: [SiteTriggerZoneItemModel] { preview.items }
    private var liveScrollOffset = CGPoint.zero
    private var livePanelCollapsed = true
    private weak var previewDeviceMenu: TitleSelectView?
    private var previewCandidateSpaces: [SiteTriggerZoneCandidates.Space] = []
    private var previewCandidateSelection = SiteTriggerZoneCandidates.Selection()
    #endif
    private var syncTask: _Concurrency.Task<Void, Never>?
    private var failure: SiteTriggerZoneCoordinator.Failure?
    private var retryZoneID: UUID?

    init(site: SiteData) {
        coordinator = SiteTriggerZoneCoordinator(site: site)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        MeshLibManager.manager.removeGlobalMessageObserver(messageObserverID)
        #if DEBUG
        MeshLibManager.manager.removeGlobalMessageObserver(diagnosticMessageObserverID)
        #endif
    }

    override func loadView() {
        addPanel = GroupPathSequenceDeviceAddView()
        addPanel.isSequence = false
        addPanel.contentHeightPolicy = .dynamicSelected
        // Stage 1 owns the Mesh connection only; member operations remain disabled.
        addPanel.canAddDevice = false
        addPanel.delegate = self
        meshConnection.onChange = { [weak self] in
            guard let self, self.isViewLoaded else { return }
            #if DEBUG
            if self.candidatePageVisible, self.isForeground, !self.presentation.isPreview {
                let target = self.meshConnection.target
                print("[SiteZoneSync][mesh-session] site=\(self.coordinator.site.id) space=\(target?.spaceID ?? "none") phase=\(self.meshConnection.phase) connected=\(target.map(self.meshConnection.isConnected(to:)) ?? false) observer=read-only")
            }
            #endif
            if self.meshConnection.phase == .failed { self.quickState = .stop }
            self.updatePanel(items: self.content.items)
        }
        addPanel.quickAddView.guideView.steps = [
            .init(imageName: "proximity_lighting_step1", title: "zone_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "zone_add_step2".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "zone_quick_add_step3".localizedString, textColor: SubText_Color)
        ]
        content = SiteTriggerZoneContentView(panel: addPanel)
        addPanel.contentHeightChanged = { [weak self] height in
            guard let self else { return }
            self.content.setPanelHeight(height, animated: self.allowPanelAnimations && !self.isChangingViewSize)
        }
        content.add = { [weak self] in self?.addZone() }
        content.select = { [weak self] id in
            self?.selectZone(id)
        }
        content.operation = { [weak self] id, operation in self?.performOperation(operation, zoneID: id) }
        content.retry = { [weak self] in self?.retry() }
        content.syncTap = { [weak self] id in self?.showDeviceSyncPreview(zoneID: id) }
        content.deviceTap = { [weak self] zoneID, spaceID, deviceID, source in
            #if DEBUG
            if self?.presentation.isPreview == true {
                self?.showPreviewDeviceMenu(zoneID: zoneID, spaceID: spaceID, deviceID: deviceID, source: source)
            } else {
                self?.removeMember(zoneID: zoneID, spaceID: spaceID, deviceID: deviceID)
            }
            #else
            self?.removeMember(zoneID: zoneID, spaceID: spaceID, deviceID: deviceID)
            #endif
        }
        view = content
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enteredForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        title = "trigger_zone".localizedString
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.left"),
            style: .plain, target: self, action: #selector(attemptLeave))
        addBarButton = UIBarButtonItem(image: UIImage(named: "path_add")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(addZone))
        addBarButton.accessibilityIdentifier = "site-zones-add"
        siteTasksBarButton = UIBarButtonItem(image: UIImage(systemName: "list.bullet.rectangle"),
                                            style: .plain, target: self,
                                            action: #selector(showSiteDeviceSyncPreview))
        siteTasksBarButton.accessibilityIdentifier = "site-zones-site-tasks"
        siteTasksBarButton.accessibilityLabel = "site_zones_site_tasks_title".localizedString
        #if DEBUG
        previewBarButton = UIBarButtonItem(title: "test".localizedString, style: .plain, target: self, action: #selector(togglePreview))
        previewBarButton.accessibilityIdentifier = "site-zones-preview-toggle"
        previewBarButton.accessibilityLabel = "site_zones_preview_toggle".localizedString
        #endif
        updateNavigationActions(hasSiteTasks: false)
        reload()
    }

    private func updateNavigationActions(hasSiteTasks: Bool) {
        var actions = [addBarButton!]
        if hasSiteTasks { actions.append(siteTasksBarButton) }
        #if DEBUG
        actions.append(previewBarButton)
        #endif
        navigationItem.rightBarButtonItems = actions
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isForeground = UIApplication.shared.applicationState != .background
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        meshConnection.refresh()
        allowPanelAnimations = false
        candidatePageVisible = true
        #if DEBUG
        startDiagnosticMessageObservation()
        #endif
        reload()
        loadCandidateSpaces()
        synchronize()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        allowPanelAnimations = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        allowPanelAnimations = false
        candidatePageVisible = false
        candidateRequestID = UUID()
        #if DEBUG
        stopDiagnosticMessageObservation()
        #endif
        stopMessageObservation()
        dismissCandidateMenus()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true
            || navigationController?.viewControllers.contains(self) == false {
            quickConnectionActive = false
            meshConnection.leave()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        isChangingViewSize = true
        dismissCandidateMenus()
        #if DEBUG
        previewDeviceMenu?.dismiss()
        #endif
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.isChangingViewSize = false
        }
    }

    private func reload() {
        content.allowsSelectedEmptyPanel = true
        #if DEBUG
        if presentation.isPreview {
            updateNavigationActions(hasSiteTasks: false)
            content.render(items: previewItems, selectedID: selectedID, canCreate: false, canSave: true, isPreview: true)
            content.setStatus("site_zones_preview_mode".localizedString, allowsRetry: false)
            addBarButton?.isEnabled = false
            updatePanel(items: previewItems)
            return
        }
        #endif
        do {
            let state = try coordinator.state()
            let zones = state.data.zones ?? []
            let knownSchema = state.data.fields["schemaVersion"] == .integer(1)
                || state.data.fields["schemaVersion"] == .integer(2)
            let supported = state.rejectedRemote == nil && !state.hasAmbiguousRemote
                && knownSchema && state.data.zones != nil
            let ids = zones.map(\.zoneId)
            let sourceOnly = retainedChangesAreProvenSourceOnly(state)
            let hasSiteTasks = !sourceOnly && (state.serverData?.zones.map {
                SiteTriggerZoneSyncPlanningPolicy.hasDeletedZoneCleanup(
                    confirmedZones: $0, changes: state.deviceSyncChanges ?? [])
            } ?? false)
            updateNavigationActions(hasSiteTasks: hasSiteTasks)
            presentation.reconcileLiveIDs(ids)
            let selectedZone = zones.first(where: { $0.zoneId == selectedID })
            let selectedMembers = selectedZone.flatMap {
                SiteTriggerZoneTopologyReader.resolvedMembers(of: $0, site: coordinator.site)
            }
            if let draft = memberDraft,
               (selectedZone?.zoneId != draft.zoneID || selectedMembers != draft.base) {
                if draft.isDirty { staleMemberDraft = draft }
                memberDraft = nil
            }
            if let selectedID, let selectedMembers,
               memberDraft?.zoneID != selectedID || memberDraft?.isDirty == false {
                memberDraft = SiteTriggerZoneDraft(zoneID: selectedID, members: selectedMembers)
            }
            let canEdit = supported && !state.conflict && coordinator.site.canManageSiteTriggerZones
                && failure != .permission
            let canCreate = canEdit && state.data.supportsMemberEditing
            let items = zones.enumerated().map { index, zone in
                let cloudPending = state.pending.map { pending in
                    pending.base?.zones?.first(where: { $0.zoneId == zone.zoneId })
                        != pending.target.zones?.first(where: { $0.zoneId == zone.zoneId })
                } ?? false
                let deviceState = SiteTriggerZoneItemModel.TaskState.devices(
                    hasMembers: !zone.isEmpty,
                    hasPendingChange: state.deviceSyncChanges?.contains(where: {
                        $0.zoneID == zone.zoneId && $0.hasKnownDeviceDelta
                    }) == true && !sourceOnly
                )
                let resolvedMembers = zone.zoneId == selectedID ? selectedMembers : nil
                return itemModel(zone: zone, index: index,
                                 canEdit: canEdit && (state.data.supportsZoneEditing(zone.zoneId)
                                     || resolvedMembers != nil)
                                     && (!zone.isEmpty || state.data.supportsMemberEditing),
                                 resolvedMembers: resolvedMembers,
                                 cloudPending: cloudPending, deviceState: deviceState)
            }
            content.render(items: items, selectedID: selectedID, canCreate: canCreate, canSave: syncTask == nil)
            addBarButton?.isEnabled = canCreate
            updatePanel(items: items)
            let status = state.hasAmbiguousRemote ? SiteTriggerZoneCoordinator.Failure.ambiguousRemote.message
                : !supported ? SiteTriggerZoneCoordinator.Failure.unsupported.message
                : state.conflict ? SiteTriggerZoneCoordinator.Failure.conflict.message
                : (state.pending != nil ? "site_zones_sync_pending".localizedString
                   : staleMemberDraft != nil ? "site_zone_draft_stale".localizedString
                   : state.needsArchivedReview ? "site_zones_server_replaced".localizedString
                   : failure == .network || failure == .unconfirmed ? nil : failure?.message)
            content.setStatus(status)
            content.emptyStateView.isHidden = !ids.isEmpty || !supported
        } catch {
            updateNavigationActions(hasSiteTasks: false)
            content.render(items: [], selectedID: nil, canCreate: false, canSave: false)
            content.emptyStateView.isHidden = true
            addBarButton?.isEnabled = false
            content.setStatus(SiteTriggerZoneCoordinator.Failure.storage.message)
        }
    }

    private func retainedChangesAreProvenSourceOnly(_ state: SiteTriggerZoneState) -> Bool {
        guard state.pending == nil, !state.conflict, !state.hasAmbiguousRemote,
              state.rejectedRemote == nil, state.serverData == state.data,
              let zones = state.serverData?.zones else { return false }
        return SiteTriggerZoneSyncPlanningPolicy.allRetainedChangesAreSourceOnly(
            confirmedZones: zones, changes: state.deviceSyncChanges ?? [])
    }

    private func itemModel(zone: SiteTriggerZone, index: Int, canEdit: Bool,
                           resolvedMembers: [SiteTriggerZoneMember]?,
                           cloudPending: Bool, deviceState: SiteTriggerZoneItemModel.TaskState) -> SiteTriggerZoneItemModel {
        let members = memberDraft?.zoneID == zone.zoneId
            ? (memberDraft?.members ?? []).map(SiteTriggerZoneDisplayMember.init)
            : zone.displayMembers
        let name = "\("zone".localizedString) \(index + 1)"
        if members.isEmpty {
            guard zone.isEmpty else {
                return SiteTriggerZoneItemModel(id: zone.zoneId, name: name,
                    hasCompleteSpaceList: false, allowsEditing: false,
                    hasSavedMembers: true,
                    sync: .init(cloud: cloudPending ? .pending : .settled, devices: deviceState))
            }
            var item = SiteTriggerZoneItemModel.empty(id: zone.zoneId, name: name, canEdit: canEdit)
            item.hasUnsavedChanges = memberDraft?.zoneID == zone.zoneId && memberDraft?.isDirty == true
            item.hasSavedMembers = !zone.isEmpty
            item.sync.cloud = cloudPending ? .pending : .settled
            item.sync.devices = deviceState
            return item
        }
        var item = SiteTriggerZoneItemModel(id: zone.zoneId, name: name)
        item.hasCompleteSpaceList = zone.hasCompleteDisplayMembers
        item.hasUnverifiedMembers = zone.members == nil && resolvedMembers == nil
        item.needsCloudMigration = zone.members == nil && resolvedMembers != nil
        item.allowsEditing = canEdit
        item.hasUnsavedChanges = memberDraft?.zoneID == zone.zoneId && memberDraft?.isDirty == true
        item.hasSavedMembers = !zone.isEmpty
        item.sync.cloud = cloudPending ? .pending : .settled
        item.sync.devices = deviceState
        let spaceIDs = Array(NSOrderedSet(array: members.map(\.identity.spaceID))) as? [String] ?? []
        item.spaces = spaceIDs.map { id in
            let space = coordinator.site.spaces.first { $0.id == id }
            let access: SiteTriggerZoneItemModel.Access
            switch space?.permission {
            case .owner: access = .owner
            case .editor: access = .editor
            case .visitor: access = .visitor
            case nil: access = .unknown
            }
            let devices = members.filter { $0.identity.spaceID == id }.map { member -> SiteTriggerZoneItemModel.Device in
                let candidate = candidateSpaces.first { $0.id == id }?.devices.first {
                    $0.identity.deviceID == member.identity.nodeUUID.uuidString
                }
                let address: String
                if let value = member.primaryAddress {
                    address = String(format: "%04X", value)
                } else { address = member.identity.nodeUUID.uuidString }
                return .init(id: member.identity.nodeUUID.uuidString, name: candidate?.name ?? address)
            }
            return .init(id: id, name: space?.name, access: access,
                         authorizationConfirmed: space?.canEditing == true || access == .visitor,
                         devices: devices, disclosedDeviceCount: devices.count,
                         sync: .init(cloud: cloudPending ? .pending : .settled, devices: deviceState))
        }
        return item
    }

    private func selectZone(_ id: UUID) {
        guard selectedID != id else { return }
        let finish = { [weak self] in
            guard let self else { return }
            self.stopMessageObservation()
            self.quickConnectionActive = false
            self.quickState = .stop
            self.selectedCandidateID = nil
            self.triggerCandidates = []
            self.presentation.select(id)
            self.memberDraft = (try? self.coordinator.state().data.zones)?
                .first(where: { $0.zoneId == id }).flatMap(SiteTriggerZoneDraft.init(zone:))
            self.reload()
            if let item = self.content.items.first(where: { $0.id == id }), item.canEdit || item.usesEmptyStyle {
                self.addPanel.setCollapsed(false, animated: true)
            }
        }
        if memberDraft?.isDirty == true { confirmUnsaved(afterSave: finish, afterDiscard: finish) }
        else { finish() }
    }

    @objc private func attemptLeave() {
        let leave: () -> Void = { [weak self] in
            _ = self?.navigationController?.popViewController(animated: true)
        }
        if memberDraft?.isDirty == true { confirmUnsaved(afterSave: leave, afterDiscard: leave) }
        else { leave() }
    }

    private func confirmUnsaved(afterSave: @escaping () -> Void, afterDiscard: @escaping () -> Void) {
        guard let zoneID = selectedID else { return }
        let alert = UIAlertController(title: "notification".localizedString,
                                      message: "site_zone_unsaved_changes".localizedString,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Save".localizedString, style: .default) { [weak self] _ in
            self?.saveZone(zoneID, completion: { success in if success { afterSave() } })
        })
        alert.addAction(UIAlertAction(title: "site_zone_discard".localizedString, style: .destructive) { [weak self] _ in
            self?.memberDraft?.reset()
            afterDiscard()
        })
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        present(alert, animated: true)
    }

    private func changeQuickState(_ state: QuickAddState) {
        guard let selectedID, content.items.first(where: { $0.id == selectedID })?.canEdit == true,
              candidateSelection.spaceID != nil else { return }
        switch state {
        case .adding:
            quickState = .adding
            quickConnectionActive = true
            meshConnection.start()
        case .pause:
            guard quickState == .adding else { return }
            quickState = .pause
        case .stop:
            quickState = .stop
            quickConnectionActive = false
        }
        updatePanel(items: content.items)
    }

    private func removeMember(zoneID: UUID, spaceID: String, deviceID: String) {
        guard selectedID == zoneID, memberDraft?.zoneID == zoneID,
              content.items.first(where: { $0.id == zoneID })?.canEdit == true,
              let uuid = UUID(uuidString: deviceID),
              memberDraft?.members.contains(where: { $0.identity.spaceID == spaceID && $0.identity.nodeUUID == uuid }) == true else { return }
        let alert = UIAlertController(title: "notification".localizedString,
                                      message: "site_zone_remove_member".localizedString,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "remove".localizedString, style: .destructive) { [weak self] _ in
            guard let self, self.selectedID == zoneID else { return }
            if self.memberDraft?.remove(.init(spaceID: spaceID, nodeUUID: uuid)) == true { self.reload() }
        })
        alert.addAction(UIAlertAction(title: "cancel".localizedString, style: .cancel))
        present(alert, animated: true)
    }

    private func updatePanel(items: [SiteTriggerZoneItemModel]) {
        let index = items.firstIndex { $0.id == selectedID && ($0.canEdit || $0.usesEmptyStyle) }
        addPanel.updateHeaderIndex(index.map { $0 + 1 })
        guard let index else { addPanel.clearBrowseTarget(); return }
        let spaces: [SiteTriggerZoneCandidates.Space]
        let selection: SiteTriggerZoneCandidates.Selection
        var memberships: [SiteTriggerZoneCandidates.Membership] = []
        #if DEBUG
        if presentation.isPreview {
            spaces = previewCandidateSpaces
            previewCandidateSelection.reconcile(spaces)
            selection = previewCandidateSelection
            memberships = previewItems.map { item in
                .init(zoneID: item.id, devices: Set(item.spaces.flatMap { space in
                    space.devices.map { .init(siteID: SiteTriggerZoneCandidatePreview.siteID, spaceID: space.id, deviceID: $0.id) }
                }))
            }
        } else {
            spaces = candidateSpaces
            selection = candidateSelection
            memberships = liveMemberships()
        }
        #else
        spaces = candidateSpaces
        selection = candidateSelection
        memberships = liveMemberships()
        #endif
        let selected = spaces.first { $0.id == selection.spaceID && $0.isSelectable }
        let devices = SiteTriggerZoneCandidates.filteredDevices(in: selected, zoneID: items[index].id,
                                                                memberships: memberships, includeAdded: selection.includeAdded)
        let listIncomplete = !presentation.isPreview && candidateListIncomplete
        let retryAvailable = !presentation.isPreview && (listIncomplete || spaces.contains { $0.availability == .unavailable }) && selected == nil
        let placeholder = listIncomplete ? "site_zone_data_unavailable" : SiteTriggerZoneCandidates.placeholderKey(for: spaces)
        let empty = retryAvailable ? "site_zone_data_retry".localizedString : SiteTriggerZoneCandidates.emptyMessageKey(spaces: spaces, selected: selected,
                                                             visibleDevices: devices, includeAdded: selection.includeAdded)?.localizedString
        let unavailable = retryAvailable ? "site_zone_data_retry".localizedString : SiteTriggerZoneCandidates.emptyMessageKey(spaces: spaces, selected: nil,
                                                                   visibleDevices: [], includeAdded: selection.includeAdded)?.localizedString
        let requestID = candidateRequestID
        let zoneID = selectedID
        let isPreview = presentation.isPreview
        let validCallback: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.candidatePageVisible && self.candidateRequestID == requestID
                && self.selectedID == zoneID && self.presentation.isPreview == isPreview
                && UserData.currentUserId == self.account && UserData.currentServerRegion == self.region
        }
        var browseConfiguration = GroupPathSequenceBrowseConfiguration(spaces: spaces.map { space in
            let suffix: String?
            switch space.availability {
            case .restricted: suffix = (space.accessLabelKey ?? "site_zones_access_unknown").localizedString
            case .unavailable: suffix = "site_zone_data_unavailable".localizedString
            case .loading: suffix = "site_zone_loading_spaces".localizedString
            case .ready, .noGroups: suffix = nil
            }
            return .init(id: space.id, title: space.name + (suffix.map { " · " + $0 } ?? ""), enabled: space.isSelectable)
        }, selectedSpaceID: selected?.id, placeholder: placeholder.localizedString,
           includeAdded: selection.includeAdded,
           devices: devices.map { .init(id: "\($0.identity.spaceID)-\($0.identity.deviceID)", name: $0.name) },
           emptyMessage: empty, unavailableMessage: unavailable,
           selectSpace: { [weak self] id in
            guard validCallback(), let self else { return }
            #if DEBUG
            if isPreview {
                self.previewCandidateSelection.select(id, in: self.previewCandidateSpaces)
                self.updatePanel(items: self.content.items)
                return
            }
            #endif
            let previous = self.candidateSelection.spaceID
            self.candidateSelection.select(id, in: self.candidateSpaces)
            if previous != self.candidateSelection.spaceID {
                self.quickConnectionActive = false
                self.quickState = .stop
                self.selectedCandidateID = nil
                self.triggerCandidates = []
                self.stopMessageObservation()
                self.selectConnectionSpace(autoConnect: self.addPanel.selectedMode != .quickAdd)
            }
            self.loadCandidateSpaces(devicesFor: self.candidateSelection.spaceID)
        }, changeFilter: { [weak self] includeAdded in
            guard validCallback(), let self else { return }
            #if DEBUG
            if isPreview { self.previewCandidateSelection.includeAdded = includeAdded }
            else { self.candidateSelection.includeAdded = includeAdded }
            #else
            self.candidateSelection.includeAdded = includeAdded
            #endif
            self.updatePanel(items: self.content.items)
        }, retry: retryAvailable ? { [weak self] in
            guard validCallback() else { return }
            self?.loadCandidateSpaces()
        } : nil)
        if !isPreview, let selected {
            browseConfiguration.connectionPhase = meshConnection.target?.spaceID == selected.id ? meshConnection.phase : .idle
            browseConfiguration.quickConnectionActive = quickConnectionActive
            browseConfiguration.quickState = quickState
            browseConfiguration.connectedNoticeKey = ""
            browseConfiguration.showHelp = { [weak self] in
                guard validCallback(), let self else { return }
                let key: String
                switch self.addPanel.selectedMode {
                case .quickAdd: key = "site_zone_quick_help"
                case .triggerAdd: key = "site_zone_trigger_help"
                case .manuallyAdd: key = "site_zone_manual_help"
                }
                let alert = UIAlertController(title: self.addPanel.selectedMode.title,
                                              message: key.localizedString, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "ok".localizedString, style: .default))
                self.present(alert, animated: true)
            }
            browseConfiguration.triggerDevices = devices.filter { triggerCandidates.contains($0.identity) }
                .map { .init(id: "\($0.identity.spaceID)-\($0.identity.deviceID)", name: $0.name) }
            browseConfiguration.selectedDeviceID = selectedCandidateID
            browseConfiguration.selectDevice = { [weak self] id in
                guard validCallback() else { return }
                self?.handleCandidateTap(id)
            }
            browseConfiguration.changeQuickState = { [weak self] state in
                guard validCallback() else { return }
                self?.changeQuickState(state)
            }
            browseConfiguration.startConnection = { [weak self] in
                guard validCallback(), let self else { return }
                self.quickConnectionActive = true
                self.meshConnection.start()
                self.updatePanel(items: self.content.items)
            }
            browseConfiguration.retryConnection = { [weak self] in
                guard validCallback(), let self else { return }
                self.meshConnection.retry()
            }
        }
        addPanel.configureBrowse(browseConfiguration)
        addPanel.refreshPreferredHeight()
        reconcileMessageObservation()
    }

    private func liveMemberships() -> [SiteTriggerZoneCandidates.Membership] {
        guard let zones = try? coordinator.state().data.zones else { return [] }
        return zones.map { zone in
            let members = memberDraft?.zoneID == zone.zoneId
                ? (memberDraft?.members ?? []).map(SiteTriggerZoneDisplayMember.init)
                : zone.displayMembers
            return .init(zoneID: zone.zoneId, devices: Set(members.map {
                .init(siteID: coordinator.site.id, spaceID: $0.identity.spaceID,
                      deviceID: $0.identity.nodeUUID.uuidString)
            }))
        }
    }

    @objc private func showSiteDeviceSyncPreview() {
        guard presentation.permitsLiveOperations, let state = try? coordinator.state(),
              let confirmedZones = state.serverData?.zones else { return }
        let liveIDs = Set(confirmedZones.map(\.zoneId))
        let deleted = (state.deviceSyncChanges ?? []).filter {
            !liveIDs.contains($0.zoneID) && $0.hasKnownDeviceDelta
        }
        guard let selected = deleted.first else { reload(); return }
        let cloudConfirmed = state.pending == nil && !state.conflict
            && !state.hasAmbiguousRemote && state.rejectedRemote == nil
            && state.serverData == state.data
        var parts = [
            "site_zones_device_sync_not_available".localizedString,
            String(format: "site_zones_site_tasks_retained".localizedString, deleted.count)
        ]
        if cloudConfirmed {
            let result = SiteTriggerZoneTopologyReader.makeDifferencePlan(
                site: coordinator.site, state: state, selectedZoneID: selected.zoneID)
            #if DEBUG
            logDeviceSyncPreview(zoneID: selected.zoneID, state: state,
                                 cloudConfirmed: true, origin: "site-level",
                                 planResult: result)
            #endif
            switch result {
            case .success(let plan):
                let attribution = SiteTriggerZoneSyncPlanningPolicy.attributeTasks(
                    plan, liveZoneIDs: liveIDs)
                parts.append(String(format: "site_zones_site_tasks_tentative".localizedString,
                                    attribution.siteLevel.count))
                parts.append("site_zones_device_preview_shared_impact".localizedString)
                if !plan.issues.isEmpty {
                    parts.append("site_zones_device_preview_blocked".localizedString)
                    parts.append(deviceBlockerDetails(plan.blockers))
                }
            case .failure(let error):
                parts.append("site_zones_device_preview_plan_unavailable".localizedString)
                parts.append(deviceBlockerDetails([error.blocker]))
            }
        } else {
            parts.append("site_zones_device_preview_cloud_unconfirmed".localizedString)
        }
        let alert = UIAlertController(title: "site_zones_site_tasks_title".localizedString,
                                      message: parts.joined(separator: "\n\n"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ok".localizedString, style: .default))
        present(alert, animated: true)
    }

    private func showDeviceSyncPreview(zoneID: UUID) {
        guard presentation.permitsLiveOperations else {
            SiteTriggerZoneItemStyle.syncAlert().show()
            return
        }
        let state = try? coordinator.state()
        let zones = state?.data.zones ?? []
        let index = zones.firstIndex { $0.zoneId == zoneID }
        let title = index.map { String(format: "site_zones_device_preview_zone_title".localizedString, $0 + 1) }
            ?? "site_zones_device_preview_title".localizedString
        let change = state?.deviceSyncChanges?.first { $0.zoneID == zoneID }
        let cloudConfirmed = state.map {
            $0.pending == nil && !$0.conflict && !$0.hasAmbiguousRemote
                && $0.rejectedRemote == nil && $0.serverData == $0.data
        } == true
        let planResult = cloudConfirmed ? state.map {
            SiteTriggerZoneTopologyReader.makeDifferencePlan(
                site: coordinator.site, state: $0, selectedZoneID: zoneID)
        } : nil
        #if DEBUG
        logDeviceSyncPreview(zoneID: zoneID, state: state,
                             cloudConfirmed: cloudConfirmed, origin: "preview",
                             planResult: planResult)
        #endif
        let detail: String
        if state == nil || index == nil {
            detail = "site_zones_device_preview_unavailable".localizedString
        } else if !cloudConfirmed {
            detail = "site_zones_device_preview_cloud_unconfirmed".localizedString
        } else if let impact = change?.knownMemberImpact, impact.hasDelta {
            detail = String(format: "site_zones_device_preview_member_changes".localizedString,
                            impact.added, impact.removed, impact.changed)
        } else if change != nil, change?.knownMemberImpact == nil {
            detail = "site_zones_device_preview_unavailable".localizedString
        } else {
            detail = "site_zones_device_preview_unverified".localizedString
        }
        var parts = ["site_zones_device_sync_not_available".localizedString, detail]
        if let state, retainedChangesAreProvenSourceOnly(state) {
            parts.append("site_zones_device_preview_source_only".localizedString)
        }
        if let planResult {
            switch planResult {
            case .success(let plan):
                let liveIDs = Set(state?.serverData?.zones?.map(\.zoneId) ?? [])
                let attribution = SiteTriggerZoneSyncPlanningPolicy.attributeTasks(
                    plan, liveZoneIDs: liveIDs)
                parts.append(String(
                    format: "site_zones_device_preview_attribution".localizedString,
                    attribution.directByZone[zoneID]?.count ?? 0,
                    attribution.sharedByZone[zoneID]?.count ?? 0,
                    attribution.siteLevel.count))
                parts.append("site_zones_device_preview_shared_impact".localizedString)
                if !plan.issues.isEmpty {
                    parts.append("site_zones_device_preview_blocked".localizedString)
                    parts.append(deviceBlockerDetails(plan.blockers))
                }
            case .failure(let error):
                parts.append("site_zones_device_preview_plan_unavailable".localizedString)
                parts.append(deviceBlockerDetails([error.blocker]))
            }
        }
        let message = parts.joined(separator: "\n\n")
        let alert = UIAlertController(title: title,
                                      message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ok".localizedString, style: .default))
        present(alert, animated: true)
    }

    private func deviceBlockerDetails(
        _ blockers: [SiteTriggerZoneSyncPlanningPolicy.Blocker]
    ) -> String {
        blockers.map { ("site_zones_device_blocker_" + $0.rawValue).localizedString }
            .joined(separator: "\n")
    }

    #if DEBUG
    private func startDiagnosticMessageObservation() {
        guard diagnosticMessageObserverID == nil, candidatePageVisible, isForeground,
              !presentation.isPreview else { return }
        let siteID = coordinator.site.id
        let siteMeshUUID = coordinator.site.meshUUID
        let scopeID = diagnosticMessageScopeID
        diagnosticMessageObserverID = MeshLibManager.manager.addGlobalMessageObserver {
            [weak self] manager, message, source, destination in
            let event: String
            let triggerAddress: UInt16
            let relay: UInt8?
            let vendorResult: String?
            if let status = message as? SensorStatus,
               let value = status.values.first(where: { $0.property.id == DeviceProperty.presenceDetected.id }),
               case .bool(let presence) = value.value {
                event = presence ? "presence-on" : "presence-off"
                triggerAddress = source
                relay = nil
                vendorResult = nil
            } else if let vendor = message as? SunricherVendorSet,
                      case .proximityLightingTrigger(let count, let embeddedSource) = vendor.function {
                event = "proximity-trigger"
                triggerAddress = embeddedSource
                relay = count
                vendorResult = nil
            } else if let vendor = message as? SunricherVendorStatus {
                switch vendor.status.code {
                case .proximityLightingEnabled, .proximityLightingRelaySet,
                     .proximityLightingNeighborSet:
                    event = "proximity-ret"
                    triggerAddress = source
                    relay = nil
                    vendorResult = "code=\(vendor.status.code) success=\(vendor.status.isSuccessful) error=\(vendor.status.errorCode.map(String.init) ?? "none")"
                default:
                    return
                }
            } else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.candidatePageVisible, self.isForeground,
                      !self.presentation.isPreview,
                      self.diagnosticMessageScopeID == scopeID,
                      UserData.currentUserId == self.account,
                      UserData.currentServerRegion == self.region,
                      manager.meshNetwork?.uuid.uuidString.caseInsensitiveCompare(siteMeshUUID) == .orderedSame
                else { return }
                let target = self.meshConnection.target
                print("[SiteZoneSync][passive-trigger] site=\(siteID) event=\(event) meshSource=\(source) triggerAddress=\(triggerAddress) destination=\(destination) relay=\(relay.map(String.init) ?? "n/a") vendorResult=\(vendorResult ?? "n/a") activeSpace=\(target?.spaceID ?? "none") meshConnected=\(target.map(self.meshConnection.isConnected(to:)) ?? false) observer=read-only deviceEvidence=unverified")
            }
        }
        let target = meshConnection.target
        print("[SiteZoneSync][passive-trigger] phase=active site=\(siteID) mesh=\(siteMeshUUID) scope=visible-page activeSpace=\(target?.spaceID ?? "none") meshConnected=\(target.map(meshConnection.isConnected(to:)) ?? false) observer=read-only")
    }

    private func stopDiagnosticMessageObservation() {
        guard diagnosticMessageObserverID != nil else { return }
        diagnosticMessageScopeID = UUID()
        MeshLibManager.manager.removeGlobalMessageObserver(diagnosticMessageObserverID)
        diagnosticMessageObserverID = nil
        print("[SiteZoneSync][passive-trigger] phase=stopped site=\(coordinator.site.id)")
    }

    private func logDeviceSyncPreview(zoneID: UUID, state: SiteTriggerZoneState?,
                                      cloudConfirmed: Bool, origin: String,
                                      planResult: Result<SiteTriggerZoneSyncPlanningPolicy.Plan,
                                                         SiteTriggerZoneTopologyReader.ReadError>? = nil) {
        let impact = state?.deviceSyncChanges?.first { $0.zoneID == zoneID }?.knownMemberImpact
        let cloudFingerprint = state?.serverData.flatMap {
            SiteTriggerZoneSyncPlanningPolicy.cloudFingerprint(
                siteID: coordinator.site.id, data: $0)
        } ?? "unavailable"
        print("[SiteZoneSync][preview] origin=\(origin) site=\(coordinator.site.id) zone=\(zoneID) cloudConfirmed=\(cloudConfirmed) cloudVersion=\(state?.serverTimestamp ?? -1) cloudFingerprint=\(cloudFingerprint) retainedChanges=\(state?.deviceSyncChanges?.count ?? 0) memberAdded=\(impact?.added ?? -1) memberRemoved=\(impact?.removed ?? -1) memberChanged=\(impact?.changed ?? -1) deviceEvidence=unverified sender=disabled")
        guard cloudConfirmed, let state else { return }
        switch planResult ?? SiteTriggerZoneTopologyReader.makeDifferencePlan(
            site: coordinator.site, state: state, selectedZoneID: zoneID
        ) {
        case .failure(let error):
            print("[SiteZoneSync][plan] scope=site site=\(coordinator.site.id) selectedZone=\(zoneID) result=blocked reason=\(error)")
        case .success(let plan):
            let issues = plan.issues.map { String(describing: $0) }.sorted().joined(separator: ",")
            print("[SiteZoneSync][plan] scope=site site=\(coordinator.site.id) selectedZone=\(zoneID) targetFingerprint=\(plan.targetFingerprint ?? "unavailable") tentativeTasks=\(plan.taskCount) topologyIssues=[\(issues)] deviceEvidence=unverified sender=disabled")
            let liveIDs = Set(state.serverData?.zones?.map(\.zoneId) ?? [])
            let attribution = SiteTriggerZoneSyncPlanningPolicy.attributeTasks(
                plan, liveZoneIDs: liveIDs)
            print("[SiteZoneSync][plan-attribution] zone=\(zoneID) directRelationships=\(attribution.directByZone[zoneID]?.count ?? 0) sharedDeviceOrSpace=\(attribution.sharedByZone[zoneID]?.count ?? 0) siteLevel=\(attribution.siteLevel.count) tentative=true")
            for space in plan.spaces {
                let transport = space.transportKeyCandidate
                print("[SiteZoneSync][plan-space] space=\(space.spaceID) remove=\(space.remove.count) configuration=\(space.configuration.count) transportNetKeyIndex=\(transport.map { String($0.networkIndex) } ?? "unknown") transportAppKeyIndex=\(transport.map { String($0.applicationIndex) } ?? "unknown") transportIdentityResolved=\(transport?.materialIdentity?.isEmpty == false) transportEvidence=candidate-only")
                for task in space.remove + space.configuration {
                    let target = task.target
                    let key = target?.forwardKeyReference
                    let sources = task.sources.map { String(describing: $0) }.sorted().joined(separator: ",")
                    let relationships = task.relationshipSources.map { String(describing: $0) }
                        .sorted().joined(separator: ",")
                    print("[SiteZoneSync][plan-task] space=\(space.spaceID) node=\(task.deviceID.nodeUUID) kind=\(task.kind) removed=\(task.removedNeighbors) targetNeighborCount=\(target?.neighborAddresses.count ?? 0) forward=\(String(describing: target?.forwardKey)) netKeyIndex=\(key.map { String($0.networkIndex) } ?? "unknown") appKeyIndex=\(key.map { String($0.applicationIndex) } ?? "unknown") ttl=\(target?.ttl.map(String.init) ?? "unknown") relationshipSources=[\(relationships)] sources=[\(sources)]")
                }
            }
        }
    }
    #endif

    private func stopMessageObservation() {
        #if DEBUG
        if let observedContext {
            print("[SiteZoneSync][trigger-observer] phase=stopped context=\(observedContext)")
        }
        #endif
        MeshLibManager.manager.removeGlobalMessageObserver(messageObserverID)
        messageObserverID = nil
        observedContext = nil
        messageScopeID = UUID()
    }

    private func reconcileMessageObservation() {
        guard candidatePageVisible, isForeground, !presentation.isPreview,
              UserData.currentUserId == account, UserData.currentServerRegion == region,
              let zoneID = selectedID,
              content.items.first(where: { $0.id == zoneID })?.canEdit == true,
              let target = meshConnection.target,
              target.spaceID == candidateSelection.spaceID,
              meshConnection.isConnected(to: target),
              (addPanel.selectedMode == .triggerAdd ||
               (addPanel.selectedMode == .quickAdd && quickState == .adding)) else {
            if messageObserverID != nil { stopMessageObservation() }
            return
        }
        let scope = "\(zoneID.uuidString)/\(target.spaceID)/\(candidateRequestID.uuidString)/\(addPanel.selectedMode.title)"
        guard observedContext != scope else { return }
        stopMessageObservation()
        observedContext = scope
        let token = messageScopeID
        #if DEBUG
        print("[SiteZoneSync][trigger-observer] phase=active context=\(scope) mode=\(addPanel.selectedMode.title) appForeground=\(isForeground) meshConnected=true")
        #endif
        messageObserverID = MeshLibManager.manager.addGlobalMessageObserver { [weak self] _, message, source, _ in
            var address = source
            let detected: Bool
            if let status = message as? SensorStatus,
               let value = status.values.first(where: { $0.property.id == DeviceProperty.presenceDetected.id }),
               case .bool(let presence) = value.value {
                detected = presence
            } else if let vendor = message as? SunricherVendorSet,
                      case .proximityLightingTrigger(_, let embeddedSource) = vendor.function {
                address = embeddedSource
                detected = true
            } else { detected = false }
            guard detected else { return }
            #if DEBUG
            print("[SiteZoneSync][trigger-observer] phase=received context=\(scope) meshSource=\(source) triggerAddress=\(address) message=\(type(of: message))")
            #endif
            DispatchQueue.main.async { [weak self] in
                self?.handleTrigger(address: address, token: token, target: target, zoneID: zoneID)
            }
        }
    }

    private func handleTrigger(address: UInt16, token: UUID,
                               target: SiteTriggerZoneMeshConnection.Target, zoneID: UUID) {
        guard messageScopeID == token, candidatePageVisible, isForeground, !presentation.isPreview,
              UserData.currentUserId == account, UserData.currentServerRegion == region,
              selectedID == zoneID, meshConnection.target == target,
              meshConnection.isConnected(to: target), candidateSelection.spaceID == target.spaceID,
              let space = coordinator.site.spaces.first(where: { $0.id == target.spaceID }),
              space.canEditing, coordinator.site.state == .normal,
              let candidateSpace = candidateSpaces.first(where: { $0.id == target.spaceID }),
              let device = SiteTriggerZoneCandidates.device(for: address, in: candidateSpace),
              SiteTriggerZoneCandidates.filteredDevices(in: candidateSpace, zoneID: zoneID,
                  memberships: liveMemberships(), includeAdded: candidateSelection.includeAdded)
                  .contains(where: { $0.identity == device.identity }) else { return }
        switch addPanel.selectedMode {
        case .quickAdd:
            guard quickState == .adding else { return }
            addMember(device, triggerAddress: address, identify: true)
        case .triggerAdd:
            if !triggerCandidates.contains(device.identity) {
                triggerCandidates.append(device.identity)
                updatePanel(items: content.items)
            }
        case .manuallyAdd: break
        }
    }

    private func handleCandidateTap(_ id: String) {
        guard UserData.currentUserId == account, UserData.currentServerRegion == region,
              let zoneID = selectedID, memberDraft?.zoneID == zoneID,
              content.items.first(where: { $0.id == zoneID })?.canEdit == true,
              meshConnection.target.map(meshConnection.isConnected(to:)) == true,
              let spaceID = candidateSelection.spaceID,
              let space = candidateSpaces.first(where: { $0.id == spaceID && $0.isSelectable }),
              let device = SiteTriggerZoneCandidates.filteredDevices(in: space, zoneID: zoneID,
                  memberships: liveMemberships(), includeAdded: candidateSelection.includeAdded)
                  .first(where: { "\($0.identity.spaceID)-\($0.identity.deviceID)" == id }),
              addPanel.selectedMode == .manuallyAdd ||
                  (addPanel.selectedMode == .triggerAdd && triggerCandidates.contains(device.identity)) else { return }
        if selectedCandidateID == id {
            selectedCandidateID = nil
            addMember(device, triggerAddress: device.address, identify: true)
        } else {
            selectedCandidateID = id
            updatePanel(items: content.items)
        }
    }

    @objc private func enteredBackground() {
        isForeground = false
        if quickState == .adding { quickState = .pause }
        #if DEBUG
        stopDiagnosticMessageObservation()
        #endif
        stopMessageObservation()
        if isViewLoaded { updatePanel(items: content.items) }
    }

    @objc private func enteredForeground() {
        isForeground = true
        meshConnection.refresh()
        #if DEBUG
        if candidatePageVisible { startDiagnosticMessageObservation() }
        #endif
        if isViewLoaded { updatePanel(items: content.items) }
    }

    private func addMember(_ device: SiteTriggerZoneCandidates.Device,
                           triggerAddress: UInt16, identify: Bool) {
        guard UserData.currentUserId == account, UserData.currentServerRegion == region,
              let uuid = UUID(uuidString: device.identity.deviceID),
              let target = meshConnection.target, target.spaceID == device.identity.spaceID,
              meshConnection.isConnected(to: target),
              device.elementAddresses.contains(triggerAddress),
              memberDraft?.zoneID == selectedID else { return }
        let member = SiteTriggerZoneMember(identity: .init(spaceID: device.identity.spaceID, nodeUUID: uuid),
                                           groupAddress: device.groupAddress, primaryAddress: device.address,
                                           deviceAddress: device.deviceAddress)
        guard memberDraft?.add(member) == true else { return }
        triggerCandidates.removeAll { $0 == device.identity }
        reload()
        if identify, meshConnection.target == target, meshConnection.isConnected(to: target) {
            MeshAPI.identify(address: device.address)
        }
    }

    private func selectConnectionSpace(autoConnect: Bool) {
        guard !presentation.isPreview,
              UserData.currentUserId == account, UserData.currentServerRegion == region,
              let spaceID = candidateSelection.spaceID,
              let candidate = candidateSpaces.first(where: { $0.id == spaceID && $0.isSelectable }),
              let space = coordinator.site.spaces.first(where: { $0.id == candidate.id }) else {
            meshConnection.select(nil, autoConnect: false)
            return
        }
        let target = SiteTriggerZoneMeshConnection.Target(spaceID: space.id, meshUUID: space.meshUUID,
                                                            networkID: space.meshNetworkId)
        meshConnection.select(target, autoConnect: autoConnect)
    }

    private func loadCandidateSpaces(devicesFor spaceID: String? = nil) {
        guard candidatePageVisible, !presentation.isPreview,
              UserData.currentUserId == account, UserData.currentServerRegion == region else { return }
        dismissCandidateMenus()
        let requestID = UUID()
        candidateRequestID = requestID
        selectedCandidateID = nil
        triggerCandidates = []
        let site = coordinator.site
        let account = UserData.currentUserId
        let region = UserData.currentServerRegion
        let requests = site.spaces.map { space -> SiteTriggerZoneCandidateReader.Request in
            let permitted = site.state == .normal && space.siteId == site.id && space.meshUUID == site.meshUUID && space.canEditing
            return .init(siteID: site.id, meshUUID: space.meshUUID, subnetID: space.meshNetworkId,
                         space: .init(id: space.id, name: space.name,
                                      accessLabelKey: permitted ? nil : (space.permission == .visitor ? "visitor" : "site_zones_access_unknown"),
                                      availability: permitted ? .loading : .restricted), expectedGroupCount: space.groupCount)
        }
        let source = SiteTriggerZoneCandidateReader.Source(
            appPath: NSHomeDirectory() + "/Documents/\(account)/sunsmart.sqlite3",
            meshPath: MeshDataManager.customDatabasePath ?? NSHomeDirectory() + "/Documents/mesh.sqlite3",
            eligibleProfileTypes: [Profile.ProfileType.proximityLighting.rawValue, Profile.ProfileType.proximityLightingWithPhotocell.rawValue],
            excludedGroupAddresses: [.meshOTAGroupAddress, .localClientGroupAddress, .subElementBroadcastGroupAddress])
        if spaceID == nil {
            candidateLoadState.reset()
            candidateListIncomplete = (site.spaceCount ?? site.spaces.count) > site.spaces.count
            candidateSpaces = requests.map(\.space)
        } else {
            candidateSpaces = candidateSpaces.map { current in
                var current = current
                if current.id == spaceID { current.devices = []; current.devicesLoaded = false }
                return current
            }
        }
        updatePanel(items: content.items)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SiteTriggerZoneCandidateReader.load(requests, source: source, devicesFor: spaceID)
            DispatchQueue.main.async {
                guard let self, self.candidatePageVisible, !self.presentation.isPreview,
                      self.candidateRequestID == requestID, UserData.currentUserId == account,
                      UserData.currentServerRegion == region else { return }
                self.candidateSpaces = self.candidateLoadState.accept(result, devicesFor: spaceID)
                let previous = self.candidateSelection.spaceID
                self.candidateSelection.reconcile(self.candidateSpaces)
                if previous != self.candidateSelection.spaceID || self.meshConnection.target == nil {
                    self.quickConnectionActive = false
                    self.quickState = .stop
                    self.selectedCandidateID = nil
                    self.triggerCandidates = []
                    self.stopMessageObservation()
                    self.selectConnectionSpace(autoConnect: self.addPanel.selectedMode != .quickAdd)
                }
                self.updatePanel(items: self.content.items)
                if let selected = self.candidateSelection.spaceID,
                   self.candidateSpaces.first(where: { $0.id == selected })?.devicesLoaded == false {
                    self.loadCandidateSpaces(devicesFor: selected)
                }
            }
        }
    }

    private func dismissCandidateMenus() {
        viewIfLoaded?.window?.subviews.compactMap { $0 as? TitleSelectView }.forEach { $0.dismiss() }
    }

    private func performOperation(_ operation: SiteTriggerZoneItemHeaderView.Operation, zoneID: UUID) {
        guard selectedID == zoneID, content.items.first(where: { $0.id == zoneID })?.canEdit == true else { return }
        #if DEBUG
        if presentation.isPreview {
            switch operation {
            case .reset, .delete: confirmPreviewOperation(operation, zoneID: zoneID)
            case .test, .save:
                XWHUDManager.showTipHUD("site_zones_preview_action".localizedString, isLineFeed: true)
            }
            return
        }
        #endif
        switch operation {
        case .delete:
            guard memberDraft?.members.isEmpty != false else { return }
            deleteZone(zoneID)
        case .save: saveZone(zoneID)
        case .reset:
            memberDraft?.reset()
            reload()
        case .test: break
        }
    }

    #if DEBUG
    private func showPreviewDeviceMenu(zoneID: UUID, spaceID: String, deviceID: String, source: UIView) {
        guard presentation.isPreview, let revision = preview.revision,
              let item = previewItems.first(where: { $0.id == zoneID }), item.canEdit,
              item.spaces.contains(where: { $0.id == spaceID && $0.devices.contains(where: { $0.id == deviceID }) }),
              let window = source.window else { return }
        let rect = source.convert(source.bounds, to: window)
        let safe = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: 8, dy: 8)
        let menuWidth = SCRXFrom(71)
        let x = min(max(safe.minX, rect.minX), safe.maxX - menuWidth)
        let y = rect.maxY + 8 + 30 <= safe.maxY ? rect.maxY + 8 : max(safe.minY, rect.minY - 38)
        source.layer.borderColor = Yellow_Color.cgColor
        TitleSelectView.show(titles: ["remove".localizedString], style: .default,
                             anchorPoint: CGPoint(x: x, y: y), menuWidth: menuWidth, itemHeight: 30,
                             titleFont: .systemFont(ofSize: 13, weight: .light), selectBack: { [weak self] _ in
            self?.mutatePreview(.remove(spaceID: spaceID, deviceID: deviceID), zoneID: zoneID, revision: revision)
        }, hideCallback: { [weak source] in
            source?.layer.borderColor = RGB(241, 242, 244).cgColor
        })
        previewDeviceMenu = window.subviews.last as? TitleSelectView
        previewDeviceMenu?.snp.makeConstraints { make in make.edges.equalToSuperview() }
    }

    private func confirmPreviewOperation(_ operation: SiteTriggerZoneItemHeaderView.Operation, zoneID: UUID) {
        guard let revision = preview.revision else { return }
        let key = operation == .reset ? "site_zones_preview_reset_confirm" : "site_zones_preview_delete_confirm"
        let alert = SiteTriggerZoneAlertView(title: "notification".localizedString, message: key.localizedString,
                               actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: { [weak self] _ in
            guard let self, self.selectedID == zoneID else { return }
            self.mutatePreview(operation == .reset ? .reset : .delete, zoneID: zoneID, revision: revision)
        })])
        alert.accessibilityIdentifier = "site-zone-preview-confirmation"
        alert.firstBtn.accessibilityIdentifier = "site-zone-preview-cancel"
        alert.secondBtn.accessibilityIdentifier = "site-zone-preview-confirm"
        alert.messageLabel.lineBreakMode = .byWordWrapping
        alert.messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        alert.messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        alert.contentView.snp.remakeConstraints { make in
            make.center.equalTo(alert.safeAreaLayoutGuide)
            make.width.equalTo(302).priority(.high)
            make.width.lessThanOrEqualTo(302)
            make.width.lessThanOrEqualTo(alert.safeAreaLayoutGuide).offset(-32)
            make.height.greaterThanOrEqualTo(190)
        }
        alert.show()
    }

    private func mutatePreview(_ mutation: SiteTriggerZonePreviewState.Mutation, zoneID: UUID, revision: UUID) {
        guard presentation.isPreview,
              preview.apply(mutation, zoneID: zoneID, expectedRevision: revision, zoneName: { "\("zone".localizedString) \($0)" }) else { return }
        let offset = content.tableView.contentOffset
        presentation.reconcilePreviewIDs(previewItems.map(\.id))
        reload()
        content.layoutIfNeeded()
        let table = content.tableView
        let minimum = -table.adjustedContentInset.top
        let maximum = max(minimum, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
        table.setContentOffset(CGPoint(x: 0, y: min(maximum, max(minimum, offset.y))), animated: false)
    }

    @objc private func togglePreview() {
        let previousAnimationSetting = allowPanelAnimations
        allowPanelAnimations = false
        defer { allowPanelAnimations = previousAnimationSetting }
        dismissCandidateMenus()
        candidateRequestID = UUID()
        if !presentation.isPreview {
            liveScrollOffset = content.tableView.contentOffset
            livePanelCollapsed = addPanel.isCollapsed
            preview.begin(items: SiteTriggerZonePreviewFixtures.makeItems { "\("zone".localizedString) \($0)" })
            previewCandidateSpaces = SiteTriggerZoneCandidatePreview.spaces(from: previewItems)
            previewCandidateSelection = .init()
        } else {
            preview.end()
        }
        let defaultID = previewItems.first { $0.previewCode == "D02" }?.id
        presentation.togglePreview(defaultSelectedID: defaultID)
        if presentation.isPreview { stopDiagnosticMessageObservation() }
        else { startDiagnosticMessageObservation() }
        previewBarButton.style = presentation.isPreview ? .done : .plain
        previewBarButton.tintColor = presentation.isPreview ? Yellow_Color : Bar_Color
        previewBarButton.accessibilityValue = (presentation.isPreview ? "site_zones_preview_mode" : "site_zones_live_mode").localizedString
        addPanel.setCollapsed(presentation.isPreview ? true : livePanelCollapsed)
        reload()
        if !presentation.isPreview { loadCandidateSpaces() }
        content.layoutIfNeeded()
        if presentation.isPreview, let index = previewItems.firstIndex(where: { $0.id == selectedID }) {
            let table = content.tableView
            // Include the selected header and its actions, rather than scrolling them above the viewport.
            table.setContentOffset(CGPoint(x: 0, y: table.rectForHeader(inSection: index).minY - table.adjustedContentInset.top), animated: false)
        } else {
            let table = content.tableView
            let minimum = -table.adjustedContentInset.top
            let maximum = max(minimum, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
            table.setContentOffset(CGPoint(x: 0, y: min(maximum, max(minimum, liveScrollOffset.y))), animated: false)
        }
    }
    #endif

    @objc private func addZone() {
        guard presentation.permitsLiveOperations, content.canEdit, let zones = try? coordinator.state().data.zones else { return }
        let remaining = SiteTriggerZone.maximumCount - zones.count
        guard remaining > 0 else {
            XWHUDManager.showTipHUD("not_zones_remaining".localizedString, isLineFeed: true)
            return
        }
        let message = String(format: "number_limited_range".localizedString, 1, remaining)
        SRAlertView(title: "add_trigger_zone".localizedString, message: message,
                    messageColor: Message_Color,
                    inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 3, textAlignment: .center, showClear: true),
                    actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, style: .default)],
                    textValueChangedBack: nil) { [weak self] text in
            guard let self, self.presentation.permitsLiveOperations, self.content.canEdit else { return }
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let count = Int(text), count > 0,
                  let current = try? self.coordinator.state().data.zones,
                  count <= SiteTriggerZone.maximumCount - current.count else {
                XWHUDManager.showTipHUD(message, isLineFeed: true)
                return
            }
            self.performMutation { try self.coordinator.add(count: count) }
        }.show()
    }

    private func deleteZone(_ id: UUID) {
        guard presentation.permitsLiveOperations, content.canEdit,
              (try? coordinator.state().data.zones)?.first(where: { $0.zoneId == id })?.isEmpty == true else { return }
        SRAlertView(title: "notification".localizedString, message: "zone_delete_message".localizedString,
                    actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: { [weak self] _ in
            guard let self else { return }
            self.performMutation { try self.coordinator.delete(zoneId: id) }
        })]).show()
    }

    private func performMutation(_ mutation: () throws -> Void) {
        guard presentation.permitsLiveOperations else { return }
        do {
            try mutation()
            failure = nil
            reload()
            synchronize()
        } catch {
            XWHUDManager.showTipHUD((error as? SiteTriggerZoneCoordinator.Failure ?? .storage).message, isLineFeed: true)
            reload()
        }
    }

    private func saveZone(_ id: UUID, completion: ((Bool) -> Void)? = nil) {
        #if DEBUG
        print("[SiteZoneSync][save] site=\(coordinator.site.id) zone=\(id) origin=\(completion == nil ? "operation" : "navigation") draftDirty=\(memberDraft?.isDirty == true) sender=disabled")
        #endif
        guard presentation.permitsLiveOperations, syncTask == nil, selectedID == id,
              content.items.first(where: { $0.id == id })?.canEdit == true else {
            completion?(false)
            return
        }
        if let draft = memberDraft, draft.zoneID == id,
           draft.isDirty || content.items.first(where: { $0.id == id })?.needsCloudMigration == true {
            do {
                try coordinator.saveMembers(zoneID: id, members: draft.members)
                if let zone = (try? coordinator.state().data.zones)?.first(where: { $0.zoneId == id }) {
                    memberDraft = SiteTriggerZoneDraft(zone: zone)
                }
            } catch {
                XWHUDManager.showTipHUD((error as? SiteTriggerZoneCoordinator.Failure ?? .storage).message,
                                         isLineFeed: true)
                completion?(false)
                return
            }
        }
        synchronize(zoneID: id, completion: completion)
    }

    private func retry() {
        guard presentation.permitsLiveOperations else { return }
        if staleMemberDraft != nil {
            let alert = UIAlertController(title: "notification".localizedString,
                                          message: "site_zone_draft_stale".localizedString,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "ok".localizedString, style: .default) { [weak self] _ in
                self?.staleMemberDraft = nil
                self?.reload()
            })
            present(alert, animated: true)
            return
        }
        if let state = try? coordinator.state(), state.needsArchivedReview,
           let archived = state.archivedPendings?.last {
            let message = String(format: "site_zones_archived_review".localizedString,
                                 archived.target.zones?.count ?? 0, state.data.zones?.count ?? 0)
            let alert = UIAlertController(title: "site_zones_server_replaced_title".localizedString,
                                          message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "ok".localizedString, style: .default) { [weak self] _ in
                guard let self else { return }
                _ = try? SiteTriggerZoneStore.update(self.coordinator.site) {
                    $0.acknowledgeArchivedReview()
                }
                self.failure = nil
                self.reload()
            })
            present(alert, animated: true)
            return
        }
        if (try? coordinator.state().conflict) == true {
            SRAlertView(title: "notification".localizedString, message: "site_zones_discard_draft".localizedString,
                        actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: { [weak self] _ in
                guard let self else { return }
                self.performMutation { try self.coordinator.useServerVersion() }
            })]).show()
        } else { synchronize(zoneID: retryZoneID) }
    }

    private func synchronize(zoneID: UUID? = nil, completion: ((Bool) -> Void)? = nil) {
        guard presentation.permitsLiveOperations, syncTask == nil else { completion?(false); return }
        retryZoneID = zoneID
        syncTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            let result = await coordinator.synchronize(zoneID: zoneID)
            if case .failure(let error) = result {
                failure = error
            } else {
                failure = nil
                retryZoneID = nil
                if zoneID != nil && presentation.permitsLiveOperations {
                    let state = try? coordinator.state()
                    #if DEBUG
                    if let zoneID {
                        let cloudConfirmed = state.map {
                            $0.pending == nil && !$0.conflict && !$0.hasAmbiguousRemote
                                && $0.rejectedRemote == nil && $0.serverData == $0.data
                        } == true
                        logDeviceSyncPreview(zoneID: zoneID, state: state,
                                             cloudConfirmed: cloudConfirmed, origin: "save")
                    }
                    #endif
                    let sourceOnly = state.map { self.retainedChangesAreProvenSourceOnly($0) } == true
                    #if DEBUG
                    print("[SiteZoneSync][source-only] site=\(coordinator.site.id) zone=\(zoneID?.uuidString ?? "all") proven=\(sourceOnly) retainedChanges=\(state?.deviceSyncChanges?.count ?? 0) deviceEvidence=unverified")
                    #endif
                    let deviceState = SiteTriggerZoneItemModel.TaskState.devices(
                        hasMembers: state?.data.zones?.first(where: { $0.zoneId == zoneID })?.isEmpty == false,
                        hasPendingChange: state?.deviceSyncChanges?.contains(where: {
                            $0.zoneID == zoneID && $0.hasKnownDeviceDelta
                        }) == true && !sourceOnly
                    )
                    let messageKey: String
                    switch deviceState {
                    case .pending: messageKey = "site_zone_saved_cloud_sync_unavailable"
                    case .unknown: messageKey = "site_zone_saved_cloud_unverified"
                    case .settled: messageKey = "site_zone_saved_cloud"
                    }
                    XWHUDManager.showSuccessTipHUD(messageKey.localizedString)
                    if let selectedID, let zone = (try? coordinator.state().data.zones)?
                        .first(where: { $0.zoneId == selectedID }) {
                        memberDraft = SiteTriggerZoneDraft(zone: zone)
                    }
                }
            }
            syncTask = nil
            reload()
            if case .success = result { completion?(true) }
            else { completion?(false) }
        }
        reload()
    }
}

extension SiteTriggerZoneViewController: GroupPathSequenceDeviceAddViewDelegate {
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, deviceAddModeChanged mode: PathSequenceDeviceAddMode) {
        if mode != .quickAdd {
            quickConnectionActive = false
            if quickState == .adding { quickState = .pause }
        }
        selectedCandidateID = nil
        stopMessageObservation()
        meshConnection.refresh()
        if mode != .quickAdd, meshConnection.phase == .idle { meshConnection.start() }
        updatePanel(items: content.items)
    }

    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, showAddedDevices enabled: Bool) {}
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, quickAddStateChanged state: QuickAddState) {}
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, selectDevice device: Node) {}
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, identifyDevice device: Node) {}
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, triggerDevicesRefresh triggerView: GroupPathSequenceTriggerAddView) {}
}

/// The SDK exposes one process-wide Mesh connection. This session owns only its selected Space.
final class SiteTriggerZoneMeshConnection {
    struct Target: Equatable {
        let spaceID: String
        let meshUUID: String
        let networkID: String
    }

    struct Context {
        let meshUUID: String
        let networkID: String
        let connected: Bool
    }

    protocol Transport: AnyObject {
        var context: Context? { get }
        func connect(_ target: Target)
        func disconnect()
        func loadPrimary(meshUUID: String, networkID: String)
        func addObserver(_ observer: @escaping () -> Void) -> UUID
        func removeObserver(_ id: UUID?)
    }

    private final class SDKTransport: Transport {
        var context: Context? {
            let manager = MeshLibManager.manager
            guard let network = manager.meshNetworkManager,
                  let mesh = network.meshNetwork,
                  !mesh.networkKeys.isEmpty else { return nil }
            // The SDK's currentNetworkKey getter creates and saves a random
            // Key when the Mesh has none. A read-only connection check must
            // fail closed before accessing it.
            let meshUUID = mesh.uuid.uuidString
            return Context(meshUUID: meshUUID, networkID: network.currentNetworkKey.networkId.hex,
                           connected: manager.isMeshNetworkConnected)
        }

        func connect(_ target: Target) {
            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: target.meshUUID, subNetworkId: target.networkID)
        }

        func disconnect() { MeshLibManager.manager.meshNetworkDisconnect() }

        func loadPrimary(meshUUID: String, networkID: String) {
            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: meshUUID, subNetworkId: networkID, connected: false)
        }

        func addObserver(_ observer: @escaping () -> Void) -> UUID {
            MeshLibManager.manager.addGlobalConnectionObserver { _, _ in observer() }
        }

        func removeObserver(_ id: UUID?) { MeshLibManager.manager.removeGlobalConnectionObserver(id) }
    }

    private final class RequestGate {
        private let lock = NSLock()
        private var current = UUID()
        func replace() -> UUID { lock.lock(); defer { lock.unlock() }; current = UUID(); return current }
        func matches(_ id: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return current == id }
    }

    private let primaryMeshUUID: String
    private let primaryNetworkID: String
    private let transport: Transport
    private let connectionTimeout: TimeInterval
    private let queue = DispatchQueue(label: "site.trigger.zone.mesh.connection")
    private let gate = RequestGate()
    private var connectionObserverID: UUID?
    private var timeout: DispatchWorkItem?
    private var requestID = UUID()
    private(set) var target: Target?
    private(set) var phase: GroupPathSequenceBrowseConfiguration.ConnectionPhase = .idle
    var onChange: (() -> Void)?

    init(primaryMeshUUID: String, primaryNetworkID: String,
         transport: Transport = SDKTransport(),
         connectionTimeout: TimeInterval = MeshProxyConnectionTiming.readyResultTimeout) {
        self.primaryMeshUUID = primaryMeshUUID
        self.primaryNetworkID = primaryNetworkID
        self.transport = transport
        self.connectionTimeout = connectionTimeout
        connectionObserverID = transport.addObserver { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.connectionChanged() }
        }
    }

    deinit {
        transport.removeObserver(connectionObserverID)
        timeout?.cancel()
    }

    private static func matches(_ target: Target, context: Context?) -> Bool {
        context?.meshUUID == target.meshUUID && context?.networkID == target.networkID
    }

    private func setPhase(_ value: GroupPathSequenceBrowseConfiguration.ConnectionPhase) {
        guard phase != value else { return }
        phase = value
        onChange?()
    }

    func select(_ newTarget: Target?, autoConnect: Bool) {
        guard target != newTarget else {
            if autoConnect, phase == .idle { start() }
            return
        }
        let oldTarget = target
        target = newTarget
        requestID = gate.replace()
        timeout?.cancel()
        timeout = nil
        setPhase(.idle)
        if let oldTarget {
            let primaryUUID = primaryMeshUUID
            let primaryID = primaryNetworkID
            let transport = self.transport
            queue.async {
                guard Self.matches(oldTarget, context: transport.context) else { return }
                transport.disconnect()
                if !autoConnect, transport.context == nil {
                    transport.loadPrimary(meshUUID: primaryUUID, networkID: primaryID)
                }
            }
        }
        if autoConnect { start() }
    }

    func start(forceReconnect: Bool = false) {
        guard let target else { return }
        if phase == .connected {
            if Self.matches(target, context: transport.context), transport.context?.connected == true { return }
            setPhase(.idle)
        }
        if phase == .connecting { return }
        let id = gate.replace()
        requestID = id
        timeout?.cancel()
        setPhase(.connecting)
        let gate = self.gate
        let transport = self.transport
        queue.async { [weak self] in
            guard gate.matches(id) else { return }
            let current = transport.context
            if forceReconnect || !Self.matches(target, context: current) || current?.connected != true {
                if current != nil { transport.disconnect() }
                guard gate.matches(id) else { return }
                transport.connect(target)
            }
            let loaded = Self.matches(target, context: transport.context)
            let connected = loaded && transport.context?.connected == true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestID == id, self.target == target else { return }
                if !loaded { self.fail(id: id) }
                else if connected { self.succeed(id: id) }
                else { self.scheduleTimeout(id: id) }
            }
        }
    }

    func retry() {
        guard phase == .failed else { return }
        start(forceReconnect: true)
    }

    func refresh() {
        guard phase == .connected, let target else { return }
        if !Self.matches(target, context: transport.context) || transport.context?.connected != true {
            setPhase(.failed)
        }
    }

    func isConnected(to target: Target) -> Bool {
        phase == .connected && Self.matches(target, context: transport.context)
            && transport.context?.connected == true
    }

    func leave() {
        let oldTarget = target
        target = nil
        requestID = gate.replace()
        timeout?.cancel()
        timeout = nil
        setPhase(.idle)
        guard let oldTarget else { return }
        let primaryUUID = primaryMeshUUID
        let primaryID = primaryNetworkID
        let transport = self.transport
        queue.async {
            guard Self.matches(oldTarget, context: transport.context) else { return }
            transport.disconnect()
            if transport.context == nil {
                transport.loadPrimary(meshUUID: primaryUUID, networkID: primaryID)
            }
        }
    }

    private func scheduleTimeout(id: UUID) {
        timeout?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.fail(id: id) }
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionTimeout, execute: item)
    }

    private func succeed(id: UUID) {
        guard requestID == id, phase == .connecting, let target,
              Self.matches(target, context: transport.context),
              transport.context?.connected == true else { return }
        timeout?.cancel()
        timeout = nil
        setPhase(.connected)
    }

    private func fail(id: UUID) {
        guard requestID == id, phase == .connecting, let target else { return }
        timeout?.cancel()
        timeout = nil
        setPhase(.failed)
        let transport = self.transport
        queue.async {
            if Self.matches(target, context: transport.context) { transport.disconnect() }
        }
    }

    private func connectionChanged() {
        if phase == .connected {
            refresh()
            return
        }
        guard let target,
              Self.matches(target, context: transport.context),
              transport.context?.connected == true else { return }
        succeed(id: requestID)
    }
}
