//
//  EnOceanProxyViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/13.
//

import UIKit
import NordicSigMeshSDK

class EnOceanProxyViewController: UIViewController {

    let group: Group
    let groupSwitch: GroupSwitch
    /// 支持做为按键面板代理的节点
    private var groupProxys: [Node] = []
    /// 是否展开
//    private var showProxys: Bool = true
    /// 展开的组
    private var showSections: [Int] = []
    
    /// 选择的代理
    private var selectProxy: Node?
    /// 设置的虚拟开关
    private var setSwitch: GroupSwitch!
    /// 扫码页面
    private var scanCodeVc: LBXScanViewController?
    /// 扫码到的信息
    private var enOceanData: EnOceanQRCodeData?
    /// 按键数据更新回调
    var switchDataUpdateCallback: ((GroupSwitch)->Void)?
    /// 未加入到组的设备
    private var notInGroupProxys: [Node] = []
    
    private lazy var tableView: UITableView = {
        let tableV = UITableView(frame: CGRectMake(0, view.safeAreaInsets.top, self.view.width, self.view.height - view.safeAreaInsets.top))
        tableV.backgroundColor = Background_Color
        tableV.separatorStyle = .none
        tableV.rowHeight = SCRYFrom(44)
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.register(GroupSwitchEnOceanProxyHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableV.dataSource = self
        tableV.delegate = self
        return tableV
    }()
    
    /// 加载动画
    private lazy var loadingView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "loading_big"))
        imageView.sizeToFit()
        imageView.frame = CGRect(x: (view.width - imageView.width) * 0.5, y: (view.height - imageView.height) * 0.5 - view.safeAreaInsets.top - 44, width: imageView.width, height: imageView.height)
        imageView.isHidden = true
        return imageView
    }()
    
    init(group: Group, groupSwitch: GroupSwitch) {
        self.group = group
        self.groupSwitch = groupSwitch
        super.init(nibName: nil, bundle: nil)
        self.setSwitch = groupSwitch
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "enocean_proxy".localizedString
        view.backgroundColor = Background_Color
        
        view.addSubview(tableView)
        
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo((navigationController?.navigationBar.height ?? 0))
        }
        
        view.addSubview(loadingView)
        groupProxys = group.nodes.filter({ $0.sunricherVendorModel != nil })
        
