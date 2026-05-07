//
//  PJNGatewayWiFiDFUViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

final class PJNGatewayWiFiDFUViewModel {

    let node: Node
    private(set) var model: PJNGatewayWiFiDFUModel

    init(node: Node) {
        self.node = node
        self.model = .init(
            title: "firmware_version".localizedString,
            subtitle: "new_version_found".localizedString,
            newVersionTitle: "new_version".localizedString,
            newVersion: "1.2.0",
            packageSizeText: "2024.5KB",
            releaseDateText: "\("release_date".localizedString): Jun 22,2026",
            releaseNotes: [
                "ngateway_wifi_dfu_note_1".localizedString,
                "ngateway_wifi_dfu_note_2".localizedString,
                "ngateway_wifi_dfu_note_3".localizedString,
                "ngateway_wifi_dfu_note_4".localizedString
            ],
            isReleaseNotesExpanded: false,
            currentVersionTitle: "ngateway_wifi_dfu_current_version".localizedString,
            currentVersion: node.firmwareVersion ?? "--",
            status: .readyToUpgrade
        )
    }

    func cycleStatus() {
        switch model.status {
        case .readyToUpgrade:
            model = updatedModel(status: .updating(progress: 87, message: "ngateway_wifi_dfu_loading".localizedString))
        case .updating:
            model = updatedModel(status: .upgradeComplete(progress: 100, message: "ngateway_wifi_dfu_upgrade_complete".localizedString))
        case .upgradeComplete:
            model = updatedModel(status: .downloadFailed(progress: 87, message: "ngateway_wifi_dfu_download_failed".localizedString))
        case .downloadFailed:
            model = updatedModel(status: .upgradeFailed(progress: 87, message: "ngateway_wifi_dfu_upgrade_failed".localizedString))
        case .upgradeFailed:
            model = updatedModel(status: .readyToUpgrade)
        }
    }

    func toggleReleaseNotesExpanded() {
        model = updatedModel(isReleaseNotesExpanded: !model.isReleaseNotesExpanded)
    }

    private func updatedModel(status: PJNGatewayWiFiDFUStatus) -> PJNGatewayWiFiDFUModel {
        .init(
            title: model.title,
            subtitle: model.subtitle,
            newVersionTitle: model.newVersionTitle,
            newVersion: model.newVersion,
            packageSizeText: model.packageSizeText,
            releaseDateText: model.releaseDateText,
            releaseNotes: model.releaseNotes,
            isReleaseNotesExpanded: model.isReleaseNotesExpanded,
            currentVersionTitle: model.currentVersionTitle,
            currentVersion: model.currentVersion,
            status: status
        )
    }

    private func updatedModel(isReleaseNotesExpanded: Bool) -> PJNGatewayWiFiDFUModel {
        .init(
            title: model.title,
            subtitle: model.subtitle,
            newVersionTitle: model.newVersionTitle,
            newVersion: model.newVersion,
            packageSizeText: model.packageSizeText,
            releaseDateText: model.releaseDateText,
            releaseNotes: model.releaseNotes,
            isReleaseNotesExpanded: isReleaseNotesExpanded,
            currentVersionTitle: model.currentVersionTitle,
            currentVersion: model.currentVersion,
            status: model.status
        )
    }
}
