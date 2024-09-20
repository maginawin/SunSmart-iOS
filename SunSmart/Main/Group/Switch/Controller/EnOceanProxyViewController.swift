//
//  EnOceanProxyViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/13.
//

import UIKit
import NordicSigMeshSDK

class EnOceanProxyViewController: UIViewController {

//    let linkGroup: Group?
    let switchData: DeviceSwitchData
//    let groupSwitch: GroupSwitch
    /// 支持做为按键面板代理的节点
//    private var supportProxys: [Node] = []
    /// 是否展开
//    private var showProxys: Bool = true
    /// 展开的组
    private var showSections: [Int] = []
    /// 支持的组
//    private var supportGroups: [Group] = []
    
    /// 选择的代理
    private var selectProxy: Node?
    /// 设置的虚拟开关
//    private var setSwitch: DeviceSwitchData!
    /// 扫码页面
    private var scanCodeVc: LBXScanViewController?
    /// 扫码到的信息
    private var enOceanData: EnOceanQRCodeData?
    /// 开关数据更新回调
    var switchDataUpdateCallback: ((DeviceSwitchData)->Void)?
    /// 创建新的动能开关回调
    var switchCreateCallback: ((DeviceSwitchData)->Void)?
    /// 是否已保存动能开关数据  返回bool
    var switchDataSaved: (()->Bool)?
    
    private var enOceanMacMap: [Address : String] = [:]
    
    private lazy var tableView: UITableView = {
        let tableV = UITableView(frame: CGRectMake(0, view.safeAreaInsets.top, self.view.width, self.view.height - view.safeAreaInsets.top))
        tableV.backgroundColor = Background_Color
        tableV.separatorStyle = .none
        tableV.rowHeight = SCRYFrom(44)
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "emptyCell")
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
    
    init(switchData: DeviceSwitchData) {
        self.switchData = switchData
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "\(switchData.name) \("proxy".localizedString)"
        view.backgroundColor = Background_Color
        
        view.addSubview(tableView)
        
        tableView.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo((navigationController?.navigationBar.height ?? 0))
        }
        
        view.addSubview(loadingView)
        
//        notInGroupProxys = MeshNetworkManager.instance.realNodes.filter({ $0.group == nil && $0.sunricherVendorModel != nil })
        
        
        if switchData.bindGroups.isEmpty {
            tableView.showEmptyDataView(title: "no_devices".localizedString, tipText: "group_not_proxy_message".localizedString, margin: SCRXFrom(42))
            tableView.emptyView?.backgroundColor = .clear
        }
        
        switchData.bindGroups.forEach { group in
            group.nodes.forEach { node in
                if let mac = node.enOceanMacAddress, MeshNetworkManager.instance.switchs.contains(where: { $0.enOceanMacAddress == mac && ($0.id == switchData.id || $0.deleteProxyNodeAddress != node.primaryUnicastAddress) }) {
                    self.enOceanMacMap.updateValue(mac, forKey: node.primaryUnicastAddress)
                }
            }
        }
//
//        if groupProxys.isEmpty && notInGroupProxys.isEmpty {
//            tableView.showEmptyDataView(title: "no_devices".localizedString, tipText: "group_not_proxy_message".localizedString, margin: SCRXFrom(42))
//            tableView.emptyView?.backgroundColor = .clear
//        }else {
//            if notInGroupProxys.count > 0 {
//                showSections.append(0)
//            }
//            if groupProxys.count > 0 {
//                showSections.append(1)
//            }
//        }
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
                
                // 如果开关未生成对应发布订阅组(虚拟不展示给用户看)，则自动生成一个
                var linkGroup = switchData.linkGroup
                if linkGroup == nil {
                    linkGroup = (try? MeshAPI.createGroup(name: self.switchData.name + "-Group", isVirtual: true))
                    switchData.linkGroupAddress = linkGroup?.address.address
                }
                guard let group = linkGroup else {
                    XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
                    return
                }
                
