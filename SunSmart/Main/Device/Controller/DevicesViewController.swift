//
//  DevicesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/28.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth
import SwiftyJSON

/// 全开全关状态
enum DeviceAllOnOffState {
    /// 开
    case on
    /// 关
    case off
    /// 不可用
    case disable
}

/// 设备列表更新通知
let devicesUpdateNotificationName = "devicesUpdateNotification"
/// 设备状态更新通知
let deviceStateUpdateNotificationName = "deviceStateUpdateNotification"

/// 设备添加刷新通知
let devicesAddNotificationName = "devicesAddNotification"

protocol DevicesFunctionProtocol {
    
    /// 点击编辑事件
    func footerView(_ footerView: SpaceFunctionFooterView, didEditAction edit: Bool)
    
    /// 点击排序事件
    func footerViewDidSortAction(_ footerView: SpaceFunctionFooterView)
    
    /// 点击添加事件
    func footerViewDidAddAction(_ footerView: SpaceFunctionFooterView)
    
    /// 点击删除事件
    func footerViewDidDeleteAction(_ footerView: SpaceFunctionFooterView)
}

extension DevicesFunctionProtocol {
    
    /// 点击排序事件
    func footerViewDidSortAction(_ footerView: SpaceFunctionFooterView) {
        
    }
    
    /// 点击添加事件
    func footerViewDidAddAction(_ footerView: SpaceFunctionFooterView) {
        
    }
    
    /// 点击删除事件
    func footerViewDidDeleteAction(_ footerView: SpaceFunctionFooterView) {
        
    }
    
}

class DevicesViewController: WMPageController {
    
    let footerHeight = SCRYFrom(44) + kSafeAreaBottomHeight
    /// 头部
    //    private var headerView: UIView!
    //    private var allOnBtn: UIButton!
    //    private var allOffBtn: UIButton!
    //    private var settingBtn: UIButton!
    
    /// 菜单功能
    let menuTitles: [String] = ["lights".localizedString, "switches".localizedString, "sensors".localizedString, "others".localizedString]
    
    let site: SiteData
    let space: SpaceData
    
    
    /// 使用过的引导内容索引
    private var useGuidanceMessageIndexs: [Int] = []
    /// 引导内容轮播定时器
    private var guidanceTimer: Timer?
    /// 连接loading弹窗
    private weak var connectLoadingHUD: WYProgressHUD?
    /// 是否首次连接
    private var firstConnectionNetwork: Bool = true
    
    //******** Mesh Distribution ********/
    /// 分发状态查询定时器
    private var distributionStateTimer: Timer?
    /// 当前分发的设备
    private var currentDistributionNode: Node?
    // 分发状态view
    private var distributionStateView: FirmwareDistributeUpdateStateView?
    
