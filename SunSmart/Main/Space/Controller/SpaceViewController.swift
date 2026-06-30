//
//  SpaceViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/26.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth
import SwiftyJSON

/// 空间内菜单选择修改通知
let spaceMenuIndexChangeNotificaitonName = "spaceMenuIndexChangeNotificaiton"
/// 空间弹出控制器通知
let spaceModalViewControllerNotificaitonName = "spaceModalViewControllerNotificaiton"
/// 空间内数据修改通知
/// 添加设备、编辑设备、删除设备、修复设备
/// 添加组、编辑组（基本数据 、 添加/删除设备、profile、校准、动能开关）、删除组
/// 添加场景、编辑场景（基本数据、添加/删除组、修改组参数）、删除场景
/// 添加定时、编辑定时（名称、target、enable…）、删除定时
let spaceDataChangedNotificaitonName = "spaceDataChangedNotificaiton"

/// 空间用户编辑权限变更通知
let spacePermissionChangedNotificaitonName = "spacePermissionChangedNotificaiton"

/// 空间页面分页滑动禁用通知
let spacePageDisableScrollNotificaitonName = "spacePageDisableScrollNotificaiton"

/// 网络代理设备切换通知
let meshNetworkProxyDidReplaceNotificationName = "meshNetworkProxyDidReplaceNotification"

/// space修改数据类型
enum SpaceChangeDataType {
    /// 网络数据类型
    enum NetworkDataType {
        /// ivIndex更新
        case ivIndex
        /// 地址（已使用地址/废弃地址）
        case address
    }
    /// 设备数据类型
    enum DeviceDataType {
        /// 配置设备
        case config
        /// 添加设备
        case add
        /// 删除设备
        case delete
    }
    
    /// 设备数据（包含device、group/scene等配置数据-与设备数据交互）
    case device
    /// 通用数据（group/scene等配置数据-无设备数据交互）
    case common
    /// 网络通用数据（ivIndex更新、废弃地址）
    case network(type: NetworkDataType)
}

fileprivate extension SpaceChangeDataType {
    var cloudSyncLevel: SyncLevel {
        switch self {
        case .common:
            return .slow
        case .device, .network:
            return .promptly
        }
    }
}

extension SpaceData {
    func commitLocalChangeForCloudSync(site currentSite: SiteData? = nil, changeType: SpaceChangeDataType) {
        refreshSummaryCountsFromCurrentMesh()

        guard permission == .owner || permission == .editor else {
            save()
            return
        }

        markSpaceUploadNeeded()
        guard let site = currentSite ?? SiteData.load(siteId: siteId) else {
            save()
            return
        }

        if site.spaces.isEmpty {
            site.spaces = SpaceData.load(siteId: site.id)
        }

        switch changeType {
        case .device, .common:
            enqueueSpaceSync(site: site, level: changeType.cloudSyncLevel)
        case .network(let type):
            switch type {
            case .ivIndex:
                CloudSynchronizationManager.shared.addSynchronizationHandle(
                    operation: .syncSite(site: site),
                    level: changeType.cloudSyncLevel
                )
            case .address:
                site.markSiteUploadNeededForSpaceAddressChange()
                CloudSynchronizationManager.shared.addSynchronizationHandle(
                    operation: .syncSite(site: site, syncSpaces: [self]),
                    level: changeType.cloudSyncLevel
                )
            }
        }
    }

    private func refreshSummaryCountsFromCurrentMesh() {
        let nodes = MeshNetworkManager.instance.realNodes
        deviceCount = nodes.count
        luminairesCount = nodes.filter { $0.deviceType == .light }.count
        groupCount = MeshNetworkManager.instance.groups.count
        sceneCount = MeshNetworkManager.instance.scenes.count
        scheheduleCount = MeshNetworkManager.instance.schedules.count
        switchesCount = MeshNetworkManager.instance.switchs.count
    }

    private func markSpaceUploadNeeded() {
        let now = Int64(Date().timeIntervalSince1970)
        lastUpdate = max(now, lastUpdate + 1, (lastUploadCloudTimestamp ?? 0) + 1)
        save()
    }

    private func enqueueSpaceSync(site: SiteData, level: SyncLevel) {
        if site.uploadCloud {
            CloudSynchronizationManager.shared.addSynchronizationHandle(
                operation: .syncSpace(space: self),
                level: level
            )
        } else {
            CloudSynchronizationManager.shared.addSynchronizationHandle(
                operation: .syncSite(site: site, syncSpaces: site.spaces),
                level: level
            )
        }
    }
}

fileprivate extension SiteData {
    func markSiteUploadNeededForSpaceAddressChange() {
        let now = Int64(Date().timeIntervalSince1970)
        lastUpdate = max(now, lastUpdate + 1, (lastUploadCloudTimestamp ?? 0) + 1)
        save()
    }
}

private enum SpacePresenceStopReason: String {
    case leavingSpaceFlow
    case permissionLoss
    case deallocated
    case sitesVisibleCleanup
}

extension SpaceViewController {
    
    /// 当前显示的space控制器
    static func currentSpaceVc() -> SpaceViewController? {
        guard Thread.isMainThread else {
            return nil
        }
        guard let rootVc = UIApplication.shared.keyWindow().rootViewController as? UINavigationController else {
            return nil
        }
        return rootVc.viewControllers.first(where: { $0.isKind(of: self) }) as? SpaceViewController
    }
    
    /// 当前space
    static func currentSpace() -> SpaceData? {
        guard Thread.isMainThread else {
            return SpaceData.load(subNetworkId: MeshNetworkManager.instance.currentNetworkKey.networkId.hex)
        }
        return currentSpaceVc()?.space
    }
    
    /// 当前space的设备闪烁模式
    static var currentDeviceBlinkMode: DeviceBlinkMode {
        return currentSpace()?.deviceBlinkMode ?? .none
    }
    
}


let routeTest: Bool = false

class SpaceViewController: WMPageController {

