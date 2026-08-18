//
//  GatewayViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/17.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

private enum GatewayDestructiveOperationState: Equatable {
    case idle
    case clearingAssociatedSpaces
    case deletingGatewayFromServer
    case resettingAfterServerDeletion
}

private enum GatewayDestructivePermissionResult {
    case allowed
    case denied
    case failed
}

class GatewayViewController: UIViewController, DeviceProtocol {

    var timeZoneSyncDidFinish: ((String, Int) -> Void)?
    var gatewayPageDidClose: (() -> Void)?

    private var tableView: UITableView!
    private var headerView: GatewayInformationHeaderView!
    private var footerView: UIView!
    private var copyInformationBtn: UIButton!
    private(set) var bottomView: DeviceBottomBtnView!
    private var modalDismissalStateBeforeProtectedFlow: Bool?
    private var gatewayClockCoordinator: GatewayDetailClockCoordinator!
    private var gatewayClockState = GatewayDetailClockState()
    private var gatewayClockTimer: Timer?
    private var gatewayClockReadSessionID: UUID?
    private var gatewayClockSyncPresentationID: UUID?
    private var pendingGatewayClockSync: (
        target: GatewayDetailTargetTimeZone,
        presentationID: UUID,
        startedAtUptime: TimeInterval
    )?
    private var gatewayClockAutoPromptState = GatewayClockAutoPromptState()
    private var gatewayClockAutoPromptRetryWorkItem: DispatchWorkItem?
    private var gatewayClockAutoPromptRetryID: UUID?
    private var isGatewayClockReading = false
    private var gatewayClockTickDate = Date()
    private let gatewayClockFormatter = GatewayDetailClockFormatter()
    private var gatewayClockNotificationTokens = [NSObjectProtocol]()

    private var name: String?

    private let setGatewayModel: GatewayModel
    /// 其它网关数据
//    private var otherGateways: [GatewayModel] = []

    var sections: [SectionType] {
        var baseSections: [SectionType] = [.name]
        if showsGatewayClockSections {
            baseSections.append(contentsOf: [.timeZone, .clock])
        }
        baseSections.append(contentsOf: [.associatedSpaces, .apn, .serverInformation])
        return supportsAPNConfiguration ? baseSections : baseSections.filter { $0 != .apn }
    }

    var showsGatewayClockSections: Bool {
        isGatewayProxyReady
    }
    var infoTypes: [InfoCellType] {
        return [.mac, .address, .model, .deviceType, .firmwareVersion]
    }
    /// 页面当前是否可见
    private var isViewVisible: Bool = false
    /// 防止重复进入网关恢复页面
    private var isPresentingGatewayRecovery: Bool = false
    /// 网关 4G 信号刷新定时器
    private var signalRefreshTimer: Timer?
    private var destructiveOperationState: GatewayDestructiveOperationState = .idle
    private var serverDeletionConfirmed = false

    let site: SiteData
    let gateway: Gateway
    let gatewayModel: GatewayModel
    let node: Node
    private weak var lastMessageDelegate: MeshLibManagerMessageDelegate?
    private var proxyReadyObserverID: UUID?
    private var meshConnectionObserverID: UUID?
    private var proxyReadyTimeoutTimer: Timer?
    private var proxyConnectionStateMachine: GatewayDetailProxyConnectionStateMachine

    var isGatewayProxyReady: Bool {
        proxyConnectionStateMachine.state.isReady
    }

    var gatewayProxyReadySessionID: UUID? {
        proxyConnectionStateMachine.state.readySessionID
    }

    private var isGatewayProxyConnecting: Bool {
        proxyConnectionStateMachine.state.activeAttemptID != nil
    }

    private var isGatewayBluetoothOffline: Bool {
        if case .disconnected = proxyConnectionStateMachine.state {
            return true
        }
        return false
    }

    private var canForceClearAssociatedSpaces: Bool {
        guard !gatewayModel.serverDeletionPendingLocalReset,
              !setGatewayModel.associatedSpaces.isEmpty else {
            return false
        }
        return GatewayDestructiveAccessPolicy.canPerform(
            isOwner: site.permission == .owner,
            hasAnyEditableSiteSpace: site.spaces.contains(
                where: \.canEditGatewayAssociation
            ),
            associatedSpaceEditableStates: setGatewayModel.associatedSpaces.map {
                $0.permission == .editor
            }
        )
    }

    var supportsAPNConfiguration: Bool {
        return true
    }

    var supportsGatewaySignalRefresh: Bool {
        return true
    }

    var gatewayFirmwareKind: GatewayFirmwareKind {
        return .fourG
    }

    var canConfigureCurrentGateway: Bool {
        site.canConfigureGateway(setGatewayModel)
    }

