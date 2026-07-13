//
//  WiFiGatewayViewController.swift
//  SunSmart
//

import UIKit
import NordicSigMeshSDK

final class WiFiGatewayViewController: GatewayViewController {

    private enum NetworkCredentialSource: Equatable {
        case gateway
        case phone
        case localClear
    }

    private enum PendingNetworkResultHUD {
        case success
        case failure
    }

    private enum WiFiRequestOrigin {
        case automatic
        case userInitiated
    }

    private struct ActiveWiFiRequest {
        let id: Int
        let origin: WiFiRequestOrigin
    }

    private struct WiFiHeaderStatus {
        let iconName: String
        let localizedStatusKey: String

        static let excellent = WiFiHeaderStatus(iconName: "wifi_excellent", localizedStatusKey: "wifi_status_excellent")
        static let good = WiFiHeaderStatus(iconName: "wifi_good", localizedStatusKey: "wifi_status_good")
        static let poor = WiFiHeaderStatus(iconName: "wifi_poor", localizedStatusKey: "wifi_status_poor")
        static let bad = WiFiHeaderStatus(iconName: "wifi_bad", localizedStatusKey: "wifi_status_bad")
        static let noSignal = WiFiHeaderStatus(iconName: "wifi_no_signal", localizedStatusKey: "wifi_status_no_signal")
        static let notConnected = WiFiHeaderStatus(iconName: "wifi_not_connected", localizedStatusKey: "wifi_status_not_connected")
        static let notConfigured = WiFiHeaderStatus(iconName: "wifi_not_connected", localizedStatusKey: "not_configured")
    }

    private weak var wifiHeaderView: GatewayInformationHeaderView?
    private var networkSSID: String = ""
    private var networkPassword: String = ""
    private var networkCredentialSource: NetworkCredentialSource = .localClear
    private var isNetworkConnectivityVisible: Bool = false
    private var isNetworkPasswordVisible: Bool = false
    private var networkConnectState: GatewayNetworkConnectivityCell.ConnectState = .disabled
    private var isNetworkRefreshInProgress: Bool = false
    private var networkConnectTimer: Timer?
    private var wifiRSSIStatusTimer: Timer?
    private var networkConnectionStartedAt: Date?
    private var shouldRefreshSSIDWhenActive: Bool = false
    private var isNetworkPageVisible: Bool = false
    private var pendingNetworkResultHUD: PendingNetworkResultHUD?
    private var networkOperationID: Int = 0
    private var nextWiFiRequestID: Int = 0
    private var activeWiFiRequest: ActiveWiFiRequest?
    private var pendingGatewayRecoveryAction: (() -> Void)?
    private let connectionPollInterval: TimeInterval = 2
    private let wifiRSSIStatusPollDelay: TimeInterval = 5
    private let wifiRSSIStatusRequestTimeout: TimeInterval = 2
    private let connectionPollTimeout: TimeInterval = 60
    private let wifiPasswordCacheKey = "wifi_gateway_saved_passwords_by_ssid"
    private let showsDiagnosisMenuItem = false

    override var supportsAPNConfiguration: Bool {
        return false
    }

    override var supportsGatewaySignalRefresh: Bool {
        return false
    }

    override var sections: [SectionType] {
        var sections = super.sections.filter { $0 != .info }
        guard isNetworkConnectivityVisible, let nameIndex = sections.firstIndex(of: .name) else {
            return sections
        }
        sections.insert(.networkConnectivity, at: sections.index(after: nameIndex))
        return sections
    }