    private var menuHeight = CGFloat(Int(SCRYFrom(40)))
    //    private var meunView: WMMenuView!
    private var meshNetworkConnectedObservation: NSKeyValueObservation?
    
    
    init(site: SiteData, space: SpaceData) {
        self.site = site
        self.space = space
        super.init(nibName: nil, bundle: nil)
        
        //        self.menuViewStyle = .flood
        if isIPad {
            self.menuViewLayoutMode = .center
            self.itemMargin = SCRXFrom(24)
        }
        self.menuItemCornerRadius = menuHeight * 0.5
        //        self.progressViewIsNaughty = false
        self.menuItemBackgroundColor = .clear
        //        self.scrollEnable = false
        space.meshOTADistribution = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = Background_Color
        
        //        view.layoutIfNeeded()
        
        addObservation()
        
        // 未连接上mesh网络
        if !MeshNetworkManager.instance.realNodes.isEmpty && !MeshLibManager.manager.isMeshNetworkConnected && (MeshLibManager.manager.bluetoothState == .poweredOn || MeshLibManager.manager.bluetoothState == .unknown) {
            
//            guard self.view.window != nil else { return }
            //            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 10)
            // loading
            let margin: CGFloat = isIPad ? 100 : 36
            XWHUDManager.showGifImagesHUD(in: self.wm_pageController?.view ?? self.view, gifFileName: "XWHUDManager_loading", message: getNextGuidanceMessage() ?? "", timer: 10, margin: margin)
            self.perform(#selector(self.guidanceTimeout), with: nil, afterDelay: 10)
            if let hud = XWHUDManager.currentHUD() {
                hud.bezelView.layer.cornerRadius = 20
                hud.minSize = CGSizeMake(SCREEN_WIDTH - margin * 2, 185)
                self.connectLoadingHUD = hud
                hud.addCloseButton {[weak self] in
                    guard let self = self else { return }
                    self.stopGuidanceTimer()
                    
                    // 判断是否需要申请地址
                    if self.space.applyDeviceAddressCount != nil {
                        applyDeviceAddressAlert()
                    }
                }
            }
            startGuidanceTimer()
            // 获取设备信号
            //            MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5, result: nil)
        }else {
            // 判断是否需要申请地址
            if space.applyDeviceAddressCount != nil {
                applyDeviceAddressAlert()
            }
        }
        //        meunView = WMMenuView(frame: CGRect(x: 0, y: SCRYFrom(10), width: view.width, height: SCRYFrom(32)))
        //        meunView.fontWeight = .light
        //        meunView.style = .segmented
        //        meunView.lineColor = Bar_Color
        
        
        //        meunView.contentMargin = SCRXFrom(12)
        self.scrollEnable = false
        self.menuView?.itemRateAnimation = false
        self.menuView?.delegate = self
        self.menuView?.dataSource = self
        //        view.addSubview(self.menuView!)
        //        meunView.snp.makeConstraints { make in
        //            make.left.right.equalToSuperview()
        //            make.top.equalTo(SCRYFrom(10))
        //            make.height.equalTo(SCRYFrom(32))
        //        }
        
        //        XWHUDManager.showGifImagesHUD(inView: "XWHUDManager_loading", message: "Some devices prompt REPAIR when they are added because some models cannot be set to the device.", timer: 10)
        //        addNotificaiton()
        
        startGuidanceTimer()
        
        //        selectIndex = 1
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
//        XWHUDManager.currentHUD()?.hide(animated: false)
        stopGuidanceTimer()
    }
    
    deinit {
        meshNetworkConnectedObservation = nil
        stopDistributionStateTimer()
    }
    
    /// 添加KVO观察者
    private func addObservation() {
        
        // mesh网络连接观察者
        meshNetworkConnectedObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if MeshLibManager.manager.isMeshNetworkConnected, self.firstConnectionNetwork {
                    // 首次连接上mesh网络
                    self.firstConnectionNetwork = false
                    
                    if let view = self.wm_pageController?.view {
                        XWHUDManager.hideInView(with: view)
                    }else {
                        XWHUDManager.hide()
                    }
                    self.stopGuidanceTimer()
                    
                    // 判断是否需要申请地址
                    if self.space.applyDeviceAddressCount != nil {
                        self.applyDeviceAddressAlert()
                    }
                    // 检查mesh分发情况
                    self.getMeshDistribution()
                    
                    // 同步时间
                    if MeshNetworkManager.instance.realNodes.contains(where: { $0.scheduleIds.count > 0 }) && MeshNetworkManager.instance.schedules.filter({ $0.enabled }).count > 0 {
                        // 延迟3s发送广播节点同步时间消息，避免与获取设备状态冲突
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {[weak self] in
                            self?.syncTimeNodes()
                        }
                    }
                    
                }
            }
        })
        
    }
    
    // MARK: - Guidance
    
    /// 获取下一个引导文本
    private func getNextGuidanceMessage() -> String? {
        let maxIndex = 55
        guard useGuidanceMessageIndexs.count < maxIndex else {
            return nil
        }
        // 55条文案随机一条
        let index = Int(arc4random_uniform(UInt32(maxIndex))) + 1
        // 排除重复文案
        if useGuidanceMessageIndexs.contains(Int(index)) {
            return getNextGuidanceMessage()
        }
        useGuidanceMessageIndexs.append(index)
        return "guidance_message_\(index)".localizedString
    }
    
    /// 开始轮播引导文本
    private func startGuidanceTimer() {
        guidanceTimer = Timer(timeInterval: 5, repeats: true, block: {[weak self] _ in
            guard let self = self else {
                return
            }
            self.connectLoadingHUD?.detailsLabel.text = self.getNextGuidanceMessage()
        })
        RunLoop.current.add(guidanceTimer!, forMode: .common)
    }
    
    /// 停止网络连接引导提示
    private func stopGuidanceTimer() {
        guidanceTimer?.invalidate()
        guidanceTimer = nil
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(guidanceTimeout), object: nil)
    }
    
    /// 连接网络引导超时
    @objc private func guidanceTimeout() {
        stopGuidanceTimer()
        
        // 判断是否需要申请地址
        if space.applyDeviceAddressCount != nil {
            applyDeviceAddressAlert()
        }
    }
    
    /// 申请地址提示
    private func applyDeviceAddressAlert() {
        guard NetworkRequest.shared.networkable, let applyAddressCount = space.applyDeviceAddressCount, applyAddressCount > 0 else { return }
        
        self.space.applyDeviceAddressCount = nil
        self.space.save()
        
        SRAlertView(title: "notification".localizedString, message: "device_address_apply_message".localizedString, actions: [SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: {[weak self] _ in
            self?.space.applyDeviceAddressCount = nil
            self?.space.save()
        }), SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            // 申请地址
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            NetworkRequest.shared.request(.applyAddress(siteId: self.space.siteId, type: .device, number: applyAddressCount)) {[weak self] result in
                XWHUDManager.hideInWindow()
                guard let self = self else { return }
                switch result {
                case .success(let repsonsed):
                    self.space.applyDeviceAddressCount = nil
                    self.space.save()
                    // 新增地址
                    if let site = SiteData.load(siteId: self.space.siteId), let provisionerData = JSON(repsonsed)["data"]["provisioner"].dictionaryObject {
                        site.setProvisioner(provisionerData: provisionerData)
                        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site), level: .promptly)
                    }else {
                        XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                    }
                case .failure(let error):
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
            }
            
        })]).show()
    }
    
    /// 添加按键点击事件 1.5
    func addAction(point: CGPoint) {
        
        DeviceAddMenuView(selectCallback: {[weak self] options in
            guard let self = self else { return }
            switch options {
            case .searchDevices:
                self.deviceAdd()
            case .preCreatedSwitches:
                let controller = PJSwitchesTypesVC.makePopupViewController(
                    onBack: { [weak self] in
                        self?.addAction(point: point)
                    },
                    onKineticSwitch: { [weak self] in
                        self?.switchAdd()
                    },
                    onBatterySwitch: { [weak self] in
                        guard let self = self else { return }
                        let vc = PJPreAddEightKeySwitchesVC(space: self.space)
                        if isIPad {
                            vc.preferredContentSize = iPadPreferredContentSize
                        }
                        self.present(NavigationViewController(rootViewController: vc), animated: true)
                    }
                )
                self.present(controller, animated: false)
            case .restoreDevice:
                self.devicesRestore()
            case .preCreatedSensors:
                XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
            case .preCreatedDongles:
                let controller = OthersViewController.makePopupViewController(
                    onBack: { [weak self] in
                        self?.addAction(point: point)
                    },
                    onDongles: { [weak self] in
                        self?.preCreatedDongle()
                    },
                    onFireAlarm: { [weak self] in
                        self?.showEmerFireCreatePage()
                    }
                )
                self.present(controller, animated: false)
            }
        }).show()
        
        //        let items: [MenuPopView.MenuItem] = [
        //            .init(icon: UIImage(named: "menu_light"), title: "light".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
        //                guard let self = self else { return }
        //                self.deviceAdd()
        //            }),
        //            .init(icon: UIImage(named: "menu_switch"), title: "switch".localizedString, tapItemBack: { _ in
        //                self.switchAdd()
        //            })
        //        ]
        //        MenuPopView.show(items: items, anchorPoint: point, direction: .up)
    }
    
    private func showEmerFireCreatePage() {
        let context = PJDevicesAddEntryContext(
            source: .fireAlarm,
            space: space,
            title: "add_device".localizedString,
            appointGroup: nil,
            addBehavior: .init(
                allowsTargetSelection: false,
                allowsCategorySelection: false,
                allowedTypes: [.others],
                blockedDeviceTypes: [.dongle, .gateway, .unknown],
                selectionMode: .single,
                forbiddenSelectionTip: "You can't choose other devices.",
                forbiddenDeviceTypeTip: "Cannot add, type mismatch"
            )
        )
        let vc = PJDevicesAddFlowFactory.make(context: context)
        let nav = NavigationViewController(rootViewController: vc)
        DispatchQueue.main.async { [weak self] in
            self?.present(nav, animated: true)
        }
    }
    
    /// 节点同步时间
    private func syncTimeNodes() {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
//        MeshNetworkManager.instance.realNodes.forEach { node in
//            if let model = node.timeModel {
//                MeshAPI.sendMessage(message: Node.setLocalTimeMessage(), model: model)
//            }
//        }
//        MeshNetworkManager.instance.realNodes.first?.lightLCSchedulerSetupModel
        MeshAPI.sendMessage(message: Node.setLocalTimeMessage(), address: .allNodes)
        space.lastSyncDateTimestamp = CLongLong(Date().timeIntervalSince1970)
        space.save()
        
    }
    
    /// 添加设备
    private func deviceAdd() {
        
        guard MeshNetworkManager.instance.realNodes.count < space.maxDevicesCount else {
            XWHUDManager.showTipHUD(String(format: "devices_number_exceeds_message".localizedString, space.maxDevicesCount), isLineFeed: true)
            return
        }
        //        navigationController?.pushViewController(DeviceRestoreViewController(), animated: true)
        //        return
        let vc = DeviceAddViewController(space: space)
        vc.deviceAddCallback = { nodes in
            NotificationCenter.default.post(name: .init(devicesAddNotificationName), object: nil)
            
            //            self?.loadDevices()
            //            self?.getNodesState()
            //            self?.collectionView.reloadData()
            //            self?.updateAllOnOffItemUI()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 添加动能开关
    private func switchAdd() {
        
        guard MeshNetworkManager.instance.switchs.count < 16 else {
            SRAlertView(title: "notification".localizedString, message: "switchs_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
            return
        }
        let vc = DeviceSwitchViewController(space: self.space, switchData: nil)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 预创建dongle
    private func preCreatedDongle() {
        
        let vc = DeviceDongleViewController(space: self.space, dongleData: nil)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }

    /// 恢复设备数据
    private func devicesRestore() {
        let vc = DeviceRestoreViewController(site: self.site, space: space, restoreMode: .default)
//        vc.automationRestore = true
        vc.deviceRestoreCallback = { nodes, _ in
            if nodes.count > 0 {
                NotificationCenter.default.post(name: .init(devicesAddNotificationName), object: nil)
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    // MARK: - Mesh Distribution
    
    // 获取网络内当前固件分发者
    private func getMeshDistribution() {
        
        Task {
            // 获取当前分发者
            if let currentDistribution = await MeshFirmwareDistributionManager.shared.currentActiveFirmwareDistributionNodeGet() {
                self.currentDistributionNode = currentDistribution
                startDistributionStateTimer()
            }else if self.space.permission != .visitor { // 没有分发者
                
                // 获取分发记录
                let list = MeshDistributionData.loadAll()
                // 需要获取分发中的状态的记录
                var distributionDatas: [MeshDistributionData] = []
                list.forEach { data in
                    switch data.distributionState {
                    case .none:
                        fallthrough
                    case .await:
                        fallthrough
                    case .updating:
                        fallthrough
                    case .waitingInstall:
                        distributionDatas.append(data)
                    default:
                        break
                    }
                }
                guard distributionDatas.count > 0 else {
                    return
                }
                XWHUDManager.showCustomHUD(withMessage: nil, view: SpaceViewController.currentSpaceVc()?.view ?? self.view)
                
                // 展示的分发记录
                var showDistributionDatas: [MeshDistributionData] = []
                var results: [MeshFirmwareUpgradeResultsView.FirmwareUpgradeResult] = []
                while let data = distributionDatas.first {
                    guard let distributionNode = data.distributionNode, let productId = distributionNode.productIdentifier else {
                        distributionDatas.removeFirst()
                        continue
                    }
                    // 固件大小
                    let firmwareSize = distributionNode.distributionFirmwareSize ?? UInt32(FirmwareData.load(productId: productId).first?.data.count ?? 300 * 1024)
                    
                    if let state = await MeshFirmwareDistributionManager.shared.getDistributionState(distributionNode: distributionNode, firmwareSize: firmwareSize) {
                        var updateData = data
                        updateData.distributionState = state
                        updateData.save(productId: productId)
                        
                        switch state {
                        case .complete:
                            let result = MeshFirmwareUpgradeResultsView.FirmwareUpgradeResult(name: distributionNode.categoryName ?? "Unknown", productId: productId, state: .installComplete)
                            results.append(result)
                            showDistributionDatas.append(data)
                        case .failure:
                            let result = MeshFirmwareUpgradeResultsView.FirmwareUpgradeResult(name: distributionNode.categoryName ?? "Unknown", productId: productId, state: .installFailure)
                            results.append(result)
                            showDistributionDatas.append(data)
                        default:
                            break
                        }
                    }
                    distributionDatas.removeFirst()
                }
                XWHUDManager.hideInView(with: SpaceViewController.currentSpaceVc()?.view ?? self.view)
                // 展示分发结果
                if results.count > 0 {
                    DispatchQueue.main.async {
                        MeshFirmwareUpgradeResultsView(results: results) {[weak self] showDetails in
                            if showDetails { // 详情
                                self?.pushToMeshOTADetails()
                            }else { // 知道了
                                // 清空已查看的分发状态信息
                                showDistributionDatas.forEach({
                                    if let productId = $0.distributionNode?.productIdentifier {
                                        $0.delete(productId: productId)
                                    }
                                })
                            }
                        }.show()
                    }
                }
                
            }
        }
    }
    
    /// 开启分发者状态定时器
    private func startDistributionStateTimer() {
        
        guard currentDistributionNode != nil else {
            return
        }
        
        distributionStateTimer = LCWeakTimer.scheduledTimer(timeInterval: 30, aTarget: self, selector: #selector(getMeshDistributionState), userInfo: nil, repeats: true)
        RunLoop.current.add(distributionStateTimer!, forMode: .common)
        distributionStateTimer?.fire()
    }
    
    /// 获取分发者状态
    @objc private func getMeshDistributionState() {
        
        guard let distributionNode = currentDistributionNode, let productId = distributionNode.productIdentifier else {
            distributionStateView?.hide()
            distributionStateView = nil
            stopDistributionStateTimer()
            return
        }
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
        // 固件大小
        let firmwareSize = distributionNode.distributionFirmwareSize ?? UInt32(FirmwareData.load(productId: productId).first?.data.count ?? 256 * 1024)
        MeshFirmwareDistributionManager.shared.getDistributionState(distributionNode: distributionNode, firmwareSize: firmwareSize) {[weak self] _, state in
            guard let self = self, state != nil else { return }
            
            switch state {
            case .updating(let updatePhase):
                switch updatePhase {
                case .blob(let progress, let estimateSec):
                    if self.distributionStateView == nil {
                        let cacheData = MeshDistributionData.load(productId: productId)
                        let isOwner = cacheData?.distributionAddress == distributionNode.primaryUnicastAddress
                        if isOwner {
                            self.space.meshOTADistribution = true
                        }
                        let stateView = FirmwareDistributeUpdateStateView(frame: UIScreen.main.bounds)
                        stateView.start(title: "notification".localizedString, message: "mesh_upgrade_inview_message".localizedString, distributeVersion: nil, isUpload: false, isOwner: isOwner)
                        stateView.show()
                        stateView.delegate = self
                        self.distributionStateView = stateView
                    }
                    var estimatedTime: String?
                    if estimateSec >= 0 {
                        // 剩余分钟
                        let minute = Int(ceil(Double(estimateSec) / 60.0))
                        estimatedTime = "\(minute) \("minutes".localizedString)"
                    }
                    self.distributionStateView?.update(state: .inProgress(progress: Int(progress), estimatedTime: estimatedTime))
                    // 传输固件中关闭编辑权限
                    if !self.space.disableEditorPermission {
                        self.space.disableEditorPermission = true
                        NotificationCenter.default.post(name: .init(spacePermissionChangedNotificaitonName), object: nil)
                    }
                default:
                    // 恢复权限
                    if self.space.meshOTADistribution && self.space.disableEditorPermission {
                        self.space.meshOTADistribution = false
                        self.space.disableEditorPermission = false
                        NotificationCenter.default.post(name: .init(spacePermissionChangedNotificaitonName), object: nil)
                    }
                    self.distributionStateView?.hide()
                    self.distributionStateView = nil
                    self.stopDistributionStateTimer()
                }
            default:
                // 恢复权限
                if self.space.meshOTADistribution && self.space.disableEditorPermission {
                    self.space.meshOTADistribution = false
                    self.space.disableEditorPermission = false
                    NotificationCenter.default.post(name: .init(spacePermissionChangedNotificaitonName), object: nil)
                }
                self.distributionStateView?.hide()
                self.distributionStateView = nil
                self.stopDistributionStateTimer()
            }
            
            var data = MeshDistributionData.load(productId: productId)
            data?.distributionState = state!
            data?.save(productId: productId)
        }
    }
    
    /// 停止分发者状态定时器
    private func stopDistributionStateTimer() {
        distributionStateTimer?.invalidate()
        distributionStateTimer = nil
    }
    
    /// 页面跳转到mesh ota信息
    private func pushToMeshOTADetails() {
        
        let vc = MeshFirmwareListViewController()
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
        
    }
    
}

extension DevicesViewController: MeshLibManagerDelegate, MeshLibManagerMessageDelegate {
    
    /// 蓝牙状态发生变化回调
    /// - Parameters:
    ///   - state: 蓝牙状态
    func meshNetworkManager(bluetoothDidUpdateState state: CBManagerState) {
        //        if state == .poweredOn && devices.count > 0 {
        //            // 获取设备信号
        //            MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 3, result: nil)
        //        }
    }
    
    
    ///  mesh设备连接成功
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - bearer: 代理设备
    func meshNetworkManager(_ manager: MeshNetworkManager, bearerDidOpen bearer: Bearer) {
        //       let addressList = space.meshManager?.realNodes.map({ $0.primaryUnicastAddress }) ?? []
        //        MeshAPI.resetNodes(addressList: addressList, resetSuccess: nil, resetFail: nil, resetFinish: nil)
        
        //        if view.window != nil {
        //            getNodesState()
        //        }
    }
    
    ///  mesh设备断开连接
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - bearer: 代理设备
    func meshNetworkManager(_ manager: MeshNetworkManager, bearerDidClose bearer: Bearer) {
        
    }
    
    /// ivIndex更新回调
    func meshNetworkManager(_ manager: MeshNetworkManager, didIvIndexChange ivIndex: UInt32) {
        // 通知space数据修改
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .ivIndex))
    }
    
}

extension DevicesViewController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return menuTitles.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        
        switch index {
        case 0:
            let vc = DeviceLightsViewController(site: site, space: space)
            return vc
        case 1:
            let vc = DeviceSwitchesViewController(space: space)
            return vc
        case 2:
            let vc = DeviceSensorsViewController(space: space)
            return vc
        case 3:
            let vc = DeviceOthersViewController(space: space)
            return vc
        default:
            return UIViewController()
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        //        let y = SCRYFrom(42)
        //        let footerH = SCRYFrom(44) + kSafeAreaBottomHeight
        return CGRect(x: 0, y: 0, width: view.width, height: view.height)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: SCRYFrom(isIPad ? 20 : 10), width: view.width, height: menuHeight)
    }
    
    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
        //        mainMenuView.selectIndex = Int(self.selectIndex)
    }
    
    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return !XWHUDManager.isVisible()
        //        return index < 3
    }
    
}

extension DevicesViewController {
    
    override func numbersOfTitles(in menu: WMMenuView!) -> Int {
        return menuTitles.count
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return menuTitles[index]
    }
    
    override func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
        return 14
    }
    
    override func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
        return state == .selected ? .white : Bar_Color
    }
    
    override func menuView(_ menu: WMMenuView!, widthForItemAt index: Int) -> CGFloat {
        let itemW = isIPad ? SCRXFrom(120) : SCRXFrom(80)
        return CGFloat(Int(itemW))
    }
    
    override func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
        if isIPad {
            return super.menuView(menu, itemMarginAt: index)
        }
        if index == 0 || index == 4 {
            return SCRXFrom(12)
        }
        return SCRXFrom(10)
    }
    
    override func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        
        let item = menu.item(at: index)
        item?.backgroundColor = Bar_Color
        item?.layer.borderWidth = 0
        item?.font = UIFont.systemFont(ofSize: 14)
        
        guard index != currentIndex else {
            return
        }
        
        let lastItem = menu.item(at: currentIndex)
        lastItem?.backgroundColor = RGB(254, 254, 254)
        //        self.selectIndex = Int32(index)
        
        super.menuView(menu, didSelectedIndex: index, currentIndex: currentIndex)
    }
    
    override func menuView(_ menu: WMMenuView!, initialMenuItem: WMMenuItem!, at index: Int) -> WMMenuItem! {
        
        if index == 0 {
            initialMenuItem.font = UIFont.systemFont(ofSize: 14)
            initialMenuItem.backgroundColor = Bar_Color
        }else {
            initialMenuItem.backgroundColor = RGB(254, 254, 254)
            //                .white.withAlphaComponent(0.95)
        }
        return initialMenuItem
    }
    
}

extension DevicesViewController: FirmwareDistributeUpdateStateViewDelegate {
    
    /// 点击GOT IT回调
    func firmwareUpdateCancelAction(_ view: FirmwareDistributeUpdateStateView) {
        stopDistributionStateTimer()
    }
    
    /// 点击详情回调
    func firmwareUpdateDetailsAction(_ view: FirmwareDistributeUpdateStateView) {
        stopDistributionStateTimer()
        pushToMeshOTADetails()
    }
    
}
