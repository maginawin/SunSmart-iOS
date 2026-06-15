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
            .associatedGroups,
            .eventOccursHeader,
            .fireAlarmBrightness,
            .powerLossBrightness,
            .triggerInterval,
            .eventEndsHeader,
            .restoreAction
        ]

        if state.restoreActionType == .setBrightness {
            rows.append(.restoreBrightness)
        }

        rows.append(contentsOf: [.restoreResuming, .restoreSendCount])

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
        case .associatedGroups:
            let cell: EmerFireSelectionCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "Associate With Group(s)".localizedString, value: state.groupText(), cardPosition: cardPosition(for: row))
            return cell
        case .eventOccursHeader:
            let cell: EmerFireInfoCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "When The Emergency Event Occurs", lines: [], cardPosition: cardPosition(for: row))
            return cell
        case .eventEndsHeader:
            let cell: EmerFireInfoCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(title: "When The Emergency Event Ends", lines: [], cardPosition: cardPosition(for: row))
            return cell
        case .restoreAction:
            let cell: EmerFireRestoreActionCell = tableView.dequeueReusableCell(for: indexPath)
            cell.configure(options: restoreActionOptions, selectedType: state.restoreActionType, cardPosition: cardPosition(for: row))
            cell.actionDidChange = { [weak self] actionType in
                guard let self else { return }
                self.state.updateRestoreActionType(actionType)
                self.tableView.reloadData()
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
        case .associatedGroups:
            let controller = PJDeviceGroupSelectionViewController(
                context: .init(
                    title: "select_group(s)".localizedString,
                    groups: DeviceEmerFireStore.shared.selectableGroups(),
                    selectedGroupAddresses: state.selectedGroupAddresses(),
                    disabledGroupAddresses: state.disabledAssociatedGroupAddresses(),
                    disabledSelectionTip: "Not selectable. This group is already associated with a device of the same type.".localizedString
                )
            ) { [weak self] addresses in
                self?.state.updateSelectedGroupAddresses(addresses)
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
             .associatedGroups,
             .eventOccursHeader,
             .eventEndsHeader,
             .restoreAction,
             .powerLossBrightness,
             .fireAlarmBrightness,
             .triggerInterval,
             .restoreBrightness,
             .restoreResuming,
             .restoreSendCount:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < visibleRows.count else { return SCRYFrom(84) }
        let row = visibleRows[indexPath.row]
        switch row {
        case .name:
            return SCRYFrom(80)
        case .reportToGateway:
            return SCRYFrom(56)
        case .associatedGroups:
            return SCRYFrom(78)
        case .eventOccursHeader, .eventEndsHeader:
            return SCRYFrom(58)
        case .restoreAction:
            return SCRYFrom(136)
        case .powerLossBrightness,
             .fireAlarmBrightness,
             .triggerInterval,
             .restoreBrightness,
             .restoreResuming,
             .restoreSendCount:
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

    private var restoreActionOptions: [LinkedEmerFireRestoreActionOption] {
        [
            .init(title: "Restore AUTO", type: .restoreAuto),
            .init(title: "Set Brightness to", type: .setBrightness),
            .init(title: "None", type: .none)
        ]
    }
}