    var site: SiteData!
    let space: SpaceData
    /// 删除空间回调
    var deleteSpaceCallback: (()->Void)?
    /// 是否已加载完成网络数据
    private var loadNetworkData: Bool = false
    /// 退出页面同步space中
    private var exitSyncSpace: Bool = false
    /// 心跳定时器
    private var heartbeatTimer: Timer?
    /// 是否已停止当前 Space 的在线/编辑占用跟踪
    private var hasStoppedPresenceTracking: Bool = false
    /// 是否已处理空间权限失效，避免失效心跳重复弹窗
    private var hasHandledPermissionLoss: Bool = false
    /// mesh网络内用户查询定时器
    private var userAskTimer: Timer?
    /// 是否由当前 Space 页面接管 mesh 权限探测回调
    private var isHandlingExternalVendorMessages: Bool = false
    /// 是否进行云端权限校验
    private var cloudPermissionValidation: Bool = false
    /// 是否进行mesh权限校验
    private var meshPermissionValidation: Bool = false
    /// 禁止滑动的页面索引
    private var disablePageIndex: Int?
    /// 菜单bar高度
    private var meunHeight: CGFloat = 48
    /// 自动测试定时器
    private var autoTestTimer: Timer?
    private var isAllOn: Bool = true
    private var emergencyFireControllerSceneEventManager: EmergencyFireControllerSceneEventManager?
    private var emergencyFireSceneMessageObserverId: UUID?
    
    private var networkableObservation: NSKeyValueObservation?
    private var meshNetworkConnectedObservation: NSKeyValueObservation?
    private var bluetoothStateObservation: NSKeyValueObservation?
    
    
    private lazy var autoBtn: UIButton = {
        let btn = UIButton(title: "Auto", titleSize: 17, titleWeight: .light, titleColor: .black, target: self, action: #selector(autoTestBtnAction))
        btn.setTitleColor(Bar_Color, for: .selected)
        btn.setTitle("Stop", for: .selected)
        return btn
    }()
    
    lazy var mainMenuView: SpaceMenuView = {
        let menuView = SpaceMenuView()
        menuView.itemDatas = SpaceMenuView.defalutItems
        if isIPad {
            menuView.margin = SCRXFrom(35)
            menuView.itemMargin = SCRXFrom(13)
        }
        menuView.isUserInteractionEnabled = false
        return menuView
    }()
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
        
//        self.titles = ["", "", "", "", ""]
//        self.viewControllerClasses = [SpaceDevicesViewController.self, SpaceGroupsViewController.self]
        self.menuViewStyle = .line
        self.progressHeight = 2
        self.progressColor = Bar_Color
        
        if isIPad {
            self.progressWidth = SCRXFrom(142.34)
            self.menuItemWidth = SCRXFrom(142.34)
            self.menuViewContentMargin = SCRXFrom(22)
            self.itemMargin = SCRXFrom(13)
        }else {
            self.progressWidth = SCRXFrom(64)
            self.menuItemWidth = SCRXFrom(64)
            self.menuViewContentMargin = SCRXFrom(10)
            self.itemMargin = SCRXFrom(6)
        }
        
        space.disableEditorPermission = false
        
         
//        NetworkRequest.shared.addObserver(self, forKeyPath: "networkable", context: nil)
//        MeshLibManager.manager.addObserver(self, forKeyPath: "isMeshNetworkConnected", context: nil)
//        MeshLibManager.manager.addObserver(self, forKeyPath: "bluetoothState", context: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
//        self.selectIndex = 4
        
//        MeshNetworkManager.instance.meshNetwork?.applicationKeys.first.
        super.viewDidLoad()
        
        title = space.name
        view.backgroundColor = Background_Color
        menuView?.backgroundColor = .white
        self.view.addSubview(self.mainMenuView)
        mainMenuView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(meunHeight)
        }
        
//        #if DEBUG
//        navigationItem.rightBarButtonItems = [
//            UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick)),
//            UIBarButtonItem(customView: autoBtn)
//        ]
//        #else
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
//        #endif
        
//        MeshLibManager.manager.publishModelIDs = []// .genericOnOffServerModelId, .lightLightnessServerModelId, .lightCTLServerModelId
//        MeshLibManager.manager.publishTimeModelIDs = []
//        MeshLibManager.manager.publishModeloOnly = true
//        MeshLibManager.manager.groupSubscriptionModelIDs = [.genericOnOffServerModelId, .lightLightnessServerModelId, .lightCTLTemperatureServerModelId, .lightCTLServerModelId, .sensorServerModelId, .lightLCServerModelId]
//        MeshLibManager.manager.subElementGroupSubscriptionModelIDs = [.lightCTLTemperatureServerModelId, .lightLCServerModelId]
        checkBluetoothState()
        #if DEBUG
        
        MeshLibManager.manager.showLogs = [.network, .model, .access, .lowerTransport, .upperTransport, .proxy, .bearer]

        if routeTest {
            MeshNodeHeartbeatManager.shared.autoHeartbeatLoop = false
            MeshNodeHeartbeatManager.shared.heartbeatMode = .publish
        }else {
            MeshNodeHeartbeatManager.shared.autoHeartbeatLoop = true
            MeshNodeHeartbeatManager.shared.heartbeatMode = .general
        }
        
        #else
        MeshNodeHeartbeatManager.shared.autoHeartbeatLoop = true
        MeshNodeHeartbeatManager.shared.heartbeatMode = .general
        #endif
        MeshNodeHeartbeatManager.shared.openHeartbeatShare = false
        
        
        // 添加通知监听
        addNotificaiton()
        SpaceDebugUARTManager.shared.setActiveSpace(space)
        // 获取space数据
        setNetworkConnected()
//        loadSpaceReqeust()
        if space.uploadCloud {
            if space.permission == .visitor {
                // 开始定时发送心跳
                startHeartbeatTimer()
            }else {
                // 读取space内是否有其他编辑者
                checkTheSpaceMembersRequest()
            }
        }else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                self?.configurationFlowGuidance()
            }
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        CloudSynchronizationManager.shared.delegate = self
        (self.navigationController as? NavigationViewController)?.navigationDelegate = self
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        updateSyncState()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clearTransientWindowMenus()
        ConfigurationFlowGuidanceView.current()?.hide()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if isMovingFromParent || !(navigationController?.viewControllers.contains(self) ?? false) {
            stopSpacePresenceTracking(reason: .leavingSpaceFlow)
        }
    }

    
    deinit {
        stopSpacePresenceTracking(reason: .deallocated)
        
        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == space.meshUUID && MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId {
            MeshLibManager.manager.meshNetworkDisconnect()
        }
//        MeshLibManager.manager.removeObserver(self, forKeyPath: "bluetoothState")
//        NetworkRequest.shared.removeObserver(self, forKeyPath: "networkable")
//        MeshLibManager.manager.removeObserver(self, forKeyPath: "isMeshNetworkConnected")
        bluetoothStateObservation = nil
        networkableObservation = nil
        meshNetworkConnectedObservation = nil
        print("dealloc")
        stopAutoTestTimer()
    }
    
    /// 删除当前窗口的自定义view（防止权限清空强制退出页面时未关闭自定义view）
    private func removeFromWindowSubviews() {
        
        // 关闭一切在窗口的自定义view
        let subviews = UIApplication.shared.keyWindow().subviews.filter({ $0.tag == 100 })
        subviews.forEach({ $0.removeFromSuperview() })
        
    }

    private func clearTransientWindowMenus() {
        MenuPopView.hide(animation: false)
    }
    
