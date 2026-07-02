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

    private var networkSSID: String = ""
    private var networkPassword: String = ""
    private var networkCredentialSource: NetworkCredentialSource = .localClear
    private var isNetworkConnectivityVisible: Bool = false
    private var isNetworkPasswordVisible: Bool = false
    private var networkConnectState: GatewayNetworkConnectivityCell.ConnectState = .disabled
    private var networkConnectTimer: Timer?
    private var networkConnectionStartedAt: Date?
    private var shouldRefreshSSIDWhenActive: Bool = false
    private var isNetworkPageVisible: Bool = false
    private var pendingNetworkResultHUD: PendingNetworkResultHUD?
    private var networkOperationID: Int = 0
    private let connectionPollInterval: TimeInterval = 2
    private let connectionPollTimeout: TimeInterval = 60
    private let wifiPasswordCacheKey = "wifi_gateway_saved_passwords_by_ssid"

    override var supportsAPNConfiguration: Bool {
        return false
    }

    override var sections: [SectionType] {
        var sections = super.sections
        guard isNetworkConnectivityVisible, let activateIndex = sections.firstIndex(of: .activate) else {
            return sections
        }
        sections.insert(.networkConnectivity, at: sections.index(after: activateIndex))
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
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isNetworkPageVisible = false
        if isMovingFromParent || navigationController?.isBeingDismissed == true || isBeingDismissed {
            stopNetworkConnectionPolling()
        }
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
        bottomView.showSaveOnlyUI()
    }

    override func showRepairBottomActions() {
        bottomView.showSaveOnlyUI()
    }

    override func registerAdditionalGatewayCells(in tableView: UITableView) {
        tableView.register(GatewayNetworkConnectivityCell.classForCoder(), forCellReuseIdentifier: GatewayNetworkConnectivityCell.reuseIdentifier)
    }

    override func networkConnectivityCellHeight() -> CGFloat {
        return SCRYFrom(180)
    }

    override func configureNetworkConnectivityCell(_ cell: GatewayNetworkConnectivityCell) {
        let isConnecting = networkConnectState == .connecting
        let isConnected = networkConnectState == .connected
        cell.update(
            ssid: networkSSID,
            password: networkPassword,
            passwordVisible: isNetworkPasswordVisible,
            connectState: networkConnectState,
            showsSSIDClearButton: shouldShowSSIDClearButton(),
            canSelectWiFi: !isConnecting,
            canRefresh: canRefreshPhoneSSID(),
            canEditPassword: !isConnected && !isConnecting
        )
        cell.selectWiFiCallback = { [weak self] in
            self?.showChangeWiFiAlert()
        }
        cell.refreshCallback = { [weak self] in
            self?.refreshCurrentSSID(showsResultHUD: true)
        }
        cell.ssidClearCallback = { [weak self] in
            self?.clearNetworkSSIDLocally()
        }
        cell.passwordChangedCallback = { [weak self] password in
            self?.updateNetworkPassword(password) ?? .disabled
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
        guard networkConnectState != .connecting else { return }
        loadNetworkConnectivityFromGateway()
    }

    deinit {
        stopNetworkConnectionPolling()
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func moreClick() {
        var items: [MenuPopView.MenuItem] = []
        items.append(.init(icon: UIImage(named: "menu_wifi_dfu"), title: "WiFi DFU", tapItemBack: { _ in
            XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
        }))
        if site.deviceOperates.contains(.edit) {
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
        items.append(.init(icon: UIImage(named: "menu_diagnosis"), title: "Diagnosis", tapItemBack: { _ in
            XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
        }))

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
        networkSSID = ""
        networkPassword = ""
        networkCredentialSource = .localClear
        networkConnectState = .disabled
        isNetworkPasswordVisible = false
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

    private func sendWiFiGatewayGet(
        _ function: VendorFunctionGet,
        timeout: TimeInterval = 10,
        completion: @escaping (SunricherVendorStatus?) -> Void
    ) {
        guard let vendorModel = node.sunricherVendorModel else {
            completion(nil)
            return
        }
        MeshAPI.sendMessage(message: SunricherVendorGet(function: function), model: vendorModel, timeout: timeout) { response in
            DispatchQueue.main.async {
                completion(response as? SunricherVendorStatus)
            }
        }
    }

    private func sendWiFiGatewayCredentialsSet(
        _ credentials: WiFiGatewayCredentials,
        timeout: TimeInterval = 10,
        completion: @escaping (WiFiGatewayCredentialsSetResult?) -> Void
    ) {
        guard let vendorModel = node.sunricherVendorModel else {
            completion(nil)
            return
        }
        MeshAPI.sendMessage(message: SunricherVendorSet(function: .wifiGatewayCredentialsSet(credentials)), model: vendorModel, timeout: timeout) { response in
            DispatchQueue.main.async {
                guard let status = response as? SunricherVendorStatus,
                      case .wifiGatewayCredentialsSet(let result) = status.status.parameters else {
                    completion(nil)
                    return
                }
                completion(result)
            }
        }
    }

    private func loadNetworkConnectivityFromGateway() {
        guard node.state else {
            hideNetworkConnectivityForOfflineGateway()
            return
        }
        stopNetworkConnectionPolling()
        setNetworkConnectivityVisible(false)
        let operationID = beginNetworkOperation()
        sendWiFiGatewayGet(.wifiGatewayCredentials) { [weak self] status in
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
            networkSSID = credentials.ssid
            networkPassword = credentials.password ?? ""
            networkCredentialSource = .gateway
            loadConfiguredGatewayConnectionStatus(operationID: operationID)
        case .notConfigured:
            networkCredentialSource = .phone
            networkConnectState = .disabled
            setNetworkConnectivityVisible(true)
            refreshCurrentSSID(showsResultHUD: false)
        case .internalError, .reserved(rawValue: _):
            showCredentialsFetchFailedIfVisible()
        }
    }

    private func loadConfiguredGatewayConnectionStatus(operationID: Int) {
        sendWiFiGatewayGet(.wifiGatewayConnectionStatus) { [weak self] status in
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

    private func applyConnectionStatus(_ status: WiFiGatewayConnectionStatus, showsHUD: Bool) {
        switch status {
        case .connected:
            networkConnectState = .connected
            if showsHUD {
                handleNetworkConnectionFinished(.success)
            }
        case .notStartedOrConnecting:
            networkConnectState = networkSSID.isEmpty ? .disabled : .available
        case .passwordError, .failed, .reserved(rawValue: _):
            networkConnectState = networkSSID.isEmpty ? .disabled : .available
            if showsHUD {
                handleNetworkConnectionFinished(.failure)
            }
        }
    }

    private func refreshCurrentSSID(showsResultHUD: Bool = false) {
        guard canRefreshPhoneSSID() else { return }
        WiFiSSIDProvider.shared.fetchCurrentSSID { [weak self] ssid in
            guard let self else { return }
            self.networkSSID = ssid
            self.networkCredentialSource = ssid.isEmpty ? .localClear : .phone
            self.networkPassword = self.cachedPassword(for: ssid)
            self.networkConnectState = self.computeEditableConnectState(password: self.networkPassword)
            self.reloadSection(.networkConnectivity)
            if showsResultHUD {
                self.showRefreshSSIDResultHUD(success: !ssid.isEmpty)
            }
        }
    }

    private func canRefreshPhoneSSID() -> Bool {
        guard networkConnectState != .connecting else { return false }
        return networkCredentialSource != .gateway
    }

    private func showRefreshSSIDResultHUD(success: Bool) {
        if success {
            XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
        } else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
        }
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

    private func updateNetworkPassword(_ password: String) -> GatewayNetworkConnectivityCell.ConnectState {
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
        guard networkConnectState != .connecting else { return }
        isNetworkPasswordVisible.toggle()
        reloadSection(.networkConnectivity)
    }

    private func networkConnectButtonAction() {
        switch networkConnectState {
        case .available:
            connectNetworkWithGateway()
        case .connected:
            clearNetworkByDisconnect()
        case .disabled, .connecting:
            break
        }
    }

    private func connectNetworkWithGateway() {
        guard let credentials = makeCredentialsForConnect() else { return }
        stopNetworkConnectionPolling()
        networkConnectState = .connecting
        setNetworkConnectivityVisible(true)
        reloadSection(.networkConnectivity)
        let operationID = beginNetworkOperation()
        sendWiFiGatewayCredentialsSet(credentials) { [weak self] result in
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
        sendWiFiGatewayGet(.wifiGatewayConnectionStatus, timeout: connectionPollInterval) { [weak self] status in
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
                self.reloadSection(.networkConnectivity)
                self.handleNetworkConnectionFinished(.success)
            case .passwordError, .failed, .reserved(rawValue: _):
                self.stopNetworkConnectionPolling()
                self.networkConnectState = self.computeEditableConnectState(password: self.networkPassword)
                self.reloadSection(.networkConnectivity)
                self.handleNetworkConnectionFinished(.failure)
            case .notStartedOrConnecting:
                break
            }
        }
    }

    private func clearNetworkByDisconnect() {
        stopNetworkConnectionPolling()
        clearLocalNetworkFields()
        reloadSection(.networkConnectivity)
    }

    private func clearNetworkSSIDLocally() {
        guard networkConnectState != .connecting else { return }
        clearLocalNetworkFields()
        reloadSection(.networkConnectivity)
    }

    private func clearLocalNetworkFields() {
        networkSSID = ""
        networkPassword = ""
        networkCredentialSource = .localClear
        isNetworkPasswordVisible = false
        networkConnectState = .disabled
    }

    private func shouldShowSSIDClearButton() -> Bool {
        guard !networkSSID.isEmpty, networkConnectState != .connecting else { return false }
        if networkCredentialSource == .gateway && networkConnectState == .connected {
            return false
        }
        return true
    }

    private func showCredentialsFetchFailedIfVisible() {
        setNetworkConnectivityVisible(false)
        if isNetworkPageVisible {
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

    private func showChangeWiFiAlert() {
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