                self.switchData.proxyNodeAddress = proxyNode.primaryUnicastAddress
                self.switchData.save()
                self.reloadProxyItem(proxy: proxyNode)
                if self.switchData.enabled { // 是否启用，启用默认绑定按键
                    MeshEnOceanProxyServer.bindEnOceanSwitchKeys(proxyNode: proxyNode, group: group, sceneA: self.switchData.sceneA, sceneB: self.switchData.sceneB) {[weak self] _, _ in
                        guard let self = self else { return }
                        self.hideLoadingAnimation()
                        self.switchDataUpdateCallback?(self.switchData)
                        // 通知space数据修改
                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                    }
                }else {
                    self.hideLoadingAnimation()
                    self.switchDataUpdateCallback?(self.switchData)
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
        
        MeshEnOceanProxyServer.deleteEnOceanProxy(proxyNode: proxyNode, group: switchData.linkGroup) {[weak self] isDeleteSuccess, deleteError in
            guard let self = self else { return }
            self.hideLoadingAnimation()
            if isDeleteSuccess { // 删除代理成功
                
//                    proxyNode.saveNodeInfo(meshUUID: uuid, networkKey: networkKey)
                    
//                if let removeProxySwitch = self.group.info.switchs.first(where: { $0.proxyNode?.primaryUnicastAddress == proxyNode.primaryUnicastAddress }) {
//                    
//                    removeProxySwitch.proxyNodeAddress = nil
//                    removeProxySwitch.save()
//                    self.switchDataUpdateCallback?(removeProxySwitch)
//                }
                
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
        
        if let section = self.switchData.bindGroups.firstIndex(where: { $0.nodes.contains(proxy) }), let row = self.switchData.bindGroups[section].nodes.firstIndex(of: proxy) {
            
            tableView.reloadRows(at: [IndexPath(row: row, section: section)], with: .none)
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
          
            if let node = MeshNetworkManager.instance.realNodes.first(where: { $0.enOceanMacAddress == data.macAddress }), MeshNetworkManager.instance.switchs.contains(where: { $0.enOceanMacAddress == data.macAddress }) {
                // 提示是否动能开关已被网络内设备绑定
                let message = String(format: "switch_proxy_exist".localizedString, node.name ?? "")
//                if group.nodes.contains(node) {   // 组内设备存在同一个动能开关
//                    message = "enocean_proxies_overrun".localizedString
//                }
                SRAlertView(message: message, actions: [.init(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    self?.scanCodeVc?.startScan()
                })]).show()
                
            }else if switchData.enOceanMacAddress != nil && switchData.enOceanMacAddress != data.macAddress {
                // 如果当前虚拟动能开关已绑定了真实动能开关，并且扫描了一个新的动能开关则新建一个虚拟动能开关关联这个真实动能开关
                
                // 本地判断是否组内是否有动能开关绑定，并且该虚拟开关绑定了代理
                // group.info.switchs.contains(where: { $0.proxyNode?.enOceanMacAddress != nil && $0.proxyNode?.enOceanMacAddress != data.macAddress }) && groupSwitch.proxyNode != nil
                // 判断是否已保存，如果动能开关数据已保存，则提示创建一个新的动能开关，未保存提示先保存数据
                guard self.switchDataSaved?() ?? false else {
                    SRAlertView(title: "notification".localizedString, message: "switch_copy_failed_message".localizedString, actions: [.init(title: "ok".localizedString)]).show()
                    return
                }
              
                // 提示是否需要创建
                SRAlertView(message: "enocean_proxies_exist".localizedString, actions: [.init(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                    self?.scanCodeVc?.startScan()
                }), .init(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    guard let self = self else { return }
                    self.scanCodeVc = nil
                    self.navigationController?.popViewController(animated: true)
                    // 生成一个新的虚拟开关
                    guard let newSwitch = MeshNetworkManager.instance.createDefalutSwitch() else {
                        SRAlertView(title: "notification".localizedString, message: "switchs_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
                        return
                    }
                    
                    newSwitch.update(switchData: switchData)
                    newSwitch.unbindGroupAddresses.removeAll()
                    newSwitch.enOceanMacAddress = data.macAddress
                    newSwitch.enOceanSecurityKey = data.securityKey
                    newSwitch.save()
                    if self.switchCreateCallback != nil {
                        self.switchCreateCallback?(newSwitch)
                    }else {
                        self.navigationController?.popViewController(animated: true)
                    }
//                    self.enOceanSwitchBind(enOceanData: data)
                    // 通知space数据修改
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
                    
                })]).show()
                
            }else { // 开始绑定
                self.navigationController?.popViewController(animated: true)
                self.scanCodeVc = nil
                self.switchData.enOceanMacAddress = data.macAddress
                self.switchData.enOceanSecurityKey = data.securityKey
                if let node = self.selectProxy {
                    self.enOceanMacMap.updateValue(data.macAddress, forKey: node.primaryUnicastAddress)
                    self.switchData.proxyNodeAddress = node.primaryUnicastAddress
                    self.reloadProxyItem(proxy: node)
                }
                self.switchDataUpdateCallback?(self.switchData)
//                self.enOceanSwitchBind(enOceanData: data)
            }
            
        }else {
            showQRCodeFailed("unknown_qr_code".localizedString)
        }
        
    }
}

