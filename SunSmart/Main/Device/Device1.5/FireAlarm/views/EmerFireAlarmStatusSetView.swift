//
//  EmerFireAlarmStatusSetView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit
import SnapKit

final class EmerFireAlarmStatusSetView: UIView {

    enum HeaderAction {
        case powerLossTrigger
        case powerLossStatus
        case fireTrigger
        case fireStatus
    }

    private struct StatusItem {
        let kind: RowKind
        let title: String
        let details: [DetailViewModel]
    }

    struct DetailViewModel {
        let subtitle: String
        let value: String
    }

    struct ItemViewModel {
        let kind: RowKind
        let title: String
        let details: [DetailViewModel]
    }

    enum RowKind {
        case powerLossTrigger
        case powerLossStop
        case fireTrigger
        case fireStop
    }

    enum RowStatus {
        case triggered
        case resume
        case inactive
        case disabled

        var imageName: String {
            switch self {
            case .triggered:
                return EmergencyFireControllerIconName.Monitor.StatusSet.powerLossActive
            case .resume:
                return EmergencyFireControllerIconName.Monitor.StatusSet.fireActive
            case .inactive:
                return EmergencyFireControllerIconName.Monitor.StatusSet.inactive
            case .disabled:
                return EmergencyFireControllerIconName.Monitor.StatusSet.disabled
            }
        }
    }

    private enum Layout {
        static let collapsedHeight = SCRYFrom(40) + kSafeAreaBottomHeight
        static let panelHeight = SCRYFrom(352) + kSafeAreaBottomHeight
        static let cornerRadius = SCRYFrom(20)
        static let headerHeight = SCRYFrom(40)
        static let expandedHeaderTopInset = SCRYFrom(8)
    }

    private(set) var isExpanded = false

