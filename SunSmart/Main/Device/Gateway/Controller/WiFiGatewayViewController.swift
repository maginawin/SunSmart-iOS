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
        case configurationUnconfirmed
        case clearUnconfirmed
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
        static let noInternet = WiFiHeaderStatus(iconName: "wifi_no_internet", localizedStatusKey: "wifi_status_no_internet")
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
    private var shouldRefreshSSIDWhenActive: Bool = false
    private var isNetworkPageVisible: Bool = false
    private var pendingNetworkResultHUD: PendingNetworkResultHUD?
    private var networkOperationID: Int = 0
    private var nextWiFiRequestID: Int = 0
    private var activeWiFiRequest: ActiveWiFiRequest?
    private var automaticLoadGate = WiFiGatewayAutomaticLoadGate()
    private var proxySessionTracker = WiFiGatewayProxySessionTracker()
    private var credentialMutationReducer = WiFiGatewayCredentialMutationReducer()
    private var connectionPollingReducer = WiFiGatewayConnectionPollingReducer()
    private var pendingGatewayRecoveryAction: (() -> Void)?
    private let wifiPasswordCacheKey = "wifi_gateway_saved_passwords_by_ssid"

    override var supportsAPNConfiguration: Bool {
        return false
    }

    override var supportsGatewaySignalRefresh: Bool {
        return false
    }

    override var gatewayFirmwareKind: GatewayFirmwareKind {
        return .wifi
    }

    override var sections: [SectionType] {
        var sections = super.sections
        guard isNetworkConnectivityVisible, let nameIndex = sections.firstIndex(of: .name) else {
            return sections
        }
        sections.insert(.networkConnectivity, at: sections.index(after: nameIndex))
        return sections
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
            resetWiFiSessionForUnavailableProxy()
            return
        }
        if networkConnectState == .connected {
            requestAutomaticLoad(forceReload: false)
        } else if isGatewayProxyReady,
                  !isNetworkOperationInProgress,
                  !isWiFiRequestInProgress,
                  !isNetworkConnectivityVisible {
            requestAutomaticLoad(forceReload: true)
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

    override func gatewayProxyReadyStateDidUpdate(_ isReady: Bool) {
        if !isReady {
            resetWiFiSessionForUnavailableProxy()
            return
        }
        guard node.isKeybindComplete else {
            resetWiFiSessionForUnavailableProxy()
            return
        }
    }

    override func gatewayProxyDidBecomeReady(_ context: ProxyReadyContext) {
        stopWiFiRSSIStatusRefresh()
        guard MeshLibManager.manager.currentProxyReadyContext == context,
              gatewayProxyReadySessionID == context.sessionID else { return }
        let isNewSession = proxySessionTracker.currentSessionID != context.sessionID
        if isNewSession {
            resetWiFiSessionForUnavailableProxy()
            proxySessionTracker.begin(sessionID: context.sessionID)
        }
        automaticLoadGate.markReady(sessionID: context.sessionID)
        if isNewSession {
            requestAutomaticLoad(forceReload: true)
        } else {
            drainAutomaticLoadIfPossible()
        }
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
        guard isGatewayProxyReady else {
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

    override func performGatewayDFUAction() {
        let controller = WiFiFirmwareUpdateViewController(node: self.node)
        preventModalStackDismissalUntilReturn()
        navigationController?.pushViewController(controller, animated: true)
    }

    private func setNetworkConnectivityVisible(_ visible: Bool) {
        guard isNetworkConnectivityVisible != visible else { return }
        isNetworkConnectivityVisible = visible
        reloadGatewayTable()
    }

    private func resetWiFiSessionForUnavailableProxy() {
        automaticLoadGate.invalidate()
        stopNetworkConnectionPolling()
        stopWiFiRSSIStatusRefresh()
        networkOperationID += 1
        activeWiFiRequest = nil
        proxySessionTracker.invalidate()
        isNetworkRefreshInProgress = false
        credentialMutationReducer = WiFiGatewayCredentialMutationReducer()
        connectionPollingReducer = WiFiGatewayConnectionPollingReducer()
        pendingNetworkResultHUD = nil
        shouldRefreshSSIDWhenActive = false
        cancelPendingGatewayRecovery()
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
        drainAutomaticLoadIfPossible()
    }

    private func requestAutomaticLoad(forceReload: Bool) {
        automaticLoadGate.request(forceReload: forceReload)
        drainAutomaticLoadIfPossible()
    }

    private func drainAutomaticLoadIfPossible() {
        guard isGatewayProxyReady,
              isNetworkPageVisible,
              node.isKeybindComplete,
              !isNetworkOperationInProgress,
              !isWiFiRequestInProgress,
              let context = MeshLibManager.manager.currentProxyReadyContext,
              context.nodeAddress == node.primaryUnicastAddress,
              gatewayProxyReadySessionID == context.sessionID,
              let intent = automaticLoadGate.takeIfReady(currentSessionID: context.sessionID) else {
            return
        }

        switch intent {
        case .resume:
            if networkConnectState == .connected {
                startWiFiRSSIStatusRefresh()
            } else {
                loadNetworkConnectivityFromGateway()
            }
        case .reload:
            loadNetworkConnectivityFromGateway()
        }
    }

    private func resumePendingGatewayRecoveryIfNeeded() {
        guard activeWiFiRequest == nil, let action = pendingGatewayRecoveryAction else { return }
        pendingGatewayRecoveryAction = nil
        XWHUDManager.hideInView(with: view)
        guard isGatewayProxyReady else {
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
        subcode: WiFiGatewayV19Subcode,
        origin: WiFiRequestOrigin,
        completion: @escaping (SunricherVendorStatus?) -> Void
    ) -> Bool {
        guard isGatewayProxyReady else { return false }
        guard let requestID = beginWiFiRequest(origin: origin) else { return false }
        guard let vendorModel = node.sunricherVendorModel else {
            finishWiFiRequest(requestID) { completion(nil) }
            return true
        }
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: function),
            model: vendorModel,
            timeout: WiFiGatewayV19Timing.responseTimeout(for: subcode)
        ) { response in
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
        completion: @escaping (WiFiGatewayCredentialsSetResult?) -> Void
    ) -> Bool {
        guard isGatewayProxyReady else { return false }
        guard let requestID = beginWiFiRequest(origin: origin) else { return false }
        guard let vendorModel = node.sunricherVendorModel else {
            finishWiFiRequest(requestID) { completion(nil) }
            return true
        }
        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .wifiGatewayCredentialsSet(credentials)),
            model: vendorModel,
            timeout: WiFiGatewayV19Timing.responseTimeout(for: .credentialsSet)
        ) { response in
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
        completion: @escaping (WiFiGatewayCredentialsClearResult?) -> Void
    ) -> Bool {
        guard isGatewayProxyReady else { return false }
        guard let requestID = beginWiFiRequest(origin: origin) else { return false }
        guard let vendorModel = node.sunricherVendorModel else {
            finishWiFiRequest(requestID) { completion(nil) }
            return true
        }
        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .wifiGatewayCredentialsClear),
            model: vendorModel,
            timeout: WiFiGatewayV19Timing.responseTimeout(for: .credentialsClear)
        ) { response in
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
            resetWiFiSessionForUnavailableProxy()
            return
        }
        guard isGatewayProxyReady else {
            resetWiFiSessionForUnavailableProxy()
            return
        }
        stopNetworkConnectionPolling()
        setNetworkConnectivityVisible(false)
        let operationID = beginNetworkOperation()
        sendWiFiGatewayGet(
            .wifiGatewayCredentials,
            subcode: .credentialsRead,
            origin: .automatic
        ) { [weak self] status in
            guard let self, self.isCurrentNetworkOperation(operationID), self.isGatewayProxyReady else { return }
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
        case .unconfirmed, .reserved(rawValue: _):
            showCredentialsFetchFailedIfVisible()
        }
    }

    private func applyGatewayCredentials(_ credentials: WiFiGatewayCredentials) {
        networkSSID = credentials.ssid
        networkPassword = credentials.password ?? ""
        networkCredentialSource = .gateway
    }

    private func loadConfiguredGatewayConnectionStatus(operationID: Int) {
        sendWiFiGatewayGet(
            .wifiGatewayConnectionStatus,
            subcode: .connectionStatus,
            origin: .automatic
        ) { [weak self] status in
            guard let self, self.isCurrentNetworkOperation(operationID), self.isGatewayProxyReady else { return }
            guard let status,
                  case .wifiGatewayConnectionStatus(let connectionStatus) = status.status.parameters else {
                self.setNetworkConnectivityVisible(false)
                self.showCredentialsFetchFailedIfVisible()
                return
            }
            if case .requestFormatError = connectionStatus {
                self.setNetworkConnectivityVisible(true)
                self.reloadSection(.networkConnectivity)
                return
            }
            self.applyConnectionStatus(connectionStatus, showsHUD: false)
            self.setNetworkConnectivityVisible(true)
            self.reloadSection(.networkConnectivity)
        }
    }

    private func refreshConfiguredGatewayConnectionStatus(credentials: WiFiGatewayCredentials? = nil) {
        let operationID = beginNetworkOperation()
        sendWiFiGatewayGet(
            .wifiGatewayConnectionStatus,
            subcode: .connectionStatus,
            origin: .userInitiated
        ) { [weak self] status in
            guard let self, self.isCurrentNetworkOperation(operationID) else { return }
            guard self.isGatewayProxyReady else {
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
            if case .requestFormatError = connectionStatus {
                self.setNetworkConnectivityVisible(true)
                self.reloadSection(.networkConnectivity)
                self.finishNetworkRefresh()
                return
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
        case .requestFormatError:
            break
        }
    }

    private func refreshNetworkConnectivity() {
        guard canConfigureCurrentGateway else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard isGatewayProxyReady else {
            XWHUDManager.showErrorTipHUD("device_offline_message".localizedString)
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
        sendWiFiGatewayGet(
            .wifiGatewayCredentials,
            subcode: .credentialsRead,
            origin: .userInitiated
        ) { [weak self] status in
            guard let self, self.isCurrentNetworkOperation(operationID) else { return }
            guard self.isGatewayProxyReady else {
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
            case .unconfirmed, .reserved(rawValue: _):
                self.showRefreshNetworkConnectivityFailed()
                self.finishNetworkRefresh()
            }
        }
    }

    private func refreshCurrentSSID(showsResultHUD: Bool = false) {
        guard canRefreshPhoneSSID() else { return }
        let oldSSID = networkSSID
        let readySessionID = gatewayProxyReadySessionID
        WiFiSSIDProvider.shared.fetchCurrentSSID { [weak self] ssid in
            guard let self else { return }
            guard self.isGatewayProxyReady,
                  self.gatewayProxyReadySessionID == readySessionID else { return }
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
        guard isGatewayProxyReady,
              canConfigureCurrentGateway,
              !isNetworkOperationInProgress,
              !isWiFiRequestInProgress else { return false }
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
        networkPassword = password
        networkConnectState = computeEditableConnectState(password: password)
        return networkConnectState
    }

    private func computeEditableConnectState(password: String) -> GatewayNetworkConnectivityCell.ConnectState {
        guard (try? WiFiGatewayCredentials(ssid: networkSSID, password: password)) != nil else {
            return .disabled
        }
        return .available
    }

    private func makeCredentialsForConnect() -> WiFiGatewayCredentials? {
        guard !networkSSID.isEmpty else {
            XWHUDManager.showTipHUD("wifi_gateway_ssid_empty".localizedString, isLineFeed: true)
            return nil
        }
        do {
            return try WiFiGatewayCredentials(ssid: networkSSID, password: networkPassword)
        } catch WiFiGatewayCredentialValidationError.invalidSSIDLength(let length) {
            let key = length == 0 ? "wifi_gateway_ssid_empty" : "wifi_gateway_ssid_length_error"
            XWHUDManager.showTipHUD(key.localizedString, isLineFeed: true)
            return nil
        } catch WiFiGatewayCredentialValidationError.invalidPasswordLength(_) {
            XWHUDManager.showTipHUD("wifi_gateway_password_length_error".localizedString, isLineFeed: true)
            return nil
        } catch WiFiGatewayCredentialValidationError.invalidControlCharacter(let field, _) {
            let key = field == .ssid
                ? "wifi_gateway_ssid_character_error"
                : "wifi_gateway_password_character_error"
            XWHUDManager.showTipHUD(key.localizedString, isLineFeed: true)
            return nil
        } catch {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: true)
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
        guard isGatewayProxyReady else {
            XWHUDManager.showErrorTipHUD("device_offline_message".localizedString)
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
        credentialMutationReducer = WiFiGatewayCredentialMutationReducer()
        let target = credentialSnapshot(from: credentials)
        applyCredentialMutationAction(
            credentialMutationReducer.reduce(.start(.set(target: target))),
            operationID: operationID
        )
    }

    private func credentialSnapshot(
        from credentials: WiFiGatewayCredentials
    ) -> WiFiGatewayCredentialSnapshot {
        WiFiGatewayCredentialSnapshot(
            ssid: credentials.ssidData,
            password: credentials.passwordData
        )
    }

    private func credentialSnapshotFromCurrentFields() -> WiFiGatewayCredentialSnapshot {
        WiFiGatewayCredentialSnapshot(
            ssid: Data(networkSSID.utf8),
            password: Data(networkPassword.utf8)
        )
    }

    private func credentials(
        from snapshot: WiFiGatewayCredentialSnapshot
    ) -> WiFiGatewayCredentials? {
        guard let ssid = String(data: snapshot.ssid, encoding: .utf8),
              let password = String(data: snapshot.password, encoding: .utf8) else {
            return nil
        }
        return try? WiFiGatewayCredentials(
            ssid: ssid,
            password: password.isEmpty ? nil : password
        )
    }

    private func mutationResponse(
        from result: WiFiGatewayCredentialsSetResult?
    ) -> WiFiGatewayCredentialMutationResponse {
        switch result {
        case .accepted: return .confirmed
        case .invalidParameters: return .invalidParameters
        case .unconfirmed, .reserved, nil: return .unconfirmed
        }
    }

    private func mutationResponse(
        from result: WiFiGatewayCredentialsClearResult?
    ) -> WiFiGatewayCredentialMutationResponse {
        switch result {
        case .cleared: return .confirmed
        case .invalidParameters: return .invalidParameters
        case .unconfirmed, .reserved, nil: return .unconfirmed
        }
    }

    private func applyCredentialMutationAction(
        _ action: WiFiGatewayCredentialMutationAction,
        operationID: Int
    ) {
        guard isCurrentNetworkOperation(operationID) else { return }
        switch action {
        case .sendSet(let target):
            guard let credentials = credentials(from: target) else {
                applyCredentialMutationAction(.setTargetUnknown, operationID: operationID)
                return
            }
            sendWiFiGatewayCredentialsSet(credentials, origin: .userInitiated) { [weak self] result in
                guard let self,
                      self.isCurrentNetworkOperation(operationID),
                      self.isGatewayProxyReady else { return }
                let action = self.credentialMutationReducer.reduce(
                    .mutationResponse(self.mutationResponse(from: result))
                )
                self.applyCredentialMutationAction(action, operationID: operationID)
            }

        case .sendClear:
            sendWiFiGatewayCredentialsClear(origin: .userInitiated) { [weak self] result in
                guard let self,
                      self.isCurrentNetworkOperation(operationID),
                      self.isGatewayProxyReady else { return }
                let action = self.credentialMutationReducer.reduce(
                    .mutationResponse(self.mutationResponse(from: result))
                )
                self.applyCredentialMutationAction(action, operationID: operationID)
            }

        case .requestCredentials:
            requestCredentialMutationRecovery(operationID: operationID)

        case .setTargetReached:
            networkCredentialSource = .gateway
            startNetworkConnectionPolling(operationID: operationID)

        case .setTargetNotReached:
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConnected)
            networkConnectState = computeEditableConnectState(password: networkPassword)
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.failure)

        case .setTargetUnknown:
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConnected)
            networkConnectState = computeEditableConnectState(password: networkPassword)
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.configurationUnconfirmed)

        case .clearTargetReached:
            stopNetworkConnectionPolling()
            stopWiFiRSSIStatusRefresh()
            clearLocalNetworkFields()
            updateWiFiHeaderStatus(.notConfigured)
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.success)

        case .clearTargetNotReached(let snapshot):
            applyCredentialSnapshot(snapshot)
            networkConnectState = .connected
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.failure)
            loadConfiguredGatewayConnectionStatus(operationID: operationID)

        case .clearTargetUnknown:
            networkConnectState = .connected
            startWiFiRSSIStatusRefresh()
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.clearUnconfirmed)

        case .none:
            break
        }
    }

    private func requestCredentialMutationRecovery(operationID: Int) {
        let didStart = sendWiFiGatewayGet(
            .wifiGatewayCredentials,
            subcode: .credentialsRead,
            origin: .userInitiated
        ) { [weak self] status in
            guard let self,
                  self.isCurrentNetworkOperation(operationID),
                  self.isGatewayProxyReady else { return }
            let observation: WiFiGatewayCredentialReadObservation
            if let status,
               case .wifiGatewayCredentialsRead(let result) = status.status.parameters {
                switch result {
                case .success(let credentials):
                    observation = .credentials(self.credentialSnapshot(from: credentials))
                case .notConfigured:
                    observation = .notConfigured
                case .unconfirmed, .reserved:
                    observation = .unconfirmed
                }
            } else {
                observation = .unconfirmed
            }
            let action = self.credentialMutationReducer.reduce(
                .recoveryResponse(observation)
            )
            self.applyCredentialMutationAction(action, operationID: operationID)
        }
        if !didStart {
            let action = credentialMutationReducer.reduce(
                .recoveryResponse(.unconfirmed)
            )
            applyCredentialMutationAction(action, operationID: operationID)
        }
    }

    private func applyCredentialSnapshot(_ snapshot: WiFiGatewayCredentialSnapshot) {
        guard let ssid = String(data: snapshot.ssid, encoding: .utf8),
              let password = String(data: snapshot.password, encoding: .utf8) else { return }
        networkSSID = ssid
        networkPassword = password
        networkCredentialSource = .gateway
    }

    private func startNetworkConnectionPolling(operationID: Int) {
        networkConnectTimer?.invalidate()
        networkConnectTimer = nil
        connectionPollingReducer = WiFiGatewayConnectionPollingReducer()
        applyConnectionPollingAction(
            connectionPollingReducer.start(now: ProcessInfo.processInfo.systemUptime),
            operationID: operationID
        )
    }

    private func stopNetworkConnectionPolling() {
        networkConnectTimer?.invalidate()
        networkConnectTimer = nil
        connectionPollingReducer = WiFiGatewayConnectionPollingReducer()
    }

    private func requestConnectionPollingStatus(operationID: Int) {
        guard isGatewayProxyReady else {
            resetWiFiSessionForUnavailableProxy()
            return
        }
        let didStart = sendWiFiGatewayGet(
            .wifiGatewayConnectionStatus,
            subcode: .connectionStatus,
            origin: .userInitiated
        ) { [weak self] status in
            guard let self,
                  self.isCurrentNetworkOperation(operationID),
                  self.networkConnectState == .connecting,
                  self.isGatewayProxyReady else { return }
            let observation = self.connectionPollingObservation(from: status)
            let action = self.connectionPollingReducer.receive(
                observation,
                now: ProcessInfo.processInfo.systemUptime
            )
            self.applyConnectionPollingAction(action, operationID: operationID)
        }
        if !didStart {
            let action = connectionPollingReducer.receive(
                .noValidResult,
                now: ProcessInfo.processInfo.systemUptime
            )
            applyConnectionPollingAction(action, operationID: operationID)
        }
    }

    private func connectionPollingObservation(
        from status: SunricherVendorStatus?
    ) -> WiFiGatewayConnectionPollingObservation {
        guard let status,
              case .wifiGatewayConnectionStatus(let value) = status.status.parameters else {
            return .noValidResult
        }
        switch value {
        case .notStartedOrConnecting: return .connecting
        case .connected: return .connected
        case .passwordError: return .passwordError
        case .failed: return .failed
        case .notConfigured: return .notConfigured
        case .requestFormatError: return .requestFormatError
        case .reserved: return .reserved
        }
    }

    private func applyConnectionPollingAction(
        _ action: WiFiGatewayConnectionPollingAction,
        operationID: Int
    ) {
        guard isCurrentNetworkOperation(operationID) else { return }
        switch action {
        case .sendQuery:
            requestConnectionPollingStatus(operationID: operationID)

        case .schedule(let delay):
            networkConnectTimer?.invalidate()
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                guard let self,
                      self.isCurrentNetworkOperation(operationID),
                      self.networkConnectState == .connecting else { return }
                let action = self.connectionPollingReducer.timerFired(
                    now: ProcessInfo.processInfo.systemUptime
                )
                self.applyConnectionPollingAction(action, operationID: operationID)
            }
            networkConnectTimer = timer
            RunLoop.main.add(timer, forMode: .common)

        case .connected:
            stopNetworkConnectionPolling()
            networkConnectState = .connected
            saveCachedPassword(networkPassword, for: networkSSID)
            startWiFiRSSIStatusRefresh()
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.success)

        case .failed, .timedOut:
            stopNetworkConnectionPolling()
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConnected)
            networkConnectState = computeEditableConnectState(password: networkPassword)
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.failure)

        case .notConfigured:
            stopNetworkConnectionPolling()
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConfigured)
            networkConnectState = computeEditableConnectState(password: networkPassword)
            reloadSection(.networkConnectivity)
            handleNetworkConnectionFinished(.failure)

        case .none:
            break
        }
    }

    private func clearNetworkByDisconnect() {
        guard networkConnectState == .connected else { return }
        stopNetworkConnectionPolling()
        stopWiFiRSSIStatusRefresh()
        networkConnectState = .disconnecting
        reloadSection(.networkConnectivity)

        let operationID = beginNetworkOperation()
        credentialMutationReducer = WiFiGatewayCredentialMutationReducer()
        let previous = credentialSnapshotFromCurrentFields()
        applyCredentialMutationAction(
            credentialMutationReducer.reduce(.start(.clear(previous: previous))),
            operationID: operationID
        )
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
        guard isGatewayProxyReady, networkConnectState == .connected else {
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
              isGatewayProxyReady,
              networkConnectState == .connected else {
            stopWiFiRSSIStatusRefresh()
            return
        }
        wifiRSSIStatusTimer?.invalidate()
        wifiRSSIStatusTimer = LCWeakTimer.scheduledTimer(
            timeInterval: WiFiGatewayV19Timing.rssiPollDelay,
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
        guard isGatewayProxyReady else {
            resetWiFiSessionForUnavailableProxy()
            return
        }
        guard networkConnectState == .connected else {
            stopWiFiRSSIStatusRefresh()
            updateWiFiHeaderStatus(.notConnected)
            return
        }
        let didStart = sendWiFiGatewayGet(
            .wifiGatewayRSSIStatus,
            subcode: .rssiStatus,
            origin: .automatic
        ) { [weak self] status in
            guard let self else { return }
            guard self.isNetworkPageVisible,
                  self.node.isKeybindComplete,
                  self.isGatewayProxyReady,
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
        let signalStatus: WiFiHeaderStatus
        switch status.rssiResult {
        case .valid(let dbm):
            signalStatus = wifiHeaderStatus(forRSSIDBm: dbm)
        case .unavailable, .readFailed, .reserved:
            signalStatus = .noSignal
        }

        switch status.networkStatus {
        case .normal:
            updateWiFiHeaderStatus(signalStatus)
        case .unavailable:
            updateWiFiHeaderStatus(.noInternet)
        case .unknown, .reserved:
            updateWiFiHeaderStatus(.init(
                iconName: signalStatus.iconName,
                localizedStatusKey: "wifi_status_unknown"
            ))
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
        case .configurationUnconfirmed:
            XWHUDManager.showErrorTipHUD(
                "wifi_gateway_configuration_unconfirmed".localizedString
            )
        case .clearUnconfirmed:
            XWHUDManager.showErrorTipHUD(
                "wifi_gateway_clear_unconfirmed".localizedString
            )
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
