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
    private lazy var dfuCoordinator = WiFiFirmwareDFUCoordinator(node: node)
    private lazy var updatingView = WiFiFirmwareUpdatingView()
    private var updatingState: WiFiFirmwareUpdatingState?
    private var primaryAction: WiFiFirmwarePrimaryAction = .upgrade
    private var coordinatorActive = false

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

    override func viewDidLoad() {
        bindCoordinator()
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        activateCoordinatorIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        coordinatorActive = false
        dfuCoordinator.deactivate()
        XWHUDManager.hideInView(with: view)
    }

    override var firmwarePageTitle: String {
        return "wifi_firmware_update".localizedString
    }

    override var firmwareRequestCustomId: String {
        return "wifi"
    }

    override func normalizedServerFirmwareVersion(_ rawVersion: String) -> String {
        return (try? WiFiFirmwareDFUMetadataBuilder.firmwareID(version: rawVersion)) ?? rawVersion
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

    override var usesScrollableFirmwareContent: Bool { true }

    override var additionalFirmwareContentTopSpacing: CGFloat { 32 }

    override var additionalFirmwareContentHorizontalInset: CGFloat { 36 }

    override func makeAdditionalFirmwareContentView() -> UIView? {
        return updatingView
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
        if coordinatorActive {
            dfuCoordinator.refresh()
        } else {
            activateCoordinatorIfNeeded()
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

    override func applyAdditionalFirmwareUIState() {
        guard let updatingState else {
            primaryAction = .upgrade
            setAdditionalFirmwareContentHidden(true)
            let isEnabled: Bool
            if case .loaded = currentVersionState, let serverData = type.serverData {
                isEnabled = isNewServerFirmwareAvailable(serverData)
            } else {
                isEnabled = false
            }
            updateFirmwarePrimaryAction(
                titleKey: "wifi_firmware_upgrade",
                isEnabled: isEnabled
            )
            return
        }

        updatingView.configure(state: updatingState)
        setAdditionalFirmwareContentHidden(false)
        let presentation = primaryActionPresentation(for: updatingState)
        primaryAction = presentation.action
        updateFirmwarePrimaryAction(
            titleKey: presentation.titleKey,
            isEnabled: presentation.isEnabled
        )
    }

    @objc override func firmwarePrimaryAction() {
        switch primaryAction {
        case .upgrade, .retry:
            guard let serverData = type.serverData else { return }
            dfuCoordinator.start(filename: serverData.filename, version: serverData.version)
        case .done:
            dfuCoordinator.consumeSuccess()
        case .cancelDisabled:
            break
        }
    }

    private func bindCoordinator() {
        dfuCoordinator.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handleCoordinatorEvent(event)
            }
        }
    }

    private func activateCoordinatorIfNeeded() {
        guard !coordinatorActive else { return }
        coordinatorActive = true
        dfuCoordinator.activate()
    }

    private func handleCoordinatorEvent(_ event: WiFiFirmwareDFUCoordinator.Event) {
        switch event {
        case .loadingStart(let loading):
            if loading {
                XWHUDManager.showCustomHUD(withMessage: "Loading...".localizedString, view: view)
            } else {
                XWHUDManager.hideInView(with: view)
            }
        case .currentVersionLoading:
            currentVersionState = .loading
            refreshFirmwareUI()
        case .currentVersion(let version), .confirmedVersion(let version):
            currentVersionState = .loaded(version)
            refreshFirmwareUI()
        case .currentVersionFailed:
            currentVersionState = .failed
            refreshFirmwareUI()
        case .updateState(let state):
            updatingState = state
            refreshFirmwareUI()
        case .idle:
            updatingState = nil
            refreshFirmwareUI()
        }
    }

    private func primaryActionPresentation(
        for state: WiFiFirmwareUpdatingState
    ) -> WiFiFirmwarePrimaryActionPresentation {
        switch state.kind {
        case .downloading, .updating, .communicationUnknown:
            return .init(titleKey: "cancel", isEnabled: false, action: .cancelDisabled)
        case .connFailedTimeout, .connFailedServerUnable, .downloadFailed, .upgradeFailed:
            return .init(titleKey: "wifi_firmware_upgrade_again", isEnabled: true, action: .retry)
        case .cancelled:
            return .init(titleKey: "wifi_firmware_upgrade_again", isEnabled: true, action: .retry)
        case .upgradeComplete:
            return .init(titleKey: "done", isEnabled: true, action: .done)
        }
    }
}
