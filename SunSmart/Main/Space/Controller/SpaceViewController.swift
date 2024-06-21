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
/// 空间内数据修改通知
/// 添加设备、编辑设备、删除设备、修复设备
/// 添加组、编辑组（基本数据 、 添加/删除设备、profile、校准、动能开关）、删除组
/// 添加场景、编辑场景（基本数据、添加/删除组、修改组参数）、删除场景
/// 添加定时、编辑定时（名称、target、enable…）、删除定时
let spaceDataChangedNotificaitonName = "spaceDataChangedNotificaiton"

/// space修改数据类型
enum SpaceChangeDataType {
    /// 设备数据（包含device、group/scene等配置数据-与设备数据交互）
    case device
    /// 通用数据（group/scene等配置数据-无设备数据交互）
    case common
}

class SpaceViewController: WMPageController {

    var site: SiteData!
    let space: SpaceData
    /// 删除空间回调
    var deleteSpaceCallback: (()->Void)?
    /// 是否已加载完成网络数据
    private var loadNetworkData: Bool = false
    /// 退出页面同步space中
    private var exitSyncSpace: Bool = false
    
    lazy var mainMenuView: SpaceMenuView = {
        let menuView = SpaceMenuView(frame: CGRect(x: 0, y: kNavigationHeight, width: self.view.width, height: SCRYFrom(46)))
        menuView.itemDatas = SpaceMenuView.defalutItems
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
        self.progressWidth = SCRXFrom(64)
        self.menuItemWidth = SCRXFrom(64)
        self.menuViewContentMargin = SCRXFrom(10)
        self.itemMargin = SCRXFrom(6)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
//        self.selectIndex = 3
        
//        MeshNetworkManager.instance.meshNetwork?.applicationKeys.first.
        super.viewDidLoad()
        
        title = space.name
        view.backgroundColor = Background_Color
        menuView?.backgroundColor = .white
        self.view.addSubview(self.mainMenuView)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))

        MeshLibManager.manager.addObserver(self, forKeyPath: "bluetoothState", context: nil)
        
        MeshLibManager.manager.publishModelIDs = []// .genericOnOffServerModelId, .lightLightnessServerModelId, .lightCTLServerModelId
        MeshLibManager.manager.publishTimeModelIDs = []
        MeshLibManager.manager.publishModeloOnly = true
        MeshLibManager.manager.groupSubscriptionModelIDs = [.genericOnOffServerModelId, .lightLightnessServerModelId, .genericLevelServerModelId, .lightCTLTemperatureServerModelId, .lightCTLServerModelId, .sensorServerModelId, .lightLCServerModelId]
        checkBluetoothState()
   
        // 添加通知监听
        addNotificaiton()
        // 获取space数据
        setNetworkConnected()
