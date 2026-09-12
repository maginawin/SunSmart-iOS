import UIKit

/// Owns the complete safe-area/list/panel constraint chain; no Mesh or persistence work.
final class SiteTriggerZoneContentView: UIView, UITableViewDataSource, UITableViewDelegate {
    let tableView = UITableView(frame: .zero, style: .grouped)
    let statusButton = UIButton(type: .system)
    let emptyStateView = UIView()
    let addButton = UIButton(type: .system)
    private let panel: UIView
    private var panelHeight: NSLayoutConstraint!
    private var panelBottom: NSLayoutConstraint!
    private var statusHeight: NSLayoutConstraint!
    private(set) var items: [SiteTriggerZoneItemModel] = []
    private(set) var selectedID: UUID?
    private(set) var canEdit = false
    private var canSave = false
    private var isPreview = false
    var allowsSelectedEmptyPanel = false
    private var preferredPanelHeight: CGFloat = 44
    private var isUpdatingPanelLayout = false
    private var lastTableWidth: CGFloat = 0
    private var measuredHeights: [UUID: CGFloat] = [:]
    private lazy var sizingCell = SiteTriggerZoneItemCell(style: .default, reuseIdentifier: nil)
    private var panelAllowed: Bool {
        if allowsSelectedEmptyPanel, let item = items.first(where: { $0.id == selectedID }), item.usesEmptyStyle { return true }
        return !items.isEmpty && items.first(where: { $0.id == selectedID })?.canEdit != false
    }
    var add: (() -> Void)?
    var select: ((UUID) -> Void)?
    var operation: ((UUID, SiteTriggerZoneItemHeaderView.Operation) -> Void)?
    var retry: (() -> Void)?
    var deviceTap: ((UUID, String, String, UIView) -> Void)?
    var syncTap: (() -> Void)?

