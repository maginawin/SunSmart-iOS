import UIKit
import NordicSigMeshSDK

final class SiteTriggerZoneViewController: UIViewController {
    private let coordinator: SiteTriggerZoneCoordinator
    private var content: SiteTriggerZoneContentView!
    private var addPanel: GroupPathSequenceDeviceAddView!
    private var presentation = SiteTriggerZonePresentationState()
    private var selectedID: UUID? { presentation.selectedID }
    private var addBarButton: UIBarButtonItem!
    private var candidateSpaces: [SiteTriggerZoneCandidates.Space] = []
    private var candidateSelection = SiteTriggerZoneCandidates.Selection()
    private var candidateLoadState = SiteTriggerZoneCandidates.LoadState()
    private var candidateListIncomplete = false
    private var candidateRequestID = UUID()
    private var candidatePageVisible = false
    private var allowPanelAnimations = false
    private var isChangingViewSize = false
    #if DEBUG
    private var previewBarButton: UIBarButtonItem!
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

    override func loadView() {
        addPanel = GroupPathSequenceDeviceAddView()
        addPanel.isSequence = false
        addPanel.contentHeightPolicy = .dynamicSelected
        // Candidate browsing has no device-operation delegate or Mesh callbacks.
        addPanel.canAddDevice = false
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
            guard let self else { return }
            self.presentation.select(id)
            self.reload()
            if let item = self.content.items.first(where: { $0.id == id }), item.canEdit || item.usesEmptyStyle {
                self.addPanel.setCollapsed(false, animated: true)
            }
        }
        content.operation = { [weak self] id, operation in self?.performOperation(operation, zoneID: id) }
        content.retry = { [weak self] in self?.retry() }
        content.syncTap = { SiteTriggerZoneItemStyle.syncAlert().show() }
        content.deviceTap = { [weak self] zoneID, spaceID, deviceID, source in
            #if DEBUG
            self?.showPreviewDeviceMenu(zoneID: zoneID, spaceID: spaceID, deviceID: deviceID, source: source)
            #endif
        }
        view = content
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "trigger_zone".localizedString
        addBarButton = UIBarButtonItem(image: UIImage(named: "path_add")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(addZone))
        addBarButton.accessibilityIdentifier = "site-zones-add"
        navigationItem.rightBarButtonItems = [addBarButton]
        #if DEBUG
        previewBarButton = UIBarButtonItem(title: "test".localizedString, style: .plain, target: self, action: #selector(togglePreview))
        previewBarButton.accessibilityIdentifier = "site-zones-preview-toggle"
        previewBarButton.accessibilityLabel = "site_zones_preview_toggle".localizedString
        navigationItem.rightBarButtonItems = [addBarButton, previewBarButton]
        #endif
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        allowPanelAnimations = false
        candidatePageVisible = true
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
        dismissCandidateMenus()
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
            content.render(items: previewItems, selectedID: selectedID, canCreate: false, canSave: true, isPreview: true)
            content.setStatus("site_zones_preview_mode".localizedString, allowsRetry: false)
            addBarButton?.isEnabled = false
            updatePanel(items: previewItems)
            return
        }
        #endif
        do {
            let state = try coordinator.state()
            let supported = state.rejectedRemote == nil && state.data.supportsEmptyZoneEditing
            // Future member formats are preserved, never rendered as editable empty zones.
            let ids = supported ? (state.data.zones ?? []).map(\.zoneId) : []
            presentation.reconcileLiveIDs(ids)
            let canEdit = supported && !state.conflict && coordinator.site.canManageSiteTriggerZones
                && failure != .permission
            let items = ids.enumerated().map { index, id in
                SiteTriggerZoneItemModel.empty(id: id, name: "\("zone".localizedString) \(index + 1)", canEdit: canEdit)
            }
            content.render(items: items, selectedID: selectedID, canCreate: canEdit, canSave: syncTask == nil)
            addBarButton?.isEnabled = canEdit
            updatePanel(items: items)
            let status = !supported ? SiteTriggerZoneCoordinator.Failure.unsupported.message
                : state.conflict ? SiteTriggerZoneCoordinator.Failure.conflict.message
                : (state.pending != nil ? "site_zones_sync_pending".localizedString
                   : failure == .network || failure == .unconfirmed ? nil : failure?.message)
            content.setStatus(status)
            content.emptyStateView.isHidden = !ids.isEmpty || !supported
        } catch {
            content.render(items: [], selectedID: nil, canCreate: false, canSave: false)
            content.emptyStateView.isHidden = true
            addBarButton?.isEnabled = false
            content.setStatus(SiteTriggerZoneCoordinator.Failure.storage.message)
        }
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
        }
        #else
        spaces = candidateSpaces
        selection = candidateSelection
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
        }
        addPanel.configureBrowse(.init(spaces: spaces.map { space in
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
            self.candidateSelection.select(id, in: self.candidateSpaces)
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
        } : nil))
        addPanel.refreshPreferredHeight()
    }

    private func loadCandidateSpaces(devicesFor spaceID: String? = nil) {
        guard candidatePageVisible, !presentation.isPreview else { return }
        dismissCandidateMenus()
        let requestID = UUID()
        candidateRequestID = requestID
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
                self.candidateSelection.reconcile(self.candidateSpaces)
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
        case .delete: deleteZone(zoneID)
        case .save: saveZone(zoneID)
        case .test, .reset: break
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
        guard presentation.permitsLiveOperations, content.canEdit else { return }
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

    private func saveZone(_ id: UUID) {
        guard presentation.permitsLiveOperations, content.canEdit, syncTask == nil, selectedID == id else { return }
        synchronize(zoneID: id)
    }

    private func retry() {
        guard presentation.permitsLiveOperations else { return }
        if (try? coordinator.state().conflict) == true {
            SRAlertView(title: "notification".localizedString, message: "site_zones_discard_draft".localizedString,
                        actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: { [weak self] _ in
                guard let self else { return }
                self.performMutation { try self.coordinator.useServerVersion() }
            })]).show()
        } else { synchronize(zoneID: retryZoneID) }
    }

    private func synchronize(zoneID: UUID? = nil) {
        guard presentation.permitsLiveOperations, syncTask == nil else { return }
        retryZoneID = zoneID
        syncTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            let result = await coordinator.synchronize(zoneID: zoneID)
            if case .failure(let error) = result {
                failure = error
            } else {
                failure = nil
                retryZoneID = nil
                if zoneID != nil && presentation.permitsLiveOperations { XWHUDManager.showSuccessTipHUD("done!".localizedString) }
            }
            syncTask = nil
            reload()
        }
        reload()
    }
}
