//
//  DeviceAddTargetSelectView.swift
//  SunSmart
//
//  Created by Codex on 2026/5/12.
//

import UIKit
import SnapKit
import NordicSigMeshSDK

enum DeviceAddTargetSelection {
    case space
    case group(Group)
    case batteryPowerSwitch(PJEightKeySwitchData)
    case acPowerSwitch(PJEightKeySwitchData)
    case emergencyFire(DeviceEmerFireData)
    case dongle(DeviceDongleData)
}

final class DeviceAddTargetSelectView: UIView {

    private enum Row {
        case space
        case header(SectionKind)
        case group(Group)
        case batteryPowerSwitch(PJEightKeySwitchData)
        case acPowerSwitch(PJEightKeySwitchData)
        case emergencyFire(DeviceEmerFireData)
        case dongle(DeviceDongleData)
    }

    private enum SectionKind: CaseIterable {
        case group
        case batteryPowerSwitch
        case acPowerSwitch
        case emergencyFire
        case dongle

        var title: String {
            switch self {
            case .group:
                return "\("group".localizedString):"
            case .batteryPowerSwitch:
                return "Battery Power Switch:"
            case .acPowerSwitch:
                return "AC Power Switch:"
            case .emergencyFire:
                return "\("Emergency Controller".localizedString):"
            case .dongle:
                return "\("dongle".localizedString):"
            }
        }
    }

    private let groups: [Group]
    private let batteryPowerSwitches: [PJEightKeySwitchData]
    private let acPowerSwitches: [PJEightKeySwitchData]
    private let emergencyFireDevices: [DeviceEmerFireData]
    private let dongles: [DeviceDongleData]
    private let selectedTarget: DeviceAddTargetSelection
    private let selectionHandler: (DeviceAddTargetSelection) -> Void

    private var expandedSections: Set<SectionKind> = Set(SectionKind.allCases)
    private var rows: [Row] = []
    private var contentHeightConstraint: Constraint?

