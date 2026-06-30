//
//  LinkedEmerFireEditVC+Table.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit
import SnapKit
import NordicSigMeshSDK

extension LinkedEmerFireEditVC: UITableViewDataSource, UITableViewDelegate {

    private var visibleRows: [LinkedEmerFireEditRow] {
        var rows: [LinkedEmerFireEditRow] = [
            .name,
            .reportToGateway,
            .associatedGroups,
            .emergencyMode,
            .eventOccursHeader
        ]
        if state.workingMode.showsFireAlarmEmergencyControls {
            rows.append(.fireAlarmBrightness)
        }
        if state.workingMode.showsPowerLossEmergencyControls {
            rows.append(.powerLossBrightness)
        }
        rows.append(contentsOf: [
            .triggerInterval,
            .eventEndsHeader,
            .restoreAction,
            .restoreTiming
        ])

        return rows
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.row < visibleRows.count else { return UITableViewCell() }
        let row = visibleRows[indexPath.row]

        switch row {
        case .name:
            let cell: EmerFireNameCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(name: state.deviceName, synced: state.isSynced || !shouldShowSyncStatus)
            cell.nameDidChange = { [weak self] name in self?.state.deviceName = name }
            cell.syncAction = { [weak self] in
                self?.openSyncForCurrentDevice()
            }
            return cell
        case .reportToGateway:
            let cell: EmerFireStatusTextCell = tableView.dequeueReusableCell(for: indexPath)
            let statusText = "efc_waiting_for_setup".localizedString
            let statusColor = RGB(247, 99, 95)
            let paragraphStyle = NSMutableParagraphStyle()
            let attributedStatusText = NSMutableAttributedString(
                string: statusText,
                attributes: [
                    .foregroundColor: statusColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .paragraphStyle: paragraphStyle
                ]
            )
            cell.configure(
                leftText: "Report To Gateway".localizedString,
                rightText: statusText,
                rightAttributedText: attributedStatusText,
                rightTextColor: statusColor,
                cardPosition: cardPosition(for: row)
            )
            cell.rightTapAction = {
                XWHUDManager.showTipHUD(statusText, isLineFeed: false)
            }
            return cell
        case .associatedGroups:
            let cell: EmerFireSelectionCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "Associate With Group(s)".localizedString, value: state.groupText(), cardPosition: cardPosition(for: row))
            return cell
        case .emergencyMode:
            let cell: EmerFireSelectionCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "efc_emergency_mode".localizedString, value: state.workingModeText(), cardPosition: cardPosition(for: row))
            return cell
        case .eventOccursHeader:
            let cell: EmerFireInfoCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(
                title: "efc_event_occurs_title".localizedString,
                lines: ["efc_event_occurs_tip".localizedString],
                cardPosition: cardPosition(for: row)
            )
            return cell
        case .eventEndsHeader:
            let cell: EmerFireInfoCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(
                title: "efc_event_ends_title".localizedString,
                lines: ["efc_event_ends_tip".localizedString],
                cardPosition: cardPosition(for: row)
            )
            return cell
        case .restoreAction:
            let cell: EmerFireRestoreActionCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(
                options: restoreActionOptions,
                selectedType: state.restoreActionType,
                brightness: state.restoreBrightness,
                brightnessRange: 0...100,
                cardPosition: cardPosition(for: row)
            )
            cell.actionDidChange = { [weak self] actionType in
                guard let self else { return }
                self.state.updateRestoreActionType(actionType)
                self.tableView.reloadData()
            }
            cell.brightnessDidChange = { [weak self] value in
                self?.state.setStepperValue(for: .restoreBrightness, value: value)
            }
            return cell
        case .restoreTiming:
            let cell: EmerFireDualStepperCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(
                firstRow: .restoreResuming,
                firstConfiguration: state.stepperConfiguration(for: .restoreResuming),
                secondRow: .restoreSendCount,
                secondConfiguration: state.stepperConfiguration(for: .restoreSendCount),
                cardPosition: cardPosition(for: row)
            )
            cell.valueDidChange = { [weak self] row, value in
                self?.state.setStepperValue(for: row, value: value)
            }
            return cell
        case .fireAlarmBrightness,
             .powerLossBrightness,
             .triggerInterval,
             .restoreBrightness,
             .restoreResuming,
             .restoreSendCount:
            let cell: EmerFireStepperCell = tableView.dequeueReusableCell(for: indexPath)
            let config = state.stepperConfiguration(for: row)
            cell.configure(title: config.title, fieldTitle: config.fieldTitle, value: config.value, range: config.range, suffix: config.suffix, cardPosition: cardPosition(for: row))
            cell.valueDidChange = { [weak self] value in
                guard let self else { return }
                self.state.setStepperValue(for: row, value: value)
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard indexPath.row < visibleRows.count else { return }
        let row = visibleRows[indexPath.row]
        switch row {
        case .associatedGroups:
            let controller = PJDeviceGroupSelectionViewController(
                context: .init(
                    title: "select_group(s)".localizedString,
                    groups: DeviceEmerFireStore.shared.selectableGroups(),
                    selectedGroupAddresses: state.selectedGroupAddresses(),
                    disabledGroupAddresses: state.disabledAssociatedGroupAddresses(),
                    disabledSelectionTip: "Not selectable. This group is already associated with a device of the same type.".localizedString,
                    switchControlPolicy: .nonEmptyGroup
                )
            ) { [weak self] addresses in
                self?.state.updateSelectedGroupAddresses(addresses)
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
            navigationController?.pushViewController(controller, animated: true)
        case .emergencyMode:
            showWorkingModeSelection(at: indexPath)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < visibleRows.count else { return 0 }
        let row = visibleRows[indexPath.row]
        switch row {
        case .name,
             .reportToGateway,
             .associatedGroups,
             .emergencyMode,
             .eventOccursHeader,
             .eventEndsHeader,
             .restoreAction,
             .powerLossBrightness,
             .fireAlarmBrightness,
             .triggerInterval,
             .restoreBrightness,
             .restoreResuming,
             .restoreSendCount,
             .restoreTiming:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < visibleRows.count else { return SCRYFrom(84) }
        let row = visibleRows[indexPath.row]
        switch row {
        case .name:
            return SCRYFrom(82)
        case .reportToGateway:
            return SCRYFrom(48)
        case .associatedGroups:
            return SCRYFrom(72)
        case .emergencyMode:
            return SCRYFrom(72)
        case .eventOccursHeader, .eventEndsHeader:
            return SCRYFrom(64)
        case .restoreAction:
            return state.restoreActionType == .setBrightness ? SCRYFrom(240) : SCRYFrom(148)
        case .restoreTiming:
            return SCRYFrom(276)
        case .powerLossBrightness,
             .fireAlarmBrightness,
             .triggerInterval,
             .restoreBrightness,
             .restoreResuming,
             .restoreSendCount:
            return SCRYFrom(156)
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }

    private func cardPosition(for row: LinkedEmerFireEditRow) -> EmerFireCardPosition {
        .single
    }

    private var restoreActionOptions: [LinkedEmerFireRestoreActionOption] {
        [
            .init(title: "efc_restore_auto".localizedString, type: .restoreAuto),
            .init(title: "linked_set_brightness_to".localizedString, type: .setBrightness),
            .init(title: "restore_none".localizedString, type: .none)
        ]
    }

    private func showWorkingModeSelection(at indexPath: IndexPath) {
        let window = UIApplication.shared.keyWindow()
        let anchorPoint: CGPoint
        if let cell = tableView.cellForRow(at: indexPath) {
            let frame = cell.convert(cell.bounds, to: window)
            anchorPoint = CGPoint(
                x: frame.maxX - SCRXFrom(220),
                y: frame.maxY + SCRYFrom(2)
            )
        } else {
            anchorPoint = CGPoint(
                x: SCREEN_WIDTH - SCRXFrom(236),
                y: kNavigationHeight
            )
        }

        EmergencyFireWorkingModeSelectView.show(
            anchorPoint: anchorPoint,
            modes: state.selectableWorkingModes,
            selectedMode: state.workingMode
        ) { [weak self] mode in
            guard let self else { return }
            self.state.updateWorkingMode(mode)
            self.tableView.reloadData()
        }
    }
}

private final class EmergencyFireWorkingModeSelectView: UIView {

    private enum Layout {
        static let menuWidth = SCRXFrom(220)
        static let rowHeight = SCRYFrom(45)
        static let horizontalInset = SCRXFrom(16)
        static let cornerRadius = SCRYFrom(12)
    }

    private let modes: [EmergencyFireWorkingMode]
    private let selectedMode: EmergencyFireWorkingMode
    private let selectionHandler: (EmergencyFireWorkingMode) -> Void

    private lazy var shadeView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))
        return view
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(102, 102, 102)
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = Layout.rowHeight
        tableView.showsVerticalScrollIndicator = false
        tableView.isScrollEnabled = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmergencyFireWorkingModeSelectCell.self, forCellReuseIdentifier: "cell")
        return tableView
    }()