//        notInGroupProxys = MeshNetworkManager.instance.realNodes.filter({ $0.group == nil && $0.sunricherVendorModel != nil })
        
        if groupProxys.isEmpty && notInGroupProxys.isEmpty {
            tableView.showEmptyDataView(title: "no_devices".localizedString, tipText: "group_not_proxy_message".localizedString, margin: SCRXFrom(42))
            tableView.emptyView?.backgroundColor = .clear
        }else {
            if notInGroupProxys.count > 0 {
                showSections.append(0)
            }
            if groupProxys.count > 0 {
                showSections.append(1)
            }
        }
    }
    
    /// 显示loading动画
    private func showLoadingAnimation() {
        
        tableView.isHidden = true
        loadingView.isHidden = false
        
        loadingView.layer.addRotationAnimation(duration: 1.2, repeatCount: 9999, animationKey: "loading")
    }
    /// 隐藏loading动画
    private func hideLoadingAnimation() {
        tableView.isHidden = false
        loadingView.isHidden = true
        loadingView.layer.removeAnimation(forKey: "loading")
    }

    /// 动能开关和代理绑定
    private func enOceanSwitchBind(enOceanData: EnOceanQRCodeData) {
        
        // 网络未连接
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        guard let proxyNode = self.selectProxy else { return }
        showLoadingAnimation()
        
        MeshEnOceanProxyServer.setEnOceanProxy(proxyNode: proxyNode, securityKey: enOceanData.securityKey, macAddress: enOceanData.macAddress) {[weak self] isSuccess, error in
            guard let self = self else { return }
            
            if isSuccess {
                // 清空之前绑定的代理mac信息
//                if let removeProxySwitch = self.group.info.switchs.first(where: { $0.proxyNode?.enOceanMacAddress == enOceanData.macAddress }) {
//                    
//                    removeProxySwitch.proxyNode = nil
//                    
//                    removeProxySwitch.save(meshUUID: MeshNetworkManager.instance.meshNetwork!.uuid.uuidString)
//                    self.switchDataUpdateCallback?(removeProxySwitch)
//                }
//                
//                if let lastProxyNode = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.enOceanMacAddress == enOceanData.macAddress }), lastProxyNode.primaryUnicastAddress != proxyNode.primaryUnicastAddress {
//                    
//                    lastProxyNode.enOceanMacAddress = nil
//                    lastProxyNode.saveNodeInfo(meshUUID: MeshNetworkManager.instance.meshNetwork!.uuid.uuidString)
//                    
//                    self.reloadProxyItem(proxy: lastProxyNode)
//                }
                
                self.setSwitch.proxyNodeAddress = proxyNode.primaryUnicastAddress
                self.setSwitch.save()
                self.reloadProxyItem(proxy: proxyNode)
                if self.setSwitch.enabled { // 是否启用，启用默认绑定按键
                    MeshEnOceanProxyServer.bindEnOceanSwitchKeys(proxyNode: proxyNode, group: self.group, sceneA: self.setSwitch.sceneA, sceneB: self.setSwitch.sceneB) {[weak self] _, _ in
                        guard let self = self else { return }
                        self.hideLoadingAnimation()
                        self.switchDataUpdateCallback?(self.setSwitch)
                        // 通知space数据修改
                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                    }
                }else {
                    self.hideLoadingAnimation()
                    self.switchDataUpdateCallback?(self.setSwitch)
                    // 通知space数据修改
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                }
                
            }else if let error = error {
                self.hideLoadingAnimation()
                switch error {
                case .connectTimeout:
                    self.showSetProxyFailed(proxy: proxyNode, failedMessage: "connection_failure".localizedString)
                default:
                    self.showSetProxyFailed(proxy: proxyNode, failedMessage: "enocean_proxy_set_failed".localizedString)
                }
            }
        }
        
    }
    
    /// 动能开关和代理解绑
    private func enOceanSwitchUnBind(proxyNode: Node) {
         
        // 网络未连接
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        showLoadingAnimation()
        
        MeshEnOceanProxyServer.deleteEnOceanProxy(proxyNode: proxyNode, group: group) {[weak self] isDeleteSuccess, deleteError in
            guard let self = self else { return }
            self.hideLoadingAnimation()
            if isDeleteSuccess { // 删除代理成功
                
//                    proxyNode.saveNodeInfo(meshUUID: uuid, networkKey: networkKey)
                    
                if let removeProxySwitch = self.group.info.switchs.first(where: { $0.proxyNode?.primaryUnicastAddress == proxyNode.primaryUnicastAddress }) {
                    
                    removeProxySwitch.proxyNodeAddress = nil
                    removeProxySwitch.save()
                    self.switchDataUpdateCallback?(removeProxySwitch)
                }
                
                self.reloadProxyItem(proxy: proxyNode)
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }else {
                switch deleteError {
                case .connectTimeout:
                    self.showUnBindProxyFailed(proxy: proxyNode, failedMessage: "connection_failure".localizedString)
                default:
                    self.showUnBindProxyFailed(proxy: proxyNode, failedMessage: "switch_disable_failure".localizedString)
                }
            }
        }
    }
    
    /// 刷新代理UI
    private func reloadProxyItem(proxy: Node) {
        
        var indexPath: IndexPath?
        
        if let index = notInGroupProxys.firstIndex(of: proxy) {
            indexPath = IndexPath(row: index, section: 0)
        }else if let index = groupProxys.firstIndex(of: proxy) {
            indexPath = IndexPath(row: index, section: 1)
        }
        
        if let reloadIndexPath = indexPath {
            tableView.reloadRows(at: [reloadIndexPath], with: .none)
        }else {
            tableView.reloadData()
        }
    }
    
    /// 扫码
    private func scanQRCode() {
        
        let switchProxys = MeshNetworkManager.instance.realNodes.filter({ $0.enOceanMacAddress != nil })
        guard switchProxys.count < 16 else {
            XWHUDManager.showTipHUD("network_switch_proxy_exceed".localizedString, isLineFeed: true)
            return
        }
        
        LBXPermissions.authorizeCameraWith {[weak self] authorize in
            guard let self = self else { return }
            
            guard authorize else {
                let alertVc = UIAlertController(title: "camera_requires_alert_title".localizedString, message: "camera_requires_alert_message".localizedString, preferredStyle: .alert)
                alertVc.addAction(UIAlertAction(title: "alert_item_cancel".localizedString, style: .default))
                alertVc.addAction(UIAlertAction(title: "Settings".localizedString, style: .cancel, handler: { _ in
                    LBXPermissions.jumpToSystemPrivacySetting()
                }))
                present(alertVc, animated: true)
                return
            }
            
            var style = LBXScanViewStyle()
            style.xScanRetangleOffset = 30
            //            style.whRatio = 0.8
            //            style.isNeedShowScanBorder = false
            style.anmiationStyle = LBXScanViewAnimationStyle.None
            style.animationImage = UIImage(named: "scan_animation_line")
            style.photoframeAngleStyle = .Outer
            style.colorAngle = .white
            style.photoframeLineW = 3
            style.centerUpOffset = SCRYFit(80)
            
            let vc = LBXScanViewController()
            vc.scanStyle = style
            vc.message = "scan_panel_qr_code_message".localizedString
            vc.isOpenInterestRect = true
            vc.scanResultDelegate = self
            vc.scanFineshedExit = false
            navigationController?.pushViewController(vc, animated: true)

            scanCodeVc = vc
        }
    }
    
    /// 提示扫码失败
    private func showQRCodeFailed(_ message: String) {
        SRAlertView(message: message, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            self?.scanCodeVc?.startScan()
        })]).show()
    }
    
    /// 提示设置代理失败
    private func showSetProxyFailed(proxy: Node, failedMessage: String) {
        
        SRAlertView(message: failedMessage, actions: [.cancelAction, SRAlertAction(title: "RETRY", actionHandler: {[weak self] _ in
            if let data = self?.enOceanData {
                self?.enOceanSwitchBind(enOceanData: data)
            }
        })]).show()
    }
    
    /// 提示解绑代理失败
    private func showUnBindProxyFailed(proxy: Node, failedMessage: String) {
        
        SRAlertView(message: failedMessage, actions: [.cancelAction, SRAlertAction(title: "RETRY", actionHandler: {[weak self] _ in
            self?.enOceanSwitchUnBind(proxyNode: proxy)
        })]).show()
    }

    
}

