//
//  LinkedEmerFireEditVC+Table.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

extension LinkedEmerFireEditVC: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        LinkedEmerFireEditRow.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let row = LinkedEmerFireEditRow(rawValue: indexPath.row) else { return UITableViewCell() }

        switch row {
        case .name:
            let cell: EmerFireNameCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(name: state.deviceName, synced: state.isSynced)
            cell.nameDidChange = { [weak self] name in self?.state.deviceName = name }
            cell.syncAction = {
                XWHUDManager.showTipHUD("Devices not synced.", isLineFeed: false)
            }
            return cell
        case .reportToGateway:
            let cell: EmerFireStatusTextCell = tableView.dequeueReusableCell(for: indexPath)
            let statusText = "Waiting for setup"
            let statusColor = RGB(247, 99, 95)
            cell.configure(
                leftText: "Report To Gateway".localizedString,
                rightText: statusText,
                rightTextColor: statusColor,
                cardPosition: cardPosition(for: row)
            )
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
                switch row {
                case .powerLossEmergency: self.state.enablePowerLossEmergency = value
                case .fireAlarmEmergency: self.state.enableFireAlarmEmergency = value
                default: break
                }
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
        guard let row = LinkedEmerFireEditRow(rawValue: indexPath.row) else { return }
        switch row {
        case .powerLossGroups:
            let controller = LinkedEmerFireGroupSelectionVC(
                options: state.groupOptions,
                selectedIndex: state.powerLossGroupIndex
            ) { [weak self] selectedIndex in
                self?.state.powerLossGroupIndex = selectedIndex
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
            navigationController?.pushViewController(controller, animated: true)
        case .fireAlarmGroups:
            let controller = LinkedEmerFireGroupSelectionVC(
                options: state.groupOptions,
                selectedIndex: state.fireAlarmGroupIndex
            ) { [weak self] selectedIndex in
                self?.state.fireAlarmGroupIndex = selectedIndex
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
            navigationController?.pushViewController(controller, animated: true)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let row = LinkedEmerFireEditRow(rawValue: indexPath.row) else { return 0 }
        switch row {
        case .name:
            return SCRYFrom(92)
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
        guard let row = LinkedEmerFireEditRow(rawValue: indexPath.row) else { return SCRYFrom(84) }
        switch row {
        case .name:
            return SCRYFrom(92)
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
        switch row {
        case .name, .reportToGateway:
            return .single
        case .powerLossEmergency, .fireAlarmEmergency:
            return .top
        case .powerLossSendCount, .fireAlarmSendCount:
            return .bottom
        case .powerLossGroups, .powerLossInstructions, .powerLossBrightness, .powerRestoreInstructions, .powerLossResuming:
            return .middle
        case .fireAlarmGroups, .fireAlarmInstructions, .fireAlarmBrightness, .fireAlarmStopInstructions, .fireAlarmResuming:
            return .middle
        }
    }
}