//    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
//        
////        let newState = change![.newKey] as! CBManagerState
////        let oldState = change![NSKeyValueChangeKey.oldKey] as! CBManagerState
//        guard let key = keyPath else { return }
//        switch key {
//        case "bluetoothState":
//            checkBluetoothState()
//        case "networkable":
//            if NetworkRequest.shared.networkable { // 无网->有网 开始发送心跳
//                self.startHeartbeatTimer()
//            }else {
//                
//            }
//        case "isMeshNetworkConnected": // mesh连接成功/断开连接
//            // 连接上mesh网络
//            if MeshLibManager.manager.isMeshNetworkConnected && self.space.deviceOperates.contains(.edit) && !self.space.disableEditorPermission {
//                // 如果未完成mesh权限校验，有space编辑权限的用户进入空间连接网络后需判定是否有其他的编辑用户
//                if !self.meshPermissionValidation && (space.permission == .owner || space.permission == .editor) {
//                    MeshLibManager.manager.externalVendorMessageDelegate = self
//                    MeshAPI.sendMessage(message: ExternalVendorMessage(operation: .userPermission(.ask)), address: .localClientGroupAddress)
//                    
//                    DispatchQueue.main.async {
//                        self.startUserAskTimer()
//                    }
//                    
////                    DispatchQueue.main.async {
////                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.userPermissionAskTimeout), object: nil)
////                        self.perform(#selector(self.userPermissionAskTimeout), with: nil, afterDelay: 5)
////                    }
//                }
//            }
//        default:
//            break
//        }
//    }
    
    // MARK: - Auto AllControl Test
    
    @objc private func autoTestBtnAction(sender: UIButton) {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            startAutoTestTimer()
        }else {
            stopAutoTestTimer()
        }
    }
    
    private func startAutoTestTimer() {
        
        autoTestTimer = LCWeakTimer.scheduledTimer(timeInterval: 10, aTarget: self, selector: #selector(allControlAction), userInfo: nil, repeats: true)
        RunLoop.current.add(autoTestTimer!, forMode: .common)
    }
    
    @objc private func allControlAction() {
        self.isAllOn = !self.isAllOn
        MeshAPI.sendMessage(message: GenericOnOffSetUnacknowledged(self.isAllOn), address: .allNodes)
    }
    
    private func stopAutoTestTimer() {
        autoTestTimer?.invalidate()
        autoTestTimer = nil
    }
    
    // MARK: - Mesh Ask Timer
    /// mesh查询用户权限
    private func startUserAskTimer() {
        userAskTimer = LCWeakTimer.scheduledTimer(timeInterval: 5, aTarget: self, selector: #selector(userPermissionAskTimeout), userInfo: nil, repeats: false)
        RunLoop.current.add(userAskTimer!, forMode: .common)
    }
    
    private func stopUserAskTimer() {
        userAskTimer?.invalidate()
        userAskTimer = nil
    }
    
    /// 查询用户权限超时
    @objc private func userPermissionAskTimeout() {
        self.meshPermissionValidation = true
    }
    
    
     /// 添加通知监听
    private func addNotificaiton() {
        
        // 蓝牙状态观察者
        bluetoothStateObservation = MeshLibManager.manager.observe(\.bluetoothState, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.checkBluetoothState()
            }
        })
        
        // 手机网络状态观察者
        networkableObservation = NetworkRequest.shared.observe(\.networkable, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {//[weak self] in
//                guard let self = self else { return }
                if self.space.uploadCloud, NetworkRequest.shared.networkable { // 无网->有网 开始发送心跳
                    self.startHeartbeatTimer()
                }
            }
        })
        
        // mesh网络连接观察者
        meshNetworkConnectedObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // 连接上mesh网络
                if MeshLibManager.manager.isMeshNetworkConnected && self.space.deviceOperates.contains(.edit) && !self.space.disableEditorPermission {
                    // 如果未完成mesh权限校验，有space编辑权限的用户进入空间连接网络后需判定是否有其他的编辑用户
                    if !self.meshPermissionValidation && (self.space.permission == .owner || self.space.permission == .editor) {
                        MeshLibManager.manager.externalVendorMessageDelegate = self
                        self.isHandlingExternalVendorMessages = true
                        MeshAPI.sendMessage(message: ExternalVendorMessage(operation: .userPermission(.ask)), address: .localClientGroupAddress)
                        self.startUserAskTimer()
                    }
                }
            }
        })
        
        
        // 设备列表更新通知
        NotificationCenter.default.addObserver(forName: .init(devicesUpdateNotificationName), object: nil, queue: nil) {[weak self] _ in
            self?.updateSpaceData()
        }
        
        // 组列表更新通知
        NotificationCenter.default.addObserver(forName: .init(groupsRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            self?.updateSpaceData()
        }
        
        // 场景列表更新通知
        NotificationCenter.default.addObserver(forName: .init(scenesRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            self?.updateSpaceData()
        }
        
        // 日程列表更新通知
        NotificationCenter.default.addObserver(forName: .init(schedulesRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            self?.updateSpaceData()
        }
        
        // 开关列表更新通知
        NotificationCenter.default.addObserver(forName: .init(switchsRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            self?.updateSpaceData()
        }
        
        // 空间内菜单选择修改通知
        NotificationCenter.default.addObserver(forName: .init(spaceMenuIndexChangeNotificaitonName), object: nil, queue: .main) {[weak self] notification in
            guard let self = self, let selectIndex = notification.object as? Int, selectIndex >= 0 && selectIndex < SpaceMenuView.defalutItems.count else { return }
            self.selectIndex = Int32(selectIndex)
        }
        NotificationCenter.default.addObserver(forName: .init(spaceModalViewControllerNotificaitonName), object: nil, queue: .main) {[weak self] notification in
            guard let self = self, let modalVc = notification.object as? UIViewController else {
                return
            }
            if isIPad {
                modalVc.preferredContentSize = iPadPreferredContentSize
            }
            self.present(modalVc, animated: true)
        }
        
        
        // 空间内数据更新通知
        NotificationCenter.default.addObserver(forName: .init(spaceDataChangedNotificaitonName), object: nil, queue: .main) { [weak self] notification in
            guard let self,
                  let type = notification.object as? SpaceChangeDataType else {
                return
            }
            self.space.commitLocalChangeForCloudSync(site: self.site, changeType: type)
        }
        
        // 页面page禁止滑动通知
        NotificationCenter.default.addObserver(forName: .init(spacePageDisableScrollNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            
            if let disablePageIndex = notification.object as? Int {
                self.disablePageIndex = disablePageIndex
                self.scrollEnable = self.selectIndex != disablePageIndex
            }else {
                self.scrollEnable = true
                self.disablePageIndex = nil
            }
        }
        
    }
    
    /// 同步space
    private func syncSpace(level: SyncLevel) {
        // site已上传服务器
        if self.site.uploadCloud {
            // 同步space
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: level)
        }else {
            // 未上传服务器，site、space一起上传
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: site.spaces), level: level)
        }
    }

    private func registerEmergencyFireSceneMessageObserverIfNeeded() {
        guard !hasStoppedPresenceTracking else { return }
        guard emergencyFireSceneMessageObserverId == nil else { return }
        emergencyFireSceneMessageObserverId = MeshLibManager.manager.addGlobalMessageObserver { [weak self] _, message, source, destination in
            guard self?.emergencyFireControllerSceneEventManager != nil else { return }
            EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)
        }
    }

    private func removeEmergencyFireSceneMessageObserver() {
        MeshLibManager.manager.removeGlobalMessageObserver(emergencyFireSceneMessageObserverId)
        emergencyFireSceneMessageObserverId = nil
    }

    private func stopEmergencyFireSceneMonitoring() {
        removeEmergencyFireSceneMessageObserver()
        emergencyFireControllerSceneEventManager?.deactivate()
        emergencyFireControllerSceneEventManager = nil
    }
    
    /// 配置引导
    private func configurationFlowGuidance() {
        
        guard !exitSyncSpace else {
            return
        }
        // 判断是否空的空间，进行引导配置流程
        if view.window != nil && space.deviceOperates.contains(.edit) && space.isEmpty {
//            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.5) {[weak self] in
//                guard let self = self else { return }
                ConfigurationFlowGuidanceView(continueBack: {[weak self] in
                    guard let self = self else { return }
                    // 进入引导配置流程
                    self.space.isConfiguring = true
                    let vc = GroupAddViewController(space: self.space)
                    let navVc = NavigationViewController(rootViewController: vc)
                    if isIPad {
                        vc.preferredContentSize = iPadPreferredContentSize
                    }
                    self.present(navVc, animated: true)
                    self.selectIndex = 1
                }).show()
//            }
        }
        
    }
    
    /// 获取网络数据+网络连接
    private func setNetworkConnected() {
        // 读取网络数据
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 10)
        DispatchQueue.global().async {[weak self] in
            guard let self = self else { return }
            print("加载网络数据 \(Date().timeIntervalSince1970)")
            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.space.meshUUID, subNetworkId: self.space.meshNetworkId)
            if let manager = MeshLibManager.manager.meshNetworkManager, let meshNetwork = manager.meshNetwork {
//                self.space.meshManager = manager
                
                print("加载网络数据完成 \(Date().timeIntervalSince1970)")
                if meshNetwork.localProvisioner == nil || meshNetwork.localProvisioner?.primaryUnicastAddress == nil { // 缺少手机供应者或手机地址
                    // 如果用户有地址则自己分配一个作为手机地址
                    if let localProvisioner = manager.meshNetwork?.localProvisioner, let address = meshNetwork.nextAvailableUnicastAddress(elementsCount: 1, elementsUsing: localProvisioner, lockInAddress: false) {
                        try? meshNetwork.changeLocalNodeAddress(address)
                    }else { // 如果没有地址，则向服务器申请一个地址
                        self.requestMobileAddress()
                    }
                }
                
                manager.loadExtensionData {[weak self] result in
                    guard let self = self else { return }
                    print("加载网络扩展数据完成 \(Date().timeIntervalSince1970)")
                    guard result else {
                        XWHUDManager.showErrorTipHUD("unknown_error".localizedString)
                        return
                    }
                    guard !self.hasStoppedPresenceTracking else {
                        XWHUDManager.hide()
                        return
                    }
//                    XWHUDManager.hideInView(with: self.view)
                    XWHUDManager.hide()
                    self.loadNetworkData = true
                    self.emergencyFireControllerSceneEventManager = EmergencyFireControllerSceneEventManager {
                        DeviceEmerFireStore.shared.devices(in: self.space)
                    }
                    self.emergencyFireControllerSceneEventManager?.activate()
                    self.registerEmergencyFireSceneMessageObserverIfNeeded()
                    self.reloadData()
                    SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
                    DispatchQueue.global().async {
//                        print("设备同步状态:\(Date().timeIntervalSince1970)")
                        manager.realNodes.forEach { node in
                            node.reloadSyncStateCache()
                        }
//                        print("设备同步状态完成:\(Date().timeIntervalSince1970)")
                    }
                    
//                    if self.cloudPermissionValidation {
//                        self.configurationFlowGuidance()
//                    }
                }
            }
        }
    }
    
    // MARK: - Request
    /// 获取space数据
    private func loadSpaceReqeust() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId, spaceId: space.id, password: "")) {[weak self] result in
            guard let self = self else { return }
            XWHUDManager.hideInView(with: self.view)
            switch result {
            case .success(let response):
                if let spaceData = JSON(response)["data"].dictionaryObject {
                    Task { [weak self] in
                        guard let self = self else { return }
                        await self.space.update(spaceJsonData: spaceData)
                        self.space.save()
                        await MainActor.run {
                            self.title = self.space.name
                        }
                    }
                }
            case .failure(_):
                break
            }
            self.setNetworkConnected()
        }
        
    }
    
    /// 删除space网络请求
    private func deleteSpaceRequest() {
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        NetworkRequest.shared.request(.spaceDelete(siteId: self.site.id, spaceId: self.space.id)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                
                // 删除本地数据
                self.site.spaces.removeAll(where: { $0.id == self.space.id })
                self.space.delete()
                self.navigationController?.popViewController(animated: true)
                self.deleteSpaceCallback?()
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                
            case .failure(let error): // 删除失败，无网络/space存在编辑者
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// 解绑space
    private func unbindSpace() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        
        // 是否有同步操作正在进行,进行中则取消任务
        CloudSynchronizationManager.shared.cancelSynchronizationHandle(space: self.space)
        
        // 数据有更新没提交,先提交完成数据再解绑
        if space.permission == .editor && space.needUploadCloud {
            Task {
                let spaceData = await space.export()
                NetworkRequest.shared.request(.spaceUpload(siteId: space.siteId, spaceData: spaceData)) {[weak self] result in
                    switch result {
                    case .success(_):
                        self?.space.lastUploadCloudTimestamp = self?.space.lastUpdate
                        self?.unbindSpace()
                    case .failure(let error):
                        XWHUDManager.hide()
                        XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    }
                }
            }
            return
        }
        
        Task {
            let recycleData = await site.getRecycleAddressData(unbindSpaces: [space])
            
            let networkApi: NetowrkReqeustApi = .unbindSpaces(siteId: site.id, spaceIds: [space.id], recycleDeviceAddresses: recycleData.deviceAddresses, recycleGroupAddresses: recycleData.groupAddresses, recycleSceneAddresses: recycleData.sceneAddresses, exclusions: recycleData.exclusionAddresses?.map({ ($0.ivIndex, $0.addresses) }), provisionerData: recycleData.provisionerData)
            
            NetworkRequest.shared.request(networkApi) {[weak self] result in
                XWHUDManager.hide()
                
                guard let self = self else { return }
                switch result {
                case .success(_):
                    //                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                    if let spaceIndex = self.site.spaces.firstIndex(where: { $0.id == self.space.id }) {
                        self.site.spaces.remove(at: spaceIndex)
                    }
                    // 删除回收的地址
                    self.site.deleteProvisionerAddress(deviceAddresses: recycleData.deviceAddresses, groupAddresses: recycleData.groupAddresses, sceneAddresses: recycleData.sceneAddresses)
                    
                    self.space.delete()
                    
                    self.navigationController?.popViewController(animated: true)
                    if self.site.spaces.isEmpty && self.site.permission != .owner { // 不属于site所有者并且解绑所有spaces则清空site记录
                        self.site.delete()
                        self.site.state = .waitDeleted
                        NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
                    }else {
                        self.deleteSpaceCallback?()
                    }
                    NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                case .failure(let error):
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
            }
        }
    }
    
    /// 检查空间内成员请求，保证空间内只有一个编辑权限用户
    private func checkTheSpaceMembersRequest() {
        guard space.deviceOperates.contains(.edit), !space.disableEditorPermission else {
            return
        }
        NetworkRequest.shared.request(.spaceActiveMembers(siteId: self.space.siteId, spaceId: self.space.id)) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let users = JSON(response)["data"]["activeUsers"].arrayObject as? [[String: Any]] {
                    let userInfos: [(userId: String, permission: Permission)] = users.compactMap({ userDict in
                        if let role = userDict["role"] as? String, let permission = Permission(permissionString: role), let userId = userDict["userId"] as? String {
                            return (userId, permission)
                        }
                        return nil
                    })
                    
                    self.cloudPermissionValidation = true
                    // 判断空间内是否存在编辑权限用户
                    if userInfos.contains(where: { ($0.permission == .owner || $0.permission == .editor) && $0.userId != UserData.currentUserId }) {
                        #if DEBUG
                        print("Space active editor conflict: siteId=\(self.space.siteId), spaceId=\(self.space.id), permission=\(self.space.permission.dataString)")
                        #endif
//                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(userPermissionAskTimeout), object: nil)
                        self.stopUserAskTimer()
                        // 提示是否关闭用户编辑权限
                        self.showTransferPermissionAlert()
                    }else {
                        if space.deviceCount == 0 {
                            self.configurationFlowGuidance()
                        }
                        // 开始定时发送心跳
                        if self.space.uploadCloud {
                            self.startHeartbeatTimer()
                        }
                    }
                }
            case .failure(_):
                self.cloudPermissionValidation = true
                if space.deviceCount == 0 {
                    self.configurationFlowGuidance()
                }
                // 开始定时发送心跳
                if self.space.uploadCloud {
                    self.startHeartbeatTimer()
                }
            }
        }
        
        
    }
    
    /// 申请手机地址请求
    private func requestMobileAddress() {
//        if showHUD {
//            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
//        }
        NetworkRequest.shared.request(.applyAddress(siteId: site.id, number: 1)) {[weak self] result in
//            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let provisionerData = JSON(response)["data"]["provisioner"].dictionaryObject {
                    self.site.setProvisioner(provisionerData: provisionerData)
                    if self.site.localAddress != nil {
                        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: self.site), level: .promptly)
                    }
                }
            case .failure(_): // 申请手机地址失败
                break