    private lazy var shadeView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))
        return view
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(102, 102, 102)
        view.layer.cornerRadius = SCRYFrom(12)
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(45)
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TargetCell.self, forCellReuseIdentifier: "cell")
        return tableView
    }()

    init(
        anchorPoint: CGPoint,
        groups: [Group],
        batteryPowerSwitches: [PJEightKeySwitchData],
        acPowerSwitches: [PJEightKeySwitchData],
        emergencyFireDevices: [DeviceEmerFireData],
        dongles: [DeviceDongleData],
        selectedTarget: DeviceAddTargetSelection,
        selectionHandler: @escaping (DeviceAddTargetSelection) -> Void
    ) {
        self.groups = groups
        self.batteryPowerSwitches = batteryPowerSwitches
        self.acPowerSwitches = acPowerSwitches
        self.emergencyFireDevices = emergencyFireDevices
        self.dongles = dongles
        self.selectedTarget = selectedTarget
        self.selectionHandler = selectionHandler
        super.init(frame: UIScreen.main.bounds)
        setupUI(anchorPoint: anchorPoint)
        reloadRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show(
        anchorPoint: CGPoint,
        groups: [Group],
        batteryPowerSwitches: [PJEightKeySwitchData],
        acPowerSwitches: [PJEightKeySwitchData],
        emergencyFireDevices: [DeviceEmerFireData],
        dongles: [DeviceDongleData],
        selectedTarget: DeviceAddTargetSelection,
        selectionHandler: @escaping (DeviceAddTargetSelection) -> Void
    ) {
        let view = DeviceAddTargetSelectView(
            anchorPoint: anchorPoint,
            groups: groups,
            batteryPowerSwitches: batteryPowerSwitches,
            acPowerSwitches: acPowerSwitches,
            emergencyFireDevices: emergencyFireDevices,
            dongles: dongles,
            selectedTarget: selectedTarget,
            selectionHandler: selectionHandler
        )
        UIApplication.shared.keyWindow().addSubview(view)
        view.showAnimation()
    }

    private func setupUI(anchorPoint: CGPoint) {
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let menuWidth = SCRXFrom(220)
        let left = min(max(SCRXFrom(16), anchorPoint.x), SCREEN_WIDTH - menuWidth - SCRXFrom(16))
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(left)
            make.top.equalTo(anchorPoint.y)
            make.width.equalTo(menuWidth)
            contentHeightConstraint = make.height.equalTo(SCRYFrom(45)).constraint
        }

        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func showAnimation() {
        contentView.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.contentView.alpha = 1
        }
    }

    @objc private func dismiss() {
        UIView.animate(withDuration: 0.2) {
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    private func reloadRows() {
        rows = [.space]
        appendRows(for: .group, itemsIsEmpty: groups.isEmpty)
        if expandedSections.contains(.group) {
            rows.append(contentsOf: groups.map { .group($0) })
        }
        appendRows(for: .batteryPowerSwitch, itemsIsEmpty: batteryPowerSwitches.isEmpty)
        if expandedSections.contains(.batteryPowerSwitch) {
            rows.append(contentsOf: batteryPowerSwitches.map { .batteryPowerSwitch($0) })
        }
        appendRows(for: .acPowerSwitch, itemsIsEmpty: acPowerSwitches.isEmpty)
        if expandedSections.contains(.acPowerSwitch) {
            rows.append(contentsOf: acPowerSwitches.map { .acPowerSwitch($0) })
        }
        appendRows(for: .emergencyFire, itemsIsEmpty: emergencyFireDevices.isEmpty)
        if expandedSections.contains(.emergencyFire) {
            rows.append(contentsOf: emergencyFireDevices.map { .emergencyFire($0) })
        }
        appendRows(for: .dongle, itemsIsEmpty: dongles.isEmpty)
        if expandedSections.contains(.dongle) {
            rows.append(contentsOf: dongles.map { .dongle($0) })
        }

        let maxHeight = SCREEN_HEIGHT / 2
        let height = min(CGFloat(rows.count) * tableView.rowHeight, maxHeight)
        contentHeightConstraint?.update(offset: height)
        tableView.isScrollEnabled = CGFloat(rows.count) * tableView.rowHeight > maxHeight
        tableView.reloadData()
    }

    private func appendRows(for section: SectionKind, itemsIsEmpty: Bool) {
        guard !itemsIsEmpty else { return }
        rows.append(.header(section))
    }

    private func isSelected(_ row: Row) -> Bool {
        switch (row, selectedTarget) {
        case (.space, .space):
            return true
        case (.group(let lhs), .group(let rhs)):
            return lhs.address == rhs.address
        case (.batteryPowerSwitch(let lhs), .batteryPowerSwitch(let rhs)):
            return lhs.id == rhs.id
        case (.acPowerSwitch(let lhs), .acPowerSwitch(let rhs)):
            return lhs.id == rhs.id
        case (.emergencyFire(let lhs), .emergencyFire(let rhs)):
            return lhs.id == rhs.id
        case (.dongle(let lhs), .dongle(let rhs)):
            return lhs.id == rhs.id
        default:
            return false
        }
    }

    private func title(for row: Row) -> String {
        switch row {
        case .space:
            return "Space"
        case .header(let section):
            return section.title
        case .group(let group):
            return group.name
        case .batteryPowerSwitch(let switchData):
            return switchData.name
        case .acPowerSwitch(let switchData):
            return switchData.name
        case .emergencyFire(let device):
            return device.name
        case .dongle(let dongle):
            return dongle.name
        }
    }
}

extension DeviceAddTargetSelectView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! TargetCell
        let isHeader: Bool
        let isExpanded: Bool
        if case .header(let section) = row {
            isHeader = true
            isExpanded = expandedSections.contains(section)
        } else {
            isHeader = false
            isExpanded = false
        }
        cell.configure(title: title(for: row), isHeader: isHeader, isExpanded: isExpanded, isSelected: isSelected(row))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = rows[indexPath.row]
        switch row {
        case .space:
            selectionHandler(.space)
            dismiss()
        case .header(let section):
            if expandedSections.contains(section) {
                expandedSections.remove(section)
            } else {
                expandedSections.insert(section)
            }
            reloadRows()
        case .group(let group):
            selectionHandler(.group(group))
            dismiss()
        case .batteryPowerSwitch(let switchData):
            selectionHandler(.batteryPowerSwitch(switchData))
            dismiss()
        case .acPowerSwitch(let switchData):
            selectionHandler(.acPowerSwitch(switchData))
            dismiss()
        case .emergencyFire(let device):
            selectionHandler(.emergencyFire(device))
            dismiss()
        case .dongle(let dongle):
            selectionHandler(.dongle(dongle))
            dismiss()
        }
    }
}

private final class TargetCell: UITableViewCell {

    private let titleLabel = UILabel(text: nil, textColor: .white, fontSize: 14, fontWeight: .light)
    private let arrowView = UIImageView()
    private let selectedBackground = UIView()
    private let lineView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isHeader: Bool, isExpanded: Bool, isSelected: Bool) {
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        arrowView.isHidden = !isHeader
        arrowView.image = UIImage(systemName: isExpanded ? "chevron.down" : "chevron.right")
        selectedBackground.isHidden = isHeader || !isSelected
        lineView.isHidden = !isHeader
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        selectedBackground.backgroundColor = RGB(216, 216, 216, 0.1)
        selectedBackground.layer.cornerRadius = SCRYFrom(5)
        contentView.addSubview(selectedBackground)
        selectedBackground.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(8))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(4))
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualToSuperview().offset(-SCRXFrom(42))
        }

        arrowView.tintColor = RGB(180, 180, 180)
        arrowView.contentMode = .scaleAspectFit
        contentView.addSubview(arrowView)
        arrowView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(16))
        }

        lineView.backgroundColor = RGB(255, 255, 255, 0.12)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(8))
            make.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }
}
