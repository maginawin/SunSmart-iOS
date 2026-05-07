//
//  PJNGatewayWiFiDFUModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation

struct PJNGatewayWiFiDFUModel {
    let title: String
    let subtitle: String
    let newVersionTitle: String
    let newVersion: String
    let packageSizeText: String
    let releaseDateText: String
    let releaseNotes: [String]
    let isReleaseNotesExpanded: Bool
    let currentVersionTitle: String
    let currentVersion: String
    let status: PJNGatewayWiFiDFUStatus
}

enum PJNGatewayWiFiDFUStatus {
    case readyToUpgrade
    case updating(progress: Int, message: String)
    case upgradeComplete(progress: Int, message: String)
    case downloadFailed(progress: Int, message: String)
    case upgradeFailed(progress: Int, message: String)

    var progress: Int {
        switch self {
        case .readyToUpgrade:
            return 0
        case .updating(let progress, _),
             .upgradeComplete(let progress, _),
             .downloadFailed(let progress, _),
             .upgradeFailed(let progress, _):
            return progress
        }
    }

    var message: String {
        switch self {
        case .readyToUpgrade:
            return ""
        case .updating(_, let message),
             .upgradeComplete(_, let message),
             .downloadFailed(_, let message),
             .upgradeFailed(_, let message):
            return message
        }
    }

    var actionTitle: String {
        switch self {
        case .readyToUpgrade:
            return "ngateway_wifi_dfu_upgrade".localizedString.uppercased()
        case .updating, .upgradeComplete:
            return "cancel".localizedString.uppercased()
        case .downloadFailed, .upgradeFailed:
            return "ngateway_wifi_dfu_upgrade_again".localizedString.uppercased()
        }
    }
}
