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
        case alert
        case statusGray
        case fire
        case statusGreen
    }

    private struct StatusItem {
        let title: String
        let subtitle: String
        let value: String
    }

    private enum Layout {
        static let collapsedHeight = SCRYFrom(40) + kSafeAreaBottomHeight
        static let expandedHeight = SCRYFrom(320) + kSafeAreaBottomHeight
        static let cornerRadius = SCRYFrom(20)
        static let headerHeight = SCRYFrom(40)
    }

    var isExpanded = false {
        didSet {
            updateExpandedState(animated: true)
        }
    }

    var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }

    var headerActionHandler: ((HeaderAction) -> Void)?

    private var heightConstraint: Constraint?
    private var items: [StatusItem] = [
        .init(title: "power_supply_fails".localizedString, subtitle: "set_brightness_to".localizedString, value: "100%"),
        .init(title: "power_is_restored".localizedString, subtitle: "resuming_in".localizedString, value: "2s"),
        .init(title: "fire_alarm_occurs".localizedString, subtitle: "set_brightness_to".localizedString, value: "100%"),
        .init(title: "fire_alarm_stops".localizedString, subtitle: "resuming_in".localizedString, value: "2s")
    ]

    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.masksToBounds = true
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

    private lazy var alertButton = makeHeaderButton(image: UIImage(named: "sts1"),tintColor: nil, action: #selector(alertAction))
    private lazy var grayStatusButton = makeHeaderButton(image: UIImage(named: "sts2"),tintColor: nil, action: #selector(grayStatusAction), filled: true)
    private lazy var fireButton = makeHeaderButton(image: UIImage(named: "sts3"),tintColor: nil, action: #selector(fireAction))
    private lazy var greenStatusButton = makeHeaderButton(image: UIImage(named: "sts5"), tintColor: nil, action: #selector(greenStatusAction), filled: true)

    private lazy var headerActionsStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [alertButton, grayStatusButton, fireButton, greenStatusButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = SCRXFrom(12)
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
        updateTableHeaderFrame()
        updateExpandedState(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateItems(_ items: [EmerFireAlarmStatusItemCell.ViewModel]) {
        self.items = items.map { StatusItem(title: $0.title, subtitle: $0.subtitle, value: $0.value) }
        tableView.reloadData()
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        updateExpandedState(animated: animated)
    }

    @objc private func toggleExpanded() {
        setExpanded(!isExpanded, animated: true)
    }

    @objc private func alertAction() {
        headerActionHandler?(.alert)
    }

    @objc private func grayStatusAction() {
        headerActionHandler?(.statusGray)
    }

    @objc private func fireAction() {
        headerActionHandler?(.fire)
    }

    @objc private func greenStatusAction() {
        headerActionHandler?(.statusGreen)
    }

    private func setupUI() {
        backgroundColor = .clear
        
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            heightConstraint = make.height.equalTo(Layout.collapsedHeight).constraint
        }

        contentView.addSubview(headerButton)
        headerButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(Layout.headerHeight)
        }

        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.left.equalToSuperview().offset(SCRXFrom(24))
            make.width.height.equalTo(SCRXFrom(16))
        }

        contentView.addSubview(headerActionsStackView)
        headerActionsStackView.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalToSuperview().offset(-SCRXFrom(20))
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.left.equalTo(arrowImageView.snp.right).offset(SCRXFrom(12))
            make.right.lessThanOrEqualTo(headerActionsStackView.snp.left).offset(-SCRXFrom(12))
        }

        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(headerButton.snp.bottom)
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview().offset(-kSafeAreaBottomHeight)
        }
        tableView.tableHeaderView = legendHeaderView
    }

    private func updateExpandedState(animated: Bool) {
        let targetHeight = isExpanded ? Layout.expandedHeight : Layout.collapsedHeight
        heightConstraint?.update(offset: targetHeight)
        tableView.isHidden = !isExpanded
        arrowImageView.image = UIImage(named: isExpanded ? "arrow_down" : "arrow_up")

        let animations = { [weak self] in
            if let superview = self?.superview {
                superview.layoutIfNeeded()
            }
        }

        if animated {
            UIView.animate(withDuration: 0.25, animations: animations)
        } else {
            animations()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTableHeaderFrame()
    }

    private func updateTableHeaderFrame() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let targetHeight = legendHeaderView.intrinsicContentSize.height
        if legendHeaderView.frame.width != width || legendHeaderView.frame.height != targetHeight {
            legendHeaderView.frame = CGRect(x: 0, y: 0, width: width, height: targetHeight)
            tableView.tableHeaderView = legendHeaderView
        }
    }

    private func makeHeaderButton(
        image: UIImage?,
        tintColor: UIColor?,
        action: Selector,
        filled: Bool = false
    ) -> UIButton {
        let button = UIButton(type: .custom)
        button.snp.makeConstraints { make in
            make.width.height.equalTo(SCRXFrom(16))
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
        cell.configure(with: .init(title: item.title, subtitle: item.subtitle, value: item.value))
        return cell
    }
}
