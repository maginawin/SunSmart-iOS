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
    let menuTitles: [String] = ["lights".localizedString, "switches".localizedString, "sensors".localizedString, "gateway".localizedString]
    
    let space: SpaceData
    
    
    /// 使用过的引导内容索引
    private var useGuidanceMessageIndexs: [Int] = []
    /// 引导内容轮播定时器
    private var guidanceTimer: Timer?
    /// 连接loading弹窗
    private weak var connectLoadingHUD: WYProgressHUD?
    /// 是否首次连接
    private var firstConnectionNetwork: Bool = true
    
//    private var meunView: WMMenuView!
    
 
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
        
//        self.menuViewStyle = .flood
        self.menuItemCornerRadius = SCRYFrom(16)
//        self.progressViewIsNaughty = false
        self.menuItemBackgroundColor = .clear
//        self.scrollEnable = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = Background_Color
        
//        view.layoutIfNeeded()
        
        MeshLibManager.manager.addObserver(self, forKeyPath: "isMeshNetworkConnected", context: nil)
        
        // 未连接上mesh网络
        if !MeshNetworkManager.instance.realNodes.isEmpty && !MeshLibManager.manager.isMeshNetworkConnected && (MeshLibManager.manager.bluetoothState == .poweredOn || MeshLibManager.manager.bluetoothState == .unknown) {
//            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 10)
            // loading
            XWHUDManager.showGifImagesHUD(inView: "XWHUDManager_loading", message: getNextGuidanceMessage() ?? "", timer: 10)
            self.perform(#selector(self.guidanceTimeout), with: nil, afterDelay: 10)
            if let hud = XWHUDManager.currentHUD() {
                hud.bezelView.layer.cornerRadius = 20
                hud.minSize = CGSizeMake(SCREEN_WIDTH - 72, 185)
                self.connectLoadingHUD = hud
            }
            startGuidanceTimer()
            // 获取设备信号
            MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 3, result: nil)
        }else {
//            XWHUDManager.hideInView()
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
        
        stopGuidanceTimer()
    }
    
    deinit {
        MeshLibManager.manager.removeObserver(self, forKeyPath: "isMeshNetworkConnected")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "isMeshNetworkConnected" { // 网络连接/断开连接回调
            if MeshLibManager.manager.isMeshNetworkConnected {
//                DispatchQueue.global().async {
//                    if let node = MeshNetworkManager.instance.realNodes.first(where: { $0.isProxy }) ?? MeshNetworkManager.instance.realNodes.first {
//                        MeshAPI.sendMessage(message: ConfigRelaySet(count: 0, steps: 1), address: node.primaryUnicastAddress)
//                        sleep(1)
//                    }
//                    DispatchQueue.main.async {
//                        self.getNodesState()
                   
                //                    }
                // 首次连接上mesh网络
                if firstConnectionNetwork {
                    firstConnectionNetwork = false
                    
                    if let view = self.wm_pageController?.view {
                        XWHUDManager.hideInView(with: view)
                    }else {
                        XWHUDManager.hide()
                    }
                    stopGuidanceTimer()
                    
                    // 判断是否需要申请地址
                    if space.applyDeviceAddressCount != nil {
                        applyDeviceAddressAlert()
                    }
                    
                    // 同步时间
                    if MeshNetworkManager.instance.realNodes.contains(where: { $0.scheduleIds.count > 0 }) && MeshNetworkManager.instance.schedules.count > 0 {
                        //                if space.needSyncDate {
                        // 延迟3s发送广播节点同步时间消息，避免与获取设备状态冲突
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {[weak self] in
                            self?.syncTimeNodes()
                        }
                    }
                }
//                }
            }
        }
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
        guard let applyAddressCount = space.applyDeviceAddressCount else { return }
        
        self.space.applyDeviceAddressCount = nil
        self.space.save()
        
        SRAlertView(title: "notification".localizedString, message: "device_address_apply_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            // 申请地址
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            NetworkRequest.shared.request(.applyAddress(siteId: self.space.siteId, type: .device, number: applyAddressCount)) {[weak self] result in
                XWHUDManager.hide()
                guard let self = self else { return }
                switch result {
                case .success(let repsonsed):
                    // 新增地址
                    if let site = SiteData.load(siteId: self.space.siteId), let provisionerData = JSON(repsonsed)["data"]["provisioner"].dictionaryObject {
                        site.setProvisioner(provisionerData: provisionerData)
//                        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site), level: .promptly)
                    }else {
                        XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                    }
                case .failure(let error):
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
            }
            
        })]).show()
    }
    
    
    
    func addAction(point: CGPoint) {
        let items: [MenuPopView.MenuItem] = [
            .init(icon: UIImage(named: "menu_light"), title: "light".localizedString, tapItemBack: {[weak self] _ in
                guard let self = self else { return }
                self.deviceAdd()
            }),
            .init(icon: UIImage(named: "menu_switch"), title: "switch".localizedString, tapItemBack: { _ in
                self.switchAdd()
            })
        ]
        MenuPopView.show(items: items, anchorPoint: point, direction: .up)
    }
    