    private init(
        anchorPoint: CGPoint,
        modes: [EmergencyFireWorkingMode],
        selectedMode: EmergencyFireWorkingMode,
        selectionHandler: @escaping (EmergencyFireWorkingMode) -> Void
    ) {
        self.modes = modes
        self.selectedMode = selectedMode
        self.selectionHandler = selectionHandler
        super.init(frame: UIScreen.main.bounds)
        setupUI(anchorPoint: anchorPoint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show(
        anchorPoint: CGPoint,
        modes: [EmergencyFireWorkingMode],
        selectedMode: EmergencyFireWorkingMode,
        selectionHandler: @escaping (EmergencyFireWorkingMode) -> Void
    ) {
        let view = EmergencyFireWorkingModeSelectView(
            anchorPoint: anchorPoint,
            modes: modes,
            selectedMode: selectedMode,
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

        let contentHeight = min(CGFloat(modes.count) * Layout.rowHeight, SCREEN_HEIGHT / 2)
        let left = min(
            max(Layout.horizontalInset, anchorPoint.x),
            SCREEN_WIDTH - Layout.menuWidth - Layout.horizontalInset
        )
        let maxTop = max(Layout.horizontalInset, SCREEN_HEIGHT - contentHeight - Layout.horizontalInset)
        let top = min(max(Layout.horizontalInset, anchorPoint.y), maxTop)

        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(left)
            make.top.equalTo(top)
            make.width.equalTo(Layout.menuWidth)
            make.height.equalTo(contentHeight)
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
}

extension EmergencyFireWorkingModeSelectView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        modes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! EmergencyFireWorkingModeSelectCell
        let mode = modes[indexPath.row]
        cell.configure(title: mode.localizedTitle, selected: mode == selectedMode)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectionHandler(modes[indexPath.row])
        dismiss()
    }
}

private final class EmergencyFireWorkingModeSelectCell: UITableViewCell {

    private let titleLabel = UILabel(text: nil, textColor: .white, fontSize: 14, fontWeight: .light)
    private let selectedBackground = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, selected: Bool) {
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        selectedBackground.isHidden = !selected
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
            make.right.lessThanOrEqualToSuperview().offset(-SCRXFrom(16))
        }
    }
}