//                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    // MARK: - Heartbeat
    
    /// 开始发送心跳
    private func startHeartbeatTimer() {
        guard space.state == .normal, !hasHandledPermissionLoss, !hasStoppedPresenceTracking else {
            return
        }
        
        if heartbeatTimer != nil {
            heartbeatTimer?.invalidate()
        }
        
        #if DEBUG
        print("Space heartbeat started: siteId=\(space.siteId), spaceId=\(space.id), permission=\(space.permission.dataString)")
        #endif
        heartbeatTimer = LCWeakTimer.scheduledTimer(timeInterval: 30, aTarget: self, selector: #selector(heartbeatRequest), userInfo: nil, repeats: true)
        
        heartbeatTimer?.fire()
        RunLoop.current.add(heartbeatTimer!, forMode: .common)
    }
    
    /// 停止发送心跳
    private func stopHeartbeatTimer() {
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    func stopSpacePresenceTrackingForSitesCleanup() {
        stopSpacePresenceTracking(reason: .sitesVisibleCleanup)
    }

    private func stopSpacePresenceTracking(reason: SpacePresenceStopReason) {
        guard !hasStoppedPresenceTracking else {
            return
        }
        hasStoppedPresenceTracking = true
        stopEmergencyFireSceneMonitoring()
        stopHeartbeatTimer()
        stopUserAskTimer()
        if isHandlingExternalVendorMessages, MeshLibManager.manager.externalVendorMessageDelegate === self {
            MeshLibManager.manager.externalVendorMessageDelegate = nil
        }
        isHandlingExternalVendorMessages = false
        #if DEBUG
        print("Space presence stopped: siteId=\(space.siteId), spaceId=\(space.id), permission=\(space.permission.dataString), reason=\(reason.rawValue)")
        #endif
    }
    
    /// 心跳请求
    @objc private func heartbeatRequest() {
        guard space.state == .normal, !hasHandledPermissionLoss, !hasStoppedPresenceTracking else {
            stopHeartbeatTimer()
            return
        }
        
        NetworkRequest.shared.request(.heartbeat(siteId: self.space.siteId, spaceId: self.space.id, permission: self.space.permission)) {[weak self] result in
            guard let self else { return }
            switch result {
            case .success(_):
                break
            case .failure(let error):
//                print(error.localizedDescription)
//                if self.space.permission == .visitor {
//                    return
//                }
                switch error {
                case .noSitePermission: // 被回收权限/转让site
                    self.stopSpacePresenceTracking(reason: .permissionLoss)
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    if self.site.permission == .owner {
                        NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                        if let currentVc = UIViewController.getVisibleVc(), currentVc.presentingViewController != nil { // 退出modal页面
                            currentVc.dismiss(animated: false)
                        }
                        self?.navigationController?.popToViewController(vcClass: SiteViewController.classForCoder())
                    }
                    // 返回到site列表 通知刷新site
                    NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: true)
                case .noSpacePermission, .userUnauthorized: // 没有空间权限
                    self.handleSpacePermissionLoss()
                case .incorrectPassword, .spacePasswordOverdue: // 密码修改
                    // 正在提示
                    if self.space.requiresPasswordVerification && SRAlertView.getCurrentAlertView() != nil {
                        return
                    }
                    self.space.requiresPasswordVerification = true
                    self.space.save()
                    SRAlertView(title: "notification".localizedString, message: "the_space_password_change_message".localizedString, actions: [SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
                        if let currentVc = UIViewController.getVisibleVc(), currentVc.presentingViewController != nil { // 退出modal页面
                            currentVc.dismiss(animated: false)
                        }
                        self?.removeFromWindowSubviews()
                        self?.navigationController?.popToViewController(vcClass: SiteViewController.classForCoder())
                    })]).show()
                default:
                    break
                }
            }
        }
    }
    
    /// 处理空间权限失效
    private func handleSpacePermissionLoss() {
        guard !hasHandledPermissionLoss else {
            return
        }
        hasHandledPermissionLoss = true
        stopSpacePresenceTracking(reason: .permissionLoss)
        space.state = .waitDeleted
        space.save()
        NotificationCenter.default.post(name: .init(spacesRefreshChangeNotificationName), object: true)
        
        guard view.window != nil else {
            return
        }
        
        SRAlertView(title: "notification".localizedString, message: "the_space_cleared_visitor_message".localizedString, actions: [SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
            if self?.space.permission == .owner {
                NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
            }
            if let currentVc = UIViewController.getVisibleVc(), currentVc.presentingViewController != nil { // 退出modal页面
                currentVc.dismiss(animated: false)
            }
            self?.removeFromWindowSubviews()
            self?.navigationController?.popToViewController(vcClass: SiteViewController.classForCoder())
        })]).show()
    }
    
    /// 切换权限提示
    private func showTransferPermissionAlert() {
        
        guard !space.disableEditorPermission else { return }
        
        SRAlertView(title: "notification".localizedString, message: "space_permission_transition_message".localizedString, actions: [SRAlertAction(title: "cancel".localizedString, style: .cancel, actionHandler: {[weak self] _ in
            self?.navigationController?.popToViewController(vcClass: SiteViewController.classForCoder())
        }), SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
            // 禁用编辑权限
            self?.disableEditorPermission()
        })]).show()
        
    }
    
    /// 关闭用户编辑权限
    private func disableEditorPermission() {
        self.space.disableEditorPermission = true
        #if DEBUG
        print("Space editor permission disabled for current session: siteId=\(space.siteId), spaceId=\(space.id), permission=\(space.permission.dataString)")
        #endif
        NotificationCenter.default.post(name: .init(spacePermissionChangedNotificaitonName), object: nil)
    }
    
    /// 更新空间缓存数据
    private func updateSpaceData() {
        var saveData = false
        let nodes = MeshNetworkManager.instance.realNodes
        let lightNodes = nodes.filter({ $0.deviceType == .light })
//        MeshNetworkManager.instance.lightNodes
        if self.space.deviceCount != nodes.count {
            self.space.deviceCount = nodes.count
            saveData = true
        }
        if self.space.luminairesCount != lightNodes.count {
            self.space.luminairesCount = lightNodes.count
            saveData = true
        }
        if self.space.groupCount != MeshNetworkManager.instance.groups.count {
            self.space.groupCount = MeshNetworkManager.instance.groups.count
            saveData = true
        }
        if self.space.sceneCount != MeshNetworkManager.instance.scenes.count {
            self.space.sceneCount = MeshNetworkManager.instance.scenes.count
            saveData = true
        }
        if self.space.scheheduleCount != MeshNetworkManager.instance.schedules.count {
            self.space.scheheduleCount = MeshNetworkManager.instance.schedules.count
            saveData = true
        }
        if self.space.switchesCount != MeshNetworkManager.instance.switchs.count {
            self.space.switchesCount = MeshNetworkManager.instance.switchs.count
            saveData = true
        }
        
        if saveData {
            self.space.save()
        }
    }
    
    func checkBluetoothState() {
        if MeshLibManager.manager.bluetoothState == .unknown {
            return
        }
        
//        self.navigationController?.visibleViewController
        // modal页面
        if let childVc = self.children.first, childVc.presentedViewController != nil {
            if MeshLibManager.manager.bluetoothState == .poweredOn {
                SRAlertView.hide()
            }else {
                showBluetoothRequiredAlertView()
            }
        }else {
            if MeshLibManager.manager.bluetoothState == .poweredOn {
                if let currentVc = UIViewController.getVisibleVc(), currentVc.isKind(of: BluetoothRequiredViewController.classForCoder()) {
                    navigationController?.popViewController(animated: false)
                }
            }else {
                MenuPopView.hide()
                navigationController?.pushViewController(BluetoothRequiredViewController(), animated: false)
            }
        }

        
    }
    
    private func showBluetoothRequiredAlertView() {
        
        let alertView = SRAlertView(title: String(format: "bluetooth_required_title".localizedString, appName), message: "bluetooth_required_message".localizedString, actions: [SRAlertAction(title: "settings".localizedString, titleColor: RGB(61, 110, 246), titleFont: FONTS(SCRYFrom(15)), closeAlert: false, actionHandler: { _ in
            if let openUrl = URL(string: "App-Prefs:root=Bluetooth") {
                UIApplication.shared.open(openUrl)
            }
        }), SRAlertAction(title: "back_space_list".localizedString, titleColor: RGB(61, 110, 246), titleFont: Font_Medium_Size(15), actionHandler: {[weak self] _ in
            UIViewController.getVisibleVc()?.dismiss(animated: false)
            self?.navigationController?.popViewController(animated: true)
        })])
        alertView.messageLabel.snp.updateConstraints { make in
            make.top.equalTo(alertView.titleLabel.snp.bottom).offset(SCRYFrom(8))
        }
        alertView.show()
    }
    
    @objc private func moreClick() {
        // mesh网络连接中
        if !MeshLibManager.manager.isMeshNetworkConnected && XWHUDManager.isVisible() {
            return
        }
        
//        isIphoneX ? 18 : 15
        let touchCenterX = view.width - navigationRightItemMargin - 15
        clearTransientWindowMenus()
        
        var items: [MenuPopView.MenuItem] = []
        
        if space.spaceOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] _ in
                self?.editSpace()
            }))
        }
        if space.spaceOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] _ in
                self?.deleteSpace()
            }))
        }
        if space.spaceOperates.contains(.shareEditor) || space.spaceOperates.contains(.shareVisitor) {
            items.append(.init(icon: UIImage(named: "menu_share"), title: "share".localizedString, tapItemBack: {[weak self] _ in
                self?.shareSpace()
            }))
        }
        if space.canDebug {
            items.append(.init(icon: UIImage(named: "menu_profile_test"), title: "debug".localizedString, tapItemBack: {[weak self] _ in
                self?.openSpaceDebug()
            }))
        }
        if space.spaceOperates.contains(.exit) {
            items.append(.init(icon: UIImage(named: "menu_unbind"), title: "unbind".localizedString, tapItemBack: {[weak self] _ in
                SRAlertView(title: "notification".localizedString, message: "space_unbind_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    self?.unbindSpace()
                })]).show()
            }))
        }
