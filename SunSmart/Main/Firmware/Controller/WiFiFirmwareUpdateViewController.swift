//
//  WiFiFirmwareUpdateViewController.swift
//  SunSmart
//
//  Created by Codex on 2026/7/13.
//

import UIKit

final class WiFiFirmwareUpdateViewController: FirmwareVersionViewController {

    convenience init() {
        self.init(
            type: FirmwareUpdateTypeData(
                productId: 0x2721,
                targetVersion: "0.0.1",
                nodes: []
            )
        )
    }

    override var firmwarePageTitle: String {
        return "wifi_firmware_update".localizedString
    }

    override var firmwareRequestCustomId: String {
        return "wifi"
    }

    override var displayedCurrentTargetVersion: String? {
        return "0.0.1"
    }

    override var showsFirmwareDeleteButton: Bool {
        return false
    }

    override var showsBetaImportAction: Bool {
        return false
    }

    override var firmwarePrimaryActionTitle: String {
        return "wifi_firmware_upgrade".localizedString
    }

    @objc override func firmwarePrimaryAction() {
        XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
    }
}