extension EnOceanProxyViewController: LBXScanViewControllerDelegate {
    
    func scanFinished(scanResult: LBXScanResult, error: String?) {
        
        if let content = scanResult.strScanned, let data = EnOceanQRCodeData(qrcode: content) {
            self.enOceanData = data
          
            if let node = MeshNetworkManager.instance.realNodes.first(where: { $0.enOceanMacAddress == data.macAddress }) {
                // 提示是否动能开关已被网络内设备绑定
                var message = String(format: "switch_proxy_exist".localizedString, node.name ?? "")
                if group.nodes.contains(node) {   // 组内设备存在同一个动能开关
                    message = "enocean_proxies_overrun".localizedString
                }
                SRAlertView(message: message, actions: [.init(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    self?.scanCodeVc?.startScan()
                })]).show()
                
            }else if group.info.switchs.contains(where: { $0.proxyNode?.enOceanMacAddress != nil && $0.proxyNode?.enOceanMacAddress != data.macAddress }) && groupSwitch.proxyNode != nil { // 本地判断是否组内是否有动能开关绑定，并且该虚拟开关绑定了代理
                // 提示是否需要创建
                SRAlertView(message: "enocean_proxies_exist".localizedString, actions: [.init(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                    self?.scanCodeVc?.startScan()
                }), .init(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    guard let self = self else { return }
                    self.scanCodeVc = nil
                    self.navigationController?.popViewController(animated: true)
                    // 生成一个新的虚拟开关给
                    self.setSwitch = self.group.addGroupSwitch()
                    self.setSwitch.sceneANumber = self.groupSwitch.sceneA?.number
                    self.setSwitch.sceneBNumber = self.groupSwitch.sceneB?.number
                    self.enOceanSwitchBind(enOceanData: data)
                    
                    // 通知space数据修改
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
                    
                })]).show()
                
            }else { // 开始绑定
                self.navigationController?.popViewController(animated: true)
                self.scanCodeVc = nil
                self.enOceanSwitchBind(enOceanData: data)
            }
            
        }else {
            showQRCodeFailed("unknown_qr_code".localizedString)
        }
        
    }
}