    init?(site: SiteData, gateway: Gateway) {
        guard site.canConfigureGateway(gateway.model) else {
            return nil
        }
        self.site = site
        self.gateway = gateway
        self.gatewayModel = gateway.model
        self.node = gateway.node
        self.setGatewayModel = self.gatewayModel.copy()
        self.proxyConnectionStateMachine = GatewayDetailProxyConnectionStateMachine(
            targetAddress: gateway.node.primaryUnicastAddress
        )
        super.init(nibName: nil, bundle: nil)

//        let gateways = GatewayModel.load(siteId: gateway.siteId).filter({ $0.mac != gateway.mac })
//        // 确保是space内的网关
//        otherGateways = gateways.filter({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: $0.address) != nil })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = gatewayModel.name
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        configureNavigationItems()

        name = gatewayModel.name
        lastMessageDelegate = MeshLibManager.manager.messageDelegate

        setupUI()
        gatewayClockCoordinator = GatewayDetailClockCoordinator(
            context: GatewayInformationContext(site: site, gateway: gateway)
        )
        registerGatewayClockNotifications()
        updateData()
        updateSaveBtnState()
        registerProxyConnectionObservers()

//        Task {
//            guard let vendorModel = node.sunricherVendorModel else { return }
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimActivateState), model: vendorModel)
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewayMqttState), model: vendorModel)
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimCpin), model: vendorModel)
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimCreg), model: vendorModel)
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimCpsi), model: vendorModel)
//
//        }
        // 获取网关关联space数据
        Task { [weak self] in
            guard let self else { return }
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
            let result = await self.loadAssociatedSpaces()
            guard !Task.isCancelled else { return }
            XWHUDManager.hide()
            switch result {
            case .success(let bindSpaces):
                let currentAssociatedSpaceIds = self.gatewayModel.associatedSpaces.map({ $0.spaceId })
                self.gatewayModel.associatedSpaces = bindSpaces
                self.setGatewayModel.associatedSpaces = bindSpaces
                self.reloadSection(.associatedSpaces)
                if bindSpaces.map({ $0.spaceId }) != currentAssociatedSpaceIds {
                    self.gatewayModel.save()
                }

            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        isPresentingGatewayRecovery = false
        isViewVisible = true
        MeshLibManager.manager.messageDelegate = self
        refreshServerInformationFromPersistence()
        updateData()
        updateSaveBtnState()
        tableView.reloadData()
        reconcileCurrentProxyReadyContext()
        ensureTargetGatewayProxyConnection()
        syncSignalRefreshState(forceRefresh: isGatewayProxyReady)
        syncGatewayClockTimer()
        attemptGatewayClockAutoPrompt()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isViewVisible = false
        cancelGatewayClockAutoPromptRetry()
        stopSignalRefreshTimer()
        stopGatewayClockTimer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreModalStackDismissalIfNeeded()
    }


    func configureNavigationItems() {
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

    @objc func closeAction() {

        if setGatewayModel == gatewayModel {
            closeGatewayPage()
        }else {
            SRAlertView(title: "notification".localizedString, message: "profile_exiting_message".localizedString, actions: [SRAlertAction(title: "keep_edit".localizedString, style: .cancel), SRAlertAction(title: "EXIT".localizedString, actionHandler: {[weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {[weak self] in
                    self?.closeGatewayPage()
                }
            })]).show()
        }
    }

    @objc func moreClick() {
        let actions = GatewayMenuPolicy.menuActions(
            firmwareKind: gatewayFirmwareKind,
            canDelete: canConfigureCurrentGateway,
            isBluetoothOffline: isGatewayBluetoothOffline,
            hasAssociatedSpaces: !setGatewayModel.associatedSpaces.isEmpty,
            canForceClearSpaces: canForceClearAssociatedSpaces
        )
        let items = actions.map(makeGatewayMenuItem)
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(
            CGPoint(x: touchCenterX, y: touchCenterY),
            to: UIApplication.shared.keyWindow()
        )
        MenuPopView.show(
            items: items,
            anchorPoint: windowPoint,
            menuWidth: SCRXFrom(actions.contains(.forceClearSpaces) ? 164 : 120)
        )
    }

    private func makeGatewayMenuItem(
        _ action: GatewayMenuAction
    ) -> MenuPopView.MenuItem {
        switch action {
        case .fourGDFU:
            return .init(
                icon: UIImage(named: "menu_wifi_dfu"), title: "4g_dfu".localizedString,
                hideAnimation: false,
                performsActionAfterDismiss: true,
                tapItemBack: { [weak self] _ in
                    self?.performGatewayDFUAction()
                }
            )
        case .wifiDFU:
            return .init(
                icon: UIImage(named: "menu_wifi_dfu"), title: "wifi_dfu".localizedString,
                hideAnimation: false,
                performsActionAfterDismiss: true,
                tapItemBack: { [weak self] _ in
                    self?.performGatewayDFUAction()
                }
            )
        case .delete:
            return .init(
                icon: UIImage(named: "menu_delete"), title: "delete".localizedString,
                tapItemBack: { [weak self] _ in
                    self?.deleteBtnAction()
                }
            )
        case .information:
            return .init(
                icon: UIImage(named: "menu_information"), title: "information".localizedString, hideAnimation: false, performsActionAfterDismiss: true,
                tapItemBack: { [weak self] _ in
                    guard let self else { return }
                    let controller = DeviceInformationViewController(
                        node: self.node,
                        showsGroupSection: false,
                        showsSceneSection: false,
                        gatewayContext: GatewayInformationContext(site: self.site, gateway: self.gateway)
                    )
                    self.preventModalStackDismissalUntilReturn()
                    self.pushDeviceInformationController(controller)
                }
            )
        case .identify:
            return .init(
                icon: UIImage(named: "menu_identify"), title: "identify".localizedString,
                tapItemBack: { [weak self] _ in
                    guard let self else { return }
                    MeshAPI.identify(address: self.node.primaryUnicastAddress)
                }
            )
        case .forceClearSpaces:
            return .init(
                icon: UIImage(named: "menu_clear_spaces"),
                title: "gateway_force_clear_spaces".localizedString,
                tapItemBack: { [weak self] _ in
                    self?.showForceClearAssociatedSpacesConfirmation()
                }
            )
        }
    }

    func performGatewayDFUAction() {
        XWHUDManager.showTipHUD(
            "under_development".localizedString,
            isLineFeed: true
        )
    }

    func preventModalStackDismissalUntilReturn() {
        guard let navigationController else { return }
        if modalDismissalStateBeforeProtectedFlow == nil {
            modalDismissalStateBeforeProtectedFlow = navigationController.isModalInPresentation
        }
        navigationController.isModalInPresentation = true
    }

    private func restoreModalStackDismissalIfNeeded() {
        guard let previousState = modalDismissalStateBeforeProtectedFlow else { return }
        navigationController?.isModalInPresentation = previousState
        modalDismissalStateBeforeProtectedFlow = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // EmptyDataView uses frame layout, update it after container frame is finalized.
        view.emptyView?.frame = view.bounds
    }

    func closeGatewayPage() {
        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1  {
            let completion = gatewayPageDidClose
            dismiss(animated: true) {
                completion?()
            }
        }else {
            navigationController?.popViewController(animated: true)
            gatewayPageDidClose?()
        }
    }

    deinit {
        gatewayClockCoordinator?.finishPage()
        cancelGatewayClockAutoPromptRetry()
        stopGatewayClockTimer()
        gatewayClockNotificationTokens.forEach(NotificationCenter.default.removeObserver)
        stopSignalRefreshTimer()
        cancelProxyReadyTimeout()
        MeshLibManager.manager.messageDelegate = self.lastMessageDelegate
        if let proxyReadyObserverID {
            MeshLibManager.manager.removeGlobalProxyReadyObserver(proxyReadyObserverID)
        }
        if let meshConnectionObserverID {
            MeshLibManager.manager.removeGlobalConnectionObserver(meshConnectionObserverID)
        }

        MeshLibManager.manager.close()

        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
    }

    private func registerProxyConnectionObservers() {
        proxyReadyObserverID = MeshLibManager.manager.addGlobalProxyReadyObserver { [weak self] context in
            self?.handleProxyReady(context)
        }
        meshConnectionObserverID = MeshLibManager.manager.addGlobalConnectionObserver { [weak self] _, isConnected in
            guard !isConnected else { return }
            self?.handleProxyConnectionEvent(.meshDisconnected)
        }
        reconcileCurrentProxyReadyContext()
    }

    private func reconcileCurrentProxyReadyContext() {
        guard let context = MeshLibManager.manager.currentProxyReadyContext else {
            if isGatewayProxyReady {
                handleProxyConnectionEvent(.meshDisconnected)
            }
            return
        }
        handleProxyReady(context)
    }

    private func handleProxyReady(_ context: ProxyReadyContext) {
        let isTargetContext = context.nodeAddress == node.primaryUnicastAddress
        handleProxyConnectionEvent(
            .proxyReady(nodeAddress: context.nodeAddress, sessionID: context.sessionID),
            readyContext: isTargetContext ? context : nil
        )
    }

    private func ensureTargetGatewayProxyConnection() {
        if let context = MeshLibManager.manager.currentProxyReadyContext,
           context.nodeAddress == node.primaryUnicastAddress {
            handleProxyReady(context)
            return
        }
        guard !isGatewayProxyReady, !isGatewayProxyConnecting else { return }

        let attemptID = UUID()
        handleProxyConnectionEvent(.startConnecting(attemptID: attemptID))
        MeshLibManager.manager.connectProxy(node: node) { [weak self] succeeded in
            DispatchQueue.main.async {
                guard let self else { return }
                self.handleProxyConnectionEvent(
                    .connectCompleted(attemptID: attemptID, succeeded: succeeded)
                )
                guard succeeded,
                      self.proxyConnectionStateMachine.state.activeAttemptID == attemptID else {
                    return
                }
                self.scheduleProxyReadyTimeout(for: attemptID)
            }
        }
    }

    private func handleProxyConnectionEvent(
        _ event: GatewayDetailProxyConnectionEvent,
        readyContext: ProxyReadyContext? = nil
    ) {
        let changed = proxyConnectionStateMachine.reduce(event)
        let isCurrentReadyContext = readyContext.map {
            gatewayProxyReadySessionID == $0.sessionID
        } ?? false
        guard changed || isCurrentReadyContext else { return }

        if changed {
            if !isGatewayProxyConnecting {
                cancelProxyReadyTimeout()
            }
            renderProxyConnectionState()
            gatewayProxyReadyStateDidUpdate(isGatewayProxyReady)
        }

        if let readyContext, isCurrentReadyContext {
            gatewayProxyDidBecomeReady(readyContext)
        }

        guard changed else { return }

        guard isViewVisible,
              !isGatewayProxyReady,
              !isGatewayProxyConnecting else {
            return
        }
        switch event {
        case .meshDisconnected,
             .proxyReady(nodeAddress: _, sessionID: _):
            DispatchQueue.main.async { [weak self] in
                self?.ensureTargetGatewayProxyConnection()
            }
        default:
            break
        }
    }

    private func renderProxyConnectionState() {
        switch proxyConnectionStateMachine.state {
        case .connecting:
            headerView.showConnectingUI()
            stopSignalRefreshTimer()
        case .ready:
            headerView.hideConnectingUI()
            syncSignalRefreshState(forceRefresh: true)
        case .disconnected:
            headerView.hideConnectingUI()
            stopSignalRefreshTimer()
            clearGatewaySignal()
        }
        updateData()
        updateSaveBtnState()
    }

    private func scheduleProxyReadyTimeout(for attemptID: UUID) {
        cancelProxyReadyTimeout()
        proxyReadyTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.handleProxyConnectionEvent(.readyTimedOut(attemptID: attemptID))
        }
        if let proxyReadyTimeoutTimer {
            RunLoop.main.add(proxyReadyTimeoutTimer, forMode: .common)
        }
    }

    private func cancelProxyReadyTimeout() {
        proxyReadyTimeoutTimer?.invalidate()
        proxyReadyTimeoutTimer = nil
    }

    /// 获取网关信号
    private func getGatewaySignal() {
        guard supportsGatewaySignalRefresh else {
            clearGatewaySignal()
            return
        }
        guard isGatewayProxyReady else {
            clearGatewaySignal()
            return
        }
        guard let vendorModel = self.node.sunricherVendorModel else { return }
        MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimCpin), model: vendorModel) {[weak self] response in
            guard let self = self else { return }
            guard self.isGatewayProxyReady else {
                self.clearGatewaySignal()
                return
            }
            if let statusMessage = response as? SunricherVendorStatus, case .gatewaySimCpinState(let cpin, let csqRssi, _) = statusMessage.status.parameters {
                self.gatewayModel.csqRssi = Int(csqRssi)
                self.gatewayModel.isSimInserted = cpin >= 0
            }else {
                self.gatewayModel.csqRssi = nil
            }
            self.updateData()
        }
    }

    @objc private func refreshGatewaySignal() {
        guard supportsGatewaySignalRefresh else {
            stopSignalRefreshTimer()
            clearGatewaySignal()
            return
        }
        guard isGatewayProxyReady else {
            stopSignalRefreshTimer()
            clearGatewaySignal()
            return
        }
        getGatewaySignal()
    }

    private func syncSignalRefreshState(forceRefresh: Bool = false) {
        guard supportsGatewaySignalRefresh else {
            stopSignalRefreshTimer()
            clearGatewaySignal()
            return
        }
        guard isViewLoaded, isViewVisible else {
            stopSignalRefreshTimer()
            return
        }

        if isGatewayProxyReady {
            startSignalRefreshTimer()
            if forceRefresh {
                getGatewaySignal()
            }
        } else {
            stopSignalRefreshTimer()
            clearGatewaySignal()
        }
    }

    private func startSignalRefreshTimer() {
        guard signalRefreshTimer == nil else { return }
        signalRefreshTimer = LCWeakTimer.scheduledTimer(timeInterval: 10, aTarget: self, selector: #selector(refreshGatewaySignal), userInfo: nil, repeats: true)
        if let signalRefreshTimer {
            RunLoop.main.add(signalRefreshTimer, forMode: .common)
        }
    }

    private func stopSignalRefreshTimer() {
        signalRefreshTimer?.invalidate()
        signalRefreshTimer = nil
    }

    private func clearGatewaySignal() {
        guard gatewayModel.csqRssi != nil else { return }
        gatewayModel.csqRssi = nil
        updateData()
    }

    /// 获取已关联的spaces
    private func loadAssociatedSpaces(
        maximumDuration: TimeInterval? = nil
    ) async -> Result<[GatewaySpaceData], Error> {

        let target = NetowrkReqeustApi.gatewayAssociationSpaceList(
            siteId: gatewayModel.siteId,
            gatewayId: gatewayModel.mac
        )
        let result: Result<[String: Any], NetworkApiError>
        if let maximumDuration {
            result = await NetworkRequest.shared.request(
                target,
                maximumDuration: maximumDuration
            )
        } else {
            result = await NetworkRequest.shared.request(target)
        }
        switch result {
        case .success(let response):
            let list = JSON(response)["data"]["refSpaces"].arrayValue
            // 网关已绑定的space
            let bindSpaces: [GatewaySpaceData] = list.compactMap { spaceJson in
                guard let spaceId = spaceJson["spaceId"].string, let spaceName = spaceJson["spaceName"].string, let deviceCount = spaceJson["deviceCount"].int, let appKeyIndex = spaceJson["appKey"]["index"].uInt16 else {
                    return nil
                }
                let gatewaySpace = GatewaySpaceData(spaceId: spaceId, spaceName: spaceName, deviceCount: deviceCount, appKeyIndex: appKeyIndex)
                let space = SpaceData.load(
                    siteId: self.gatewayModel.siteId,
                    spaceId: spaceId
                ).first
                gatewaySpace.updatePermission(from: space)
                return gatewaySpace
            }
            return .success(bindSpaces)

        case .failure(let error):
            return .failure(error)
        }
    }


    @objc private func copyInformationBtnAction() {

        var copyContent: String = ""
//        if gateway.name {
            copyContent.append("\("name".localizedString): \(gatewayModel.name)")
//        }else {
//            copyContent.append("\("name".localizedString): N/A")
//        }

//        if let mac = node.gatewayModel?.mac {
        copyContent.append("\n\("MAC".localizedString): \(node.macAddressResult ?? gatewayModel.mac)")
//        }else {
//            copyContent.append("\n\("MAC".localizedString): N/A")
//        }
        copyContent.append("\n\("address".localizedString): \(node.primaryUnicastAddress)")

        if let modelName = node.modelName {
            copyContent.append("\n\("model".localizedString): \(modelName)")
        }

        if let categoryName = node.categoryName {
            copyContent.append("\n\("device_type".localizedString): \(categoryName)")
        }

        if let version = node.firmwareVersion {
            copyContent.append("\n\("firmware".localizedString): \(version)")
        }

//        if let activate = gateway.activate {
            copyContent.append("\n\("activate".localizedString): \(gatewayModel.activate ? "Yes".localizedString : "No".localizedString)")
//        }else {
//            copyContent.append("\n\("activate".localizedString): N/A")
//        }

        let associatedSpaces = gatewayAssociatedSpacesToDisplay()
        if associatedSpaces.count > 0 {
            let spacesName = associatedSpaces.map({ $0.spaceName }).joined(separator: ",")
            copyContent.append("\n\("associated_spaces".localizedString): \(spacesName)")
        }else {
            copyContent.append("\n\("associated_spaces".localizedString): \("no_associated_spaces".localizedString)")
        }

        if supportsAPNConfiguration {
            if let apn = gatewayModel.apn {
                copyContent.append("\n\("apn".localizedString): \(apn)")
            }else {
                copyContent.append("\n\("apn".localizedString): \("not_set".localizedString)")
            }
        }
        if let mqttServerInfo = gatewayModel.mqttServerInfo {
            let serverStr = mqttServerInfo.serverAddress.replacingOccurrences(of: "tcp://", with: "")
            let serverAddressArray = serverStr.components(separatedBy: ":")
            if let ip = serverAddressArray.first {
                copyContent.append("\n\("server_address".localizedString): \(ip)")
            }else {
                copyContent.append("\n\("server_address".localizedString): N/A")
            }
            if serverAddressArray.count >= 2 {
                let port = serverAddressArray[1]
                copyContent.append("\n\("port".localizedString): \(port)")
            }else {
                copyContent.append("\n\("port".localizedString): N/A")
            }
            copyContent.append("\n\("client_id".localizedString): \(mqttServerInfo.clientId)")
        }else {
            copyContent.append("\n\("server_address".localizedString): N/A")
            copyContent.append("\n\("port".localizedString): N/A")
            copyContent.append("\n\("client_id".localizedString): N/A")
        }

        UIPasteboard.general.string = copyContent
        XWHUDManager.showTipHUD("copy_success".localizedString, isLineFeed: false)
    }

    private func updateData() {

        if node.isKeybindComplete {

            view.hideEmptyDataView()
            headerView.updateData(gateway: gateway, isProxyReady: isGatewayProxyReady)
            if isGatewayProxyConnecting {
                bottomView.deleteBtn.isEnabled = false
            }else {
                if !canConfigureCurrentGateway {
                    bottomView.deleteBtn.isEnabled = false
                }else {
                    bottomView.deleteBtn.isEnabled = true
                }
            }

            showConfiguredBottomActions()
        } else {
            if view.emptyView == nil {
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) {[weak self] in
                    // 修复
                    self?.performGatewayRepair()
                }
                if let emptyView = view.emptyView {
                    if canConfigureCurrentGateway {
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                        }
                    }else {
                        emptyView.button.isHidden = true
                    }
                }
                view.bringSubviewToFront(bottomView)
                showRepairBottomActions()
            }
        }
    }

    func showConfiguredBottomActions() {
        applyBottomActionMode(
            GatewayMenuPolicy.bottomActionMode(isConfigured: true)
        )
    }

    func showRepairBottomActions() {
        applyBottomActionMode(
            GatewayMenuPolicy.bottomActionMode(isConfigured: false)
        )
    }

    private func applyBottomActionMode(_ mode: GatewayBottomActionMode) {
        switch mode {
        case .saveOnly:
            bottomView.isHidden = false
            bottomView.showSaveOnlyUI()
        case .hidden:
            bottomView.isHidden = true
        }
    }

    /// 修复
    func performGatewayRepair() {

        repairDevices(nodes: [node], result: {[weak self] _, _ in
            guard let self = self else { return }
            if self.node.isKeybindComplete {
                self.updateData()
//                self.getNodeState()
                // 通知网关数据修改
                NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
            }
        })
    }

    /// 保存
    @objc private func saveBtnAction() {
        guard let name = self.name, !name.isAllInputTextEmpty() else {
            return
        }
        guard site.canConfigureGateway(setGatewayModel) else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }

        bottomView.saveBtn.isEnabled = false
        Task { [weak self] in
            guard let self = self else { return }
            let associationResult = await self.saveAssociatedSpacesIfNeeded()
            guard associationResult.succeeded else {
                if associationResult.topologyChanged {
                    self.notifySiteGatewayAssociationTopologyChanged()
                }
                self.updateSaveBtnState()
                return
            }
            self.persistGatewayConfiguration(
                name: name,
                associationTopologyChanged: associationResult.topologyChanged
            )
        }
    }

    private func persistGatewayConfiguration(
        name: String,
        associationTopologyChanged: Bool
    ) {
        if gateway.name != name {
            self.setGatewayModel.name = name
            self.gateway.name = name
            self.node.name = name
            self.title = name
            self.node.save()
        }

        gatewayModel.update(gatewayModel: setGatewayModel)
        gateway.model.save()
        if associationTopologyChanged {
            notifySiteGatewayAssociationTopologyChanged()
        }
        //        node.gatewayModel?.update(gatewayModel: setGatewayModel)
        //        node.gatewayModel?.save()

        updateSaveBtnState()
        // 判断是否需要同步设备数据
        guard node.getNodeSyncGatewayData(gateway: setGatewayModel).count > 0 else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            // 通知网关数据修改
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
            return
        }
        let vc = SyncDevicesViewController(type: .devices([node]))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
                self?.updateSaveBtnState()
                self?.tableView.reloadData()
            }
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            self.updateSaveBtnState()
            self.tableView.reloadData()

            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func notifySiteGatewayAssociationTopologyChanged() {
        NotificationCenter.default.post(
            name: .init(siteGatewayAssociationTopologyChangedNotificationName),
            object: gateway
        )
    }

    private struct AssociatedSpacesSaveResult {
        let succeeded: Bool
        let topologyChanged: Bool
    }

    private func saveAssociatedSpacesIfNeeded() async -> AssociatedSpacesSaveResult {
        let baselineSpaces = gatewayModel.associatedSpaces
        let requestedSpaces = setGatewayModel.associatedSpaces
        guard Set(baselineSpaces.map(\.spaceId)) !=
                Set(requestedSpaces.map(\.spaceId)) else {
            return .init(succeeded: true, topologyChanged: false)
        }
        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("gateway_associated_no_network_message".localizedString, isLineFeed: true, afterDelay: 1.5)
            return .init(succeeded: false, topologyChanged: false)
        }

        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        let latestSpaces: [GatewaySpaceData]
        switch await loadAssociatedSpaces() {
        case .success(let spaces):
            latestSpaces = spaces
        case .failure(let error):
            XWHUDManager.hide()
            XWHUDManager.showErrorTipHUD(error.localizedDescription)
            return .init(succeeded: false, topologyChanged: false)
        }

        let editableSpaceIDs = Set(
            site.spaces
                .filter(\.canEditGatewayAssociation)
                .map(\.id)
        )
        let mutationResolution = GatewayAssociatedSpaceMutationPolicy.resolve(
            isOwner: site.permission == .owner,
            baselineSpaceIDs: baselineSpaces.map(\.spaceId),
            latestServerSpaceIDs: latestSpaces.map(\.spaceId),
            requestedSpaceIDs: requestedSpaces.map(\.spaceId),
            editableSpaceIDs: editableSpaceIDs
        )

        let mutationPlan: GatewayAssociatedSpaceMutationPlan
        switch mutationResolution {
        case .allowed(let plan):
            mutationPlan = plan
        case .topologyChanged:
            applyAuthoritativeAssociatedSpaces(latestSpaces)
            XWHUDManager.hide()
            XWHUDManager.showTipHUD(
                "gateway_associated_spaces_changed_message".localizedString,
                isLineFeed: true,
                afterDelay: 1.5
            )
            return .init(succeeded: false, topologyChanged: true)
        case .denied:
            applyAuthoritativeAssociatedSpaces(latestSpaces)
            XWHUDManager.hide()
            XWHUDManager.showErrorTipHUD("no_permission".localizedString)
            return .init(succeeded: false, topologyChanged: false)
        }

        let addSpaces = mutationPlan.additionSpaceIDs.compactMap { spaceID in
            requestedSpaces.first(where: {
                $0.spaceId.caseInsensitiveCompare(spaceID) == .orderedSame
            })
        }
        let unbindSpaces = mutationPlan.removalSpaceIDs.compactMap { spaceID in
            latestSpaces.first(where: {
                $0.spaceId.caseInsensitiveCompare(spaceID) == .orderedSame
            })
        }
        var topologyChanged = false
        for space in addSpaces {
            let result = await NetworkRequest.shared.request(.gatewayBindSpace(spaceId: space.spaceId, gatewayId: gateway.mac))
            switch result {
            case .success:
                topologyChanged = true
            case .failure(let error):
                await reconcileAssociatedSpacesAfterPartialSave()
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
                return .init(
                    succeeded: false,
                    topologyChanged: topologyChanged
                )
            }
        }
        for space in unbindSpaces {
            let result = await NetworkRequest.shared.request(.gatewayUnbindSpace(spaceId: space.spaceId, gatewayId: gateway.mac))
            switch result {
            case .success:
                topologyChanged = true
            case .failure(let error):
                await reconcileAssociatedSpacesAfterPartialSave()
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
                return .init(
                    succeeded: false,
                    topologyChanged: topologyChanged
                )
            }
        }
        XWHUDManager.hide()
        return .init(succeeded: true, topologyChanged: topologyChanged)
    }

    private func reconcileAssociatedSpacesAfterPartialSave() async {
        guard case .success(let spaces) = await loadAssociatedSpaces() else {
            return
        }
        applyAuthoritativeAssociatedSpaces(spaces)
    }

    private func applyAuthoritativeAssociatedSpaces(
        _ spaces: [GatewaySpaceData]
    ) {
        gatewayModel.associatedSpaces = spaces
        setGatewayModel.associatedSpaces = spaces
        gatewayModel.save()
        reloadSection(.associatedSpaces)
        reloadSection(.name)
        updateSaveBtnState()
    }

    private func showForceClearAssociatedSpacesConfirmation() {
        guard destructiveOperationState == .idle,
              isGatewayBluetoothOffline,
              !setGatewayModel.associatedSpaces.isEmpty else {
            return
        }
        let actionFont = UIFont.systemFont(
            ofSize: SCRYFrom(15),
            weight: .light
        )
        SRAlertView(
            title: "gateway_force_clear_spaces_title".localizedString,
            titleColor: Title_Color,
            titleFont: UIFont.systemFont(ofSize: SCRYFrom(15), weight: .regular),
            message: "gateway_force_clear_spaces_message".localizedString,
            messageColor: Title_Color,
            messageFont: actionFont,
            tapBackgroundHide: false,
            contentMinHeight: SCRYFrom(222),
            actions: [
                .cancelAction,
                SRAlertAction(
                    title: "gateway_force_clear_spaces_action".localizedString,
                    titleColor: Error_Red_Color,
                    titleFont: actionFont,
                    style: .destructive,
                    performsActionAfterDismiss: true,
                    actionHandler: { [weak self] _ in
                        self?.beginForceClearAssociatedSpaces()
                    }
                )
            ]
        ).show()
    }

    private func beginForceClearAssociatedSpaces() {
        guard destructiveOperationState == .idle else { return }
        destructiveOperationState = .clearingAssociatedSpaces
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)

        Task { [weak self] in
            guard let self else { return }
            switch await self.verifyDestructiveOperationPermission(deadline: deadline) {
            case .allowed:
                break
            case .denied:
                XWHUDManager.hide()
                self.destructiveOperationState = .idle
                XWHUDManager.showErrorTipHUD("no_permission".localizedString)
                return
            case .failed:
                self.finishForceClearAssociatedSpacesWithFailure()
                return
            }

            let remainingDuration = self.remainingDuration(until: deadline)
            let result = await NetworkRequest.shared.request(
                .gatewayUnbindAllSpaces(gatewayId: self.gateway.mac),
                maximumDuration: remainingDuration
            )
            guard self.destructiveOperationState == .clearingAssociatedSpaces else {
                return
            }
            switch result {
            case .success:
                self.gatewayModel.associatedSpaces.removeAll()
                self.setGatewayModel.associatedSpaces.removeAll()
                self.gatewayModel.save()
                self.reloadSection(.associatedSpaces)
                self.updateSaveBtnState()
                self.notifySiteGatewayAssociationTopologyChanged()
                XWHUDManager.hide()
                self.destructiveOperationState = .idle
                ToastStatusView.show(
                    in: self.view,
                    message: "gateway_force_clear_spaces_success".localizedString,
                    type: .success,
                    appearance: .siteUpdate,
                    position: .bottom
                )
            case .failure:
                self.finishForceClearAssociatedSpacesWithFailure()
            }
        }
    }

    private func finishForceClearAssociatedSpacesWithFailure() {
        XWHUDManager.hide()
        destructiveOperationState = .idle
        ToastStatusView.show(
            in: view,
            message: "gateway_force_clear_spaces_failed".localizedString,
            type: .failure,
            appearance: .siteUpdate,
            position: .bottom
        )
    }

    private func verifyDestructiveOperationPermission(
        deadline: TimeInterval
    ) async -> GatewayDestructivePermissionResult {
        if site.permission == .owner {
            return .allowed
        }
        let remainingDuration = remainingDuration(until: deadline)
        guard remainingDuration > 0 else {
            return .failed
        }
        switch await loadAssociatedSpaces(maximumDuration: remainingDuration) {
        case .success(let spaces):
            return GatewayDestructiveAccessPolicy.canPerform(
                isOwner: site.permission == .owner,
                hasAnyEditableSiteSpace: site.spaces.contains(
                    where: \.canEditGatewayAssociation
                ),
                associatedSpaceEditableStates: spaces.map {
                    $0.permission == .editor
                }
            )
                ? .allowed
                : .denied
        case .failure:
            return .failed
        }
    }

    private func remainingDuration(until deadline: TimeInterval) -> TimeInterval {
        max(0, deadline - ProcessInfo.processInfo.systemUptime)
    }

    /// 删除
    @objc func deleteBtnAction() {

        guard destructiveOperationState == .idle,
              canConfigureCurrentGateway else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }

        SRAlertView(title: "notification".localizedString, message: "gateway_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            self?.beginGatewayDeletion()
        })]).show()

    }

    private func beginGatewayDeletion() {
        guard destructiveOperationState == .idle else { return }
        if gatewayModel.serverDeletionPendingLocalReset {
            serverDeletionConfirmed = true
            destructiveOperationState = .resettingAfterServerDeletion
            resetNodeAfterServerDeletion()
            return
        }
        destructiveOperationState = .deletingGatewayFromServer
        serverDeletionConfirmed = false
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        XWHUDManager.showCustomHUD(
            withMessage: "deleting".localizedString,
            isWindow: true
        )

        Task { [weak self] in
            guard let self else { return }
            switch await self.verifyDestructiveOperationPermission(deadline: deadline) {
            case .allowed:
                break
            case .denied:
                XWHUDManager.hide()
                self.destructiveOperationState = .idle
                XWHUDManager.showErrorTipHUD("no_permission".localizedString)
                return
            case .failed:
                self.finishGatewayServerDeletionWithFailure(
                    restoreCloudSynchronization: false
                )
                return
            }

            let syncOperation = SyncOperation.syncGateway(
                gateway: self.gatewayModel,
                node: self.node
            )
            let shouldRestoreCloudSynchronization =
                self.gatewayModel.needUploadCloud ||
                CloudSynchronizationManager.shared.getGatewayCurrentSyncState(
                    self.gatewayModel
                ) != nil
            self.gatewayModel.isServerDeletionInProgress = true
            CloudSynchronizationManager.shared.cancelSynchronizationHandle(
                operation: syncOperation
            )
            await GatewayServerAuthorizationService.shared
                .waitForInFlightAuthorizationToFinish(
                    gateway: self.gatewayModel
                )

            let remainingDuration = self.remainingDuration(until: deadline)
            let deleteResult = await NetworkRequest.shared.request(
                .gatewayDelete(gatewayId: self.gateway.mac),
                maximumDuration: remainingDuration
            )
            guard self.destructiveOperationState == .deletingGatewayFromServer else {
                return
            }
            switch deleteResult {
            case .success:
                self.gatewayModel.serverDeletionPendingLocalReset = true
                self.setGatewayModel.serverDeletionPendingLocalReset = true
                self.gatewayModel.isServerDeletionInProgress = false
                self.gatewayModel.save()
                self.serverDeletionConfirmed = true
                self.destructiveOperationState = .resettingAfterServerDeletion
                XWHUDManager.hide()
                self.resetNodeAfterServerDeletion()
            case .failure:
                self.finishGatewayServerDeletionWithFailure(
                    restoreCloudSynchronization: shouldRestoreCloudSynchronization
                )
            }
        }
    }

    private func finishGatewayServerDeletionWithFailure(
        restoreCloudSynchronization: Bool
    ) {
        XWHUDManager.hide()
        gatewayModel.isServerDeletionInProgress = false
        destructiveOperationState = .idle
        serverDeletionConfirmed = false
        if restoreCloudSynchronization,
           !gatewayModel.serverDeletionPendingLocalReset {
            CloudSynchronizationManager.shared.addSynchronizationHandle(
                operation: .syncGateway(gateway: gatewayModel, node: node),
                level: .promptly
            )
        }
        ToastStatusView.show(
            in: view,
            message: "gateway_delete_server_failed".localizedString,
            type: .failure,
            appearance: .siteUpdate,
            position: .bottom
        )
    }

    /// 服务器删除成功后重置设备
    private func resetNodeAfterServerDeletion() {
        guard serverDeletionConfirmed,
              destructiveOperationState == .resettingAfterServerDeletion else {
            return
        }
        self.deleteNodes(nodes: [node], forceDeleteMessage: "gateway_force_delete_message".localizedString, forceDeleteNote: "gateway_force_delete_note".localizedString) {[weak self] successNodes, _ in
            guard let self = self else { return }
            if successNodes.contains(where: { $0.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
                    self.gatewayModel.delete()
                    self.serverDeletionConfirmed = false
                    self.destructiveOperationState = .idle
                    self.closeGatewayPage()
                    NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
                }
            }else {
                self.serverDeletionConfirmed = false
                self.destructiveOperationState = .idle
                self.tableView.reloadData()
            }
        }

    }


    /// 服务器授权绑定网关
    private func authorizeRequest() {

        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }

        Task {
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)

            // 判断网关是否注册mqtt服务
            if self.gatewayModel.mqttServerInfo == nil,
               let localNodeDict = await node.export() {
                let nodeDict = GatewayRegistrationPayloadPolicy
                    .mergeOpaqueAssociationData(
                        localNode: localNodeDict,
                        remoteNode: gatewayModel.registrationProtectionSnapshot?.nodeData,
                        associatedAppKeyIndexes: gatewayModel.associatedSpaces.map(
                            \.appKeyIndex
                        ),
                        isActivated: gatewayModel.activate
                    )
                let gatewayRegisterResult = await NetworkRequest.shared.request(.gatewayRegister(siteId: self.site.id, gatewayId: self.gateway.mac, nodeId: self.node.uuid.uuidString, node: nodeDict, updateTimestamp: self.gateway.lastUpdate))
                switch gatewayRegisterResult {
                case .success(let response):
                    // MQTT参数
                    if let data = response["data"] as? [String: Any],
                       let username = data["mqttUsername"] as? String,
                       let password = data["mqttPassword"] as? String,
                       let clientId = data["mqttClientId"] as? String,
                       let host = data["host"] as? String, let port = data["port"] as? Int {
                        let mqttServerInfo = GatewayInformation.MQTTConnectInformation(customId: customId, serverAddress: "tcp://\(host):\(port)", userName: username, password: password, clientId: clientId, keepalive: 60, clearSession: true, authMode: .none, sslVersion: .all)
                        self.setGatewayModel.mqttServerInfo = mqttServerInfo
                        self.gatewayModel.mqttServerInfo = mqttServerInfo
                        self.gatewayModel.save()

                        // 同步到设备
                        if let vendorModel = self.node.sunricherVendorModel {
                            _ = await MeshAPI.sendMessage(message: SunricherVendorSet(function: .gatewayMQTTConnectInfoSet(connectInfo: mqttServerInfo)), model: vendorModel)
                        }

                        // 通知网关数据修改
                        NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
                    }
                case .failure:
                    XWHUDManager.hide()
                    XWHUDManager.showErrorTipHUD("server_failure".localizedString)
                    return
                }
            }

