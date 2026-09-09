import UIKit

final class SiteTriggerZoneViewController: UIViewController {
    private let coordinator: SiteTriggerZoneCoordinator
    private var content: SiteTriggerZoneContentView!
    private var addPanel: GroupPathSequenceDeviceAddView!
    private var presentation = SiteTriggerZonePresentationState()
    private var selectedID: UUID? { presentation.selectedID }
    private var addBarButton: UIBarButtonItem!
    #if DEBUG
    private var previewBarButton: UIBarButtonItem!
    private var preview = SiteTriggerZonePreviewState()
    private var previewItems: [SiteTriggerZoneItemModel] { preview.items }
    private var liveScrollOffset = CGPoint.zero
    private var livePanelCollapsed = true
    private weak var previewDeviceMenu: TitleSelectView?
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
        // Presentation only: no Mesh delegate, device enumeration or add/identify callbacks.
        addPanel.canAddDevice = false
        addPanel.quickAddView.guideView.steps = [
            .init(imageName: "proximity_lighting_step1", title: "zone_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "zone_add_step2".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "zone_quick_add_step3".localizedString, textColor: SubText_Color)
        ]
        content = SiteTriggerZoneContentView(panel: addPanel)
        addPanel.contentHeightChanged = { [weak self] height in self?.content.setPanelHeight(height) }
        content.add = { [weak self] in self?.addZone() }
        content.select = { [weak self] id in
            guard let self else { return }
            self.presentation.select(id)
            self.reload()
            if self.content.items.first(where: { $0.id == id })?.canEdit == true {
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
        reload()
        synchronize()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        #if DEBUG
        previewDeviceMenu?.dismiss()
        #endif
        super.viewWillTransition(to: size, with: coordinator)
    }

    private func reload() {
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
        let index = items.firstIndex { $0.id == selectedID && $0.canEdit }
        addPanel.updateHeaderIndex(index.map { $0 + 1 })
        addPanel.refreshPreferredHeight()
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
        if !presentation.isPreview {
            liveScrollOffset = content.tableView.contentOffset
            livePanelCollapsed = addPanel.isCollapsed
            preview.begin(items: SiteTriggerZonePreviewFixtures.makeItems { "\("zone".localizedString) \($0)" })
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