    init(panel: UIView) {
        self.panel = panel
        super.init(frame: .zero)
        backgroundColor = Background_Color
        [statusButton, tableView, panel, emptyStateView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        statusButton.titleLabel?.font = .systemFont(ofSize: 12)
        statusButton.titleLabel?.numberOfLines = 0
        statusButton.setTitleColor(Red_Color, for: .normal)
        statusButton.accessibilityIdentifier = "site-zones-status"
        statusButton.addTarget(self, action: #selector(retryAction), for: .touchUpInside)
        statusHeight = statusButton.heightAnchor.constraint(equalToConstant: 0)
        panelHeight = panel.heightAnchor.constraint(equalToConstant: 0)
        panelHeight.priority = .defaultHigh
        panelBottom = panel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SCRYFrom(16))
        NSLayoutConstraint.activate([
            statusButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            statusButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            statusButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), statusHeight,
            tableView.topAnchor.constraint(equalTo: statusButton.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            tableView.bottomAnchor.constraint(equalTo: panel.topAnchor, constant: -8),
            tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panelBottom, panelHeight,
            emptyStateView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: tableView.topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: tableView.bottomAnchor)
        ])
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.sectionHeaderHeight = 40
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 0
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.register(SiteTriggerZoneItemCell.self, forCellReuseIdentifier: "item")
        tableView.register(SiteTriggerZoneItemHeaderView.self, forHeaderFooterViewReuseIdentifier: "item-header")
        tableView.register(SiteTriggerZoneHeaderView.self, forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(SiteTriggerZoneEmptyCell.self, forCellReuseIdentifier: "zone")
        tableView.accessibilityIdentifier = "site-zones-list"
        let title = UILabel()
        title.text = "no_trigger_zones".localizedString
        title.font = .systemFont(ofSize: 14, weight: .light)
        title.textColor = Message_Color
        title.numberOfLines = 0
        title.textAlignment = .center
        addButton.setTitle("add_trigger_zone".localizedString, for: .normal)
        addButton.setTitleColor(.white, for: .normal)
        addButton.backgroundColor = Bar_Color
        addButton.layer.cornerRadius = 8
        addButton.accessibilityIdentifier = "site-zones-add-empty"
        addButton.addTarget(self, action: #selector(addAction), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, addButton])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor, constant: -40),
            stack.widthAnchor.constraint(equalToConstant: 216),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyStateView.leadingAnchor),
            addButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(items: [SiteTriggerZoneItemModel], selectedID: UUID?, canCreate: Bool, canSave: Bool, isPreview: Bool = false) {
        self.items = items
        self.selectedID = selectedID
        self.canEdit = canCreate
        self.canSave = canSave
        self.isPreview = isPreview
        reload()
    }

    func setPanelHeight(_ height: CGFloat, animated: Bool = false) {
        preferredPanelHeight = height
        let targetHeight = panelAllowed ? height : 0
        let visibilityChanged = panel.isHidden == panelAllowed
        panel.isHidden = !panelAllowed
        guard abs(panelHeight.constant - targetHeight) > 0.5 else { return }
        guard animated, window != nil, !visibilityChanged, panelAllowed,
              !isUpdatingPanelLayout else {
            panelHeight.constant = targetHeight
            return
        }

        // Height callbacks can also arrive while the panel is laying out its content.
        isUpdatingPanelLayout = true
        defer { isUpdatingPanelLayout = false }
        layoutIfNeeded()
        // A layout callback may have supplied a newer preferred height.
        panelHeight.constant = panelAllowed ? preferredPanelHeight : 0
        UIView.animate(withDuration: 0.25, delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.layoutIfNeeded()
        }
    }

    func setStatus(_ text: String?, allowsRetry: Bool = true) {
        statusButton.setTitle(text, for: .normal)
        statusButton.isHidden = text == nil
        statusButton.isUserInteractionEnabled = allowsRetry
        statusButton.setTitleColor(allowsRetry ? Red_Color : SubText_Color, for: .normal)
        statusHeight.constant = text == nil ? 0 : 52
    }

    private func reload() {
        measuredHeights.removeAll()
        emptyStateView.isHidden = !items.isEmpty
        addButton.isEnabled = canEdit
        addButton.alpha = canEdit ? 1 : 0.5
        setPanelHeight(preferredPanelHeight)
        tableView.reloadData()
    }

    override func layoutSubviews() {
        updatePanelBottomSpacing()
        super.layoutSubviews()
        // Invalidate self-sizing rows after rotation or an iPad window width change.
        if tableView.bounds.width > 0, abs(lastTableWidth - tableView.bounds.width) > 0.5 {
            lastTableWidth = tableView.bounds.width
            measuredHeights.removeAll()
            tableView.reloadData()
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updatePanelBottomSpacing()
    }

    private func updatePanelBottomSpacing() {
        // Match Space Trigger Zone without adding padding on top of the safe area.
        panelBottom?.constant = -max(safeAreaInsets.bottom, SCRYFrom(16))
    }

    @objc private func addAction() { add?() }
    @objc private func retryAction() { retry?() }
    func numberOfSections(in tableView: UITableView) -> Int { items.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let item = items[indexPath.section]
        if item.usesEmptyStyle { return 72 }
        if let height = measuredHeights[item.id] { return height }
        let width = max(1, tableView.bounds.width)
        sizingCell.configure(item, selected: false, width: width)
        let height = ceil(sizingCell.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
        measuredHeights[item.id] = height
        return height
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.section]
        let cell: UITableViewCell
        if item.usesEmptyStyle {
            let empty = tableView.dequeueReusableCell(withIdentifier: "zone", for: indexPath) as! SiteTriggerZoneEmptyCell
            empty.setSelectedZone(item.id == selectedID)
            cell = empty
        } else {
            let populated = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath) as! SiteTriggerZoneItemCell
            populated.configure(item, selected: item.id == selectedID, width: tableView.bounds.width)
            populated.deviceTap = { [weak self] spaceID, deviceID, source in
                self?.deviceTap?(item.id, spaceID, deviceID, source)
            }
            populated.syncTap = { [weak self] in self?.syncTap?() }
            cell = populated
        }
        cell.accessibilityIdentifier = "site-zone-\(indexPath.section + 1)"
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        select?(items[indexPath.section].id)
    }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        40
    }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let item = items[section]
        let id = item.id
        if !item.usesEmptyStyle || item.sync.needsSync {
            let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "item-header") as! SiteTriggerZoneItemHeaderView
            header.configure(item, selected: id == selectedID, width: tableView.bounds.width, actionsEnabled: isPreview)
            header.select = { [weak self] in self?.select?(id) }
            header.operate = { [weak self] action in self?.operation?(id, action) }
            header.syncTap = { [weak self] in self?.syncTap?() }
            return header
        }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupPathSequencePathHeaderView
        header.nameLabel.text = item.name
        header.isSelect = id == selectedID
        header.testBtn.isEnabled = false
        header.resetBtn.isEnabled = false
        header.deleteBtn.isEnabled = item.canEdit
        header.deleteBtn.accessibilityIdentifier = "site-zone-delete-\(section + 1)"
        header.saveBtn.isEnabled = item.canEdit && canSave
        header.saveBtn.accessibilityIdentifier = "site-zone-save-\(section + 1)"
        header.viewSelectActionCallback = { [weak self] in self?.select?(id) }
        header.operationActionCallback = { [weak self] operation in
            switch operation {
            case .delete: self?.operation?(id, .delete)
            case .save: self?.operation?(id, .save)
            default: break
            }
        }
        return header
    }
    private func previewCaption(_ section: Int) -> UILabel? {
        guard isPreview, let code = items[section].previewCode else { return nil }
        let item = items[section]
        let roles = item.spaces.map { SiteTriggerZoneItemStyle.accessTitle($0.access) }.joined(separator: " / ")
        let state = item.needsSync ? "site_zones_item_needs_sync".localizedString : ""
        let label = SiteTriggerZoneItemStyle.label([code, roles, state].filter { !$0.isEmpty }.joined(separator: " · "))
        label.numberOfLines = 0
        return label
    }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard let label = previewCaption(section) else { return 8 }
        return ceil(label.sizeThatFits(CGSize(width: max(1, tableView.bounds.width - 16), height: .greatestFiniteMagnitude)).height) + 16
    }
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let container = UIView()
        if let label = previewCaption(section) {
            SiteTriggerZoneItemStyle.pin(label, to: container, insets: .init(top: 4, left: 8, bottom: 12, right: 8))
        }
        return container
    }
}