//#if DEBUG
//        items.append(.init(icon: UIImage(named: "menu_edit"), title: "reply".localizedString, tapItemBack: {[weak self] _ in
//            guard let self = self else { return }
//            let vc = DevicesReplySetViewController()
//            self.navigationController?.pushViewController(vc, animated: true)
//        }))
//#endif
        
        
        MenuPopView.show(items: items, anchorPoint: CGPoint(x: touchCenterX, y: view.safeAreaInsets.top), menuWidth: SCRXFrom(108))
    }
    
    private func openSpaceDebug() {
        let vc = SpaceDebugViewController(space: space) { [weak self] in
            self?.restoreMeshConnectionAfterDebug()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func restoreMeshConnectionAfterDebug() {
        guard !MeshLibManager.manager.isMeshNetworkConnected else {
            SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: space)
            return
        }
        setNetworkConnected()
    }

    /// 编辑空间
    private func editSpace() {
        
        var imageNames: [String] = []
        for id in 1...24 {
            imageNames.append("space_picture_\(id)")
        }
        let columnNum = isIPad ? 4 : 2
        let vc = InfoEditViewController(name: space.name, imageNames: imageNames, selectImageIndex: max(space.imageId - 1, 0), columnNum: columnNum)
        vc.itemHeight = isIPad ? SCRYFrom(104) : nil
        vc.nameEditChangedCallback = {[weak self] name in
            guard let self = self else { return false }
            return SpaceData.isTautonym(spaceName: name, siteId: self.space.siteId) && name != self.space.name
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return true }
            self.space.name = name
            self.space.imageId = imageId + 1
            self.space.lastUpdate = Int64(Date().timeIntervalSince1970)
            self.space.save()
            self.title = name
            self.syncSpace(level: .normal)
            return true
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 删除空间
    private func deleteSpace() {
        
        SRAlertView(title: "notification".localizedString, message: "space_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: { _ in
            // 提示1s
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                XWHUDManager.hide()
                guard let self = self else { return }
                // 空间内存在设备
                if self.space.deviceCount > 0 {
                    XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
                }else { // 空间未存在设备，删除成功
                    
                    // 是否有同步操作正在进行,进行中则取消任务
                    CloudSynchronizationManager.shared.cancelSynchronizationHandle(space: self.space)
                    
                    // 提交到云端需要网络才能删除
                    if self.space.uploadCloud {
                        self.deleteSpaceRequest()
                    }else { // 只存在于本地，删除数据
                        self.site.spaces.removeAll(where: { $0.id == self.space.id })
                        self.space.delete()
                        self.navigationController?.popViewController(animated: true)
                        self.deleteSpaceCallback?()
                        NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                    }
          
                }
            }
        })]).show()
        
    }
    
    /// 分享space
    private func shareSpace() {
        
        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }
        if let handle = CloudSynchronizationManager.shared.getSpaceCurrentSyncState(space) {
            // site正在排队
            if case .wait = handle.state {
                XWHUDManager.showTipHUD("sync_data_unfinished_message".localizedString, isLineFeed: true)
                // 修改任务等级为紧急
                CloudSynchronizationManager.shared.setSynchronizationHandleLevel(handle: handle, level: .promptly)
                return
            }
            // site正在同步中
            if case .inProgress = handle.state {
                XWHUDManager.showTipHUD("syncing_data_message".localizedString, isLineFeed: true)
                return
            }
        }
        // space需要提交数据
        if space.needUploadCloud {
            self.syncSpace(level: .promptly)
            XWHUDManager.showTipHUD("sync_data_unfinished_message".localizedString, isLineFeed: true)
            return
        }
    
        var networkApi: NetowrkReqeustApi!
        // 有分享code则读取之前的数据
