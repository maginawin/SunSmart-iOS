//
//  SpaceViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/26.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth

class SpaceViewController: WMPageController {

    let space: SpaceData
    /// 删除空间回调
    var deleteSpaceCallback: (()->Void)?
    
    lazy var mainMenuView: SpaceMenuView = {
        let menuView = SpaceMenuView(frame: CGRect(x: 0, y: kNavigationHeight, width: self.view.width, height: SCRYFrom(46)))
        menuView.itemDatas = SpaceMenuView.defalutItems
        menuView.isUserInteractionEnabled = false
        return menuView
    }()
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
        
        self.titles = ["main".localizedString, "group".localizedString, "scene".localizedString, "timed".localizedString, "more".localizedString]
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
        self.selectIndex = 3
        MeshLibManager.manager.setMeshNetworkConnected(meshUUID: space.meshUUID)
        if let manager = MeshLibManager.manager.meshNetworkManager {
            space.meshManager = manager
            manager.loadExtensionData()
        }
        
        super.viewDidLoad()

        title = space.name
        view.backgroundColor = Background_Color
        menuView?.backgroundColor = .white
        view.addSubview(mainMenuView)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))

        MeshLibManager.manager.addObserver(self, forKeyPath: "bluetoothState", context: nil)
        
        MeshLibManager.manager.supportModelIDs = [.genericOnOffServerModelId, .lightLightnessServerModelId, .lightCTLServerModelId, .lightCTLTemperatureServerModelId, .sceneServerModelId, .sceneSetupServerModelId]
        MeshLibManager.manager.publishModelIDs = []
        MeshLibManager.manager.groupSubscriptionModelIDs = [.genericOnOffServerModelId, .lightLightnessServerModelId, .lightCTLTemperatureServerModelId, .lightCTLServerModelId,]
        checkBluetoothState()
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
    
    func checkBluetoothState() {
        if MeshLibManager.manager.bluetoothState == .unknown {
            return
        }
        if MeshLibManager.manager.bluetoothState == .poweredOn {
            if let currentVc = UIViewController.getVisibleVc(), currentVc.isKind(of: BluetoothRequiredViewController.classForCoder()) {
//                self.presentedViewController?.dismiss(animated: true)
                navigationController?.popViewController(animated: false)
            }
        }else {
//            if self.view.window != nil {
                MenuPopView.hide()
                navigationController?.pushViewController(BluetoothRequiredViewController(), animated: false)
//            }
            
        }
    }
    
    @objc private func moreClick() {
        // mesh网络连接中
        if !MeshLibManager.manager.isMeshNetworkConnected && XWHUDManager.isVisible() {
            return
        }
        MenuPopView.show(items: [
            .init(icon: UIImage(named: "edit"), title: "edit_space".localizedString, tapItemBack: {[weak self] item in
                self?.editSpace()
            }),
            .init(icon: UIImage(named: "menu_delete"), title: "delete_space".localizedString, tapItemBack: {[weak self] item in
                self?.deleteSpace()
            }),
        ], anchorPoint: CGPoint(x: view.width - SCRXFrom(20) - 15, y: kNavigationHeight), menuWidth: SCRXFrom(154))
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
            guard let self = self else { return }
            self.space.name = name
            self.space.imageId = imageId + 1
            self.space.save()
            self.title = name
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
                    self.space.delete()
                    self.navigationController?.popViewController(animated: true)
                    self.deleteSpaceCallback?()
                }
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
            }
        })]).show()
        
    }
    
}

extension SpaceViewController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return self.titles!.count
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
        return titles![index]
    }
    
    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
        mainMenuView.selectIndex = Int(self.selectIndex)
    }
    
    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return !XWHUDManager.isVisible()
//        return index < 3
    }
    
}