//             判断网关是否绑定到space
//            if !gateway.associatedSpaces.contains(where: { $0.id == self.space.id }) {
//                let bindSpaceResult = await NetworkRequest.shared.request(.gatewayBindSpace(spaceId: self.space.id, gatewayId: gateway.mac))
//                switch bindSpaceResult {
//                case .success:
//                    gateway.associatedSpaces.append(self.space)
//                    self.setGatewayModel?.associatedSpaces.append(self.space)
//                    gateway.save()
//                    break
//                case .failure:
//                    XWHUDManager.hide()
////                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
//                    XWHUDManager.showErrorTipHUD("server_failure".localizedString)
//                    return
//                }
//            }

            XWHUDManager.hide()
            self.tableView.reloadData()
            self.updateSaveBtnState()
        }
    }

    func performServerAuthorization() {
        authorizeRequest()
    }

    func refreshServerInformationFromPersistence() {
        guard let persistedGateway = GatewayModel.load(
            siteId: gatewayModel.siteId,
            macAddress: gatewayModel.mac
        ).first else {
            return
        }
        gatewayModel.mqttServerInfo = persistedGateway.mqttServerInfo
        setGatewayModel.mqttServerInfo = persistedGateway.mqttServerInfo
    }

    func recoverServerInformation() {
        guard canConfigureCurrentGateway,
              !isPresentingGatewayRecovery,
              let navigationController else {
            return
        }
        isPresentingGatewayRecovery = true

        let controller = SyncDevicesViewController(
            type: .gatewayServerRecovery(
                node: node,
                gateway: gatewayModel
            )
        )
        controller.syncSuccessCallback = { [weak self] _ in
            guard let self else { return }
            self.refreshServerInformationFromPersistence()
            self.updateData()
            self.updateSaveBtnState()
            self.tableView.reloadData()
            NotificationCenter.default.post(
                name: .init(siteGatewayDataChangedNotificaitonName),
                object: self.gateway
            )
        }
        navigationController.pushViewController(controller, animated: true)
    }

    func resync(trigger: SyncDevicesViewController.GatewayRecoveryTrigger) {

        guard !isPresentingGatewayRecovery,
              let navigationController else {
            return
        }
        isPresentingGatewayRecovery = true

        let vc = SyncDevicesViewController(
            type: .gatewayRecovery(
                node: node,
                gateway: gatewayModel,
                trigger: trigger
            ),
            reSync: !trigger.startsImmediately
        )
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            self.refreshServerInformationFromPersistence()
            self.updateData()
            self.updateSaveBtnState()
            self.tableView.reloadData()
            // 通知网关数据修改
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
        }
        navigationController.pushViewController(vc, animated: true)

    }

    func prepareForGatewayRecovery(_ completion: @escaping () -> Void) {
        completion()
    }

    private func associatedSpaces() {

        guard canConfigureCurrentGateway else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }

        guard gatewayModel.mqttServerInfo != nil else {
            XWHUDManager.showTipHUD("associate_space_unauthorized_message".localizedString, isLineFeed: true, afterDelay: 1.5)
            return
        }

        let vc = GatewayAssociatedSpacesController(
            gateway: setGatewayModel
        ) { [weak self] in
            self?.loadAssociatedSpaceCandidates() ?? .unavailable
        }
        vc.associatedSpacesSelectCallback = {[weak self] spaces in
            guard let self = self else { return }
            self.setGatewayModel.associatedSpaces = spaces
            self.reloadSection(.associatedSpaces)
            self.reloadSection(.name)
            self.updateSaveBtnState()
        }
        navigationController?.pushViewController(vc, animated: true)

    }

    private func loadAssociatedSpaceCandidates() -> GatewayAssociatedSpacesCandidateLoadResult {
        guard let meshNetwork = MeshNetwork.load(
            meshUUID: site.meshUUID,
            subnetworkId: site.meshNetworkId,
            allData: false
        ) else {
            return .unavailable
        }

        var appKeyIndicesByNetworkId: [String: UInt16] = [:]
        meshNetwork.applicationKeys.forEach { appKey in
            let networkId = appKey.boundNetworkKey.networkId.hex.lowercased()
            if appKeyIndicesByNetworkId[networkId] == nil {
                appKeyIndicesByNetworkId[networkId] = appKey.index
            }
        }

        let candidateInputs = site.spaces.map { space in
            GatewayAssociatedSpaceCandidateInput(
                spaceId: space.id,
                canEdit: space.canEditGatewayAssociation,
                associatedGatewayId: space.relevanceGatewayId,
                meshNetworkId: space.meshNetworkId
            )
        }
        let resolution = GatewayAssociatedSpaceCandidatePolicy.resolve(
            spaces: candidateInputs,
            currentGatewayId: gateway.mac,
            appKeyIndicesByNetworkId: appKeyIndicesByNetworkId
        )

        switch resolution {
        case .available(let candidates):
            let spaces = candidates.compactMap { candidate -> GatewaySpaceData? in
                guard let space = site.spaces.first(where: {
                    $0.id == candidate.spaceId
                }) else {
                    return nil
                }
                return GatewaySpaceData(
                    spaceId: space.id,
                    spaceName: space.name,
                    deviceCount: space.deviceCount,
                    appKeyIndex: candidate.appKeyIndex,
                    permission: .editor
                )
            }
            return .available(spaces)
        case .unavailable(let missingAppKeySpaceIds):
#if DEBUG
            print(
                "Gateway Associated Spaces missing AppKey:",
                missingAppKeySpaceIds
            )
#endif
            return .unavailable
        }
    }

    /// 解除空间关联
    private func unbindAssociatedSpace(_ space: GatewaySpaceData) {

        guard canConfigureCurrentGateway else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }

        if let index = setGatewayModel.associatedSpaces.firstIndex(where: { $0.spaceId == space.spaceId }) {
            setGatewayModel.associatedSpaces.remove(at: index)
            reloadSection(.associatedSpaces)
            reloadSection(.name)
            updateSaveBtnState()
        }
    }

    /// 选择sim卡 APN
    private func selectSIMAPN(point: CGPoint) {
        var items = GatewaySIMApnInfo.all.map({ GatewayAPNMenuView.APNMenuItem(title: $0.country, children: $0.apns) })
        items.insert(GatewayAPNMenuView.APNMenuItem(title: "not_set".localizedString, children: nil), at: 0)

        GatewayAPNMenuView(menuItems: items, selectApnName: setGatewayModel.apn, showPoint: point) {[weak self] apn in
            guard let self = self else { return }
            if apn == "not_set".localizedString { // 未选择
                self.setGatewayModel.apn = nil
            }else {
                self.setGatewayModel.apn = apn
            }
            if let section = self.sections.firstIndex(of: .apn) {
                self.tableView.reloadSections(IndexSet(integer: section), with: .none)
            }
            self.updateSaveBtnState()
        }.show()

    }

    /// 刷新section
    func reloadSection(_ section: SectionType) {
        if let section = self.sections.firstIndex(of: section) {
            tableView.reloadSections(IndexSet(integer: section), with: .none)
        }
    }

    func reloadGatewayTable() {
        tableView.reloadData()
    }

    private func gatewayAssociatedSpacesToDisplay() -> [GatewaySpaceData] {
        return setGatewayModel.associatedSpaces
    }

    func makeGatewayInformationHeaderView(frame: CGRect) -> GatewayInformationHeaderView {
        return GatewayInformationHeaderView(frame: frame)
    }

    private func setupUI() {

        bottomView = DeviceBottomBtnView()
        bottomView.createBtn.setTitle("DELETE".localizedString, for: .normal)
        bottomView.createBtn.setTitleColor(Red_Color, for: .normal)
        bottomView.createBtn.addTarget(self, action: #selector(deleteBtnAction), for: .touchUpInside)
        bottomView.saveBtn.addTarget(self, action: #selector(saveBtnAction), for: .touchUpInside)
        bottomView.deleteBtn.addTarget(self, action: #selector(deleteBtnAction), for: .touchUpInside)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }

        headerView = makeGatewayInformationHeaderView(frame: CGRect(x: 0, y: 0, width: view.width - SCRXFrom(32), height: SCRYFrom(72)))


        footerView = UIView(frame: CGRect(x: 0, y: 0, width: view.width - SCRXFrom(32), height: SCRYFrom(62)))
        copyInformationBtn = UIButton(title: "copy_gateway_information".localizedString, titleSize: 14, titleColor: ImportantText_Color, normalImageName: "share_copy", target: self, action: #selector(copyInformationBtnAction))
        copyInformationBtn.setImagePosition(position: .right, spacing: SCRXFrom(8))
        footerView.addSubview(copyInformationBtn)
        copyInformationBtn.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "infoCell")
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "associatedSpacesCell")
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "apnCell")
        tableView.register(GatewayNameViewCell.classForCoder(), forCellReuseIdentifier: "name")
        tableView.register(GatewayServerInformationViewCell.classForCoder(), forCellReuseIdentifier: "serverInformation")
        tableView.register(GatewayClockOffsetCell.classForCoder(), forCellReuseIdentifier: GatewayClockOffsetCell.reuseIdentifier)
        tableView.register(GatewaySectionHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        registerAdditionalGatewayCells(in: tableView)
        tableView.estimatedSectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = SCRYFrom(41)
        tableView.showsVerticalScrollIndicator = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.enableKeyboardDismissal()
//        tableView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: 0, right: SCRXFrom(16))
        tableView.tableHeaderView = headerView
        tableView.tableFooterView = footerView
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }

        if !canConfigureCurrentGateway {
            bottomView.isHidden = true
            tableView.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(view.safeAreaLayoutGuide)
                make.bottom.equalToSuperview()
            }
        }

    }

    /// 更新保存按钮状态
    private func updateSaveBtnState() {
        if self.isGatewayProxyConnecting {
            bottomView.saveBtn.isEnabled = false
        }else {
            bottomView.saveBtn.isEnabled = canConfigureCurrentGateway && (!(setGatewayModel == gatewayModel) || (!(name?.isAllInputTextEmpty() ?? true) && node.name != name))
        }
    }

    private func configureActivateCell(_ cell: CustomTableViewCell) {
        cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
        cell.titleLabel.text = "activate".localizedString
        cell.contentLabel.text = nil
        cell.cellStyle = .switch
        cell.enabledSwitch.isOn = setGatewayModel.activate
        cell.switchActionCallback = { [weak self, weak cell] enable in
            guard let self = self else { return }
            guard !self.isGatewayProxyConnecting else {
                return
            }
            guard self.canConfigureCurrentGateway else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            guard self.gatewayModel.mqttServerInfo != nil else {
                XWHUDManager.showErrorTipHUD("gateway_not_authorize_message".localizedString)
                return
            }
//            guard !self.otherGateways.contains(where: { $0.activate }) else {
//                SRAlertView(title: "notification".localizedString, message: "gateway_disable_activate_message".localizedString, actions: [SRAlertAction(title: "GOT IT".localizedString)]).show()
//                return
//            }
            cell?.enabledSwitch.isOn = enable
            self.setGatewayModel.activate = enable
            self.updateSaveBtnState()
        }
    }

    func registerAdditionalGatewayCells(in tableView: UITableView) {}

    func configureNetworkConnectivityCell(_ cell: GatewayNetworkConnectivityCell) {}

    func networkConnectivityCellHeight() -> CGFloat {
        return UITableView.automaticDimension
    }

    func gatewayProxyReadyStateDidUpdate(_ isReady: Bool) {
        if isReady {
            syncGatewayClockTimer()
        } else {
            gatewayClockAutoPromptState.end(sessionID: nil)
            cancelGatewayClockAutoPromptRetry()
            gatewayClockReadSessionID = nil
            gatewayClockSyncPresentationID = nil
            pendingGatewayClockSync = nil
            isGatewayClockReading = false
            gatewayClockState = GatewayDetailClockState()
            stopGatewayClockTimer()
        }
        reloadGatewayTable()
    }

    func gatewayProxyDidBecomeReady(_ context: ProxyReadyContext) {
        guard gatewayProxyReadySessionID == context.sessionID,
              gatewayClockReadSessionID != context.sessionID else {
            return
        }
        gatewayClockReadSessionID = context.sessionID
        readGatewayClock(autoPromptSessionID: context.sessionID)
    }

    private func currentGatewayClockTarget(at date: Date = Date()) -> GatewayDetailTargetTimeZone {
        GatewayDetailTimeZoneResolver.resolve(
            storageValue: site.timezone,
            phoneTimeZone: .current,
            at: date
        )
    }

    private func registerGatewayClockNotifications() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.significantTimeChangeNotification,
            .NSSystemTimeZoneDidChange
        ]
        gatewayClockNotificationTokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.gatewayClockEnvironmentDidChange()
            }
        }
    }

    private func gatewayClockEnvironmentDidChange() {
        guard showsGatewayClockSections else { return }
        gatewayClockState = GatewayDetailClockState()
        reloadSection(.timeZone)
        reloadSection(.clock)
        readGatewayClock()
    }

    private func readGatewayClock(autoPromptSessionID: UUID? = nil) {
        guard showsGatewayClockSections, !isGatewayClockReading,
              !gatewayClockState.isSyncing else { return }
        let target = currentGatewayClockTarget()
        isGatewayClockReading = true
        reloadSection(.clock)
        let started = gatewayClockCoordinator.read(target: target) { [weak self] result in
            guard let self else { return }
            self.isGatewayClockReading = false
            switch result {
            case .success(let value):
                self.gatewayClockState.accept(
                    sample: value.0,
                    offBySeconds: value.1,
                    targetOffsetMinutes: target.offsetMinutes,
                    targetIsMeshEncodable: target.isMeshEncodable
                )
            case .failure:
                self.gatewayClockState.failRead()
            }
            self.reloadSection(.timeZone)
            self.reloadSection(.clock)
            if let pendingSync = self.pendingGatewayClockSync {
                self.pendingGatewayClockSync = nil
                self.startGatewayClockSynchronization(
                    target: pendingSync.target,
                    presentationID: pendingSync.presentationID,
                    startedAtUptime: pendingSync.startedAtUptime
                )
                return
            }
            if let autoPromptSessionID,
               self.isCurrentGatewayProxySession(autoPromptSessionID) {
                self.gatewayClockAutoPromptState.request(
                    sessionID: autoPromptSessionID,
                    requiresSync: self.gatewayClockState.requiresSync
                )
                self.attemptGatewayClockAutoPrompt()
            }
        }
        if !started {
            isGatewayClockReading = false
        }
    }

    private func synchronizeGatewayClock() {
        guard showsGatewayClockSections, !gatewayClockState.isSyncing else { return }
        markCurrentGatewayClockSessionHandled()
        let target = currentGatewayClockTarget()
        let presentationID = UUID()
        let startedAtUptime = ProcessInfo.processInfo.systemUptime
        gatewayClockSyncPresentationID = presentationID
        gatewayClockState.beginSync()
        reloadSection(.clock)
        if isGatewayClockReading {
            pendingGatewayClockSync = (
                target: target,
                presentationID: presentationID,
                startedAtUptime: startedAtUptime
            )
            return
        }
        startGatewayClockSynchronization(
            target: target,
            presentationID: presentationID,
            startedAtUptime: startedAtUptime
        )
    }

    private func startGatewayClockSynchronization(
        target: GatewayDetailTargetTimeZone,
        presentationID: UUID,
        startedAtUptime: TimeInterval
    ) {
        var completionWasDelivered = false
        let started = gatewayClockCoordinator.synchronize(target: target) { [weak self] result in
            completionWasDelivered = true
            self?.scheduleGatewayClockSyncCompletion(
                result,
                target: target,
                presentationID: presentationID,
                startedAtUptime: startedAtUptime
            )
        }
        if !started, !completionWasDelivered {
            scheduleGatewayClockSyncCompletion(
                .failure(.disconnected),
                target: target,
                presentationID: presentationID,
                startedAtUptime: startedAtUptime
            )
        }
    }

    private func scheduleGatewayClockSyncCompletion(
        _ result: Result<(GatewayDetailClockSample, Int), GatewayDetailClockCoordinatorError>,
        target: GatewayDetailTargetTimeZone,
        presentationID: UUID,
        startedAtUptime: TimeInterval
    ) {
        let remainingDuration = GatewayDetailClockCore.remainingSyncPresentationDuration(
            startedAtUptime: startedAtUptime,
            completedAtUptime: ProcessInfo.processInfo.systemUptime
        )
        let completion = { [weak self] in
            guard let self,
                  self.gatewayClockSyncPresentationID == presentationID else { return }
            self.gatewayClockSyncPresentationID = nil
            switch result {
            case .success(let value):
                self.gatewayClockState.completeSync(
                    sample: value.0,
                    offBySeconds: value.1,
                    targetOffsetMinutes: target.offsetMinutes,
                    targetIsMeshEncodable: target.isMeshEncodable
                )
                self.timeZoneSyncDidFinish?(
                    self.gateway.mac,
                    value.0.offsetMinutes
                )
                ToastStatusView.show(
                    in: self.view,
                    message: "gateway_clock_synced".localizedString,
                    type: .success,
                    appearance: .siteUpdate,
                    position: .bottom
                )
            case .failure:
                self.gatewayClockState.failSync()
                ToastStatusView.show(
                    in: self.view,
                    message: "gateway_clock_sync_failed".localizedString,
                    type: .failure,
                    appearance: .siteUpdate,
                    position: .bottom
                )
            }
            self.reloadSection(.timeZone)
            self.reloadSection(.clock)
        }
        if remainingDuration > 0 {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + remainingDuration,
                execute: completion
            )
        } else {
            completion()
        }
    }

    private func showGatewayClockSyncPrompt() {
        markCurrentGatewayClockSessionHandled()
        let target = currentGatewayClockTarget()
        let message: String
        if let sample = gatewayClockState.sample {
            message = String(
                format: "gateway_time_zone_sync_message".localizedString,
                target.displayOffset,
                GatewayDetailTargetTimeZone(
                    identifier: "",
                    offsetMinutes: sample.offsetMinutes,
                    source: .site
                ).displayOffset
            )
        } else {
            message = String(
                format: "gateway_time_zone_sync_unknown_message".localizedString,
                target.displayOffset
            )
        }
        SRAlertView(
            title: "gateway_time_zone_sync_title".localizedString,
            message: message,
            actions: [
                SRAlertAction(title: "Later".localizedString, style: .cancel),
                SRAlertAction(
                    title: "gateway_sync_now".localizedString,
                    performsActionAfterDismiss: true,
                    actionHandler: { [weak self] _ in
                        self?.synchronizeGatewayClock()
                    }
                )
            ]
        ).show()
    }

    private func isCurrentGatewayProxySession(_ sessionID: UUID) -> Bool {
        guard isGatewayProxyReady,
              gatewayProxyReadySessionID == sessionID,
              let context = MeshLibManager.manager.currentProxyReadyContext else {
            return false
        }
        return context.sessionID == sessionID
            && context.nodeAddress == node.primaryUnicastAddress
    }

    private func markCurrentGatewayClockSessionHandled() {
        guard let sessionID = gatewayProxyReadySessionID else { return }
        gatewayClockAutoPromptState.markHandled(sessionID: sessionID)
        cancelGatewayClockAutoPromptRetry()
    }

    private func attemptGatewayClockAutoPrompt() {
        cancelGatewayClockAutoPromptRetry()
        guard let sessionID = gatewayClockAutoPromptState.pendingSessionID else { return }
        guard isCurrentGatewayProxySession(sessionID) else {
            gatewayClockAutoPromptState.end(sessionID: sessionID)
            return
        }
        guard gatewayClockState.requiresSync else {
            gatewayClockAutoPromptState.end(sessionID: sessionID)
            return
        }

        let hasExistingAlert = SRAlertView.getCurrentAlertView() != nil
        if gatewayClockAutoPromptState.shouldPresent(
            sessionID: sessionID,
            isViewVisible: isViewVisible,
            requiresSync: gatewayClockState.requiresSync,
            isSyncing: gatewayClockState.isSyncing,
            hasPendingSync: pendingGatewayClockSync != nil,
            hasExistingAlert: hasExistingAlert
        ) {
            gatewayClockAutoPromptState.markHandled(sessionID: sessionID)
            showGatewayClockSyncPrompt()
            return
        }

        guard isViewVisible,
              !gatewayClockState.isSyncing,
              pendingGatewayClockSync == nil,
              hasExistingAlert else {
            return
        }
        scheduleGatewayClockAutoPromptRetry()
    }

    private func scheduleGatewayClockAutoPromptRetry() {
        guard gatewayClockAutoPromptRetryWorkItem == nil else { return }
        let retryID = UUID()
        let workItem = DispatchWorkItem { [weak self] in
            guard self?.gatewayClockAutoPromptRetryID == retryID else { return }
            self?.gatewayClockAutoPromptRetryWorkItem = nil
            self?.gatewayClockAutoPromptRetryID = nil
            self?.attemptGatewayClockAutoPrompt()
        }
        gatewayClockAutoPromptRetryID = retryID
        gatewayClockAutoPromptRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func cancelGatewayClockAutoPromptRetry() {
        gatewayClockAutoPromptRetryWorkItem?.cancel()
        gatewayClockAutoPromptRetryWorkItem = nil
        gatewayClockAutoPromptRetryID = nil
    }

    private func syncGatewayClockTimer() {
        guard isViewVisible, showsGatewayClockSections else {
            stopGatewayClockTimer()
            return
        }
        guard gatewayClockTimer == nil else { return }
        gatewayClockTimer = LCWeakTimer.scheduledTimer(
            timeInterval: 0.5,
            aTarget: self,
            selector: #selector(refreshGatewayClockRows),
            userInfo: nil,
            repeats: true
        )
        if let gatewayClockTimer {
            RunLoop.main.add(gatewayClockTimer, forMode: .default)
        }
    }

    private func stopGatewayClockTimer() {
        gatewayClockTimer?.invalidate()
        gatewayClockTimer = nil
    }

    @objc private func refreshGatewayClockRows() {
        guard showsGatewayClockSections else { return }
        gatewayClockTickDate = Date()
        guard !(tableView.isTracking || tableView.isDragging || tableView.isDecelerating) else {
            return
        }
        updateVisibleGatewayClockRows()
    }

    private func updateVisibleGatewayClockRows() {
        guard showsGatewayClockSections,
              let section = sections.firstIndex(of: .clock) else { return }
        let target = currentGatewayClockTarget(at: gatewayClockTickDate)
        for row in 0..<2 {
            let indexPath = IndexPath(row: row, section: section)
            guard let cell = tableView.cellForRow(at: indexPath) as? CustomTableViewCell else {
                continue
            }
            configureGatewayClockTimeCell(cell, row: row, target: target)
        }
    }

    private func configureGatewayClockTimeCell(
        _ cell: CustomTableViewCell,
        row: Int,
        target: GatewayDetailTargetTimeZone
    ) {
        cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
        cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        cell.contentLabel.textColor = SubText_Color
        cell.cellStyle = .none
        cell.lineView.isHidden = false
        if row == 0 {
            cell.titleLabel.text = "gateway".localizedString
            if let offBy = gatewayClockState.offBySeconds {
                let gatewayDate = GatewayDetailClockCore.gatewayDisplayDate(
                    localDate: gatewayClockTickDate,
                    offBySeconds: offBy
                )
                cell.contentLabel.text = gatewayClockFormatter.format(
                    date: gatewayDate,
                    offsetMinutes: target.offsetMinutes
                )
            } else {
                cell.contentLabel.text = "--"
            }
        } else {
            cell.titleLabel.text = "gateway_local_time".localizedString
            cell.contentLabel.text = gatewayClockFormatter.format(
                date: gatewayClockTickDate,
                offsetMinutes: target.offsetMinutes
            )
        }
    }

}