//        if let shareCode = space.shareCode, space.editorPassword != nil || space.permission == .editor {
        if let shareCode = space.shareCode {
            networkApi = .shareInfo(shareId: shareCode)
        }else {
            // 还没有设置编辑者密码
            if space.permission == .owner && space.editorPassword == nil {
                space.editorPassword = String.generateRandomNumberString()
            }
            networkApi = .spaceShare(space: space)
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(networkApi) {[weak self] result in
            
            guard let self = self else {
                XWHUDManager.hide()
                return
            }
            switch result {
            case .success(let response):
                guard let code = JSON(response)["data"]["token"].string else {
                    XWHUDManager.hide()
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                    return
                }
                
                var spaceSave = false
                // 更新owner数据
                if let ownerData = JSON(response)["data"]["space"]["owner"].dictionaryObject {
                    if let userId = ownerData["userId"] as? String, let userName = ownerData["username"] as? String {
                        if self.space.owner?.uuid != userId {
                            self.space.owner = .init(name: userName, uuid: userId)
                            spaceSave = true
                        }
                    }
                }
                
                // 更新editor数据
                if let editorData = JSON(response)["data"]["space"]["editor"].dictionaryObject {
                    if let userId = editorData["userId"] as? String, let userName = editorData["username"] as? String {
                        if self.space.editor?.uuid != userId {
                            self.space.editor = .init(name: userName, uuid: userId)
                            spaceSave = true
                        }
                    }else {
                        if self.space.editor != nil {
                            self.space.editor = nil
                            spaceSave = true
                        }
                    }
                }
                
                if self.space.permission == .owner, let editorPassword = JSON(response)["data"]["space"]["editorPasswd"].string, space.editorPassword != editorPassword {
                    self.space.editorPassword = editorPassword
                    spaceSave = true
                }
                
                if let visitorPassword = JSON(response)["data"]["space"]["visitorPasswd"].string {
                    if self.space.vistorPassword ?? "" != visitorPassword {
                        if visitorPassword.isEmpty {
                            self.space.vistorPassword = nil
//                                space.vistorPasswordEnable = false
                        }else {
                            self.space.vistorPassword = visitorPassword
//                                space.vistorPasswordEnable = true
                        }
                        spaceSave = true
                    }
                }
                
                // 邀请码
                if self.space.shareCode != code {
                    self.space.shareCode = code
                    spaceSave = true
                }
                if spaceSave {
                    self.space.save()
                }
                let vc = SharingSettingViewController(type: .space(site: self.site, space: self.space))
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                }
                self.present(NavigationViewController(rootViewController: vc), animated: true) {
                    XWHUDManager.hide()
                }
            case .failure(let error):
                if error == .resourceNotFound {
                    self.space.shareCode = nil
                    self.space.save()
                }
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    
    /// 更新同步状态
    private func updateSyncState() {
        
        if view.window != nil, let state = CloudSynchronizationManager.shared.getSpaceCurrentSyncState(space)?.state {
            switch state {
            case .inProgress:
                self.showNavigationBarLoading()
            case .successful:
                self.showNavigationBarSuccessful()
            case .failure:
                self.showNavigationBarFailure {[weak self] in
                    // 点击失败图标
                    guard let self = self, let error = self.space.showSyncCloudError else { return }
                    SRAlertView(title: "synchronization_failure".localizedString, message: error.localizedDescription, actions: [.cancelAction, SRAlertAction(title: "SYNC".localizedString, actionHandler: { _ in
                        self.syncSpace(level: .promptly)
                    })]).show()
                }
            default:
                break
            }
        }
    }
    
    /// 退出页面立即同步space数据
    private func promptlySyncSpace() {
        
        XWHUDManager.showCustomHUD(withMessage: "syncing_data".localizedString, isWindow: true)
        
        ConfigurationFlowGuidanceView.current()?.hide()
        exitSyncSpace = true
        self.syncSpace(level: .promptly)
        
    }
    /// 展示同步space数据失败页面
    private func showSyncSpaceFailedAlert() {
        
        SRAlertView(title: "notification".localizedString, message: "space_sync_failed_message".localizedString, actions: [SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })]).show()
    }
    
}