extension EnOceanProxyViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if showSections.contains(section) {
            switch section {
            case 0:
                return notInGroupProxys.count
            case 1:
                return groupProxys.count
            default:
                break
            }
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        var node: Node!
        if indexPath.section == 0 {
            node = notInGroupProxys[indexPath.row]
        }else {
            node = groupProxys[indexPath.row]
        }
        cell.cellStyle = .switch
        cell.iconImageView.isHidden = false
        cell.iconImageView.image = UIImage(named: "device_light")
        cell.titleX = SCRXFrom(54)
        cell.titleLabel.text = node.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        if let macAddress = node.enOceanMacAddress {
            cell.contentLabel.text = "ID:\(macAddress)"
            cell.enabledSwitch.isOn = true
        }else {
            cell.contentLabel.text = nil
            cell.enabledSwitch.isOn = false
        }
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(13), weight: .light)
        cell.contentLabel.isHidden = false
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.contentHorizontalPriority = .required
        cell.selectionStyle = .none
        cell.iconImageClickCallback = {
            MeshAPI.identify(address: node.primaryUnicastAddress)
        }
        cell.switchActionCallback = {[weak self] isOn in
            // 网络未连接
            guard MeshLibManager.manager.isMeshNetworkConnected else {
                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                return
            }
            guard let self = self else { return }
            self.setSwitch = self.groupSwitch
            if isOn {
                self.selectProxy = node
                self.scanQRCode()
            }else { // 关闭代理设置
                self.enOceanSwitchUnBind(proxyNode: node)
            }
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        switch section {
        case 0:
            if notInGroupProxys.isEmpty {
                return nil
            }
        case 1:
            if groupProxys.isEmpty {
                return nil
            }
        default:
            break
        }
        
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupSwitchEnOceanProxyHeaderView
        if section == 0 {
            headerView.titleLabel.text = "not_in_groups".localizedString
        }else {
            headerView.titleLabel.text = group.name
        }
        headerView.contentLabel.text = nil
        headerView.isShow = showSections.contains(section)
        headerView.viewActionCallback = {[weak self] isShow in
            if isShow {
                self?.showSections.append(section)
            }else {
                self?.showSections.removeAll(where: { section == $0 })
            }
            tableView.reloadSections(IndexSet(integer: section), with: .automatic)
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
//        if supportProxys.isEmpty {
//            return 0
//        }
        switch section {
        case 0:
            if notInGroupProxys.isEmpty {
                return 0
            }
        case 1:
            if groupProxys.isEmpty {
                return 0
            }
        default:
            break
        }
        
        return SCRYFrom(44)
    }
    
}