extension GatewayViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionType = sections[section]
        switch sectionType {
        case .associatedSpaces:
            return max(gatewayAssociatedSpacesToDisplay().count, 1)
        case .info:
            return infoTypes.count
        case .clock:
            return 3
        case .networkConnectivity:
            return 1
        default:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionType = sections[indexPath.section]
        var tableviewCell: UITableViewCell!

        switch sectionType {
        case .name:
            let nameCell = tableView.dequeueReusableCell(withIdentifier: "name", for: indexPath) as! GatewayNameViewCell
            nameCell.nameField.text = name
            nameCell.nameField.isEnabled = canConfigureCurrentGateway
            nameCell.nameEditChangedCallback = {[weak self] name in
                if name.count > 32 && !name.isEmpty { // 长度超限
                    self?.bottomView.saveBtn.isEnabled = false
                    return "text_length_exceeded".localizedString
                }else if (MeshNetworkManager.instance.isNodeTautonym(nodeName: name) ) && name != self?.node.name { // 重名
                    self?.bottomView.saveBtn.isEnabled = false
                    return "name_already_exists".localizedString
                }
                self?.name = name
                self?.updateSaveBtnState()
                return nil
            }
            tableviewCell = nameCell
        case .timeZone:
            let cell = tableView.dequeueReusableCell(withIdentifier: "infoCell", for: indexPath) as! CustomTableViewCell
            let target = currentGatewayClockTarget(at: gatewayClockTickDate)
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
            cell.titleLabel.text = target.identifier
            cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            cell.contentLabel.textColor = SubText_Color
            cell.contentLabel.text = target.displayOffset
            cell.cellStyle = .none
            cell.lineView.isHidden = true
            tableviewCell = cell
        case .clock:
            let target = currentGatewayClockTarget(at: gatewayClockTickDate)
            if indexPath.row < 2 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "infoCell", for: indexPath) as! CustomTableViewCell
                configureGatewayClockTimeCell(
                    cell,
                    row: indexPath.row,
                    target: target
                )
                tableviewCell = cell
            } else {
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: GatewayClockOffsetCell.reuseIdentifier,
                    for: indexPath
                ) as! GatewayClockOffsetCell
                cell.update(
                    offBySeconds: gatewayClockState.offBySeconds,
                    isSyncing: gatewayClockState.isSyncing,
                    action: { [weak self] in
                        self?.synchronizeGatewayClock()
                    }
                )
                tableviewCell = cell
            }
        case .activate:
            let cell = tableView.dequeueReusableCell(withIdentifier: "infoCell", for: indexPath) as! CustomTableViewCell
            configureActivateCell(cell)
            tableviewCell = cell
        case .networkConnectivity:
            let cell = tableView.dequeueReusableCell(withIdentifier: GatewayNetworkConnectivityCell.reuseIdentifier, for: indexPath) as! GatewayNetworkConnectivityCell
            configureNetworkConnectivityCell(cell)
            tableviewCell = cell
        case .info:
            let cell = tableView.dequeueReusableCell(withIdentifier: "infoCell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
            cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            cell.contentLabel.textColor = SubText_Color
            cell.contentLabel.text = nil
            cell.switchActionCallback = nil
            cell.cellStyle = .none
            let cellType = infoTypes[indexPath.row]
            cell.titleLabel.text = cellType.title
            switch cellType {
            case .mac:
                cell.contentLabel.text = node.macAddressResult
            case .address:
                cell.contentLabel.text = "\(node.primaryUnicastAddress)"
            case .model:
                cell.contentLabel.text = node.modelName ?? "--"
            case .deviceType:
                cell.contentLabel.text = node.categoryName ?? "--"
            case .firmwareVersion:
                cell.contentLabel.text = node.firmwareVersion ?? "--"
            }

            tableviewCell = cell
        case .associatedSpaces:
            let cell = tableView.dequeueReusableCell(withIdentifier: "associatedSpacesCell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            let associatedSpaces = gatewayAssociatedSpacesToDisplay()
            if associatedSpaces.count > 0 {
                let space = associatedSpaces[indexPath.row]
                cell.titleLabel.textColor = TextBlack_Color
                cell.titleLabel.text = space.spaceName
                cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
                cell.contentLabel.text = "\("nodes".localizedString) \(space.deviceCount)"
                cell.contentLabel.textColor = SubText_Color
                cell.cellStyle = .icon
                cell.arrowImageView.isHidden = true
                cell.iconX = tableView.width - SCRXFrom(8) - 30
                cell.iconImageView.image = UIImage(named: "share_delete")
                if space.permission == .permissionException || space.permission == .permissionLoss || space.permission == .none {
                    cell.titleLabel.textColor = Message_Color
                    cell.iconImageView.image = UIImage(named: "share_delete")?.withTintColor(Message_Color)
                }

                cell.iconImageClickCallback = {[weak self] in
                    guard let self = self else { return }
                    guard !self.isGatewayProxyConnecting else {
                        return
                    }
                    guard self.canConfigureCurrentGateway, space.permission == .editor else {
                        return
                    }
                    // 删除
                    self.unbindAssociatedSpace(space)
                }
            }else {
                cell.titleLabel.text = "no_associated_spaces".localizedString
                cell.titleLabel.textColor = Message_Color
                cell.cellStyle = .none
                cell.contentLabel.text = nil
            }
            cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
            tableviewCell = cell
        case .apn:
            let cell = tableView.dequeueReusableCell(withIdentifier: "apnCell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
            cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            cell.cellStyle = .arrow
            cell.titleLabel.text = nil
            cell.arrowImageView.image = UIImage(named: "arrow_down_black")
            cell.contentLabel.text = setGatewayModel.apn
            cell.contentLabel.textColor = ImportantText_Color
            tableviewCell = cell
        case .serverInformation:
            let cell = tableView.dequeueReusableCell(withIdentifier: "serverInformation", for: indexPath) as! GatewayServerInformationViewCell
            if let serverInfo = setGatewayModel.mqttServerInfo {
                let serverStr = serverInfo.serverAddress.replacingOccurrences(of: "tcp://", with: "")
                let serverAddressArray = serverStr.components(separatedBy: ":")
                cell.serverAddressField.text = serverAddressArray.first ?? "N/A"
                cell.portField.text = serverAddressArray.count >= 2 ? serverAddressArray[1] : "N/A"
                cell.clientIdField.text = serverInfo.clientId
            }else {
                cell.serverAddressField.text = "N/A"
                cell.portField.text = "N/A"
                cell.clientIdField.text = "N/A"
            }
            tableviewCell = cell
        }
        tableviewCell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
        tableviewCell.selectionStyle = .none
        return tableviewCell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let sectionType = sections[indexPath.section]
        if sectionType == .serverInformation {
            return SCRYFrom(144)
        }
        if sectionType == .networkConnectivity {
            return networkConnectivityCellHeight()
        }
        return SCRYFrom(44)
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard !decelerate else { return }
        refreshGatewayClockRows()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        refreshGatewayClockRows()
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if sections[section] == .activate || sections[section] == .clock {
            return UIView()
        }

        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GatewaySectionHeaderView
        let sectionType = sections[section]
        headerView.operationBtn.isHidden = true
        headerView.operationBtn.setImage(nil, for: .normal)
        headerView.operationBtn.setTitleColor(Bar_Color, for: .normal)
        headerView.operationBtn.layer.cornerRadius = 0
        headerView.operationBtn.layer.borderWidth = 0
        headerView.messageLabel.isHidden = true
        headerView.titleLabel.snp.remakeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.bottom.equalToSuperview().offset(SCRYFrom(-8))
        }
        headerView.messageLabel.snp.remakeConstraints { make in
            make.top.equalTo(headerView.titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.left.equalTo(headerView.titleLabel)
            make.right.equalTo(SCRXFrom(-102))
        }
        switch sectionType {
        case .name:
            headerView.titleLabel.text = "name".localizedString
            if node.getNodeSyncGatewayData(gateway: gatewayModel).count > 0 {
                headerView.operationBtn.isHidden = false
                headerView.operationBtn.setImage(UIImage(named: "schedule_sync_failed"), for: .normal)
                headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
                headerView.operationBtn.setTitle("devices_not_synced".localizedString, for: .normal)
                headerView.operationBtn.setTitleColor(Red_Color, for: .normal)
                headerView.operationBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
                headerView.operationBtn.snp.remakeConstraints { make in
                    make.right.equalTo(0)
                    make.bottom.equalToSuperview().offset(SCRYFrom(-6))
                }
            }
        case .timeZone:
            headerView.titleLabel.text = "site_time_zone_title".localizedString
            if gatewayClockState.requiresSync {
                headerView.operationBtn.isHidden = false
                headerView.operationBtn.setTitle("gateway_sync_required".localizedString, for: .normal)
                headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
                headerView.operationBtn.setTitleColor(Red_Color, for: .normal)
                headerView.operationBtn.snp.remakeConstraints { make in
                    make.right.equalTo(SCRXFrom(-12))
                    make.centerY.equalTo(headerView.titleLabel)
                }
            }
        case .clock:
            break
        case .info:
            headerView.titleLabel.text = nil
            headerView.titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalToSuperview().offset(SCRYFrom(16))
                make.bottom.equalToSuperview()
            }
        case .activate:
            break
        case .networkConnectivity:
            headerView.titleLabel.text = "network_connectivity".localizedString
        case .associatedSpaces:
            headerView.titleLabel.text = "associated_spaces".localizedString
            headerView.operationBtn.isHidden = false
            headerView.operationBtn.setTitle("\("Add".localizedString) ＋", for: .normal)
            headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14)
            headerView.operationBtn.snp.remakeConstraints { make in
                make.right.equalTo(SCRXFrom(-12))
                make.centerY.equalTo(headerView.titleLabel)
            }
        case .apn:
            headerView.titleLabel.text = "apn".localizedString
        case .serverInformation:
            headerView.titleLabel.text = "server_information".localizedString
            if setGatewayModel.mqttServerInfo == nil {
                headerView.messageLabel.isHidden = false
                headerView.messageLabel.text = "gateway_server_not_authorize".localizedString
                headerView.operationBtn.isHidden = false
                headerView.operationBtn.setTitle("authorize".localizedString, for: .normal)
                headerView.operationBtn.layer.cornerRadius = SCRYFrom(5)
                headerView.operationBtn.layer.borderWidth = 0.5
                headerView.operationBtn.layer.borderColor = Bar_Color.cgColor
                headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13)

                headerView.titleLabel.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                    make.top.equalToSuperview().offset(SCRYFrom(16))
                }
                headerView.messageLabel.snp.remakeConstraints { make in
                    make.top.equalTo(headerView.titleLabel.snp.bottom).offset(SCRYFrom(8))
                    make.left.equalTo(headerView.titleLabel)
                    make.right.equalTo(SCRXFrom(-86))
                    make.bottom.equalTo(SCRYFrom(-8))
                }

                headerView.operationBtn.snp.remakeConstraints { make in
                    make.right.equalToSuperview()
                    make.top.equalTo(headerView.messageLabel)
                    make.width.equalTo(SCRXFrom(66))
                    make.height.equalTo(SCRYFrom(32))
                    make.bottom.lessThanOrEqualTo(SCRYFrom(-8))
                }
            }
        }
        headerView.operationActionCallback = {[weak self] in
            guard let self = self else { return }
            guard !self.isGatewayProxyConnecting else {
                return
            }
            switch sectionType {
            case .name: // 同步
                guard self.canConfigureCurrentGateway else {
                    XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                    return
                }
                prepareForGatewayRecovery { [weak self] in
                    self?.resync(trigger: .devicesNotSynced)
                }
            case .timeZone:
                self.showGatewayClockSyncPrompt()
            case .associatedSpaces: // 添加space
                associatedSpaces()
            case .serverInformation: // 服务器授权
                guard self.canConfigureCurrentGateway else {
                    XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                    return
                }
                self.performServerAuthorization()
            default:
                break
            }
        }
        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if sections[section] == .activate {
            return SCRYFrom(16)
        }
        if sections[section] == .clock {
            return SCRYFrom(12)
        }

        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        let sectionType = sections[section]
        switch sectionType {
        case .serverInformation:
            if setGatewayModel.mqttServerInfo == nil {
                return SCRYFrom(80)
            }
            return SCRYFrom(44)
        case .activate:
            return SCRYFrom(16)
        case .clock:
            return SCRYFrom(12)
        default:
            return SCRYFrom(44)
        }
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        let sectionType = sections[indexPath.section]
        switch sectionType {
        case .apn:
            guard self.canConfigureCurrentGateway else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            if let cell = tableView.cellForRow(at: indexPath) {
                let viewPoint = view.convert(CGPoint(x: cell.frame.maxX - GatewayAPNMenuView.defaultWidth, y: cell.frame.maxY), from: tableView)
                var windowPoint = view.convert(viewPoint, to: UIApplication.shared.keyWindow())
                if windowPoint.y + GatewayAPNMenuView.defaultHeight > SCREEN_HEIGHT {
                    windowPoint = CGPoint(x: windowPoint.x, y: windowPoint.y - GatewayAPNMenuView.defaultHeight - SCRYFrom(44))
                }
                selectSIMAPN(point: windowPoint)
            }

        default:
            break
        }
    }

}

