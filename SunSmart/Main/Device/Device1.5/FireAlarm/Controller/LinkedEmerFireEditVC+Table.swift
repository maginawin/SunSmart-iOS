//
//  LinkedEmerFireEditVC+Table.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

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
            showWorkingModeSelection()
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

    private func showWorkingModeSelection() {
        let actions = state.selectableWorkingModes.map { mode in
            SRAlertAction(title: mode.localizedTitle, actionHandler: { [weak self] _ in
                guard let self else { return }
                self.state.updateWorkingMode(mode)
                self.tableView.reloadData()
            })
        }
        SRAlertView(
            title: "efc_emergency_mode".localizedString,
            actions: actions + [.cancelAction]
        ).show()
    }
}