    var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }

    var headerActionHandler: ((HeaderAction) -> Void)?
    var collapsedHeight: CGFloat { Layout.collapsedHeight }
    var expandedOverlayHeightProvider: (() -> CGFloat)?
    var heightChangeHandler: ((CGFloat) -> Void)?
    var expansionChangedHandler: ((Bool) -> Void)?

    private var contentTopConstraint: Constraint?
    private var topViewTopConstraint: Constraint?
    private var items: [StatusItem] = []

    private lazy var shadeView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isHidden = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        return view
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var topView: UIView = {
        let view = UIView()
        return view
    }()

    private lazy var headerButton: UIButton = {
        let button = UIButton(type: .custom)
        button.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        return button
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: "Status & Settings".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .regular)
        label.textAlignment = .center
        return label
    }()

    private lazy var arrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "arrow_up"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var powerLossTriggerButton = makeHeaderButton(image: UIImage(named: EmergencyFireControllerIconName.Monitor.StatusSet.powerLossEnabled),tintColor: nil, action: #selector(powerLossTriggerAction))
    private lazy var powerLossStatusButton = makeHeaderButton(image: UIImage(named: EmergencyFireControllerIconName.Monitor.StatusSet.powerLossActive),tintColor: nil, action: #selector(powerLossStatusAction), filled: true)
    private lazy var fireTriggerButton = makeHeaderButton(image: UIImage(named: EmergencyFireControllerIconName.Monitor.StatusSet.fireEnabled),tintColor: nil, action: #selector(fireTriggerAction))
    private lazy var fireStatusButton = makeHeaderButton(image: UIImage(named: EmergencyFireControllerIconName.Monitor.StatusSet.fireActive), tintColor: nil, action: #selector(fireStatusAction), filled: true)

    private lazy var headerActionsStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [powerLossTriggerButton, powerLossStatusButton, fireTriggerButton, fireStatusButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = SCRXFrom(12)
        stackView.isUserInteractionEnabled = false
        return stackView
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .white
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(64)
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(14), left: 0, bottom: SCRYFrom(14), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmerFireAlarmStatusItemCell.self)
        return tableView
    }()

    private lazy var legendHeaderView = EmerFireAlarmStatusLegendHeaderView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        updateExpandedState(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateItems(_ items: [ItemViewModel]) {
        self.items = items.map {
            StatusItem(kind: $0.kind, title: $0.title, details: $0.details)
        }
        tableView.reloadData()
    }

    func updateRowStatuses(powerLossTrigger: RowStatus, powerLossStop: RowStatus, fireTrigger: RowStatus, fireStop: RowStatus) {
        updateHeaderButtonImages(
            powerLossTrigger: powerLossTrigger,
            powerLossStop: powerLossStop,
            fireTrigger: fireTrigger,
            fireStop: fireStop
        )
    }

    private func updateHeaderButtonImages(powerLossTrigger: RowStatus, powerLossStop: RowStatus, fireTrigger: RowStatus, fireStop: RowStatus) {
        powerLossTriggerButton.setImage(UIImage(named: triggerHeaderImageName(enabledImageName: EmergencyFireControllerIconName.Monitor.StatusSet.powerLossEnabled, disabledImageName: EmergencyFireControllerIconName.Monitor.StatusSet.powerLossDisabled, status: powerLossTrigger)), for: .normal)
        powerLossStatusButton.setImage(UIImage(named: powerLossStop.imageName), for: .normal)
        fireTriggerButton.setImage(UIImage(named: triggerHeaderImageName(enabledImageName: EmergencyFireControllerIconName.Monitor.StatusSet.fireEnabled, disabledImageName: EmergencyFireControllerIconName.Monitor.StatusSet.fireDisabled, status: fireTrigger)), for: .normal)
        fireStatusButton.setImage(UIImage(named: fireStop.imageName), for: .normal)
    }

    private func triggerHeaderImageName(enabledImageName: String, disabledImageName: String, status: RowStatus) -> String {
        status == .disabled ? disabledImageName : enabledImageName
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else {
            updateExpandedState(animated: animated)
            return
        }
        isExpanded = expanded
        updateExpandedState(animated: animated)
    }

    @objc private func toggleExpanded() {
        setExpanded(!isExpanded, animated: true)
    }

    @objc private func shadeViewAction() {
        setExpanded(false, animated: true)
    }

    @objc private func powerLossTriggerAction() {
        headerActionHandler?(.powerLossTrigger)
    }

    @objc private func powerLossStatusAction() {
        headerActionHandler?(.powerLossStatus)
    }

    @objc private func fireTriggerAction() {
        headerActionHandler?(.fireTrigger)
    }

    @objc private func fireStatusAction() {
        headerActionHandler?(.fireStatus)
    }

    private func setupUI() {
        backgroundColor = .clear
        clipsToBounds = true

        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            contentTopConstraint = make.top.equalToSuperview().constraint
            make.height.equalTo(Layout.panelHeight)
        }

        contentView.addSubview(topView)
        topView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            topViewTopConstraint = make.top.equalToSuperview().constraint
            make.height.equalTo(Layout.headerHeight)
        }

        topView.addSubview(headerButton)
        headerButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        topView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.left.equalToSuperview().offset(SCRXFrom(24))
        }

        topView.addSubview(headerActionsStackView)
        headerActionsStackView.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalToSuperview().offset(-SCRXFrom(20))
        }

        topView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.left.equalTo(arrowImageView.snp.right).offset(SCRXFrom(12))
            make.right.lessThanOrEqualTo(headerActionsStackView.snp.left).offset(-SCRXFrom(12))
        }

        contentView.addSubview(legendHeaderView)
        legendHeaderView.snp.makeConstraints { make in
            make.top.equalTo(topView.snp.bottom)
            make.left.right.equalToSuperview().inset(SCRXFrom(20))
            make.height.equalTo(legendHeaderView.intrinsicContentSize.height)
        }

        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(legendHeaderView.snp.bottom)
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview().offset(-kSafeAreaBottomHeight)
        }
    }

    private func updateExpandedState(animated: Bool) {
        let targetHeight = isExpanded ? expandedHeight() : Layout.collapsedHeight
        let contentTop = isExpanded ? max(0, targetHeight - Layout.panelHeight) : 0
        heightChangeHandler?(targetHeight)
        expansionChangedHandler?(isExpanded)
        contentTopConstraint?.update(offset: contentTop)
        topViewTopConstraint?.update(offset: isExpanded ? Layout.expandedHeaderTopInset : 0)
        shadeView.isHidden = !isExpanded
        legendHeaderView.isHidden = !isExpanded
        tableView.isHidden = !isExpanded
        arrowImageView.image = UIImage(named: isExpanded ? "arrow_down" : "arrow_up")

        let animations = { [weak self] in
            guard let self else { return }
            self.superview?.layoutIfNeeded()
            self.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: 0.3, animations: animations)
        } else {
            animations()
        }
    }

    private func expandedHeight() -> CGFloat {
        if let height = expandedOverlayHeightProvider?(), height > Layout.collapsedHeight {
            return height
        }
        return Layout.panelHeight
    }

    private func makeHeaderButton(
        image: UIImage?,
        tintColor: UIColor?,
        action: Selector,
        filled: Bool = false
    ) -> UIButton {
        let button = UIButton(type: .custom)
        button.snp.makeConstraints { make in
            make.width.height.equalTo(SCRXFrom(20))
        }
        if let image {
            button.setImage(image, for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
        } else {
            button.backgroundColor = tintColor
            button.layer.cornerRadius = SCRXFrom(8)
        }
        if filled {
            button.layer.borderWidth = 0
        }
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
}

extension EmerFireAlarmStatusSetView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: EmerFireAlarmStatusItemCell = tableView.dequeueReusableCell(for: indexPath)
        
        let item = items[indexPath.row]
        cell.configure(with: .init(title: item.title, details: item.details))
        return cell
    }
}