//        loadSpaceReqeust()
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
        ConfigurationFlowGuidanceView.current()?.hide()
    }
    
    /// 配置引导
    private func configurationFlowGuidance() {
        
        guard !exitSyncSpace else {
            return
        }
        // 判断是否空的空间，进行引导配置流程
        if view.window != nil && space.permission != .visitor && space.isEmpty {
//            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.5) {[weak self] in
//                guard let self = self else { return }
                ConfigurationFlowGuidanceView(continueBack: {[weak self] in
                    guard let self = self else { return }
                    // 进入引导配置流程
                    self.space.isConfiguring = true
                    let vc = GroupAddViewController(space: self.space)
                    let navVc = NavigationViewController(rootViewController: vc)
                    self.present(navVc, animated: true)
                    self.selectIndex = 1
                }).show()
//            }
        }
        
    }
    
    deinit {
        if MeshLibManager.manager.meshNetworkManager?.meshNetwork?.uuid.uuidString == space.meshUUID {
            MeshLibManager.manager.meshNetworkDisconnect()
        }
        MeshLibManager.manager.removeObserver(self, forKeyPath: "bluetoothState")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
//        let newState = change![.newKey] as! CBManagerState
//        let oldState = change![NSKeyValueChangeKey.oldKey] as! CBManagerState
           
        checkBluetoothState()
    }
    
     /// 添加通知监听
    private func addNotificaiton() {
        
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
        // 空间内菜单选择修改通知
        NotificationCenter.default.addObserver(forName: .init(spaceMenuIndexChangeNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self, let selectIndex = notification.object as? Int, selectIndex >= 0 && selectIndex < SpaceMenuView.defalutItems.count else { return }
            self.selectIndex = Int32(selectIndex)
        }
        // 空间内数据更新通知
        NotificationCenter.default.addObserver(forName: .init(spaceDataChangedNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self, let type = notification.object as? SpaceChangeDataType else { return }
            self.space.lastUpdate = Int64(Date().timeIntervalSince1970)
            self.space.save()
            switch type {
            case .device:
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: self.space), level: .promptly)
            case .common:
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: self.space), level: .slow)
            }
        }
        
    }
    
    /// 获取网络数据+网络连接
    private func setNetworkConnected() {
        // 读取网络数据
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 2)
        DispatchQueue.global().async {
            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.space.meshUUID, subNetwork: self.space.meshNetworkKey)
            if let manager = MeshLibManager.manager.meshNetworkManager {
                self.space.meshManager = manager
                manager.loadExtensionData {[weak self] in
                    guard let self = self else { return }
//                    XWHUDManager.hideInView(with: self.view)
                    self.loadNetworkData = true
                    self.reloadData()
                    self.configurationFlowGuidance()
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
                    Task {
                        await self.space.update(spaceJsonData: spaceData)
                        self.title = self.space.name
                        self.space.save()
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
        NetworkRequest.shared.request(.siteDelete(siteId: self.site.id)) {[weak self] result in
            XWHUDManager.hide()
            switch result {
            case .success(_):
                // 删除本地数据
                self?.space.delete()
                self?.navigationController?.popViewController(animated: true)
                self?.deleteSpaceCallback?()
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                
            case .failure(let error): // 删除失败，无网络/space存在编辑者
                XWHUDManager.showTipHUD(error.localizedDescription, isLineFeed: true)
            }
        }
    }
    
    
    /// 更新空间缓存数据
    private func updateSpaceData() {
        var saveData = false
        let nodes = MeshNetworkManager.instance.realNodes
        let lightNodes = MeshNetworkManager.instance.lightNodes
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
        if self.space.switchesCount != MeshNetworkManager.instance.subnetworkSwitchProxys.count {
            self.space.scheheduleCount = MeshNetworkManager.instance.subnetworkSwitchProxys.count
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
        
        let alertView = SRAlertView(title: "bluetooth_required_title".localizedString, message: "bluetooth_required_message".localizedString, actions: [SRAlertAction(title: "settings".localizedString, titleColor: RGB(61, 110, 246), titleFont: FONTS(SCRYFrom(15)), closeAlert: false, actionHandler: { _ in
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
        if space.spaceOperates.contains(.exit) {
            items.append(.init(icon: UIImage(named: "menu_unbind"), title: "unbind".localizedString, tapItemBack: {[weak self] _ in
                self?.unbindSpace()
            }))
        }
        
        MenuPopView.show(items: items, anchorPoint: CGPoint(x: view.width - 18 - 15, y: kNavigationHeight), menuWidth: SCRXFrom(154))
    }
    
    /// 编辑空间
    private func editSpace() {
        
        var imageNames: [String] = []
        for id in 1...24 {
            imageNames.append("space_picture_\(id)")
        }
        let vc = InfoEditViewController(name: space.name, imageNames: imageNames, selectImageIndex: max(space.imageId - 1, 0), columnNum: 2)
        vc.nameEditChangedCallback = {[weak self] name in
            guard let self = self else { return false }
            return SpaceData.isTautonym(spaceName: name, siteId: self.space.siteId) && name != self.space.name
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return true }
            self.space.name = name
            self.space.imageId = imageId + 1
            self.space.save()
            self.title = name
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: self.space), level: .normal)
            return true
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
                    // 提交到云端需要网络才能删除
                    if self.space.uploadCloud {
                        self.deleteSpaceRequest()
                    }else { // 只存在于本地，删除数据
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
        let vc = SharingSettingViewController(type: .space(site: self.site, space: self.space))
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 解绑space
    private func unbindSpace() {
        
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
                    
                }
            default:
                break
            }
        }
    }
    
    /// 退出页面立即同步space数据
    private func promptlySyncSpace() {
        
        ConfigurationFlowGuidanceView.current()?.hide()
        
        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .promptly)
        exitSyncSpace = true
        XWHUDManager.showCustomHUD(withMessage: "syncing_data".localizedString, isWindow: true)
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
            let vc = DevicesViewController(space: space)
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
        default:
            return UIViewController()
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = kNavigationHeight + SCRYFrom(48)
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: kNavigationHeight, width: view.width, height: SCRYFrom(48))
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return ""
    }
    
    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
        mainMenuView.selectIndex = Int(self.selectIndex)
    }
    
    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return !XWHUDManager.isVisible()
//        return index < 3
    }
    
}

extension SpaceViewController: NavigationViewControllerDelegate {
    
    /// 点击返回item回调
    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController) {
        
        guard space.needUploadCloud else {
            self.navigationController?.popViewController(animated: true)
            return
        }
        promptlySyncSpace()
    }
    
    /// pop手势begin回调，返回是否可以pop
    func navigationController(_ navigationController: NavigationViewController, gestureRecognizerShould gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 无网络并且更新了数据
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
    func cloudSynchManager(_ manager: CloudSynchronizationManager, didStartSync handle: CloudSynchronizationHandle) {
        updateSyncState()
    }
    
    /// 同步数据成功回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSynchManager(_ manager: CloudSynchronizationManager, didSyncFinished handle: CloudSynchronizationHandle) {
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
    func cloudSynchManager(_ manager: CloudSynchronizationManager, didSyncFailure handle: CloudSynchronizationHandle, error: NetworkApiError) {
        updateSyncState()
        if exitSyncSpace { // 提示数据同步失败
            XWHUDManager.hide()
            showSyncSpaceFailedAlert()
        }
    }
}