    override var infoTypes: [InfoCellType] {
        return []
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        isNetworkPageVisible = true
        showPendingNetworkResultHUDIfNeeded()
        guard node.isKeybindComplete else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        if networkConnectState == .connected {
            startWiFiRSSIStatusRefresh()
        } else if node.state,
                  !isNetworkOperationInProgress,
                  !isWiFiRequestInProgress,
                  !isNetworkConnectivityVisible {
            loadNetworkConnectivityFromGateway()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isNetworkPageVisible = false
        stopWiFiRSSIStatusRefresh()
        if isMovingFromParent || navigationController?.isBeingDismissed == true || isBeingDismissed {
            stopNetworkConnectionPolling()
            cancelPendingGatewayRecovery()
        }
    }

    override func closeGatewayPage() {
        cancelPendingGatewayRecovery()
        super.closeGatewayPage()
    }

    override func configureNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(closeAction)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(moreClick)
        )
    }

    override func showConfiguredBottomActions() {
        bottomView.isHidden = false
        bottomView.showSaveOnlyUI()
    }

    override func showRepairBottomActions() {
        bottomView.isHidden = true
    }

    override func registerAdditionalGatewayCells(in tableView: UITableView) {
        tableView.register(GatewayNetworkConnectivityCell.classForCoder(), forCellReuseIdentifier: GatewayNetworkConnectivityCell.reuseIdentifier)
    }

    override func networkConnectivityCellHeight() -> CGFloat {
        return SCRYFrom(180)
    }

    override func makeGatewayInformationHeaderView(frame: CGRect) -> GatewayInformationHeaderView {
        let headerView = super.makeGatewayInformationHeaderView(frame: frame)
        headerView.setGatewayStateStyle(.sigMesh)
        headerView.setWiFiStatusVisible(true)
        headerView.updateWiFiStatus(iconName: "wifi_not_connected", status: "wifi_status_not_connected".localizedString)
        wifiHeaderView = headerView
        return headerView
    }

    override func configureNetworkConnectivityCell(_ cell: GatewayNetworkConnectivityCell) {
        let isOperating = !canConfigureCurrentGateway || isNetworkOperationInProgress || isWiFiRequestInProgress
        cell.update(
            ssid: networkSSID,
            password: networkPassword,
            passwordVisible: isNetworkPasswordVisible,
            connectState: networkConnectState,
            showsSSIDClearButton: shouldShowSSIDClearButton(),
            canSelectWiFi: !isOperating,
            canRefresh: !isOperating && !isNetworkRefreshInProgress,
            isRefreshing: isNetworkRefreshInProgress,
            canEditSSID: canEditNetworkSSID(),
            canEditPassword: canEditNetworkPassword(),
            canTogglePasswordVisibility: canToggleNetworkPasswordVisibility()
        )
        cell.selectWiFiCallback = { [weak self] in
            self?.showChangeWiFiAlert()
        }
        cell.refreshCallback = { [weak self] in
            self?.refreshNetworkConnectivity()
        }
        cell.ssidClearCallback = { [weak self] in
            self?.clearNetworkSSIDLocally()
        }
        cell.ssidChangedCallback = { [weak self] ssid in
            self?.updateNetworkSSID(ssid) ?? .disabled
        }
        cell.passwordChangedCallback = { [weak self] password in
            self?.updateNetworkPassword(password) ?? .disabled
        }
        cell.lockedEditCallback = { [weak self] in
            self?.showDisconnectFirstTip()
        }
        cell.togglePasswordVisibilityCallback = { [weak self] in
            self?.toggleNetworkPasswordVisibility()
        }
        cell.connectActionCallback = { [weak self] in
            self?.networkConnectButtonAction()
        }
    }

    override func gatewayOnlineStateDidUpdate(_ isOnline: Bool) {
        if !isOnline {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        guard node.isKeybindComplete else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        guard !isNetworkOperationInProgress, !isWiFiRequestInProgress else { return }
        loadNetworkConnectivityFromGateway()
    }

    override func performGatewayRepair() {
        prepareForGatewayRecovery { [weak self] in
            self?.resync(trigger: .repair)
        }
    }

    override func performServerAuthorization() {
        prepareForGatewayRecovery { [weak self] in
            self?.recoverServerInformation()
        }
    }

    override func prepareForGatewayRecovery(_ completion: @escaping () -> Void) {
        guard canConfigureCurrentGateway else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard node.state else {
            XWHUDManager.showErrorTipHUD("device_offline_message".localizedString)
            return
        }
        guard !isNetworkOperationInProgress,
              !isNetworkRefreshInProgress,
              activeWiFiRequest?.origin != .userInitiated else {
            XWHUDManager.showTipHUD("wifi_gateway_wait_current_operation".localizedString, isLineFeed: true)
            return
        }

        stopWiFiRSSIStatusRefresh()
        guard activeWiFiRequest == nil else {
            guard pendingGatewayRecoveryAction == nil else { return }
            pendingGatewayRecoveryAction = completion
            pendingNetworkResultHUD = nil
            XWHUDManager.showCustomHUD(withMessage: "preparing_device_sync".localizedString, view: view)
            return
        }
        completion()
    }

    deinit {
        stopNetworkConnectionPolling()
        stopWiFiRSSIStatusRefresh()
        pendingGatewayRecoveryAction = nil
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func moreClick() {
        var items: [MenuPopView.MenuItem] = []
        items.append(.init(icon: UIImage(named: "menu_wifi_dfu"), title: "wifi_dfu".localizedString, hideAnimation: false, performsActionAfterDismiss: true, tapItemBack: { [weak self] _ in
            guard let self else { return }
            let controller = WiFiFirmwareUpdateViewController()
            self.navigationController?.pushViewController(controller, animated: true)
        }))
        if canConfigureCurrentGateway {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                self?.deleteBtnAction()
            }))
        }
        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, hideAnimation: false, performsActionAfterDismiss: true, tapItemBack: { [weak self] _ in
            guard let self else { return }
            let controller = DeviceInformationViewController(node: self.node, showsGroupSection: false, showsSceneSection: false)
            self.pushDeviceInformationController(controller)
        }))
        items.append(.init(icon: UIImage(named: "menu_identify"), title: "Identify", tapItemBack: { [weak self] _ in
            guard let self else { return }
            MeshAPI.identify(address: self.node.primaryUnicastAddress)
        }))
        if showsDiagnosisMenuItem {
            items.append(.init(icon: UIImage(named: "menu_diagnosis"), title: "Diagnosis", tapItemBack: { _ in
                XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
            }))
        }

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(120))
    }

    private func setNetworkConnectivityVisible(_ visible: Bool) {
        guard isNetworkConnectivityVisible != visible else { return }
        isNetworkConnectivityVisible = visible
        reloadGatewayTable()
    }

    private func hideNetworkConnectivityForOfflineGateway() {
        stopNetworkConnectionPolling()
        stopWiFiRSSIStatusRefresh()
        networkSSID = ""
        networkPassword = ""
        networkCredentialSource = .localClear
        networkConnectState = .disabled
        isNetworkPasswordVisible = false
        updateWiFiHeaderStatus(.notConnected)
        setNetworkConnectivityVisible(false)
    }

    @discardableResult
    private func beginNetworkOperation() -> Int {
        networkOperationID += 1
        return networkOperationID
    }

    private func isCurrentNetworkOperation(_ operationID: Int) -> Bool {
        operationID == networkOperationID
    }

    private var isNetworkOperationInProgress: Bool {
        return networkConnectState == .connecting || networkConnectState == .disconnecting
    }

    private var isWiFiRequestInProgress: Bool {
        return activeWiFiRequest != nil
    }

    private func beginWiFiRequest(origin: WiFiRequestOrigin) -> Int? {
        guard activeWiFiRequest == nil else { return nil }
        nextWiFiRequestID += 1
        activeWiFiRequest = ActiveWiFiRequest(id: nextWiFiRequestID, origin: origin)
        reloadSection(.networkConnectivity)
        return nextWiFiRequestID
    }

    private func finishWiFiRequest(_ requestID: Int, completion: () -> Void) {
        guard activeWiFiRequest?.id == requestID else { return }
        activeWiFiRequest = nil
        completion()
        resumePendingGatewayRecoveryIfNeeded()
        reloadSection(.networkConnectivity)
    }

    private func resumePendingGatewayRecoveryIfNeeded() {
        guard activeWiFiRequest == nil, let action = pendingGatewayRecoveryAction else { return }
        pendingGatewayRecoveryAction = nil
        XWHUDManager.hideInView(with: view)
        guard node.state else {
            if isNetworkPageVisible {
                XWHUDManager.showErrorTipHUD("device_offline_message".localizedString)
            }
            return
        }
        action()
    }

    private func cancelPendingGatewayRecovery() {
        guard pendingGatewayRecoveryAction != nil else { return }
        pendingGatewayRecoveryAction = nil
        XWHUDManager.hideInView(with: view)
    }

    @discardableResult
    private func sendWiFiGatewayGet(
        _ function: VendorFunctionGet,
        origin: WiFiRequestOrigin,
        timeout: TimeInterval = 10,
        completion: @escaping (SunricherVendorStatus?) -> Void
    ) -> Bool {
        guard let requestID = beginWiFiRequest(origin: origin) else { return false }
        guard let vendorModel = node.sunricherVendorModel else {
            finishWiFiRequest(requestID) { completion(nil) }
            return true
        }
        MeshAPI.sendMessage(message: SunricherVendorGet(function: function), model: vendorModel, timeout: timeout) { response in
            DispatchQueue.main.async {
                self.finishWiFiRequest(requestID) {
                    completion(response as? SunricherVendorStatus)
                }
            }
        }
        return true
    }

    @discardableResult
    private func sendWiFiGatewayCredentialsSet(
        _ credentials: WiFiGatewayCredentials,
        origin: WiFiRequestOrigin,
        timeout: TimeInterval = 10,
        completion: @escaping (WiFiGatewayCredentialsSetResult?) -> Void
    ) -> Bool {
        guard let requestID = beginWiFiRequest(origin: origin) else { return false }
        guard let vendorModel = node.sunricherVendorModel else {
            finishWiFiRequest(requestID) { completion(nil) }
            return true
        }
        MeshAPI.sendMessage(message: SunricherVendorSet(function: .wifiGatewayCredentialsSet(credentials)), model: vendorModel, timeout: timeout) { response in
            DispatchQueue.main.async {
                self.finishWiFiRequest(requestID) {
                    guard let status = response as? SunricherVendorStatus,
                          case .wifiGatewayCredentialsSet(let result) = status.status.parameters else {
                        completion(nil)
                        return
                    }
                    completion(result)
                }
            }
        }
        return true
    }

    @discardableResult
    private func sendWiFiGatewayCredentialsClear(
        origin: WiFiRequestOrigin,
        timeout: TimeInterval = 10,
        completion: @escaping (WiFiGatewayCredentialsClearResult?) -> Void
    ) -> Bool {
        guard let requestID = beginWiFiRequest(origin: origin) else { return false }
        guard let vendorModel = node.sunricherVendorModel else {
            finishWiFiRequest(requestID) { completion(nil) }
            return true
        }
        MeshAPI.sendMessage(message: SunricherVendorSet(function: .wifiGatewayCredentialsClear), model: vendorModel, timeout: timeout) { response in
            DispatchQueue.main.async {
                self.finishWiFiRequest(requestID) {
                    guard let status = response as? SunricherVendorStatus,
                          case .wifiGatewayCredentialsClear(let result) = status.status.parameters else {
                        completion(nil)
                        return
                    }
                    completion(result)
                }
            }
        }
        return true
    }

    private func loadNetworkConnectivityFromGateway() {
        guard node.isKeybindComplete else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        guard node.state else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        stopNetworkConnectionPolling()
        setNetworkConnectivityVisible(false)
        let operationID = beginNetworkOperation()
        sendWiFiGatewayGet(.wifiGatewayCredentials, origin: .automatic) { [weak self] status in
            guard let self, self.isCurrentNetworkOperation(operationID), self.node.state else { return }
            guard let status,
                  case .wifiGatewayCredentialsRead(let result) = status.status.parameters else {
                self.showCredentialsFetchFailedIfVisible()
                return
            }
            self.handleCredentialsReadResult(result, operationID: operationID)
        }
    }

    private func handleCredentialsReadResult(_ result: WiFiGatewayCredentialsReadResult, operationID: Int) {
        switch result {
        case .success(let credentials):
            applyGatewayCredentials(credentials)
            loadConfiguredGatewayConnectionStatus(operationID: operationID)
        case .notConfigured:
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConfigured)
            networkCredentialSource = .phone
            networkConnectState = .disabled
            setNetworkConnectivityVisible(true)
            refreshCurrentSSID(showsResultHUD: false)
        case .internalError, .reserved(rawValue: _):
            showCredentialsFetchFailedIfVisible()
        }
    }

    private func applyGatewayCredentials(_ credentials: WiFiGatewayCredentials) {
        networkSSID = credentials.ssid
        networkPassword = credentials.password ?? ""
        networkCredentialSource = .gateway
    }

    private func loadConfiguredGatewayConnectionStatus(operationID: Int) {
        sendWiFiGatewayGet(.wifiGatewayConnectionStatus, origin: .automatic) { [weak self] status in
            guard let self, self.isCurrentNetworkOperation(operationID), self.node.state else { return }
            guard let status,
                  case .wifiGatewayConnectionStatus(let connectionStatus) = status.status.parameters else {
                self.setNetworkConnectivityVisible(false)
                self.showCredentialsFetchFailedIfVisible()
                return
            }
            self.applyConnectionStatus(connectionStatus, showsHUD: false)
            self.setNetworkConnectivityVisible(true)
            self.reloadSection(.networkConnectivity)
        }
    }

    private func refreshConfiguredGatewayConnectionStatus(credentials: WiFiGatewayCredentials? = nil) {
        let operationID = beginNetworkOperation()
        sendWiFiGatewayGet(.wifiGatewayConnectionStatus, origin: .userInitiated) { [weak self] status in
            guard let self, self.isCurrentNetworkOperation(operationID) else { return }
            guard self.node.state else {
                self.finishNetworkRefresh()
                return
            }
            guard let status,
                  case .wifiGatewayConnectionStatus(let connectionStatus) = status.status.parameters else {
                self.showRefreshNetworkConnectivityFailed()
                self.finishNetworkRefresh()
                return
            }
            if let credentials {
                self.applyGatewayCredentials(credentials)
            }
            self.applyConnectionStatus(connectionStatus, showsHUD: false)
            self.setNetworkConnectivityVisible(true)
            self.reloadSection(.networkConnectivity)
            self.finishNetworkRefresh()
        }
    }

    private func applyConnectionStatus(_ status: WiFiGatewayConnectionStatus, showsHUD: Bool) {
        switch status {
        case .connected:
            networkConnectState = .connected
            startWiFiRSSIStatusRefresh()
            if showsHUD {
                handleNetworkConnectionFinished(.success)
            }
        case .notStartedOrConnecting, .notConfigured:
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConnected)
            networkConnectState = networkSSID.isEmpty ? .disabled : .available
        case .passwordError, .failed, .reserved(rawValue: _):
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConnected)
            networkConnectState = networkSSID.isEmpty ? .disabled : .available
            if showsHUD {
                handleNetworkConnectionFinished(.failure)
            }
        }
    }

    private func refreshNetworkConnectivity() {
        guard canConfigureCurrentGateway else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard !isNetworkOperationInProgress, !isWiFiRequestInProgress, beginNetworkRefresh() else {
            if isNetworkOperationInProgress || isWiFiRequestInProgress {
                XWHUDManager.showTipHUD("wifi_gateway_wait_current_operation".localizedString, isLineFeed: true)
            }
            return
        }
        if networkConnectState == .connected {
            refreshGatewayCredentials(usesPhoneSSIDWhenNotConnected: false)
        } else {
            refreshCurrentSSID(showsResultHUD: true)
        }
    }

    private func refreshGatewayCredentials(usesPhoneSSIDWhenNotConnected: Bool = true) {
        let operationID = beginNetworkOperation()
        sendWiFiGatewayGet(.wifiGatewayCredentials, origin: .userInitiated) { [weak self] status in
            guard let self, self.isCurrentNetworkOperation(operationID) else { return }
            guard self.node.state else {
                self.finishNetworkRefresh()
                return
            }
            guard let status,
                  case .wifiGatewayCredentialsRead(let result) = status.status.parameters else {
                self.showRefreshNetworkConnectivityFailed()
                self.finishNetworkRefresh()
                return
            }
            switch result {
            case .success(let credentials):
                self.refreshConfiguredGatewayConnectionStatus(credentials: credentials)
            case .notConfigured:
                self.stopWiFiRSSIStatusRefresh()
                self.updateWiFiHeaderStatus(.notConfigured)
                self.setNetworkConnectivityVisible(true)
                if usesPhoneSSIDWhenNotConnected {
                    self.networkCredentialSource = .phone
                    self.networkConnectState = .disabled
                    self.refreshCurrentSSID(showsResultHUD: false)
                } else {
                    self.clearNetworkFieldsWithoutChangingHeader()
                    self.reloadSection(.networkConnectivity)
                    self.finishNetworkRefresh()
                }
            case .internalError, .reserved(rawValue: _):
                self.showRefreshNetworkConnectivityFailed()
                self.finishNetworkRefresh()
            }
        }
    }

    private func refreshCurrentSSID(showsResultHUD: Bool = false) {
        guard canRefreshPhoneSSID() else { return }
        let oldSSID = networkSSID
        WiFiSSIDProvider.shared.fetchCurrentSSID { [weak self] ssid in
            guard let self else { return }
            if showsResultHUD, ssid.isEmpty {
                self.finishNetworkRefresh()
                self.showPhoneNotConnectedToWiFiTip()
                return
            }
            self.networkSSID = ssid
            self.networkCredentialSource = ssid.isEmpty ? .localClear : .phone
            self.networkPassword = self.cachedPassword(for: ssid)
            self.networkConnectState = self.computeEditableConnectState(password: self.networkPassword)
            self.reloadSection(.networkConnectivity)
            if showsResultHUD {
                self.showRefreshSSIDChangedHUD(oldSSID: oldSSID, newSSID: ssid)
            }
            self.finishNetworkRefresh()
        }
    }

    private func beginNetworkRefresh() -> Bool {
        guard !isNetworkRefreshInProgress else { return false }
        isNetworkRefreshInProgress = true
        reloadSection(.networkConnectivity)
        return true
    }

    private func finishNetworkRefresh() {
        guard isNetworkRefreshInProgress else { return }
        isNetworkRefreshInProgress = false
        reloadSection(.networkConnectivity)
    }

    private func canRefreshPhoneSSID() -> Bool {
        guard canConfigureCurrentGateway, !isNetworkOperationInProgress, !isWiFiRequestInProgress else { return false }
        return networkConnectState != .connected
    }

    private func canEditNetworkSSID() -> Bool {
        guard canConfigureCurrentGateway, !isNetworkOperationInProgress, !isWiFiRequestInProgress else { return false }
        return networkConnectState != .connected
    }

    private func canEditNetworkPassword() -> Bool {
        guard canConfigureCurrentGateway, !isNetworkOperationInProgress, !isWiFiRequestInProgress else { return false }
        return networkConnectState != .connected
    }

    private func canToggleNetworkPasswordVisibility() -> Bool {
        return canConfigureCurrentGateway && !isNetworkOperationInProgress && !isWiFiRequestInProgress
    }

    private func showRefreshSSIDChangedHUD(oldSSID: String, newSSID: String) {
        let localizedKey = oldSSID == newSSID ? "network_unchanged" : "updated_to_the_new_network"
        XWHUDManager.showTipHUD(localizedKey.localizedString, isLineFeed: true)
    }

    private func showPhoneNotConnectedToWiFiTip() {
        XWHUDManager.showTipHUD("phone_not_connected_to_wifi".localizedString, isLineFeed: true)
    }

    @objc private func appDidBecomeActive() {
        guard shouldRefreshSSIDWhenActive else { return }
        shouldRefreshSSIDWhenActive = false
        guard canRefreshPhoneSSID() else { return }
        refreshCurrentSSID()
    }

    private func cachedPassword(for ssid: String) -> String {
        guard !ssid.isEmpty,
              let values = UserDefaults.standard.dictionary(forKey: wifiPasswordCacheKey) as? [String: String] else {
            return ""
        }
        return values[ssid] ?? ""
    }

    private func saveCachedPassword(_ password: String, for ssid: String) {
        guard !ssid.isEmpty else { return }
        var values = UserDefaults.standard.dictionary(forKey: wifiPasswordCacheKey) as? [String: String] ?? [:]
        values[ssid] = password
        UserDefaults.standard.set(values, forKey: wifiPasswordCacheKey)
    }

    private func updateNetworkSSID(_ ssid: String) -> GatewayNetworkConnectivityCell.ConnectState {
        guard canEditNetworkSSID() else { return networkConnectState }
        networkSSID = ssid
        networkCredentialSource = ssid.isEmpty ? .localClear : .phone
        networkConnectState = computeEditableConnectState(password: networkPassword)
        return networkConnectState
    }

    private func updateNetworkPassword(_ password: String) -> GatewayNetworkConnectivityCell.ConnectState {
        guard canEditNetworkPassword() else { return networkConnectState }
        guard password.canBeConverted(to: .ascii) else {
            XWHUDManager.showTipHUD("wifi_gateway_password_character_error".localizedString, isLineFeed: true)
            return networkConnectState
        }
        networkPassword = password
        networkConnectState = computeEditableConnectState(password: password)
        return networkConnectState
    }

    private func computeEditableConnectState(password: String) -> GatewayNetworkConnectivityCell.ConnectState {
        guard !networkSSID.isEmpty else { return .disabled }
        guard password.isEmpty || (8...63).contains(password.count) else { return .disabled }
        return .available
    }

    private func makeCredentialsForConnect() -> WiFiGatewayCredentials? {
        guard !networkSSID.isEmpty else {
            XWHUDManager.showTipHUD("wifi_gateway_ssid_empty".localizedString, isLineFeed: true)
            return nil
        }
        do {
            return try WiFiGatewayCredentials(ssid: networkSSID, password: networkPassword)
        } catch WiFiGatewayCredentialValidationError.invalidPasswordLength(_) {
            XWHUDManager.showTipHUD("wifi_gateway_password_length_error".localizedString, isLineFeed: true)
            return nil
        } catch WiFiGatewayCredentialValidationError.invalidCharacter(field: .password, byte: _) {
            XWHUDManager.showTipHUD("wifi_gateway_password_character_error".localizedString, isLineFeed: true)
            return nil
        } catch {
            XWHUDManager.showTipHUD("wifi_gateway_ssid_empty".localizedString, isLineFeed: true)
            return nil
        }
    }

    private func toggleNetworkPasswordVisibility() {
        guard !isNetworkOperationInProgress, !isWiFiRequestInProgress else { return }
        isNetworkPasswordVisible.toggle()
        reloadSection(.networkConnectivity)
    }

    private func networkConnectButtonAction() {
        guard canConfigureCurrentGateway else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard !isWiFiRequestInProgress else {
            XWHUDManager.showTipHUD("wifi_gateway_wait_current_operation".localizedString, isLineFeed: true)
            return
        }
        switch networkConnectState {
        case .available:
            connectNetworkWithGateway()
        case .connected:
            clearNetworkByDisconnect()
        case .disabled, .connecting, .disconnecting:
            break
        }
    }

    private func connectNetworkWithGateway() {
        guard let credentials = makeCredentialsForConnect() else { return }
        stopNetworkConnectionPolling()
        stopWiFiRSSIStatusRefresh()
        updateWiFiHeaderStatus(.notConnected)
        networkConnectState = .connecting
        setNetworkConnectivityVisible(true)
        reloadSection(.networkConnectivity)
        let operationID = beginNetworkOperation()
        sendWiFiGatewayCredentialsSet(credentials, origin: .userInitiated) { [weak self] result in
            guard let self, self.isCurrentNetworkOperation(operationID), self.node.state else { return }
            guard result == .accepted else {
                self.networkConnectState = self.computeEditableConnectState(password: self.networkPassword)
                self.reloadSection(.networkConnectivity)
                self.handleNetworkConnectionFinished(.failure)
                return
            }
            self.networkCredentialSource = .gateway
            self.networkConnectionStartedAt = Date()
            self.startNetworkConnectionPolling()
        }
    }

    private func startNetworkConnectionPolling() {
        networkConnectTimer?.invalidate()
        pollNetworkConnectionStatus()
        networkConnectTimer = LCWeakTimer.scheduledTimer(timeInterval: connectionPollInterval, aTarget: self, selector: #selector(pollNetworkConnectionStatus), userInfo: nil, repeats: true)
        if let networkConnectTimer {
            RunLoop.main.add(networkConnectTimer, forMode: .common)
        }
    }

    private func stopNetworkConnectionPolling() {
        networkConnectTimer?.invalidate()
        networkConnectTimer = nil
        networkConnectionStartedAt = nil
    }

    @objc private func pollNetworkConnectionStatus() {
        guard node.state else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        if let startedAt = networkConnectionStartedAt, Date().timeIntervalSince(startedAt) >= connectionPollTimeout {
            stopNetworkConnectionPolling()
            networkConnectState = computeEditableConnectState(password: networkPassword)
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.failure)
            return
        }
        sendWiFiGatewayGet(
            .wifiGatewayConnectionStatus,
            origin: .userInitiated,
            timeout: connectionPollInterval
        ) { [weak self] status in
            guard let self, self.networkConnectState == .connecting, self.node.state else { return }
            guard let status,
                  case .wifiGatewayConnectionStatus(let connectionStatus) = status.status.parameters else {
                return
            }
            switch connectionStatus {
            case .connected:
                self.stopNetworkConnectionPolling()
                self.networkConnectState = .connected
                self.saveCachedPassword(self.networkPassword, for: self.networkSSID)
                self.startWiFiRSSIStatusRefresh()
                self.reloadSection(.networkConnectivity)
                self.handleNetworkConnectionFinished(.success)
            case .passwordError, .failed, .notConfigured, .reserved(rawValue: _):
                self.stopNetworkConnectionPolling()
                self.stopWiFiRSSIStatusRefresh()
                self.updateWiFiHeaderStatus(.notConnected)
                self.networkConnectState = self.computeEditableConnectState(password: self.networkPassword)
                self.reloadSection(.networkConnectivity)
                self.handleNetworkConnectionFinished(.failure)
            case .notStartedOrConnecting:
                break
            }
        }
    }

    private func clearNetworkByDisconnect() {
        guard networkConnectState == .connected else { return }
        stopNetworkConnectionPolling()
        stopWiFiRSSIStatusRefresh()
        networkConnectState = .disconnecting
        reloadSection(.networkConnectivity)

        let operationID = beginNetworkOperation()
        sendWiFiGatewayCredentialsClear(origin: .userInitiated) { [weak self] result in
            guard let self, self.isCurrentNetworkOperation(operationID) else { return }
            self.completeNetworkDisconnectClear(result)
        }
    }

    private func completeNetworkDisconnectClear(_ result: WiFiGatewayCredentialsClearResult?) {
        stopNetworkConnectionPolling()
        stopWiFiRSSIStatusRefresh()
        clearLocalNetworkFields()
        reloadSection(.networkConnectivity)

        if result == .cleared {
            updateWiFiHeaderStatus(.notConfigured)
            handleNetworkConnectionFinished(.success)
        } else {
            handleNetworkConnectionFinished(.failure)
        }
    }

    private func clearNetworkSSIDLocally() {
        guard canConfigureCurrentGateway, !isNetworkOperationInProgress, !isWiFiRequestInProgress else { return }
        clearLocalNetworkFields()
        reloadSection(.networkConnectivity)
    }

    private func clearLocalNetworkFields() {
        clearNetworkFieldsWithoutChangingHeader()
        updateWiFiHeaderStatus(.notConnected)
    }

    private func clearNetworkFieldsWithoutChangingHeader() {
        networkSSID = ""
        networkPassword = ""
        networkCredentialSource = .localClear
        isNetworkPasswordVisible = false
        networkConnectState = .disabled
    }

    private func startWiFiRSSIStatusRefresh() {
        guard isNetworkPageVisible, node.isKeybindComplete else {
            stopWiFiRSSIStatusRefresh()
            return
        }
        guard node.state, networkConnectState == .connected else {
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConnected)
            return
        }
        wifiRSSIStatusTimer?.invalidate()
        wifiRSSIStatusTimer = nil
        refreshWiFiRSSIStatus()
    }

    private func stopWiFiRSSIStatusRefresh() {
        wifiRSSIStatusTimer?.invalidate()
        wifiRSSIStatusTimer = nil
    }

    private func scheduleNextWiFiRSSIStatusRefresh() {
        guard isNetworkPageVisible,
              node.isKeybindComplete,
              node.state,
              networkConnectState == .connected else {
            stopWiFiRSSIStatusRefresh()
            return
        }
        wifiRSSIStatusTimer?.invalidate()
        wifiRSSIStatusTimer = LCWeakTimer.scheduledTimer(
            timeInterval: wifiRSSIStatusPollDelay,
            aTarget: self,
            selector: #selector(refreshWiFiRSSIStatus),
            userInfo: nil,
            repeats: false
        )
        if let wifiRSSIStatusTimer {
            RunLoop.main.add(wifiRSSIStatusTimer, forMode: .common)
        }
    }

    @objc private func refreshWiFiRSSIStatus() {
        guard isNetworkPageVisible, node.isKeybindComplete else {
            stopWiFiRSSIStatusRefresh()
            return
        }
        guard node.state else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        guard networkConnectState == .connected else {
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConnected)
            return
        }
        let didStart = sendWiFiGatewayGet(
            .wifiGatewayRSSIStatus,
            origin: .automatic,
            timeout: wifiRSSIStatusRequestTimeout
        ) { [weak self] status in
            guard let self else { return }
            guard self.isNetworkPageVisible,
                  self.node.isKeybindComplete,
                  self.node.state,
                  self.networkConnectState == .connected else {
                self.stopWiFiRSSIStatusRefresh()
                return
            }
            if let status,
               case .wifiGatewayRSSIStatus(let rssiStatus) = status.status.parameters {
                self.applyWiFiRSSIStatus(rssiStatus)
            } else {
                self.updateWiFiHeaderStatus(.noSignal)
            }
            self.scheduleNextWiFiRSSIStatusRefresh()
        }
        if !didStart {
            scheduleNextWiFiRSSIStatusRefresh()
        }
    }

    private func applyWiFiRSSIStatus(_ status: WiFiGatewayRSSIStatus) {
        switch status {
        case .valid(let dbm, let networkStatus):
            updateWiFiHeaderStatus(wifiHeaderStatus(forRSSIDBm: dbm, networkStatus: networkStatus))
        case .unavailable, .readFailed, .reserved(rawValue: _):
            updateWiFiHeaderStatus(.noSignal)
        }
    }

    private func wifiHeaderStatus(forRSSIDBm dbm: Int8) -> WiFiHeaderStatus {
        if dbm > -60 {
            return .excellent
        } else if dbm <= -60 && dbm > -69 {
            return .good
        } else if dbm <= -69 && dbm > -80 {
            return .poor
        } else if dbm <= -80 {
            return .bad
        }
        return .noSignal
    }

    private func wifiHeaderStatus(
        forRSSIDBm dbm: Int8,
        networkStatus: WiFiGatewayNetworkStatus
    ) -> WiFiHeaderStatus {
        let rssiStatus = wifiHeaderStatus(forRSSIDBm: dbm)
        switch networkStatus {
        case .normal, .notReported:
            return rssiStatus
        case .unavailable:
            return WiFiHeaderStatus(
                iconName: rssiStatus.iconName,
                localizedStatusKey: "wifi_status_no_internet"
            )
        case .unknown, .reserved(rawValue: _):
            return WiFiHeaderStatus(
                iconName: rssiStatus.iconName,
                localizedStatusKey: "wifi_status_unknown"
            )
        }
    }

    private func updateWiFiHeaderStatus(_ status: WiFiHeaderStatus) {
        wifiHeaderView?.updateWiFiStatus(iconName: status.iconName, status: status.localizedStatusKey.localizedString)
    }

    private func shouldShowSSIDClearButton() -> Bool {
        guard !networkSSID.isEmpty, !isNetworkOperationInProgress, !isWiFiRequestInProgress else { return false }
        if networkCredentialSource == .gateway && networkConnectState == .connected {
            return false
        }
        return true
    }

    private func showCredentialsFetchFailedIfVisible() {
        setNetworkConnectivityVisible(false)
        if isNetworkPageVisible, pendingGatewayRecoveryAction == nil {
            XWHUDManager.showErrorTipHUD("failed_to_retrieve_data".localizedString)
        }
    }

    private func showRefreshNetworkConnectivityFailed() {
        if isNetworkPageVisible, pendingGatewayRecoveryAction == nil {
            XWHUDManager.showErrorTipHUD("failed_to_retrieve_data".localizedString)
        }
    }

    private func handleNetworkConnectionFinished(_ result: PendingNetworkResultHUD) {
        if isNetworkPageVisible {
            showNetworkResultHUD(result)
        } else {
            pendingNetworkResultHUD = result
        }
    }

    private func showPendingNetworkResultHUDIfNeeded() {
        guard let pendingNetworkResultHUD else { return }
        self.pendingNetworkResultHUD = nil
        showNetworkResultHUD(pendingNetworkResultHUD)
    }

    private func showNetworkResultHUD(_ result: PendingNetworkResultHUD) {
        switch result {
        case .success:
            XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
        case .failure:
            XWHUDManager.showErrorTipHUD("failed".localizedString)
        }
    }

    private func showDisconnectFirstTip() {
        XWHUDManager.showTipHUD("please_disconnect_first".localizedString, isLineFeed: true)
    }

    private func showChangeWiFiAlert() {
        guard canConfigureCurrentGateway else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard !isWiFiRequestInProgress else {
            XWHUDManager.showTipHUD("wifi_gateway_wait_current_operation".localizedString, isLineFeed: true)
            return
        }
        guard networkConnectState != .connected else {
            showDisconnectFirstTip()
            return
        }
        GatewayChangeWiFiAlertView.show { [weak self] in
            self?.openSystemSettingsForWiFiChange()
        }
    }

    private func openSystemSettingsForWiFiChange() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(settingsURL) else {
            XWHUDManager.showTipHUD("network_error".localizedString, isLineFeed: true)
            return
        }
        shouldRefreshSSIDWhenActive = true
        UIApplication.shared.open(settingsURL)
    }
}
