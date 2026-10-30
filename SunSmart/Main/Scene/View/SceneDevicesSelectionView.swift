import UIKit
import NordicSigMeshSDK

final class SceneDevicesSelectionView: UIView, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private(set) var selection: SceneDraftSelection
    var onChange: (() -> Void)?
    var onSettings: ((SceneDeviceSettingsTarget) -> Void)?
    var onRemoveCategory: (([TimedSchedulerNodeIdentity]) -> Void)?
    var onIdentify: ((Node) -> Void)?
    var editingEnabled = true { didSet { if oldValue != editingEnabled { reload() } } }
    /// Details reuse the category/parameter rows without any editing or control actions.
    let displayingSavedConfiguration: Bool
    var syncSnapshot: SceneGroupSyncSnapshot? { didSet { reload() } }
    var selecting = false {
        didSet {
            guard oldValue != selecting else { return }
            collapsed = selecting ? selectionCollapsed : settingsCollapsed
            selection.filter.reset(); search.text = nil
            reload()
        }
    }
    let editorStyle: Bool
    var onPreview: (() -> Void)?
    var onEditSelection: (() -> Void)?
    var onPreviewDetails: (() -> Void)?
    var previewPhase: SceneDevicePreviewState.Phase = .recommended { didSet { updateEditorHeader() } }
    private var selectionCollapsed = Set<UInt16>()
    private var settingsCollapsed = Set<UInt16>()
    private var knownSelectionCategories = Set<UInt16>()
    private let editorHeader = UIStackView()
    private let searchToolbar = UIStackView()
    private let selectedToolbar = UIStackView()
    private let selectedHeading = UILabel()
    private let previewButton = UIButton(type: .custom)
    private let editButton = UIButton(type: .custom)
    private let collapseButton = UIButton(type: .custom)
    private let searchCollapseButton = UIButton(type: .custom)
    private let previewBanner = ScenePreviewStatusView()
    private let search = DeviceNameFilterSearchView.makeInlineSearchField(placeholder: "scene_search_devices_groups".localizedString)
    private let countLabel = UILabel()
    private let table = SceneDeviceGroupsTableView(frame: .zero, style: .grouped)
    private let tableViewport = UIView()
    private let scopeLabel = UILabel()
    private var candidates: [SceneDraftSelection.Candidate] = []
    private var categories: [UInt16] = []
    private var categoryNames: [UInt16: String] = [:]
    private var collapsed = Set<UInt16>()

    init(selection: SceneDraftSelection, editorStyle: Bool = false, displayingSavedConfiguration: Bool = false) {
        self.selection = selection; self.editorStyle = editorStyle
        self.displayingSavedConfiguration = displayingSavedConfiguration
        super.init(frame: .zero)
        if displayingSavedConfiguration {
            setupSavedLayout()
            reload()
            return
        }
        search.delegate = self
        search.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        if editorStyle {
            setupEditorLayout()
            reload()
            return
        }
        search.snp.makeConstraints { make in make.height.equalTo(44) }
        countLabel.font = .systemFont(ofSize: 12, weight: .light); countLabel.textColor = RGB(148, 163, 184)
        let collapse = UIButton(type: .custom)
        collapse.setImage(UIImage(named: "devices_fold"), for: .normal)
        collapse.accessibilityLabel = "scene_expand_collapse_all".localizedString
        collapse.addTarget(self, action: #selector(toggleAll), for: .touchUpInside)
        let toolbar = UIStackView(arrangedSubviews: [search, countLabel, collapse]); toolbar.alignment = .center; toolbar.spacing = 4
        collapse.snp.makeConstraints { make in make.width.height.equalTo(44) }
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(toolbar)
        toolbar.snp.makeConstraints { make in make.top.equalToSuperview(); make.left.right.equalToSuperview().inset(16); make.height.equalTo(52) }
        scopeLabel.text = "scene_select_filtered_hint".localizedString
        scopeLabel.font = .systemFont(ofSize: 12); scopeLabel.numberOfLines = 0; scopeLabel.textColor = RGB(148, 163, 184)
        addSubview(scopeLabel)
        scopeLabel.snp.makeConstraints { make in make.top.equalTo(toolbar.snp.bottom); make.left.right.equalToSuperview().inset(16) }
        table.dataSource = self; table.delegate = self; table.backgroundColor = .clear
        table.keyboardDismissMode = .onDrag; table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 64
        table.sectionFooterHeight = 0.01; table.separatorColor = RGB(193, 207, 226, 0.3)
        table.register(SceneDeviceSettingsCell.self, forCellReuseIdentifier: "device")
        addSubview(table)
        table.snp.makeConstraints { make in make.top.equalTo(scopeLabel.snp.bottom).offset(8); make.left.right.bottom.equalToSuperview() }
        reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateSavedConfiguration(_ draft: SceneDraft, snapshot: SceneGroupSyncSnapshot?) {
        guard displayingSavedConfiguration else { return }
        selection = SceneDraftSelection(draft: draft)
        syncSnapshot = snapshot
    }

    /// Unknown async reads are not proof of pending work. Durable operations are.
    static func savedStatus(configuration: SceneConfiguration?, snapshot: SceneGroupSyncSnapshot?) -> String? {
        let current = snapshot?.isCurrent == true ? snapshot : nil
        let cleanup = current?.pendingCleanup.count ?? configuration?.pendingOperations.filter { $0.action == .remove }.count ?? 0
        if cleanup > 0 { return String(format: "scene_cleanup_count".localizedString, cleanup) }
        let pending = current?.needsAnySync ?? (configuration?.isDeleting == true || configuration?.pendingOperations.isEmpty == false)
        return pending ? "scene_pending_sync".localizedString : nil
    }

    private func setupSavedLayout() {
        let summary = UIStackView(arrangedSubviews: [countLabel, scopeLabel])
        summary.axis = .vertical; summary.spacing = 8
        countLabel.font = .systemFont(ofSize: 14)
        countLabel.textColor = RGB(148, 163, 184); countLabel.textAlignment = .center
        countLabel.numberOfLines = 0
        countLabel.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(20) }
        scopeLabel.font = .systemFont(ofSize: 12, weight: .light)
        scopeLabel.textColor = RGB(148, 163, 184); scopeLabel.textAlignment = .center
        scopeLabel.numberOfLines = 0
        addSubview(summary)
        summary.snp.makeConstraints { make in make.top.equalToSuperview(); make.left.right.equalToSuperview().inset(16) }
        table.dataSource = self; table.delegate = self; table.backgroundColor = .clear
        table.contentInsetAdjustmentBehavior = .never; table.sectionHeaderTopPadding = 0
        table.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 0.01))
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 60
        table.estimatedSectionHeaderHeight = 48; table.estimatedSectionFooterHeight = 0
        table.separatorStyle = .none; table.allowsSelection = false
        table.contentInset.bottom = 16
        table.register(SceneDeviceSettingsCell.self, forCellReuseIdentifier: "device")
        addSubview(table)
        table.snp.makeConstraints { make in
            make.top.equalTo(summary.snp.bottom).offset(20)
            make.left.right.equalToSuperview().inset(16); make.bottom.equalToSuperview()
        }
    }

    private func savedSectionHeader(_ section: Int) -> UIView {
        let header = UIView(); header.backgroundColor = .white
        header.layer.cornerRadius = 16; header.clipsToBounds = true
        header.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let title = UILabel(); title.text = categoryNames[categories[section]]
        title.font = .systemFont(ofSize: 14, weight: .light); title.textColor = TextBlack_Color
        title.numberOfLines = 0
        title.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(24) }
        let count = UILabel(); count.font = .systemFont(ofSize: 12, weight: .light)
        count.textColor = RGB(148, 163, 184)
        let total = rows(section).count
        count.text = String(format: (total == 1 ? "scene_member_count_one" : "scene_member_count_many").localizedString, total)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [title, count]); row.alignment = .center; row.spacing = 12
        header.addSubview(row)
        row.snp.makeConstraints { make in make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)) }
        let line = UIView(); line.backgroundColor = RGB(193, 207, 226, 0.4); header.addSubview(line)
        line.snp.makeConstraints { make in make.left.right.bottom.equalToSuperview(); make.height.equalTo(0.5) }
        return header
    }
    private func setupEditorLayout() {
        editorHeader.axis = .vertical; editorHeader.spacing = 8
        addSubview(editorHeader)
        editorHeader.snp.makeConstraints { make in make.top.equalToSuperview(); make.left.right.equalToSuperview().inset(16) }
        searchToolbar.alignment = .center; searchToolbar.spacing = 8
        let searchSpacer = UIView()
        searchToolbar.addArrangedSubview(search); searchToolbar.addArrangedSubview(searchSpacer)
        searchToolbar.addArrangedSubview(countLabel); searchToolbar.addArrangedSubview(searchCollapseButton)
        search.snp.makeConstraints { make in
            make.height.equalTo(36)
            make.width.equalTo(searchToolbar.snp.width).multipliedBy(228.0 / 343.0).priority(750)
        }
        let searchIconContainer = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        let searchIcon = UIImageView(image: UIImage(named: "scene_editor_search"))
        searchIcon.frame = CGRect(x: 12, y: 10, width: 16, height: 16)
        searchIconContainer.addSubview(searchIcon); search.leftView = searchIconContainer
        search.layer.borderColor = UIColor.white.cgColor; search.layer.cornerRadius = 10
        search.font = .systemFont(ofSize: 14, weight: .light)
        countLabel.font = .systemFont(ofSize: 12, weight: .light); countLabel.textColor = RGB(148, 163, 184)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        searchToolbar.snp.makeConstraints { make in make.height.equalTo(52).priority(999) }
        let searchSeparator = UIView(); searchSeparator.backgroundColor = RGB(193, 207, 226, 0.3)
        searchToolbar.addSubview(searchSeparator)
        searchSeparator.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(-16); make.right.equalToSuperview().offset(16)
            make.bottom.equalToSuperview(); make.height.equalTo(0.5)
        }
        selectedToolbar.alignment = .center; selectedToolbar.spacing = 8
        selectedHeading.font = .systemFont(ofSize: 14, weight: .light); selectedHeading.textColor = RGB(64, 79, 102)
        selectedHeading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        [selectedHeading, previewButton, editButton, collapseButton].forEach(selectedToolbar.addArrangedSubview)
        selectedToolbar.snp.makeConstraints { make in make.height.equalTo(30).priority(999) }
        [previewButton, editButton, collapseButton, searchCollapseButton].forEach { button in
            button.snp.makeConstraints { make in make.width.height.equalTo(30) }
            button.imageView?.contentMode = .scaleAspectFit
        }
        previewButton.setImage(UIImage(named: "scene_editor_play_ring"), for: .normal)
        let play = UIImageView(image: UIImage(named: "scene_editor_play_symbol"))
        previewButton.addSubview(play)
        play.snp.makeConstraints { make in make.left.equalToSuperview().offset(12.021); make.top.equalToSuperview().offset(9.888); make.width.equalTo(8.13854); make.height.equalTo(10.3308) }
        previewButton.accessibilityLabel = "preview".localizedString
        previewButton.addAction(UIAction { [weak self] _ in self?.onPreview?() }, for: .touchUpInside)
        editButton.setImage(UIImage(named: "scene_editor_edit"), for: .normal)
        editButton.accessibilityLabel = "scene_select_devices".localizedString
        editButton.addAction(UIAction { [weak self] _ in self?.onEditSelection?() }, for: .touchUpInside)
        [collapseButton, searchCollapseButton].forEach { button in
            button.setImage(UIImage(named: "scene_editor_expand_all"), for: .normal)
            button.accessibilityLabel = "scene_expand_collapse_all".localizedString
            button.addTarget(self, action: #selector(toggleAll), for: .touchUpInside)
        }
        previewBanner.onDetails = { [weak self] in self?.onPreviewDetails?() }
        [searchToolbar, selectedToolbar, previewBanner].forEach(editorHeader.addArrangedSubview)
        table.dataSource = self; table.delegate = self; table.backgroundColor = .clear
        table.contentInsetAdjustmentBehavior = .never
        table.sectionHeaderTopPadding = 0
        table.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 0.01))
        table.sectionFooterHeight = .leastNormalMagnitude; table.estimatedSectionFooterHeight = 0
        table.keyboardDismissMode = .onDrag; table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 52
        table.separatorColor = RGB(193, 207, 226, 0.3); table.separatorInset = .zero
        table.register(SceneDeviceSettingsCell.self, forCellReuseIdentifier: "device")
        table.showsCardShadow = true
        table.clipsToBounds = false
        table.contentInset.bottom = 4
        // Keep the shadow outside the table's 16pt margins, while still clipping
        // scrolling rows below the toolbar/banner and above the keyboard.
        tableViewport.clipsToBounds = true
        addSubview(tableViewport); tableViewport.addSubview(table)
        tableViewport.snp.makeConstraints { make in
            make.top.equalTo(editorHeader.snp.bottom).offset(12)
            make.left.right.bottom.equalToSuperview()
        }
        table.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.left.right.equalToSuperview().inset(16); make.bottom.equalToSuperview()
        }
    }
    private func updateEditorHeader() {
        guard editorStyle else { return }
        searchToolbar.isHidden = !selecting; selectedToolbar.isHidden = selecting
        selectedHeading.text = String(format: "scene_selected_devices_title".localizedString, selection.draft.deviceMembers.count)
        previewButton.isEnabled = editingEnabled; editButton.isEnabled = editingEnabled
        previewButton.alpha = editingEnabled ? 1 : 0.5; editButton.alpha = editingEnabled ? 1 : 0.5
        previewBanner.update(previewPhase)
        previewBanner.isHidden = selecting || !selection.hasUnsavedChanges
            || selection.draft.deviceMembers.isEmpty || previewPhase == .applied
        let allCollapsed = !categories.isEmpty && categories.allSatisfy { collapsed.contains($0) }
        [collapseButton, searchCollapseButton].forEach { $0.transform = allCollapsed ? CGAffineTransform(rotationAngle: .pi) : .identity }
        tableViewport.snp.updateConstraints { make in make.top.equalTo(editorHeader.snp.bottom).offset(selecting ? 8 : 12) }
    }
    private func editorSectionHeader(_ section: Int) -> UIView {
        let key = categories[section], items = rows(section)
        let selected = items.filter { selection.isSelected($0.identity) }
        let eligible = selection.filtered(items)
        let allSelected = !eligible.isEmpty && eligible.allSatisfy { selection.isSelected($0.identity) }
        let header = UIView(); header.backgroundColor = .white; header.clipsToBounds = true
        var corners: CACornerMask = []
        if section == 0 { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if section == categories.count - 1 && (collapsed.contains(key) || items.isEmpty) { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        header.layer.cornerRadius = 16; header.layer.maskedCorners = corners
        let check = UIButton(type: .custom)
        check.setImage(UIImage(named: allSelected ? "device_select" : "device_select_un"), for: .normal)
        check.isEnabled = editingEnabled && !eligible.isEmpty; check.alpha = check.isEnabled ? 1 : 0.5
        check.accessibilityLabel = "scene_select_filtered_hint".localizedString
        check.addAction(UIAction { [weak self] _ in
            guard let self, self.editingEnabled else { return }
            do { try self.selection.selectFiltered(items, selected: !allSelected); self.changed() }
            catch { TimedSchedulerBindings.showFailure(error) }
        }, for: .touchUpInside)
        let title = UIButton(type: .custom); title.contentHorizontalAlignment = .left
        title.titleLabel?.numberOfLines = 2
        let name = categoryNames[key] ?? ""
        let summary = selecting ? String(format: "scene_category_selected_count".localizedString, selected.count, items.count)
            : String(format: "scene_selected_count".localizedString, selected.count)
        let text = NSMutableAttributedString(string: name + "\n", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .light), .foregroundColor: TextBlack_Color])
        text.append(NSAttributedString(string: summary, attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .light), .foregroundColor: RGB(148, 163, 184)]))
        title.setAttributedTitle(text, for: .normal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let expand = UIButton(type: .custom); expand.setImage(UIImage(named: "scene_editor_expand"), for: .normal)
        expand.transform = collapsed.contains(key) ? CGAffineTransform(rotationAngle: -.pi / 2) : .identity
        expand.accessibilityLabel = "scene_expand_collapse_all".localizedString
        let toggle = UIAction { [weak self] _ in
            guard let self else { return }
            if self.collapsed.contains(key) { self.collapsed.remove(key) } else { self.collapsed.insert(key) }
            self.rememberExpansion(); self.table.reloadData()
        }
        title.addAction(toggle, for: .touchUpInside); expand.addAction(toggle, for: .touchUpInside)
        let settings = UIButton(type: .custom); settings.setImage(UIImage(named: "scene_editor_settings"), for: .normal)
        settings.isEnabled = editingEnabled && !selected.isEmpty; settings.alpha = settings.isEnabled ? 1 : 0.5
        settings.accessibilityLabel = "settings".localizedString
        settings.addAction(UIAction { [weak self] _ in self?.onSettings?(.category(selected.map(\.identity))) }, for: .touchUpInside)
        let remove = UIButton(type: .custom); remove.setImage(UIImage(named: "scene_editor_remove"), for: .normal)
        remove.isEnabled = editingEnabled && !selected.isEmpty; remove.alpha = remove.isEnabled ? 1 : 0.5
        remove.accessibilityLabel = "remove".localizedString
        remove.addAction(UIAction { [weak self] _ in self?.onRemoveCategory?(selected.map(\.identity)) }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: selecting ? [check, title, settings, expand] : [title, settings, remove, expand])
        row.alignment = .center; row.spacing = 8
        header.addSubview(row)
        row.snp.makeConstraints { make in make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: selecting ? 12 : 16, bottom: 10, right: selecting ? 12 : 16)) }
        [check, settings, remove, expand].filter { $0.superview != nil }.forEach { button in button.snp.makeConstraints { make in make.width.height.equalTo(30) } }
        let line = UIView(); line.backgroundColor = RGB(193, 207, 226, 0.3); header.addSubview(line)
        line.snp.makeConstraints { make in make.left.right.bottom.equalToSuperview(); make.height.equalTo(0.5) }
        return header
    }
    func node(for identity: TimedSchedulerNodeIdentity) -> Node? {
        MeshNetworkManager.instance.realNodes.first { node in
            node.network?.uuid.uuidString == selection.draft.scope.meshUUID && node.subNetworkId == selection.draft.scope.networkID
                && node.timedSchedulerIdentity.flatMap { try? SceneConfiguration.identity($0) } == identity
        }
    }
    func reload() {
        let savedOffset = table.contentOffset
        let draft = selection.draft
        candidates = MeshNetworkManager.instance.realNodes.compactMap { node in
            guard node.network?.uuid.uuidString == draft.scope.meshUUID, node.subNetworkId == draft.scope.networkID,
                  let raw = node.timedSchedulerIdentity, let identity = try? SceneConfiguration.identity(raw) else { return nil }
            guard !editorStyle || (node.onoffModel != nil && node.sceneSetupModel != nil)
                || selection.isSelected(identity) || selection.isExisting(identity) else { return nil }
            return .init(identity: identity, name: node.name ?? node.primaryUnicastAddress.hex,
                category: node.group?.name ?? "not_in_group".localizedString, categoryID: node.group?.address.address ?? 0,
                canAdd: node.state && node.isKeybindComplete && node.onoffModel != nil && node.sceneSetupModel != nil,
                defaults: SceneParameters(isOn: true, lightness: UInt16.max, cct: 4500).resolved(for: node))
        }
        // Missing nodes remain removable by their original provisioning identity.
        for member in draft.deviceMembers where !candidates.contains(where: { $0.identity == member.identity }) {
            candidates.append(.init(identity: member.identity, name: member.identity.unicastAddress,
                category: "not_in_group".localizedString, categoryID: 0, canAdd: false, defaults: member.parameters))
        }
        candidates = (editorStyle ? selection.displayed(candidates) : selection.filtered(candidates))
            .filter { selecting || selection.isSelected($0.identity) }
        categoryNames = [0: "not_in_group".localizedString]
        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == draft.scope.meshUUID,
           MeshNetworkManager.instance.currentNetworkKey.networkId.hex == draft.scope.networkID {
            for group in MeshNetworkManager.instance.groups { categoryNames[group.address.address] = group.name }
        }
        for candidate in candidates { categoryNames[candidate.categoryID] = candidate.category }
        categories = selection.visibleCategoryIDs(categoryNames, candidates: candidates, selecting: selecting)
        if editorStyle {
            if selecting {
                // New categories start collapsed; notifications never reset an expanded category.
                collapsed.formUnion(Set(categories).subtracting(knownSelectionCategories))
                knownSelectionCategories.formUnion(categories)
                selectionCollapsed = collapsed
            }
            updateEditorHeader()
        }
        search.isHidden = displayingSavedConfiguration
        let summaryKey = draft.deviceMembers.count == 1 ? "scene_device_summary_one" : "scene_device_summary"
        countLabel.text = String(format: (displayingSavedConfiguration ? summaryKey : "scene_selected_count").localizedString, draft.deviceMembers.count)
        scopeLabel.isHidden = !selecting && draft.deviceMembers.isEmpty
        scopeLabel.text = (selecting ? "scene_select_filtered_hint" : "scene_preview_recommended").localizedString
        if displayingSavedConfiguration {
            scopeLabel.text = Self.savedStatus(configuration: draft.sourceConfiguration, snapshot: syncSnapshot)
            scopeLabel.isHidden = scopeLabel.text == nil
        }
        scopeLabel.textColor = selecting || displayingSavedConfiguration ? RGB(148, 163, 184) : TextBlack_Color
        scopeLabel.backgroundColor = selecting || displayingSavedConfiguration ? .clear : RGB(255, 244, 221)
        scopeLabel.layer.cornerRadius = 12; scopeLabel.clipsToBounds = true
        table.reloadData()
        if categories.isEmpty {
            let label = UILabel(); label.numberOfLines = 0; label.textAlignment = .center
            label.font = .systemFont(ofSize: 15, weight: .light); label.textColor = RGB(148, 163, 184)
            label.text = selection.filter.isActive ? "scene_no_search_results".localizedString : "scene_no_devices_hint".localizedString
            if !selection.filter.isActive && !selecting {
                let scroll = UIScrollView()
                let illustration = UIImageView(image: UIImage(named: "data_empty")); illustration.contentMode = .scaleAspectFit
                let stack = UIStackView(arrangedSubviews: [illustration, label]); stack.axis = .vertical; stack.spacing = 24
                scroll.addSubview(stack)
                stack.snp.makeConstraints { make in
                    make.top.equalTo(scroll.contentLayoutGuide).offset(24); make.bottom.equalTo(scroll.contentLayoutGuide).offset(-24)
                    make.left.right.equalTo(scroll.contentLayoutGuide).inset(20); make.width.equalTo(scroll.frameLayoutGuide).offset(-40)
                }
                illustration.snp.makeConstraints { make in make.height.equalTo(194) }
                table.backgroundView = scroll
            } else { table.backgroundView = label }
        } else { table.backgroundView = nil }
        if displayingSavedConfiguration {
            layoutIfNeeded(); table.layoutIfNeeded()
            let maximumY = max(0, table.contentSize.height + table.adjustedContentInset.bottom - table.bounds.height)
            table.setContentOffset(CGPoint(x: 0, y: min(max(0, savedOffset.y), maximumY)), animated: false)
        }
    }
    @objc private func searchChanged() { selection.filter.submit(search.text ?? ""); reload() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
    @objc private func toggleAll() {
        let allCollapsed = !categories.isEmpty && categories.allSatisfy { collapsed.contains($0) }
        if allCollapsed { collapsed.subtract(categories) } else { collapsed.formUnion(categories) }
        rememberExpansion(); table.reloadData()
    }
    private func rememberExpansion() {
        if selecting { selectionCollapsed = collapsed } else { settingsCollapsed = collapsed }
        updateEditorHeader()
    }
    func numberOfSections(in tableView: UITableView) -> Int { categories.count }
    private func rows(_ section: Int) -> [SceneDraftSelection.Candidate] { candidates.filter { $0.categoryID == categories[section] } }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { collapsed.contains(categories[section]) ? 0 : rows(section).count }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        displayingSavedConfiguration ? UITableView.automaticDimension : (editorStyle ? 56 : 60)
    }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        displayingSavedConfiguration && section < categories.count - 1 ? 12 : .leastNormalMagnitude
    }
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        displayingSavedConfiguration ? UIView() : nil
    }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if displayingSavedConfiguration { return savedSectionHeader(section) }
        if editorStyle { return editorSectionHeader(section) }
        let items = rows(section), selected = items.filter { selection.isSelected($0.identity) }
        let header = UIView(); header.backgroundColor = .white
        let check = UIButton(type: .custom)
        check.setImage(UIImage(named: selecting ? (!items.isEmpty && selected.count == items.count ? "device_select" : "device_select_un") : "scene_delete"), for: .normal)
        check.isHidden = displayingSavedConfiguration
        check.isEnabled = !items.isEmpty
        check.accessibilityLabel = (selecting ? "scene_select_filtered_hint" : "remove").localizedString
        check.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if !self.selecting { self.onRemoveCategory?(selected.map(\.identity)); return }
            do { try self.selection.selectFiltered(items, selected: selected.count != items.count); self.changed() }
            catch { TimedSchedulerBindings.showFailure(error) }
        }, for: .touchUpInside)
        let title = UIButton(type: .system); title.contentHorizontalAlignment = .left
        title.titleLabel?.numberOfLines = 0; title.titleLabel?.font = .systemFont(ofSize: 14, weight: .light)
        let summary = selecting ? "\(selected.count)/\(items.count)" : String(format: "scene_selected_count".localizedString, selected.count)
        title.setTitle("\(categoryNames[categories[section]] ?? "")\n\(summary)", for: .normal); title.setTitleColor(TextBlack_Color, for: .normal)
        let expand = UIButton(type: .custom)
        expand.setImage(UIImage(named: collapsed.contains(categories[section]) ? "arrow_fold" : "arrow_unfold"), for: .normal)
        let toggle = UIAction { [weak self] _ in
            guard let self else { return }; let key = self.categories[section]
            if self.collapsed.contains(key) { self.collapsed.remove(key) } else { self.collapsed.insert(key) }; self.table.reloadData()
        }
        title.addAction(toggle, for: .touchUpInside); expand.addAction(toggle, for: .touchUpInside)
        let settings = UIButton(type: .custom); settings.setImage(UIImage(named: "settings"), for: .normal)
        settings.isHidden = displayingSavedConfiguration
        settings.isEnabled = !selected.isEmpty; settings.accessibilityLabel = "settings".localizedString
        settings.addAction(UIAction { [weak self] _ in self?.onSettings?(.category(selected.map(\.identity))) }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [check, title, settings, expand]); row.alignment = .center; row.spacing = 8
        header.addSubview(row); row.snp.makeConstraints { make in make.edges.equalToSuperview().inset(UIEdgeInsets(top: 2, left: 16, bottom: 2, right: 16)) }
        [check, settings, expand].forEach { button in button.snp.makeConstraints { make in make.width.height.equalTo(44) } }
        return header
    }
    private func changed() { reload(); onChange?() }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = rows(indexPath.section)[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "device", for: indexPath) as! SceneDeviceSettingsCell
        let node = node(for: item.identity), selected = selection.isSelected(item.identity)
        cell.configureLayout(editor: editorStyle, selecting: selecting, saved: displayingSavedConfiguration)
        let lastInSection = indexPath.row == rows(indexPath.section).count - 1
        cell.layer.cornerRadius = lastInSection && (displayingSavedConfiguration || (editorStyle && indexPath.section == categories.count - 1)) ? 16 : 0
        cell.savedSeparator.isHidden = !displayingSavedConfiguration || lastInSection
        cell.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        cell.nameLabel.text = item.name
        cell.nameLabel.accessibilityLabel = item.name
        cell.nameLabel.textColor = node?.state == true ? TextBlack_Color : RGB(148, 163, 184)
        cell.deviceIcon.image = UIImage(named: node?.iconName ?? "device_unknown")
        cell.checkButton.isSelected = selected
        let removing = !selecting && editorStyle
        cell.checkButton.setImage(UIImage(named: removing ? "scene_editor_remove" : "device_select_un"), for: .normal)
        cell.checkButton.setImage(UIImage(named: selecting ? "device_select" : (editorStyle ? "scene_editor_remove" : "scene_delete")), for: .selected)
        cell.checkButton.accessibilityLabel = (removing ? "remove" : "scene_select_devices").localizedString
        cell.checkButton.isEnabled = editingEnabled && (selected || item.canAdd || selection.isExisting(item.identity))
        cell.checkButton.alpha = cell.checkButton.isEnabled ? 1 : 0.5
        let parameters = selection.draft.deviceMembers.first { $0.identity == item.identity }?.parameters ?? item.defaults
        cell.parametersLabel.text = Self.summary(parameters, node: node)
        cell.parametersLabel.isHidden = editorStyle && selecting && node?.state != true && !selected
        cell.deviceIcon.alpha = !editorStyle || node?.state == true ? 1 : 0.45
        let currentSnapshot = syncSnapshot?.isCurrent == true ? syncSnapshot : nil
        let pendingWrite = currentSnapshot.map { $0.configurationPending || $0.pendingDevices.contains(item.identity) }
            ?? (selection.draft.sourceConfiguration?.pendingOperations.contains { $0.identity == item.identity && $0.action == .write } == true)
        if displayingSavedConfiguration && pendingWrite {
            cell.parametersLabel.text! += " · " + "scene_pending_sync".localizedString
        }
        cell.checkButton.isHidden = displayingSavedConfiguration
        cell.settingsButton.isHidden = displayingSavedConfiguration
        cell.identifyButton.isHidden = displayingSavedConfiguration
        cell.settingsButton.isEnabled = editingEnabled && selected
        cell.identifyButton.isEnabled = editingEnabled && node?.state == true
        // Offline members remain editable; dim their icon without discarding that capability.
        cell.settingsButton.alpha = cell.settingsButton.isEnabled && (!editorStyle || node?.state == true) ? 1 : 0.5
        cell.identifyButton.alpha = cell.identifyButton.isEnabled ? 1 : 0.5
        if displayingSavedConfiguration {
            cell.onSelect = nil; cell.onSettings = nil; cell.onIdentify = nil
            return cell
        }
        cell.onSelect = { [weak self] in
            guard let self, self.editingEnabled else { return }
            do { try self.selection.setSelected(item, selected: !selected); self.changed() } catch { TimedSchedulerBindings.showFailure(error) }
        }
        cell.onSettings = { [weak self] in self?.onSettings?(.device(item.identity)) }
        cell.onIdentify = { [weak self] in if let node { self?.onIdentify?(node) } }
        return cell
    }
    static func summary(_ parameters: SceneParameters, node: Node?) -> String {
        guard parameters.isOn else { return "OFF".localizedString }
        guard node?.lightnessModel != nil else { return "ON".localizedString }
        let lightness = Node.getLightness100(lightness: parameters.lightness)
        return node?.effectiveSupportCct == true ? "\(lightness)% · \(parameters.cct)K" : "\(lightness)%"
    }
}