//    /// 获取节点状态
//    @objc private func getNodesState() {
//        guard MeshLibManager.manager.isMeshNetworkConnected else {
//            return
//        }
//        if let view = self.wm_pageController?.view {
//            XWHUDManager.hideInView(with: view)
//        }else {
//            XWHUDManager.hide()
//        }
//        stopGuidanceTimer()
//
//        MeshAPI.sendMessage(message: LightLightnessGet(), address: .allNodes)
//        
//        if devices.contains(where: { $0.ctlModel != nil }) {
//            MeshAPI.sendMessage(message: LightCTLGet(), address: .allNodes)
//        }
//        
////        MeshAPI.sendMessage(message: LightCTLTemperatureRangeGet(), address: .allNodes)
//        
//        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 3, result: nil)
////        if refreshControl.isRefreshing {
////            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {[weak self] in
////                guard let self = self else { return }
////                self.refreshControl.endRefreshing()
////            }
////        }
////        }
//    }
    
    /// 节点同步时间
    private func syncTimeNodes() {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
        MeshAPI.sendMessage(message: Node.setLocalTimeMessage(), address: .allNodes)
        space.lastSyncDateTimestamp = CLongLong(Date().timeIntervalSince1970)
        space.save()
    }
    
    /// 修复设备
    func repairNodes(nodes: [Node], complete: ((_ successList: [Node], _ failedList: [Node])->Void)?) {
        if nodes.isEmpty {
            complete?([], [])
            return
        }
        // 是否连接网络
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_repair_offline".localizedString, isLineFeed: true)
            complete?([], [])
            return
        }
        // 多设备配置
        if nodes.count > 1 {
            let alertView =  SRAlertView(title: "repairing".localizedString, titleFont: FONTS(SCRYFrom(15)), message: "0/\(nodes.count)", messageColor: TextBlack_Color, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "loading_big"), loadingState: true, btnText: "STOP".localizedString, btnTextColor: .white, btnTextFont: Font_Medium_Size(SCRYFrom(15))) {[weak self] in
                SRAlertView.hide()
                MeshAPI.stopKeyBind(keyBindFinish: { (successNodes, failedNodes) in
                    complete?(successNodes, failedNodes)
                })
//                self?.updateUI()
//                self?.getNodesState()
            }
            alertView.show()
            
            MeshAPI.startKeyBind(nodes: nodes, startKeyBind: { node in
                let index = (nodes.firstIndex(of: node) ?? 0) + 1
                alertView.messageLabel.text = "\(index)/\(nodes.count)"
            }, keyBindSuccess: nil, keyBindFail: nil) { [weak self] successList, failList in
                
                SRAlertView.hide()
                guard let self = self else { return }
//                successList.forEach({
//                    $0.saveNodeInfo(meshUUID: self.space.meshUUID, networkKey: self.space.meshNetworkKey)
//                })
                if failList.isEmpty { // 全部修复成功
                    if MeshLibManager.manager.bluetoothState == .poweredOn {
                        XWHUDManager.showSuccessTipHUD("complete!".localizedString)
                    }
//                    self.getNodesState()
                }else { // 全部/部分修复失败
                    self.repairFailed(nodes: failList)
                }
                complete?(successList, failList)
//                self.updateUI()
                
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }
            
        }else { // 单设备配置
            XWHUDManager.showCustomHUD(withMessage: "repairing".localizedString, isWindow: true)

            MeshAPI.startKeyBind(node: nodes.first!, startKeyBind: nil) {[weak self] node in
                XWHUDManager.hide()
                if MeshLibManager.manager.bluetoothState == .poweredOn {
                    XWHUDManager.showSuccessTipHUD("complete!".localizedString)
                }
                guard let self = self else { return }
//                node.saveNodeInfo(meshUUID: self.space.meshUUID, networkKey: self.space.meshNetworkKey)
//                self.updateUI()
                complete?(nodes, [])
                
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//                MeshAPI.getNodeCTLState(address: node.primaryUnicastAddress)
            } keyBindFail: {[weak self] _ in
                XWHUDManager.hide()
//                self?.updateUI()
                complete?([], nodes)
                self?.repairFailed(nodes: nodes)
                
                // 通知space数据修改
//                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }
        }
        
    }
    
    /// 修复失败
    private func repairFailed(nodes: [Node]) {
        
        let alertView = SRAlertView(message: "repair_failed_message".localizedString, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "alert_failed"), actions: [.cancelAction, SRAlertAction(title: "repair".localizedString, style: .default, actionHandler: {[weak self] _ in
//            self?.repairNodes(nodes: nodes)
        })])
        alertView.stateImageView.snp.remakeConstraints { make in
            make.top.equalTo(SCRYFrom(24))
            make.centerX.equalToSuperview()
        }
        alertView.messageLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(27))
            make.right.equalTo(SCRXFrom(-27))
            make.top.equalTo(alertView.stateImageView.snp.bottom).offset(SCRYFrom(16))
        }
        alertView.hLineView.snp.remakeConstraints { make in
            make.left.right.equalTo(0)
            make.height.equalTo(0.5)
            make.top.equalTo(alertView.messageLabel.snp.bottom).offset(SCRYFrom(16))
        }
        alertView.show()
    }
    
   
    /// 添加设备
    private func deviceAdd() {
        
        guard MeshNetworkManager.instance.realNodes.count < 100 else {
            return
        }
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
        present(NavigationViewController(rootViewController: vc), animated: true)
        
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
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
            let vc = DeviceLightsViewController(space: space)
            return vc
        case 1:
            let vc = DeviceSwitchesViewController(space: space)
            return vc
        case 2:
            let vc = DeviceSensorsViewController(space: space)
            return vc
        case 3:
            let vc = GatewaysViewController(space: space)
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
        return CGRect(x: 0, y: SCRYFrom(10), width: view.width, height: SCRYFrom(32))
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
        return SCRXFrom(80)
    }
    
    override func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
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
        lastItem?.layer.borderColor = RGB(220, 220, 220).cgColor
        lastItem?.layer.borderWidth = 0.5
//        self.selectIndex = Int32(index)
        
        super.menuView(menu, didSelectedIndex: index, currentIndex: currentIndex)
    }
    
    override func menuView(_ menu: WMMenuView!, initialMenuItem: WMMenuItem!, at index: Int) -> WMMenuItem! {
        
        if index == 0 {
            initialMenuItem.layer.borderWidth = 0
            initialMenuItem.font = UIFont.systemFont(ofSize: 14)
            initialMenuItem.backgroundColor = Bar_Color
        }else {
            initialMenuItem.layer.borderColor = RGB(220, 220, 220).cgColor
            initialMenuItem.layer.borderWidth = 0.5
            initialMenuItem.backgroundColor = RGB(254, 254, 254)
//                .white.withAlphaComponent(0.95)
        }
        return initialMenuItem
    }
    
}