extension SpaceViewController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        guard loadNetworkData else {
            return 0
        }
        return SpaceMenuView.defalutItems.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        
        switch index {
        case 0:
            let vc = DevicesViewController(site: site, space: space)
            return vc
        case 1:
            let vc = GroupsViewController(space: space)
            return vc
        case 2:
            let vc = ScenesViewController(space: space)
            return vc
        case 3:
            let vc = TimedViewController(space: space)
            return vc
        case 4:
            let vc = SpaceMoreViewController(site: site, space: space)
            return vc
        default:
            return UIViewController()
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = view.safeAreaInsets.top + meunHeight
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: view.safeAreaInsets.top, width: view.width, height: meunHeight)
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return ""
    }
    
    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
        mainMenuView.selectIndex = Int(self.selectIndex)
        if let disablePageIndex = self.disablePageIndex, selectIndex == disablePageIndex {
            self.scrollEnable = false
        }
    }
    
    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return !XWHUDManager.isVisible()
//        return index < 3
    }
    
    override func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        super.menuView(menu, didSelectedIndex: index, currentIndex: currentIndex)
        
        if let disablePageIndex = self.disablePageIndex, index == disablePageIndex {
            self.scrollEnable = false
        }else {
            self.scrollEnable = true
        }
    }
    
}

