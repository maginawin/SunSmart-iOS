//
//  LinkedEmerFireEditVC+Table.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit
import NordicSigMeshSDK

extension LinkedEmerFireEditVC: UITableViewDataSource, UITableViewDelegate {

    private var visibleRows: [LinkedEmerFireEditRow] {
        var rows: [LinkedEmerFireEditRow] = [
            .name,
            .reportToGateway,
            .powerLossEmergency
        ]

        if state.enablePowerLossEmergency {
            rows.append(contentsOf: [
                .powerLossGroups,
                .powerLossInstructions,
                .powerLossBrightness,
                .powerRestoreInstructions,
                .powerLossResuming,
                .powerLossSendCount
            ])
        }

        rows.append(.fireAlarmEmergency)

        if state.enableFireAlarmEmergency {
            rows.append(contentsOf: [
                .fireAlarmGroups,
                .fireAlarmInstructions,
                .fireAlarmBrightness,
                .fireAlarmStopInstructions,
                .fireAlarmResuming,
                .fireAlarmSendCount
            ])
        }

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
            cell.configure(name: state.deviceName, synced: state.isSynced)
            cell.nameDidChange = { [weak self] name in self?.state.deviceName = name }
            cell.syncAction = { [weak self] in
                self?.openSyncForCurrentDevice()
            }
            return cell
        case .reportToGateway:
            let cell: EmerFireStatusTextCell = tableView.dequeueReusableCell(for: indexPath)
            let statusText = "Waiting for setup"
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
        case .powerLossEmergency, .fireAlarmEmergency:
            let cell: EmerFireToggleCell = tableView.dequeueReusableCell(for: indexPath)
            let title: String
            let isOn: Bool
            switch row {
            case .powerLossEmergency:
                title = "Enable Power Loss Emergency".localizedString
                isOn = state.enablePowerLossEmergency
            default:
                title = "Enable Fire Alarm Emergency".localizedString
                isOn = state.enableFireAlarmEmergency
            }
            cell.configure(title: title, isOn: isOn, cardPosition: cardPosition(for: row))
            cell.switchValueDidChange = { [weak self] value in
                guard let self else { return }
                self.state.updateEmergencySelection(for: row, value: value)
                self.tableView.reloadData()
            }
            return cell
        case .powerLossGroups, .fireAlarmGroups:
            let cell: EmerFireSelectionCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "Associate With Group(s)".localizedString, value: state.groupText(for: row), cardPosition: cardPosition(for: row))
            return cell
        case .powerLossInstructions:
            let cell: EmerFireInfoCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "When normal power supply fails:", lines: state.powerLossInstructions, cardPosition: cardPosition(for: row))
            return cell
        case .powerRestoreInstructions:
            let cell: EmerFireInfoCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "When normal power is restored:", lines: state.powerRestoreInstructions, cardPosition: cardPosition(for: row))
            return cell
        case .fireAlarmInstructions:
            let cell: EmerFireInfoCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "When Fire Alarm Occurs:", lines: state.fireAlarmInstructions, cardPosition: cardPosition(for: row))
            return cell
        case .fireAlarmStopInstructions:
            let cell: EmerFireInfoCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "When Fire Alarm Stops:", lines: state.fireAlarmStopInstructions, cardPosition: cardPosition(for: row))
            return cell
        case .powerLossBrightness, .powerLossResuming, .powerLossSendCount, .fireAlarmBrightness, .fireAlarmResuming, .fireAlarmSendCount:
            let cell: EmerFireStepperCell = tableView.dequeueReusableCell(for: indexPath)
            let config = state.stepperConfiguration(for: row)
            cell.configure(title: config.title, value: config.value, range: config.range, suffix: config.suffix, cardPosition: cardPosition(for: row))
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
        case .powerLossGroups:
            let controller = PJDeviceGroupSelectionViewController(
                context: .init(
                    title: "select_group(s)".localizedString,
                    groups: DeviceEmerFireStore.shared.selectableGroups(),
                    selectedGroupAddresses: state.selectedGroupAddresses(for: row),
                    disabledGroupAddresses: state.disabledGroupAddresses(for: row),
                    disabledSelectionTip: "Not selectable. This group is already associated with a device of the same type."
                )
            ) { [weak self] addresses in
                self?.state.updateSelectedGroupAddresses(for: row, addresses: addresses)
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
            navigationController?.pushViewController(controller, animated: true)
        case .fireAlarmGroups:
            let controller = PJDeviceGroupSelectionViewController(
                context: .init(
                    title: "select_group(s)".localizedString,
                    groups: DeviceEmerFireStore.shared.selectableGroups(),
                    selectedGroupAddresses: state.selectedGroupAddresses(for: row),
                    disabledGroupAddresses: state.disabledGroupAddresses(for: row),
                    disabledSelectionTip: "Not selectable. This group is already associated with a device of the same type."
                )
            ) { [weak self] addresses in
                self?.state.updateSelectedGroupAddresses(for: row, addresses: addresses)
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
            navigationController?.pushViewController(controller, animated: true)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < visibleRows.count else { return 0 }
        let row = visibleRows[indexPath.row]
        switch row {
        case .name:
            return SCRYFrom(80)
        case .reportToGateway,
             .powerLossEmergency,
             .fireAlarmEmergency,
             .powerLossGroups,
             .fireAlarmGroups,
             .powerLossInstructions,
             .powerRestoreInstructions,
             .fireAlarmInstructions,
             .fireAlarmStopInstructions,
             .powerLossBrightness,
             .powerLossResuming,
             .powerLossSendCount,
             .fireAlarmBrightness,
             .fireAlarmResuming,
             .fireAlarmSendCount:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < visibleRows.count else { return SCRYFrom(84) }
        let row = visibleRows[indexPath.row]
        switch row {
        case .name:
            return SCRYFrom(80)
        case .reportToGateway, .powerLossEmergency, .fireAlarmEmergency:
            return SCRYFrom(56)
        case .powerLossGroups, .fireAlarmGroups:
            return SCRYFrom(78)
        case .powerLossInstructions, .powerRestoreInstructions, .fireAlarmInstructions, .fireAlarmStopInstructions:
            return SCRYFrom(110)
        case .powerLossBrightness, .powerLossResuming, .powerLossSendCount, .fireAlarmBrightness, .fireAlarmResuming, .fireAlarmSendCount:
            return SCRYFrom(84)
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNormalMagnitude
    }

    private func cardPosition(for row: LinkedEmerFireEditRow) -> EmerFireCardPosition {
        guard let index = visibleRows.firstIndex(of: row) else {
            return .single
        }

        let currentGroup = row.cardGroup
        let previousGroup = index > 0 ? visibleRows[index - 1].cardGroup : nil
        let nextGroup = index + 1 < visibleRows.count ? visibleRows[index + 1].cardGroup : nil

        let isFirstInGroup = previousGroup != currentGroup
        let isLastInGroup = nextGroup != currentGroup

        switch (isFirstInGroup, isLastInGroup) {
        case (true, true):
            return .single
        case (true, false):
            return .top
        case (false, true):
            return .bottom
        case (false, false):
            return .middle
        }
    }
}