extension EnOceanProxyViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return switchData.bindGroups.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let group = switchData.bindGroups[section]
        if showSections.contains(section) {
            return max(group.nodes.count, 1) // 无数据时显示空数据cell
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let isLast = indexPath.section == tableView.numberOfSections - 1 && indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1
        
        let group = switchData.bindGroups[indexPath.section]
        if indexPath.row == 0 && group.nodes.isEmpty { // 没有设备
            let emptyCell = tableView.dequeueReusableCell(withIdentifier: "emptyCell", for: indexPath) as! CustomTableViewCell
            emptyCell.cellStyle = .none
            emptyCell.titleLabel.text = "no_devices".localizedString
            emptyCell.titleLabel.textColor = SubText_Color
            emptyCell.titleLabel.font = FONTS(SCRYFrom(14))
            emptyCell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
            emptyCell.configureCell(isFirst: false, isLast: isLast)
            return emptyCell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        
        let node = group.nodes[indexPath.row]
        cell.cellStyle = .switch
        cell.iconImageView.isHidden = false
        cell.iconImageView.image = UIImage(named: "device_light")
        cell.titleX = SCRXFrom(54)
        cell.titleLabel.text = node.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        
        cell.configureCell(isFirst: false, isLast: isLast)
        
        let macAddress = self.enOceanMacMap[node.primaryUnicastAddress]
//        node.enOceanMacAddress ?? (switchData.proxyNodeAddress == node.primaryUnicastAddress ? switchData.enOceanMacAddress : nil)
        
        if macAddress != nil {
            cell.contentLabel.text = "ID:\(macAddress!)"
            cell.enabledSwitch.isOn = true
        }else {
            cell.contentLabel.text = nil
            cell.enabledSwitch.isOn = false
        }
//        cell.enabledSwitch.isHidden = !node.supportEnOceanProxy
//        node.enOceanMacAddress = data.macAddress
        
        cell.enabledSwitch.isEnabled = (macAddress == nil || macAddress == switchData.enOceanMacAddress) && node.supportEnOceanProxy && !MeshNetworkManager.instance.switchs.contains(where: { $0.id != switchData.id && $0.deleteProxyNodeAddress == node.primaryUnicastAddress })
        
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(13), weight: .light)
        cell.contentLabel.isHidden = false
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.contentHorizontalPriority = .required
        cell.selectionStyle = .none
        cell.iconImageClickCallback = {
            MeshAPI.identify(address: node.primaryUnicastAddress)
        }
        cell.switchActionCallback = {[weak self] isOn in
            guard let self = self, node.enOceanMacAddress == nil || macAddress == self.switchData.enOceanMacAddress else {
                return
            }
            guard node.isKeybindComplete else {
                XWHUDManager.showTipHUD("switch_proxy_repair_message".localizedString, isLineFeed: true)
                return
            }
            guard node.supportEnOceanProxy else {
                XWHUDManager.showTipHUD("switch_proxy_notsupport_message".localizedString, isLineFeed: true)
                return
            }
            // 判断不是待删除代理设备
            guard !MeshNetworkManager.instance.switchs.contains(where: { $0.deleteProxyNodeAddress == node.primaryUnicastAddress }) else {
                XWHUDManager.showTipHUD("switch_proxy_notsupport_message".localizedString, isLineFeed: true)
                return
            }
            // 网络未连接
//            guard MeshLibManager.manager.isMeshNetworkConnected else {
//                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
//                return
//            }
//            self.setSwitch = self.switchData
            if isOn {
                self.selectProxy = node
                self.scanQRCode()
            }else { // 关闭代理设置
                self.switchData.enOceanMacAddress = nil
                self.switchData.enOceanSecurityKey = nil
                self.switchData.proxyNodeAddress = nil
                self.enOceanMacMap.removeValue(forKey: node.primaryUnicastAddress)
                tableView.reloadRows(at: [indexPath], with: .none)
                self.switchDataUpdateCallback?(self.switchData)
//                self.enOceanSwitchUnBind(proxyNode: node)
            }
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {

        
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupSwitchEnOceanProxyHeaderView
        headerView.titleLabel.text = switchData.bindGroups[section].name
        headerView.contentLabel.text = nil
        headerView.isShow = showSections.contains(section)
        let isLast = section == tableView.numberOfSections - 1 && !showSections.contains(section)
        headerView.configureCell(isFirst: section == 0, isLast: isLast)
        headerView.lineView.isHidden = isLast
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
        return SCRYFrom(44)
    }
    
}