extension SpaceViewController: NavigationViewControllerDelegate {
    
    /// 点击返回item回调
    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController) {
      
        guard space.needUploadCloud, navigationController.topViewController == self else {
            self.navigationController?.popViewController(animated: true)
            return
        }
        promptlySyncSpace()
    }
    
    /// pop手势begin回调，返回是否可以pop
    func navigationController(_ navigationController: NavigationViewController, gestureRecognizerShould gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 无网络并且更新了数据
        guard navigationController.topViewController == self else {
            return true
        }
        guard selectIndex == 0 else {
            return false
        }
        guard space.needUploadCloud else {
            return true
        }
        promptlySyncSpace()
        return false
    }
}

extension SpaceViewController: CloudSynchronizationManagerDelegate {
    
    /// 开始同步数据回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didStartSync handle: CloudSynchronizationHandle) {
        updateSyncState()
    }
    
    /// 同步数据成功回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFinished handle: CloudSynchronizationHandle) {
        updateSyncState()
        if exitSyncSpace {
            XWHUDManager.hide()
            navigationController?.popViewController(animated: true)
        }
    }
    
    /// 同步数据失败回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFailure handle: CloudSynchronizationHandle, error: NetworkApiError) {
        updateSyncState()
        if exitSyncSpace { // 提示数据同步失败
            XWHUDManager.hide()
            showSyncSpaceFailedAlert()
        }
    }
    
    /// 同步数据操作取消回调
    func cloudSyncManager(_ manager: CloudSynchronizationManager, cancelSyncHandle handle: CloudSynchronizationHandle) {
        updateSyncState()
    }
}

extension SpaceViewController: MeshExternalVendorMessageDelegate {
    
    /// 收到外部自定义消息回调
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - message: 消息体
    ///   - source: 来源设备地址
    ///   - destination: 接收设备地址
    func meshNetworkManager(_ manager: MeshNetworkManager,
                            didReceiveMessage message: ExternalVendorMessage,
                            sentFrom source: Address, to destination: Address) {
        
        guard source != manager.meshNetwork?.localProvisioner?.node?.primaryUnicastAddress, !self.meshPermissionValidation, let operation = message.unmarshal() else {
            return
        }
        
        switch operation {
        case .userPermission(let event):
            switch event {
            case .ask: // 收到其他人查询权限消息
                // 回复自己的权限给对方
                MeshAPI.sendMessage(message: ExternalVendorMessage(operation: .userPermission(.reply(permission: self.space.permission))), address: source)
            case .reply(let permission): // 收到对方回复权限消息
                if permission == .owner || permission == .editor {
//                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(userPermissionAskTimeout), object: nil)
                    stopUserAskTimer()
                    // 关闭用户编辑权限
                    showTransferPermissionAlert()
                    self.meshPermissionValidation = true
                }
            }
        }
        
    }
    
}
