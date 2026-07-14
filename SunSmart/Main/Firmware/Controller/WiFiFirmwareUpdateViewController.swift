//
//  WiFiFirmwareUpdateViewController.swift
//  SunSmart
//
//  Created by Codex on 2026/7/13.
//

import UIKit
import NordicSigMeshSDK

final class WiFiFirmwareUpdateViewController: FirmwareVersionViewController {

    private enum CurrentVersionState {
        case loading
        case loaded(String)
        case failed
    }

    private let node: Node
    private var currentVersionState: CurrentVersionState = .loading
    private var currentVersionRequestID: Int = 0

    init(node: Node) {
        self.node = node
        super.init(
            type: FirmwareUpdateTypeData(
                productId: 0x2721,
                targetVersion: nil,
                nodes: [node]
            )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var firmwarePageTitle: String {
        return "wifi_firmware_update".localizedString
    }

    override var firmwareRequestCustomId: String {
        return "wifi"
    }

    override var currentVersionTitleText: String {
        return "current_version".localizedString
    }

    override var currentVersionDisplayText: String {
        switch currentVersionState {
        case .loading:
            return "Loading...".localizedString
        case .loaded(let version):
            return version
        case .failed:
            return "failed".localizedString
        }
    }

    override var displayedCurrentTargetVersion: String? {
        guard case .loaded(let version) = currentVersionState else { return nil }
        return version
    }

    override var createsUIBeforeCloudRequest: Bool {
        return true
    }

    override var requiresAdditionalFirmwareReload: Bool {
        guard case .failed = currentVersionState else { return false }
        return true
    }

    override var resetsServerFirmwareBeforeCloudRequest: Bool {
        return true
    }

    override func isNewServerFirmwareAvailable(_ serverData: FirmwareServerData) -> Bool {
        guard let displayedCurrentTargetVersion,
              let currentVersion = normalizedVersion(displayedCurrentTargetVersion),
              let newVersion = normalizedVersion(serverData.version) else {
            return false
        }
        return newVersion.compare(currentVersion, options: .numeric) == .orderedDescending
    }

    override func shouldShowServerFirmwareDetails(_ serverData: FirmwareServerData) -> Bool {
        if case .failed = currentVersionState {
            return true
        }
        return isNewServerFirmwareAvailable(serverData)
    }

    override func loadAdditionalFirmwareData() {
        currentVersionRequestID += 1
        let requestID = currentVersionRequestID
        currentVersionState = .loading
        refreshFirmwareUI()

        guard node.state,
              node.isKeybindComplete,
              let vendorModel = node.sunricherVendorModel else {
            currentVersionState = .failed
            refreshFirmwareUI()
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .wifiGatewayFirmwareVersion),
            model: vendorModel,
            timeout: 10
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self, self.currentVersionRequestID == requestID else { return }
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayFirmwareVersion(.success(let version)) = status.status.parameters else {
                    self.currentVersionState = .failed
                    self.refreshFirmwareUI()
                    return
                }
                self.currentVersionState = .loaded(version)
                self.refreshFirmwareUI()
            }
        }
    }

    private func normalizedVersion(_ version: String) -> String? {
        let normalized: String
        if version.first == "v" || version.first == "V" {
            normalized = String(version.dropFirst())
        } else {
            normalized = version
        }
        return normalized.isEmpty ? nil : normalized
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