/// One shadow for the entire Device Groups card, not one shadow per row/section.
/// Paths follow the content extent so folding, filtering and self-sizing rows
/// don't leave a shadow around an empty, fixed-height scroll viewport.
private final class SceneDeviceGroupsTableView: UITableView {
    var showsCardShadow = false { didSet { setNeedsLayout() } }
    private let softShadow = CALayer()
    private let contactShadow = CALayer()
    private var cardRect = CGRect.null

    override init(frame: CGRect, style: UITableView.Style) {
        super.init(frame: frame, style: style)
        // Figma 721:6652: (0, 1, blur 3, spread 0) and
        // (0, 1, blur 2, spread -1), both black at 10%.
        for shadow in [softShadow, contactShadow] {
            shadow.shadowColor = UIColor.black.cgColor
            shadow.shadowOpacity = 0.1
            shadow.shadowOffset = CGSize(width: 0, height: 1)
            shadow.isHidden = true
            layer.addSublayer(shadow)
        }
        softShadow.zPosition = -1; contactShadow.zPosition = -2
        softShadow.shadowRadius = 1.5; contactShadow.shadowRadius = 1
        softShadow.backgroundColor = UIColor.white.cgColor
        softShadow.cornerRadius = 16
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let visible = showsCardShadow && numberOfSections > 0 && bounds.width > 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        softShadow.isHidden = !visible; contactShadow.isHidden = !visible
        guard visible else { cardRect = .null; return }
        let first = rect(forSection: 0), last = rect(forSection: numberOfSections - 1)
        let rect = CGRect(x: 0, y: first.minY, width: bounds.width, height: last.maxY - first.minY)
        guard rect != cardRect, rect.height > 0 else { return }
        cardRect = rect
        softShadow.frame = rect; contactShadow.frame = rect
        softShadow.shadowPath = UIBezierPath(roundedRect: softShadow.bounds, cornerRadius: 16).cgPath
        contactShadow.shadowPath = UIBezierPath(roundedRect: contactShadow.bounds.insetBy(dx: 1, dy: 1), cornerRadius: 15).cgPath
    }
}

