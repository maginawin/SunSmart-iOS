import UIKit
import NordicSigMeshSDK
import SwiftyJSON

/// Both scene types share draft ownership; DONE hands durable intent to the Sync page.
class SceneSettingsViewController: UIViewController, CustomSegmentedControlDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextFieldDelegate {
    enum Mode { case settings, members, deviceSelection }
    let space: SpaceData
    let scene: Scene?
    let mode: Mode
    var sceneUpdateCallback: ((Scene) -> Void)?
    var beginSaveOnAppearance = false
    var beginPreviewOnAppearance = false
    var finishesCreation = false
    var enablesGroupLiveControl = false
    private var selection: SceneDraftSelection?
    private let coordinator = SceneSaveCoordinator()
    private var initialError: Error?
    private var devicesView: SceneDevicesSelectionView!
    private var segmented: CustomSegmentedControl!
    private let groupLayout = UICollectionViewFlowLayout()
    private lazy var groupsTable = UICollectionView(frame: .zero, collectionViewLayout: groupLayout)
    private let groupSearch = DeviceNameFilterSearchView.makeInlineSearchField(placeholder: "scene_search_groups".localizedString)
    private let groupFilter = DeviceNameFilterSession()
    private var groups: [Group] = []
    private var devicePreview = SceneDevicePreviewState()
    private var previewComparison: SceneTargetSnapshot.Comparison?
    private var previewOnline = Set<TimedSchedulerNodeIdentity>()
    private var previewReport: SceneSaveCoordinator.Report?
    private var previewToast: ToastStatusView?
    private var selectionLayout: Bool?
    private let emptyDevicesView = UIScrollView()
    private let emptyGroupsView = UIScrollView()
    private var busy = false
    private var active = false
    private var lifecycle = UUID() {
        didSet { requestedAddresses = nil }
    }
    private var requestedAddresses: UUID?
    private var syncPagePresented = false
    private var picker: SceneExecuteDataPickerView?
    private var groupPreview: MeshGroupControlSession?
    private var groupPreviewGeneration = UUID()
    private var deviceLiveGeneration = UUID()
    private var lastLightnessSample: UInt16?
    private var lastTemperatureSample: UInt16?
    private var relayLiveControl: SceneRelayLiveControl?
    private var onDeviceLiveControl: (() -> Void)?
    private var connectionObservation: NSKeyValueObservation?
    private var alert: SRAlertView?
    private var observers: [NSObjectProtocol] = []