extension GatewayViewController: MeshLibManagerMessageDelegate {

    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
            updateData()
        }
    }

    /// 设备数据修改时间戳更新
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdateTimeChange node: Node, lastUpdate: Int64) {
//        if node.lastUpdateSyncTime != lastUpdate {
            node.clearSyncStateCache()
//        }
    }
}

private final class GatewayClockOffsetCell: UITableViewCell {
    static let reuseIdentifier = "GatewayClockOffsetCell"
    private static let loadingAnimationKey = "gatewayClockSyncLoading"

    private let statusView = UIView()
    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let contentStack = UIStackView()
    private let loadingIconContainer = UIView()
    private let loadingImageView = UIImageView(
        image: UIImage(named: "site_entry_sync_loading")?.withRenderingMode(.alwaysTemplate)
    )
    private let actionTitleLabel = UILabel()
    private let lineView = UIView()
    private var action: (() -> Void)?
    private var isShowingSyncing = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        action = nil
        stopLoadingAnimation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopLoadingAnimation()
        } else if isShowingSyncing {
            startLoadingAnimation()
        }
    }

    func update(
        offBySeconds: Int?,
        isSyncing: Bool,
        action: @escaping () -> Void
    ) {
        self.action = action
        if let offBySeconds {
            titleLabel.text = String(
                format: "gateway_off_by_format".localizedString,
                GatewayDetailClockCore.formatOffBy(seconds: offBySeconds)
            )
            statusView.backgroundColor = GatewayDetailClockCore.isWithinTolerance(
                seconds: offBySeconds
            ) ? Green_Color : RGB(255, 185, 0)
        } else {
            titleLabel.text = String(
                format: "gateway_off_by_format".localizedString,
                "--"
            )
            statusView.backgroundColor = RGB(148, 163, 184)
        }
        updateSyncingAppearance(isSyncing: isSyncing)
    }

    @objc private func actionButtonTapped() {
        guard actionButton.isEnabled else { return }
        updateSyncingAppearance(isSyncing: true)
        action?()
    }

    private func updateSyncingAppearance(isSyncing: Bool) {
        isShowingSyncing = isSyncing
        actionTitleLabel.text = isSyncing
            ? "gateway_clock_syncing".localizedString
            : "gateway_sync_clock".localizedString
        actionButton.accessibilityLabel = actionTitleLabel.text
        actionButton.isEnabled = !isSyncing
        loadingIconContainer.isHidden = !isSyncing
        if isSyncing {
            startLoadingAnimation()
        } else {
            stopLoadingAnimation()
        }
    }

    private func startLoadingAnimation() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            stopLoadingAnimation()
            return
        }
        guard loadingImageView.layer.animation(forKey: Self.loadingAnimationKey) == nil else {
            return
        }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = Double.pi * 2
        animation.duration = 1
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        loadingImageView.layer.add(animation, forKey: Self.loadingAnimationKey)
    }

    private func stopLoadingAnimation() {
        loadingImageView.layer.removeAnimation(forKey: Self.loadingAnimationKey)
    }

    private func setupUI() {
        statusView.layer.cornerRadius = SCRYFrom(4)
        contentView.addSubview(statusView)
        statusView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(8))
        }

        titleLabel.font = UIFont.systemFont(ofSize: 14)
        titleLabel.textColor = TextBlack_Color
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(statusView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }

        actionButton.backgroundColor = Bar_Color.withAlphaComponent(0.1)
        actionButton.layer.cornerRadius = 10
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        contentView.addSubview(actionButton)
        actionButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalToSuperview()
            make.height.equalTo(28)
            make.width.greaterThanOrEqualTo(SCRXFrom(84))
        }

        loadingImageView.tintColor = Bar_Color
        loadingImageView.contentMode = .scaleAspectFit
        loadingIconContainer.addSubview(loadingImageView)
        loadingIconContainer.snp.makeConstraints { make in
            make.size.equalTo(24)
        }
        loadingImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(16)
        }

        actionTitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        actionTitleLabel.textColor = Bar_Color
        actionTitleLabel.textAlignment = .center
        actionTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 6
        contentStack.isUserInteractionEnabled = false
        contentStack.addArrangedSubview(loadingIconContainer)
        contentStack.addArrangedSubview(actionTitleLabel)
        actionButton.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(8)
            make.right.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
        }

        titleLabel.snp.makeConstraints { make in
            make.right.lessThanOrEqualTo(actionButton.snp.left).offset(SCRXFrom(-8))
        }

        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        lineView.isHidden = true
    }
}

extension GatewayViewController {

    /// seciton 组类型
    enum SectionType {
        /// 名称
        case name
        /// Site 时区
        case timeZone
        /// 网关与本地时间
        case clock
        /// 激活
        case activate
        /// WiFi network connectivity
        case networkConnectivity
        /// 基本信息
        case info
        /// 关联spaces
        case associatedSpaces
        /// APN
        case apn
        /// MQTT服务器信息
        case serverInformation
    }

    /// 设备信息cell类型
    enum InfoCellType {

        var title: String {
            switch self {
            case .mac:
                return "mac".localizedString
            case .address:
                return "address".localizedString
            case .model:
                return "model".localizedString
            case .deviceType:
                return "device_type".localizedString
            case .firmwareVersion:
                return "firmware".localizedString
            }
        }

        case mac
        case address
        case model
        case deviceType
        case firmwareVersion
    }
}