/// Keep Group/Space headers unchanged while giving Site zones their own Save action.
private final class SiteTriggerZoneHeaderView: GroupPathSequencePathHeaderView {
    override var isSelect: Bool {
        didSet { saveBtn.isHidden = !isSelect }
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        saveBtn.snp.remakeConstraints { make in
            make.right.equalTo(SCRXFrom(-9))
            make.top.equalTo(SCRYFrom(8))
            make.size.equalTo(CGSize(width: SCRXFrom(44), height: CGFloat(Int(SCRYFrom(28)))))
        }
        deleteBtn.snp.remakeConstraints { make in
            make.right.equalTo(saveBtn.snp.left).offset(SCRXFrom(-8))
            make.width.height.centerY.equalTo(saveBtn)
        }
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.snp.makeConstraints { make in
            make.right.lessThanOrEqualTo(testBtn.snp.left).offset(SCRXFrom(-8))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class SiteTriggerZoneEmptyCell: UITableViewCell {
    private let card = UIView()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = .white
        card.layer.cornerRadius = 10
        card.layer.borderColor = Yellow_Color.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        let label = UILabel()
        label.text = "No_Data".localizedString
        label.textColor = Message_Color
        label.font = .systemFont(ofSize: 14, weight: .light)
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setSelectedZone(_ selected: Bool) { card.layer.borderWidth = selected ? 1 : 0 }
}