    init(space: SpaceData, scene: Scene, mode: Mode = .settings) {
        self.space = space; self.scene = scene; self.mode = mode
        super.init(nibName: nil, bundle: nil)
        do { selection = SceneDraftSelection(draft: try SceneConfigurationStore().editingDraft(for: scene)) } catch { initialError = error }
    }
    init(space: SpaceData, draft: SceneDraft) {
        self.space = space; self.scene = nil; mode = .members
        selection = SceneDraftSelection(draft: draft)
        super.init(nibName: nil, bundle: nil)
    }
    private init(space: SpaceData, selection: SceneDraftSelection) {
        self.space = space; scene = nil; mode = .deviceSelection
        self.selection = selection
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func viewDidLoad() {
        super.viewDidLoad(); title = "settings".localizedString; view.backgroundColor = Background_Color
        isModalInPresentation = true
        configureNavigationButtons()
        guard let selection else {
            navigationItem.rightBarButtonItem?.title = "retry".localizedString
            return
        }
        setupEditor(selection)
    }
    private func configureNavigationButtons() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .plain, target: self, action: #selector(closeAction)).withoutSharedBackground()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: (selection == nil ? "retry" : "done").localizedString, color: .black.withAlphaComponent(0.85), target: self, sel: #selector(doneAction))
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Our navigation controller installs a back arrow during push. Both editor
        // modes use this same close/DONE configuration, including on return.
        configureNavigationButtons()
        if selection != nil { reload() }
    }
    private func setupEditor(_ selection: SceneDraftSelection) {
        navigationItem.rightBarButtonItem?.title = "done".localizedString
        segmented = CustomSegmentedControl(frame: .zero, titles: ["groups".localizedString, "Devices".localizedString])
        segmented.delegate = self
        view.addSubview(segmented)
        segmented.snp.makeConstraints { make in make.top.equalTo(view.safeAreaLayoutGuide).offset(14); make.left.right.equalToSuperview().inset(16); make.height.equalTo(SCRYFrom(44)) }
        devicesView = SceneDevicesSelectionView(selection: selection, editorStyle: true); view.addSubview(devicesView)
        devicesView.snp.makeConstraints { make in
            make.top.equalTo(segmented.snp.bottom).offset(12); make.left.right.equalToSuperview()
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        devicesView.selecting = mode == .deviceSelection
        devicesView.onPreview = { [weak self] in self?.previewAction() }
        devicesView.onEditSelection = { [weak self] in self?.selectDevices() }
        devicesView.onPreviewDetails = { [weak self] in
            guard let self, let report = self.previewReport else { return }
            self.showPreviewResults(report)
        }
        devicesView.onChange = { [weak self] in self?.draftChanged() }
        devicesView.onSettings = { [weak self] target in self?.editDevices(target) }
        devicesView.onRemoveCategory = { [weak self] identities in self?.removeCategory(identities) }
        devicesView.onIdentify = { [weak self] node in self?.identify(node) }
        setupEmptySelectionView(emptyDevicesView, titleKey: "no_device_selected", messageKey: "scene_empty_devices_message", buttonKey: "scene_select_devices", action: #selector(selectDevices))
        setupEmptySelectionView(emptyGroupsView, titleKey: "no_groups", messageKey: "scene_not_groups_message", buttonKey: "create_group", action: #selector(createGroup))
        groupSearch.delegate = self
        groupSearch.addTarget(self, action: #selector(groupSearchChanged), for: .editingChanged)
        view.addSubview(groupSearch)
        groupSearch.snp.makeConstraints { make in make.top.equalTo(segmented.snp.bottom).offset(16); make.left.right.equalToSuperview().inset(16); make.height.equalTo(44) }
        groupsTable.dataSource = self; groupsTable.delegate = self; groupsTable.backgroundColor = .clear
        groupLayout.minimumInteritemSpacing = 10; groupLayout.minimumLineSpacing = 16
        groupsTable.contentInset = UIEdgeInsets(top: 16, left: 0, bottom: 16, right: 0)
        groupsTable.keyboardDismissMode = .onDrag
        groupsTable.register(SceneMembersViewCell.self, forCellWithReuseIdentifier: "group")
        view.addSubview(groupsTable)
        groupsTable.snp.makeConstraints { make in make.top.equalTo(groupSearch.snp.bottom).offset(8); make.left.right.equalToSuperview().inset(16); make.bottom.equalTo(view.keyboardLayoutGuide.snp.top) }
        coordinator.onReport = { [weak self] report in self?.received(report) }
        coordinator.onFailure = { [weak self] error in self?.failed(error) }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.viewIfLoaded?.window != nil, self.navigationController?.topViewController === self else { return }; self.active = true; self.reload()
        })
        observeDeviceChanges()
        reload()
    }
    private func setupEmptySelectionView(_ scrollView: UIScrollView, titleKey: String, messageKey: String, buttonKey: String, action: Selector) {
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(segmented.snp.bottom); make.left.right.equalToSuperview()
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        let illustration = UIImageView(image: UIImage(named: "data_empty"))
        illustration.contentMode = .scaleAspectFit
        let title = UILabel(text: titleKey.localizedString, textColor: RGB(100, 116, 139), fontSize: 15)
        title.textAlignment = .center; title.numberOfLines = 0
        let message = UILabel(text: messageKey.localizedString, textColor: RGB(148, 163, 184), fontSize: 15, fontWeight: .light)
        message.textAlignment = .center; message.numberOfLines = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center; paragraph.minimumLineHeight = 22; paragraph.maximumLineHeight = 22
        message.attributedText = NSAttributedString(string: messageKey.localizedString, attributes: [.paragraphStyle: paragraph])
        let button = UIButton(title: buttonKey.localizedString, titleSize: 16, titleWeight: .light, titleColor: .white, target: self, action: action)
        button.backgroundColor = Bar_Color; button.layer.cornerRadius = 10
        button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOpacity = 0.1
        button.layer.shadowOffset = CGSize(width: 0, height: 2); button.layer.shadowRadius = 5
        let stack = UIStackView(arrangedSubviews: [illustration, title, message, button])
        stack.axis = .vertical; stack.alignment = .center
        stack.setCustomSpacing(2, after: illustration)
        stack.setCustomSpacing(16, after: title)
        stack.setCustomSpacing(40, after: message)
        scrollView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(scrollView.contentLayoutGuide).offset(54)
            make.left.right.equalTo(scrollView.contentLayoutGuide).inset(20)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-40)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-24)
        }
        illustration.snp.makeConstraints { make in make.width.equalTo(240); make.height.equalTo(194) }
        title.snp.makeConstraints { make in make.width.equalToSuperview(); make.height.greaterThanOrEqualTo(20) }
        message.snp.makeConstraints { make in make.width.equalToSuperview() }
        button.snp.makeConstraints { make in make.width.equalTo(216); make.height.equalTo(44) }
    }
    private func observeDeviceChanges() {
        connectionObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            DispatchQueue.main.async {
                self?.interruptGroupPreview()
                self?.interruptDeviceLiveControl()
                self?.interruptDevicePreview()
            }
        }
        for name in [UIApplication.willResignActiveNotification,
                     Notification.Name(emergencyFireControllerManualControlStateDidChangeNotificationName),
                     Notification.Name(spacePermissionChangedNotificaitonName)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.interruptGroupPreview()
                self?.interruptDeviceLiveControl()
                self?.interruptDevicePreview()
            })
        }
        for name in [devicesUpdateNotificationName, deviceStateUpdateNotificationName, groupsRefreshNotificationName, groupDataUpdateNotificationName, spacePermissionChangedNotificaitonName] {
            observers.append(NotificationCenter.default.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                guard let self, self.active else { return }
                self.reload()
            })
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); active = true
        if selection != nil { reload() }
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        if let initialError { failed(initialError) }
        if beginSaveOnAppearance { beginSaveOnAppearance = false; doneAction() }
        else if beginPreviewOnAppearance { beginPreviewOnAppearance = false; previewAction() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if mode == .deviceSelection && isMovingFromParent { selection?.filter.reset() }
        suspend()
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
    private func suspend() {
        interruptDevicePreview()
        clearPreviewToast()
        stopGroupPreview()
        stopDeviceLiveControl()
        active = false; lifecycle = UUID(); selection?.invalidateParameterEdit()
        picker?.cancel(); picker = nil; alert?.removeFromSuperview(); alert = nil
        coordinator.cancel(); setBusy(false); XWHUDManager.hide()
    }
    private func accepts(_ token: UUID, revision: UUID) -> Bool {
        active && lifecycle == token && selection?.draft.revision == revision && viewIfLoaded?.window != nil
    }
    private func setBusy(_ value: Bool) {
        busy = value
        navigationItem.rightBarButtonItem?.isEnabled = !value
        let editable = !value && coordinator.committedNumber == nil
        segmented?.isUserInteractionEnabled = editable; devicesView?.editingEnabled = editable
        groupsTable.isUserInteractionEnabled = editable; groupSearch.isUserInteractionEnabled = editable
        emptyDevicesView.isUserInteractionEnabled = editable
        emptyGroupsView.isUserInteractionEnabled = editable
    }
    private func reload() {
        guard let selection else { return }
        refreshDevicePreviewContext()
        let deviceMode = selection.draft.kind == .devices
        let selectingDevices = deviceMode && devicesView.selecting
        title = (selectingDevices ? "scene_select_devices" : "settings").localizedString
        segmented.isHidden = selectingDevices
        if selectionLayout != selectingDevices {
            selectionLayout = selectingDevices
            devicesView.snp.remakeConstraints { make in
                if selectingDevices { make.top.equalTo(view.safeAreaLayoutGuide) }
                else { make.top.equalTo(segmented.snp.bottom).offset(12) }
                make.left.right.equalToSuperview(); make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
            }
        }
        let selectedIndex = deviceMode ? 1 : 0
        if segmented.selectedIndex != selectedIndex { segmented.selectedIndex = selectedIndex }
        let showsEmptyDevices = deviceMode && !devicesView.selecting && selection.draft.deviceMembers.isEmpty
        let showsEmptyGroups = !deviceMode && MeshNetworkManager.instance.groups.isEmpty
        devicesView.isHidden = !deviceMode || showsEmptyDevices
        emptyDevicesView.isHidden = !showsEmptyDevices
        emptyGroupsView.isHidden = !showsEmptyGroups
        groupSearch.isHidden = deviceMode || showsEmptyGroups; groupsTable.isHidden = deviceMode || showsEmptyGroups
        groups = groupFilter.filtered(MeshNetworkManager.instance.groups, names: { [$0.name] })
        groupsTable.reloadData(); devicesView.reload(); setBusy(busy)
        if !deviceMode && !MeshNetworkManager.instance.groups.isEmpty && groups.isEmpty {
            let label = UILabel(); label.text = "scene_no_search_results".localizedString; label.textAlignment = .center
            groupsTable.backgroundView = label
        } else { groupsTable.backgroundView = nil }
    }
    private func draftChanged() {
        lifecycle = UUID(); coordinator.cancel()
        reload()
    }
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, shouldSelesctedItem index: Int) -> Bool {
        sceneKindChanged(index)
        // Only accepted draft changes update the tab, using the same animation as Site.
        return false
    }
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {}
    private func sceneKindChanged(_ index: Int) {
        guard let selection else { return }
        guard !busy, coordinator.committedNumber == nil else { return }
        let kind: SceneKind = index == 0 ? .groups : .devices
        var probe = selection.draft
        do { try probe.switchKind(to: kind) } catch { tip("scene_mode_locked"); return }
        if selection.draft.deviceMembers.isEmpty && selection.draft.groupParameters.isEmpty {
            changeKind(kind); return
        }
        showAlert(title: "notification", message: "scene_switch_mode_message", cancel: "cancel", confirm: "ok") { [weak self] in self?.changeKind(kind) }
    }
    private func changeKind(_ kind: SceneKind) {
        stopGroupPreview()
        stopDeviceLiveControl()
        do { try selection?.switchKind(to: kind, confirmed: true); devicesView.selecting = false; draftChanged() } catch { failed(error) }
    }
    @objc private func selectDevices() {
        guard !busy else { return }
        if devicesView.selecting && selection?.canFinishDeviceSelection != true { tip("scene_no_devices_hint"); return }
        showDeviceSelection(!devicesView.selecting)
    }
    private func showDeviceSelection(_ selecting: Bool) {
        guard let selection, let navigationController,
              navigationController.topViewController === self,
              navigationController.transitionCoordinator == nil else { return }
        view.endEditing(true)
        lifecycle = UUID(); selection.invalidateParameterEdit()
        stopGroupPreview(); stopDeviceLiveControl()
        picker?.cancel(); picker = nil; alert?.removeFromSuperview(); alert = nil
        clearPreviewToast()
        if selecting {
            guard mode != .deviceSelection else { return }
            let page = SceneSettingsViewController(space: space, selection: selection)
            page.onDeviceLiveControl = { [weak self] in self?.invalidatePreviewAfterLiveControl() }
            navigationController.pushViewController(page, animated: true)
        } else {
            guard mode == .deviceSelection else { return }
            selection.filter.reset()
            navigationController.popViewController(animated: true)
        }
    }
    @objc private func groupSearchChanged() { groupFilter.submit(groupSearch.text ?? ""); reload() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
    @objc private func createGroup() {
        guard !busy else { return }
        view.endEditing(true)
        navigationController?.pushViewController(GroupAddViewController(space: space), animated: true)
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        groups.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let group = groups[indexPath.item], parameters = selection?.draft.groupParameters[groups[indexPath.item].address.address]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "group", for: indexPath) as! SceneMembersViewCell
        let display = parameters.map { ExecuteSceneData(isOn: $0.isOn, lightness: Node.getLightness100(lightness: $0.lightness), cct: Int($0.cct)) }
        cell.updateData(group: group, sceneData: display)
        // The card represents expected settings, never the current lamp state.
        cell.bgView.backgroundColor = parameters?.isOn == false ? RGB(226, 226, 226) : .white
        cell.nameLabel.textColor = Title_Color; cell.nameLabel.maxFontSize = 12
        cell.selectBtn.isSelected = parameters != nil; cell.progressView.isHidden = parameters == nil
        cell.selectActionCallBack = { [weak self] selected in
            guard let self, let selection = self.selection else { return }
            if !selected {
                var values = selection.draft.groupParameters; values.removeValue(forKey: group.address.address)
                do { try selection.setGroupParameters(values); self.draftChanged() } catch { self.failed(error) }
            } else { self.editGroup(group) }
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard groups.indices.contains(indexPath.item) else { return }
        editGroup(groups[indexPath.item])
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns: CGFloat = isIPad ? 5 : 4
        let width = floor((collectionView.bounds.width - (columns - 1) * 10) / columns)
        return CGSize(width: width, height: width + 16)
    }
    private func editGroup(_ group: Group) {
        guard !busy, let selection else { return }
        stopGroupPreview()
        stopDeviceLiveControl()
        picker?.cancel()
        let previewGeneration = groupPreviewGeneration
        let liveControl: ((SceneExecuteDataPickerView.LiveEvent) -> Void)? = enablesGroupLiveControl ? { [weak self] event in
            guard let self, self.groupPreviewGeneration == previewGeneration else { return }
            self.handleGroupLiveControl(event, group: group)
        } : nil
        let current = selection.draft.groupParameters[group.address.address] ?? selection.draft.sourceGroupParameters[group.address.address]
        let initialBrightness = current.map { Node.getLightness100(lightness: $0.lightness) } ?? 100
        let revision = selection.draft.revision, token = lifecycle
        picker = SceneExecuteDataPickerView.show(lightness: current.map { Node.getLightness100(lightness: $0.lightness) } ?? 100,
            isOn: current?.isOn ?? true, cct: Int(current?.cct ?? 4500), lightnessLimitRange: 0...group.info.profile.lightControlData.highEndTrim,
            cctRange: group.effectiveCctRange, showCct: group.effectiveSupportCct, showDelete: false, liveControl: liveControl) { [weak self] on, brightness, cct in
                guard let self, self.accepts(token, revision: revision), self.coordinator.committedNumber == nil else { return }
                var values = selection.draft.groupParameters
                let rawBrightness = current.flatMap { value in
                    value.isOn == on && brightness == initialBrightness ? value.lightness : nil
                } ?? (on ? Node.getLightness(lightness100: brightness) : 0)
                values[group.address.address] = .init(isOn: on, lightness: rawBrightness, cct: group.clampEffectiveCct(UInt16(cct)))
                do { try selection.setGroupParameters(values); self.draftChanged() } catch { self.failed(error) }
            }
    }

    private func cancelGroupPreview() {
        groupPreview?.cancel(); groupPreview = nil
    }

    private func interruptGroupPreview() {
        guard enablesGroupLiveControl else { return }
        picker?.cancelLiveInteraction()
        cancelGroupPreview()
    }

    private func stopGroupPreview() {
        interruptGroupPreview()
        groupPreviewGeneration = UUID()
    }

    private func canControlGroup(_ group: Group) -> Bool {
        guard active, !busy, coordinator.committedNumber == nil,
              UIApplication.shared.applicationState == .active,
              let selection, selection.draft.kind == .groups,
              MeshNetworkManager.instance.groups.contains(where: { $0 === group }),
              (try? SceneConfigurationStore.validateAccess(selection.draft.scope)) != nil,
              !EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: group) else { return false }
        return MeshLibManager.manager.isMeshNetworkConnected
    }

    private func handleGroupLiveControl(_ event: SceneExecuteDataPickerView.LiveEvent, group: Group) {
        if case .cancel = event { cancelGroupPreview(); return }
        guard canControlGroup(group) else {
            cancelGroupPreview()
            return
        }
        if groupPreview == nil {
            let generation = groupPreviewGeneration
            let session = MeshGroupControlSession(address: group.address.address) { [weak self] in
                guard let self, self.groupPreviewGeneration == generation else { return false }
                return self.canControlGroup(group)
            }
            groupPreview = session
        }
        guard let session = groupPreview else { return }
        switch event {
        case .off:
            LightGroupControlCommandSender.setGroupOff(session: session)
        case .lightness(let value, let ended):
            let brightness = max(0, min(group.info.profile.lightControlData.highEndTrim, value))
            LightGroupControlCommandSender.setGroupLightness(session: session,
                lightness: Node.getLightness(lightness100: brightness), ended: ended)
        case .temperature(let value, let ended):
            guard group.effectiveSupportCct else { return }
            LightGroupControlCommandSender.setGroupColorTemperature(session: session,
                temperature: group.clampEffectiveCct(UInt16(clamping: value)), ended: ended)
        case .cancel: return
        }
    }
    private func removeCategory(_ identities: [TimedSchedulerNodeIdentity]) {
        guard !busy, let selection, !identities.isEmpty else { return }
        let token = lifecycle, revision = selection.draft.revision
        let popup = SRAlertView(title: "scene_remove_members".localizedString,
            message: String(format: "scene_remove_members_message".localizedString, identities.count), tapBackgroundHide: false,
            actions: [.cancelAction, .init(title: "remove".localizedString.uppercased(), titleColor: Error_Red_Color, style: .destructive, actionHandler: { [weak self] _ in
                guard let self, self.accepts(token, revision: revision) else { return }
                do { try selection.removeMembers(Set(identities), confirmed: true); self.draftChanged() } catch { self.failed(error) }
            })])
        alert = popup; popup.show()
    }
    private func editDevices(_ target: SceneDeviceSettingsTarget) {
        let identities = target.identities
        guard !busy, active, let selection, !identities.isEmpty else { return }
        stopDeviceLiveControl()
        picker?.cancel(); picker = nil; alert?.removeFromSuperview(); alert = nil
        let selected = selection.draft.deviceMembers.filter { identities.contains($0.identity) }
        guard let first = selected.first else { return }
        let nodes = selected.compactMap { devicesView.node(for: $0.identity) }
        let token = selection.beginParameterEdit(), life = lifecycle, revision = selection.draft.revision
        let liveControl = makeDeviceLiveControl(target)
        let apply: (Bool, Int, Int) -> Void = { [weak self] on, brightness, cct in
            guard let self, self.accepts(life, revision: revision), self.coordinator.committedNumber == nil else { return }
            let parameters = SceneParameters(isOn: on, lightness: Node.getLightness(lightness100: brightness), cct: UInt16(cct))
            do {
                try selection.finishParameterEdit(token, parameters: parameters, identities: Set(identities), apply: true) { identity, value in
                    var preservingUnits = value
                    if let old = selected.first(where: { $0.identity == identity })?.parameters,
                       old.isOn == on, Node.getLightness100(lightness: old.lightness) == brightness {
                        preservingUnits.lightness = old.lightness
                    }
                    return self.devicesView.node(for: identity).map { preservingUnits.resolved(for: $0) } ?? preservingUnits
                }
                self.draftChanged()
            } catch { self.failed(error) }
        }
        if nodes.allSatisfy({ $0.lightnessModel == nil }), !nodes.isEmpty {
            let control = CustomSegmentedControl(frame: .zero, titles: ["ON".localizedString, "OFF".localizedString])
            let popup = SRAlertView(title: nodes.count == 1 ? nodes[0].name : "settings".localizedString,
                message: "scene_relay_hint".localizedString, tapBackgroundHide: false, contentMinHeight: 230,
                actions: [.init(title: "cancel".localizedString, style: .cancel, actionHandler: { [weak self] _ in selection.invalidateParameterEdit(); self?.stopDeviceLiveControl() }),
                          .init(title: "apply".localizedString, actionHandler: { [weak self] _ in apply(control.selectedIndex == 0, 100, Int(first.parameters.cct)); self?.stopDeviceLiveControl() })])
            popup.contentView.addSubview(control)
            control.snp.makeConstraints { make in make.top.equalTo(popup.titleLabel.snp.bottom).offset(16); make.left.right.equalToSuperview().inset(24); make.height.equalTo(36) }
            popup.messageLabel.snp.remakeConstraints { make in make.top.equalTo(control.snp.bottom).offset(16); make.left.right.equalToSuperview().inset(24); make.bottom.lessThanOrEqualTo(popup.hLineView.snp.top).offset(-16) }
            control.selectedIndex = first.parameters.isOn ? 0 : 1
            if let liveControl {
                let delegate = SceneRelayLiveControl { isOn in
                    // Relay ON uses its OnOff model; it has no Lightness model.
                    liveControl(isOn ? .lightness(100, ended: true) : .off)
                }
                relayLiveControl = delegate; control.delegate = delegate
            }
            alert = popup; popup.show()
        } else {
            let single = nodes.count == 1 ? nodes.first : nil
            let maxBrightness = single.map { Node.getLightness100(lightness: $0.lightnessRange.upperBound) } ?? 100
            let ranges = nodes.filter(\.effectiveSupportCct).map(\.effectiveCctRange)
            let range = ranges.reduce(NodeAbsoluteCctRange.defaultRange) { min($0.lowerBound, $1.lowerBound)...max($0.upperBound, $1.upperBound) }
            picker = SceneExecuteDataPickerView.show(lightness: Node.getLightness100(lightness: first.parameters.lightness), isOn: first.parameters.isOn,
                cct: Int(first.parameters.cct), lightnessLimitRange: 0...maxBrightness,
                cctRange: single?.effectiveCctRange ?? range, showCct: nodes.contains(where: \.effectiveSupportCct), showDelete: false, liveControl: liveControl, picker: apply)
        }
    }
    private func makeDeviceLiveControl(_ target: SceneDeviceSettingsTarget) -> ((SceneExecuteDataPickerView.LiveEvent) -> Void)? {
        guard let identity = target.liveIdentity, let node = devicesView.node(for: identity),
              let selection else { return nil }
        let generation = deviceLiveGeneration, life = lifecycle, revision = selection.draft.revision
        return { [weak self, weak node] event in
            guard let self, let node, self.deviceLiveGeneration == generation,
                  self.accepts(life, revision: revision) else { return }
            self.handleDeviceLiveControl(event, node: node, identity: identity)
        }
    }
    private func interruptDeviceLiveControl() {
        picker?.cancelLiveInteraction()
        lastLightnessSample = nil; lastTemperatureSample = nil
    }
    private func stopDeviceLiveControl() {
        interruptDeviceLiveControl()
        deviceLiveGeneration = UUID(); relayLiveControl = nil
    }
    private func invalidatePreviewAfterLiveControl() {
        devicePreview.invalidate(); previewComparison = nil; previewOnline = []
        previewReport = nil; clearPreviewToast()
        devicesView?.previewPhase = devicePreview.phase
    }
    private func canControlDevice(_ node: Node, identity: TimedSchedulerNodeIdentity) -> Bool {
        guard active, !busy, coordinator.committedNumber == nil,
              UIApplication.shared.applicationState == .active,
              navigationController?.topViewController === self,
              let selection, selection.draft.kind == .devices, selection.isSelected(identity),
              devicesView.node(for: identity) === node, node.state,
              (try? SceneConfigurationStore.validateAccess(selection.draft.scope)) != nil,
              !EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: node) else { return false }
        return MeshLibManager.manager.isMeshNetworkConnected
    }
    private func handleDeviceLiveControl(_ event: SceneExecuteDataPickerView.LiveEvent, node: Node, identity: TimedSchedulerNodeIdentity) {
        if case .cancel = event {
            lastLightnessSample = nil; lastTemperatureSample = nil
            return
        }
        guard canControlDevice(node, identity: identity) else {
            lastLightnessSample = nil; lastTemperatureSample = nil
            return
        }
        let message: UnacknowledgedMeshMessage
        let model: Model?
        switch event {
        case .off:
            lastLightnessSample = nil; lastTemperatureSample = nil
            message = GenericOnOffSetUnacknowledged(false); model = node.onoffModel
        case .lightness(let value, let ended):
            if node.lightnessModel == nil {
                message = GenericOnOffSetUnacknowledged(value > 0); model = node.onoffModel
            } else {
                let raw = Node.getLightness(lightness100: max(0, min(100, value)))
                let brightness = raw == 0 ? 0 : max(node.lightnessRange.lowerBound, min(node.lightnessRange.upperBound, raw))
                let duplicateFinal = ended && lastLightnessSample == brightness
                lastLightnessSample = ended ? nil : brightness
                guard !duplicateFinal else { return }
                message = LightLightnessSetUnacknowledged(lightness: brightness); model = node.lightnessModel
            }
        case .temperature(let value, let ended):
            guard node.effectiveSupportCct else { return }
            let temperature = node.clampEffectiveCct(UInt16(clamping: value))
            let duplicateFinal = ended && lastTemperatureSample == temperature
            lastTemperatureSample = ended ? nil : temperature
            guard !duplicateFinal else { return }
            message = LightCTLTemperatureSetUnacknowledged(temperature: temperature, deltaUV: 0); model = node.temperatureModel
        case .cancel: return
        }
        guard let model else {
            lastLightnessSample = nil; lastTemperatureSample = nil
            return
        }
        do {
            // One unacknowledged command to this model's Element. No shared FIFO,
            // application retry or member traversal; issued packets cannot be recalled.
            try MeshNetworkManager.instance.send(message, to: model, completion: nil)
            invalidatePreviewAfterLiveControl(); onDeviceLiveControl?()
        } catch {
            lastLightnessSample = nil; lastTemperatureSample = nil
            #if DEBUG
            print("[Scene] Device live control send failed: \(type(of: error))")
            #endif
        }
    }
    private func identify(_ node: Node) {
        guard !busy, active, let selection else { return }
        do { try SceneConfigurationStore.validateAccess(selection.draft.scope) } catch { failed(error); return }
        guard let identity = node.sceneConfigurationIdentity, devicesView.node(for: identity) === node else { return }
        guard node.state, MeshLibManager.manager.isMeshNetworkConnected else { tip("device_notconnect_message"); return }
        guard !EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: node) else { tip("Uncontrollable in emergency situations"); return }
        if node.isSupportVendorIdentify {
            guard let model = node.sunricherVendorModel else { return }
            LightGroupControlCommandSender.sendVendorIdentify(SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))), model: model)
        } else { LightGroupControlCommandSender.identify(address: node.primaryUnicastAddress) }
    }
    private func clearPreviewToast() {
        previewToast?.removeFromSuperview(); previewToast = nil
    }
    private func beginDevicePreview() {
        guard let selection, !devicePreview.isRunning else { return }
        lifecycle = UUID()
        clearPreviewToast(); previewReport = nil
        devicePreview.begin(revision: selection.draft.revision)
        devicesView.previewPhase = devicePreview.phase
    }
    private func interruptDevicePreview() {
        guard devicePreview.isRunning else { return }
        lifecycle = UUID(); coordinator.cancel(); devicePreview.interrupt()
        previewReport = nil; clearPreviewToast()
        devicesView?.previewPhase = devicePreview.phase
        setBusy(false)
    }
    private func refreshDevicePreviewContext() {
        guard let selection else { return }
        let wasRunning = devicePreview.isRunning
        let changed = devicePreview.update(revision: selection.draft.revision)
        var targetsChanged = false
        if !changed, let comparison = previewComparison {
            if let snapshot = try? SceneTargetResolver.resolve(draft: selection.draft) {
                targetsChanged = snapshot.comparison != comparison
                if devicePreview.phase == .applied {
                    targetsChanged = targetsChanged || previewOnline != Set(snapshot.targets.filter { $0.node.state }.map(\.identity))
                }
            } else { targetsChanged = true }
        }
        if changed || targetsChanged {
            if wasRunning {
                lifecycle = UUID(); coordinator.cancel(); setBusy(false)
            }
            devicePreview.invalidate(); previewComparison = nil; previewOnline = []
            previewReport = nil; clearPreviewToast()
        }
        devicesView.previewPhase = devicePreview.phase
    }
    @objc private func previewAction() {
        guard devicesView?.selecting != true else { return }
        startSend(saving: false)
    }
    @objc private func doneAction() {
        guard !busy, !syncPagePresented else { return }
        guard let selection else {
            guard let scene else { return }
            do {
                let restored = SceneDraftSelection(draft: try SceneConfigurationStore().editingDraft(for: scene))
                self.selection = restored; initialError = nil
                setupEditor(restored)
            } catch { failed(error) }
            return
        }
        if coordinator.committedNumber != nil { commit(revision: selection.draft.revision); return }
        if devicesView.selecting { selectDevices(); return }
        do {
            if let unchanged = try SceneConfigurationStore().sceneIfUnchanged(draft: selection.draft) {
                stopGroupPreview()
                stopDeviceLiveControl()
                if unchanged.needSync || unchanged.info.configuration?.pendingOperations.isEmpty == false {
                    openSyncPage(unchanged)
                } else {
                    syncPagePresented = true
                    leave()
                }
                return
            }
            let snapshot = try SceneTargetResolver.resolve(draft: selection.draft)
            guard selection.draft.number != nil || snapshot.hasConfiguredMembers else { tip("scene_select_members"); return }
            startSend(saving: true)
        } catch { failed(error) }
    }
    private func startSend(saving: Bool) {
        guard !busy, active, let selection, coordinator.committedNumber == nil else { return }
        stopGroupPreview()
        stopDeviceLiveControl()
        let devicePreviewing = !saving && selection.draft.kind == .devices
        if devicePreviewing { beginDevicePreview() }
        do {
            let snapshot = try SceneTargetResolver.resolve(draft: selection.draft)
            try SceneConfigurationStore.validateAccess(selection.draft.scope)
            if devicePreviewing {
                guard !snapshot.targets.isEmpty else { interruptDevicePreview(); tip("scene_select_members"); return }
                previewComparison = snapshot.comparison
                previewOnline = Set(snapshot.targets.filter { $0.node.state }.map(\.identity))
            }
            let unknown = SceneCapacity.nodesRequiringRead(sceneSnapshot: snapshot)
            let schedulers = try TimedSchedulerBindings.nodesRequiringTopologyRead(sceneSnapshot: snapshot)
            if !unknown.isEmpty || !schedulers.isEmpty {
                setBusy(true); let token = lifecycle, revision = selection.draft.revision
                if !devicePreviewing { XWHUDManager.showCustomHUD(withMessage: "syncing_data".localizedString, isWindow: false) }
                let completion: (Bool) -> Void = { [weak self] success in
                    DispatchQueue.main.async {
                        guard let self, self.accepts(token, revision: revision) else { return }
                        self.setBusy(false); XWHUDManager.hide()
                        if success { self.startSend(saving: saving) }
                        else { self.interruptDevicePreview(); self.tip("sync_failed") }
                    }
                }
                if !unknown.isEmpty { SceneCapacity.readUnknownState(nodes: unknown, completion: completion) }
                else { ScheduleServer.readUnknownSchedulerState(nodes: schedulers, completion: completion) }
                return
            }
            _ = try TimedSchedulerBindings.prepareTopology(sceneSnapshot: snapshot)
            setBusy(true)
            if saving {
                commit(revision: selection.draft.revision)
            } else {
                if devicePreviewing {
                    devicePreview.sending(); devicesView.previewPhase = devicePreview.phase
                } else if !snapshot.targets.isEmpty { XWHUDManager.showCustomHUD(withMessage: "scene_sending".localizedString, isWindow: false) }
                try coordinator.send(draft: selection.draft, purpose: .preview)
            }
        } catch { failed(error) }
    }
    private func received(_ report: SceneSaveCoordinator.Report) {
        guard active, report.revision == selection?.draft.revision else { return }
        if selection?.draft.kind == .devices {
            guard let attempt = devicePreview.attempt else { return }
            let successful = report.results.values.filter { if case .successful = $0 { return true }; return false }.count
            let offline = report.results.values.filter { if case .offline = $0 { return true }; return false }.count
            let failed = report.results.count - successful - offline
            guard devicePreview.complete(attempt: attempt, revision: report.revision, successful: successful, failed: failed, offline: offline) else { return }
            previewReport = report
            setBusy(false); XWHUDManager.hide(); devicesView.previewPhase = devicePreview.phase
            clearPreviewToast()
            let success = devicePreview.phase == .applied
            let message = success ? "scene_preview_applied".localizedString
                : String(format: "scene_preview_result".localizedString, successful, failed, offline)
            previewToast = ToastStatusView.show(in: view, message: message, type: success ? .success : .failure,
                appearance: .siteUpdate, duration: 3)
            return
        }
        setBusy(false); XWHUDManager.hide()
        showPreviewResults(report)
    }
    private func showPreviewResults(_ report: SceneSaveCoordinator.Report) {
        let successful = report.results.values.filter { if case .successful = $0 { return true }; return false }.count
        let pending = report.results.count - successful
        var lines = [String(format: "scene_send_result".localizedString, successful, pending)]
        if let snapshot = try? selection.map({ try SceneTargetResolver.resolve(draft: $0.draft) }) {
            for target in snapshot.targets {
                let result = report.results[target.identity]
                let status: String
                switch result {
                case .successful?: status = "done!".localizedString
                case .offline?: status = "scene_offline_pending".localizedString
                default: status = "scene_failed_pending".localizedString
                }
                lines.append("\(target.node.name ?? target.node.primaryUnicastAddress.hex): \(SceneDevicesSelectionView.summary(target.parameters, node: target.node)) — \(status)")
            }
        }
        let popup = SRAlertView(title: "preview".localizedString,
            message: lines.joined(separator: "\n"), tapBackgroundHide: false, actionDirection: .vertical,
            actions: [.init(title: "ok".localizedString)])
        let resultsScroll = UIScrollView()
        popup.contentView.addSubview(resultsScroll)
        popup.messageLabel.removeFromSuperview(); resultsScroll.addSubview(popup.messageLabel)
        resultsScroll.snp.makeConstraints { make in
            make.top.equalTo(popup.titleLabel.snp.bottom).offset(20); make.left.right.equalToSuperview().inset(24)
            make.height.equalTo(min(360, max(120, view.bounds.height * 0.4)))
        }
        popup.messageLabel.snp.remakeConstraints { make in
            make.edges.equalTo(resultsScroll.contentLayoutGuide); make.width.equalTo(resultsScroll.frameLayoutGuide)
        }
        popup.hLineView.snp.remakeConstraints { make in
            make.top.equalTo(resultsScroll.snp.bottom).offset(20); make.left.right.equalToSuperview(); make.height.equalTo(0.5)
        }
        alert = popup; popup.show()
    }
    private func commit(revision: UUID, requestAddressIfNeeded: Bool = true) {
        guard active, !syncPagePresented, let selection, selection.draft.revision == revision else { return }
        do {
            setBusy(true)
            switch try coordinator.saveForSync(draft: selection.draft) {
            case .ready(let saved):
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
                openSyncPage(saved)
            case .projectionPending:
                setBusy(false); tip("scene_projection_pending")
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            }
        } catch SceneConfigurationStore.Failure.noNumber {
            if requestAddressIfNeeded { requestAddresses(revision: revision) }
            else { failed(SceneConfigurationStore.Failure.noNumber) }
        }
        catch { failed(error) }
    }
    private func requestAddresses(revision: UUID) {
        guard requestedAddresses == nil else { return }
        let request = UUID()
        requestedAddresses = request; setBusy(true); let token = lifecycle
        NetworkRequest.shared.request(.applyAddress(siteId: space.siteId, type: .scene, number: 16)) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.requestedAddresses == request,
                      self.accepts(token, revision: revision), let selection = self.selection else { return }
                self.requestedAddresses = nil; self.setBusy(false)
                do {
                    try SceneConfigurationStore.validateAccess(selection.draft.scope)
                    switch result {
                    case .success(let response):
                        guard let site = SiteData.load(siteId: self.space.siteId),
                              let data = JSON(response)["data"]["provisioner"].dictionaryObject,
                              SceneCapacity.validSceneAllocation(data) else { throw SceneConfigurationStore.Failure.noNumber }
                        site.setProvisioner(provisionerData: data)
                        guard MeshNetworkManager.instance.meshNetwork?.save() == true else { throw SceneConfigurationStore.Failure.persistence }
                        self.commit(revision: revision, requestAddressIfNeeded: false)
                    case .failure(let error): throw error
                    }
                } catch { self.failed(error) }
            }
        }
    }
    private func openSyncPage(_ saved: Scene) {
        guard !syncPagePresented, let navigationController else { setBusy(false); return }
        syncPagePresented = true
        XWHUDManager.hide()
        sceneUpdateCallback?(saved)
        NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: saved)
        NotificationCenter.default.post(name: .init(scenesRefreshNotificationName), object: nil)
        let sync = SyncDevicesViewController(type: .scene(saved))
        // Keep this editor in the stack until exit, but never return to its
        // committed draft. The Sync page independently owns stop/retry/pending.
        let returnController = navigationController.viewControllers.last(where: { $0 !== self })
        var didFinish = false
        let finish = { [weak self, weak returnController] in
            guard let self, !didFinish else { return }
            didFinish = true
            if self.scene == nil || self.finishesCreation { self.finishCreation() }
            else if let returnController {
                self.navigationController?.popToViewController(returnController, animated: true)
            }
        }
        sync.syncSuccessCallback = { _ in finish() }
        sync.backActionCallback = { _ in finish() }
        navigationController.pushViewController(sync, animated: true)
    }
    private func failed(_ error: Error) {
        guard active else { return }
        interruptDevicePreview()
        setBusy(false); XWHUDManager.hide()
        if selection == nil, scene?.info.projectionPending == true { tip("scene_projection_pending"); return }
        if let failure = error as? SceneConfigurationStore.Failure {
            switch failure {
            case .staleDraft: tip("scene_draft_stale")
            case .noNumber: tip("scene_address_unavailable")
            default: tip("save_failure")
            }
        } else { TimedSchedulerBindings.showFailure(error) }
    }
    private func tip(_ key: String) { XWHUDManager.showTipHUD(key.localizedString, isLineFeed: true) }
    private func showAlert(title: String, message: String, cancel: String, confirm: String, confirmStyle: SRAlertAction.SRAlertActionStyle = .default, action: @escaping () -> Void) {
        guard let selection else { return }; let token = lifecycle, revision = selection.draft.revision
        let popup = SRAlertView(title: title.localizedString, message: message.localizedString, tapBackgroundHide: false,
            actions: [.init(title: cancel.localizedString, style: .cancel), .init(title: confirm.localizedString, style: confirmStyle, actionHandler: { [weak self] _ in
                guard let self, self.accepts(token, revision: revision) else { return }; action()
            })])
        alert = popup; popup.show()
    }
    @objc private func closeAction() {
        if devicesView?.selecting == true { showDeviceSelection(false); return }
        interruptDevicePreview()
        if selection?.hasUnsavedChanges != true || coordinator.committedNumber != nil { leave(); return }
        if busy { lifecycle = UUID(); coordinator.cancel(); setBusy(false); XWHUDManager.hide() }
        showAlert(title: "scene_discard_title", message: "scene_discard_message", cancel: "scene_keep_editing", confirm: "scene_discard", confirmStyle: .destructive) { [weak self] in self?.leave() }
    }
    private func leave() {
        suspend()
        if finishesCreation { finishCreation() }
        else if navigationController?.viewControllers.first === self { dismiss(animated: true) }
        else { navigationController?.popViewController(animated: true) }
    }
    private func finishCreation() {
        if space.isConfiguring {
            dismiss(animated: false)
            let next = SpaceNewCreationProcessController(space: space, options: .scene)
            NotificationCenter.default.post(name: .init(spaceModalViewControllerNotificaitonName), object: NavigationViewController(rootViewController: next))
        } else { dismiss(animated: true) }
    }
}

private final class SceneRelayLiveControl: CustomSegmentedControlDelegate {
    private let changed: (Bool) -> Void
    init(changed: @escaping (Bool) -> Void) { self.changed = changed }
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, shouldSelesctedItem index: Int) -> Bool { true }
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) { changed(index == 0) }
}

private extension LightGroupControlCommandSender {
    @discardableResult
    static func setGroupOff(session: MeshGroupControlSession) -> Bool {
        session.send(GenericOnOffSetUnacknowledged(false), channel: .lightness,
                     isFinal: true, replacingAll: true)
    }

    @discardableResult
    static func setGroupLightness(session: MeshGroupControlSession, lightness: UInt16, ended: Bool) -> Bool {
        session.send(LightLightnessSetUnacknowledged(lightness: lightness), channel: .lightness, isFinal: ended)
    }

    @discardableResult
    static func setGroupColorTemperature(session: MeshGroupControlSession, temperature: UInt16, ended: Bool) -> Bool {
        session.send(LightCTLTemperatureSetUnacknowledged(temperature: temperature, deltaUV: 0),
                     channel: .temperature, isFinal: ended)
    }

}