/// Only the Devices editor uses this banner; saved details keep their sync status label.
private final class ScenePreviewStatusView: UIView {
    var onDetails: (() -> Void)?
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let iconBackground = UIView()
    private let icon = UIImageView()
    private let detailsButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 16
        iconBackground.layer.cornerRadius = 16
        iconBackground.addSubview(icon)
        icon.contentMode = .scaleAspectFit
        icon.snp.makeConstraints { make in make.center.equalToSuperview(); make.width.height.equalTo(16) }
        iconBackground.snp.makeConstraints { make in make.width.height.equalTo(32) }
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium); titleLabel.numberOfLines = 0
        messageLabel.font = .systemFont(ofSize: 12); messageLabel.numberOfLines = 0
        detailsButton.setTitle("scene_preview_details".localizedString, for: .normal)
        detailsButton.titleLabel?.font = .systemFont(ofSize: 12)
        detailsButton.contentHorizontalAlignment = .left
        detailsButton.addAction(UIAction { [weak self] _ in self?.onDetails?() }, for: .touchUpInside)
        let content = UIStackView(arrangedSubviews: [titleLabel, messageLabel, detailsButton])
        content.axis = .vertical; content.spacing = 2
        let row = UIStackView(arrangedSubviews: [iconBackground, content]); row.spacing = 12; row.alignment = .top
        addSubview(row)
        row.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12); make.left.right.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-12).priority(999)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ phase: SceneDevicePreviewState.Phase) {
        let running = phase == .preparing || phase == .applying
        let color = running ? Bar_Color : RGB(255, 149, 0)
        backgroundColor = color.withAlphaComponent(running ? 0.06 : 0.15)
        iconBackground.backgroundColor = color.withAlphaComponent(running ? 0.15 : 0.25)
        let textColor = running ? Bar_Color : RGB(64, 79, 102)
        titleLabel.textColor = textColor; messageLabel.textColor = textColor
        detailsButton.setTitleColor(textColor, for: .normal)
        icon.image = UIImage(named: running ? "scene_editor_progress" : "scene_editor_warning")
        if running && icon.layer.animation(forKey: "preview") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = CGFloat.pi * 2; spin.duration = 1; spin.repeatCount = .infinity
            icon.layer.add(spin, forKey: "preview")
        } else if !running { icon.layer.removeAnimation(forKey: "preview") }
        detailsButton.isHidden = true
        var titleKey = "scene_preview_recommended_title", message = "scene_preview_recommended_message".localizedString
        switch phase {
        case .preparing:
            titleKey = "scene_preview_applying"; message = "scene_preview_preparing".localizedString
        case .applying:
            titleKey = "scene_preview_applying"; message = "scene_preview_sending".localizedString
        case .incomplete(let successful, let failed, let offline):
            titleKey = "scene_preview_incomplete"
            message = String(format: "scene_preview_result".localizedString, successful, failed, offline)
            detailsButton.isHidden = false
        case .interrupted:
            titleKey = "scene_preview_incomplete"; message = "scene_preview_interrupted".localizedString
        case .recommended, .applied: break
        }
        titleLabel.text = titleKey.localizedString
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 20; paragraph.maximumLineHeight = 20
        messageLabel.attributedText = NSAttributedString(string: message, attributes: [.paragraphStyle: paragraph])
    }
}
