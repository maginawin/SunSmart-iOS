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
    /// 之前的代理设备地址（进入页面设置之前）
    private var lastProxyAddress: Address?
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
    /// 所有开关数据
    var switchs: [DeviceSwitchData] = []
    
    private var enOceanMacMap: [Address : String] = [:]
    
    /// 是否可编辑
    var editable: Bool = true
    
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
        
        if switchs.isEmpty {
            switchs = MeshNetworkManager.instance.switchs
        }
        
        
        view.addSubview(tableView)
        
        tableView.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
        view.addSubview(loadingView)
        
//        notInGroupProxys = MeshNetworkManager.instance.realNodes.filter({ $0.group == nil && $0.sunricherVendorModel != nil })
        
        showSections = switchData.bindGroups.enumerated().map({ $0.offset })
        lastProxyAddress = switchData.proxyNodeAddress
        
        if switchData.bindGroups.isEmpty {
            tableView.showEmptyDataView(title: "no_devices".localizedString, tipText: "group_not_proxy_message".localizedString, margin: SCRXFrom(42))
            tableView.emptyView?.backgroundColor = .clear
        }
        
        switchData.bindGroups.forEach { group in
            group.nodes.forEach { node in
                // 其他动能开关绑定的代理和动能开关mac
                if let switchData = switchs.first(where: { $0.proxyNodeAddress == node.primaryUnicastAddress && $0.proxyNode?.enOceanMacAddress?.count ?? 0 > 0 }), switchData.id != self.switchData.id, let enOceanMacAddress = switchData.proxyNode?.enOceanMacAddress {
                    self.enOceanMacMap.updateValue(enOceanMacAddress, forKey: node.primaryUnicastAddress)
                }
//                if let mac = node.enOceanMacAddress, MeshNetworkManager.instance.switchs.contains(where: { $0.enOceanMacAddress == mac && ($0.id == switchData.id || $0.deleteProxyNodeAddress != node.primaryUnicastAddress) }) {
//                    self.enOceanMacMap.updateValue(mac, forKey: node.primaryUnicastAddress)
//                }
            }
        }
        // 当前动能开关绑定的代理和动能开关mac
        if let proxyAddress = switchData.proxyNodeAddress, let mac = switchData.enOceanMacAddress {
            self.enOceanMacMap.updateValue(mac, forKey: proxyAddress)
        }

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
        
        let switchProxys = MeshNetworkManager.instance.realNodes.filter({ $0.enOceanMacAddress?.count ?? 0 > 0 })
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

    
}

extension EnOceanProxyViewController: LBXScanViewControllerDelegate {
    
    func scanFinished(scanResult: LBXScanResult, error: String?) {
        
        if let content = scanResult.strScanned, let data = EnOceanQRCodeData(qrcode: content) {
            self.enOceanData = data
          
//            if let node = MeshNetworkManager.instance.realNodes.first(where: { $0.enOceanMacAddress == data.macAddress }), MeshNetworkManager.instance.switchs.contains(where: { $0.enOceanMacAddress == data.macAddress }) {
            // 获取已绑定的动能开关的节点
            var bindNode: Node?
            if let nodeData = enOceanMacMap.first(where: { $0.value == data.macAddress }), let node = MeshNetworkManager.instance.realNodes.first(where: { $0.primaryUnicastAddress == nodeData.key }) {
                bindNode = node
            }else if let node = MeshNetworkManager.instance.realNodes.first(where: { $0.enOceanMacAddress == data.macAddress && $0.primaryUnicastAddress != lastProxyAddress }) {
                bindNode = node
            }
            
            if let node = bindNode {
                // 提示是否动能开关已被网络内设备绑定
                let message = String(format: "switch_proxy_exist".localizedString, node.name ?? "")
//                if group.nodes.contains(node) {   // 组内设备存在同一个动能开关
//                    message = "enocean_proxies_overrun".localizedString
//                }
                SRAlertView(message: message, actions: [.init(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    self?.scanCodeVc?.startScan()
                })]).show()
                
            }else if switchData.proxyNode?.enOceanMacAddress?.count ?? 0 > 0 && switchData.proxyNode?.enOceanMacAddress != data.macAddress {
                // 如果当前虚拟动能开关已绑定了真实动能开关，并且扫描了一个新的动能开关则新建一个虚拟动能开关关联这个真实动能开关
                
                // 本地判断是否组内是否有动能开关绑定，并且该虚拟开关绑定了代理
                // group.info.switchs.contains(where: { $0.proxyNode?.enOceanMacAddress != nil && $0.proxyNode?.enOceanMacAddress != data.macAddress }) && groupSwitch.proxyNode != nil
                // 判断是否已保存，如果动能开关数据已保存，则提示创建一个新的动能开关，未保存提示先保存数据
                guard self.switchDataSaved?() ?? false else {
                    SRAlertView(title: "notification".localizedString, message: "switch_copy_failed_message".localizedString, actions: [.init(title: "ok".localizedString, actionHandler: {[weak self] _ in
//                        self?.scanCodeVc?.startScan()
                        self?.scanCodeVc = nil
                        self?.navigationController?.popViewController(animated: true)
                    })]).show()
                    return
                }
              
                // 提示是否需要创建
                SRAlertView(message: "enocean_proxies_exist".localizedString, actions: [.init(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                    self?.scanCodeVc?.startScan()
                }), .init(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    guard let self = self else { return }
                    self.scanCodeVc = nil
                    self.navigationController?.popViewController(animated: false)
                    // 生成一个新的虚拟开关
                    guard self.switchs.count < 16 else {
                        SRAlertView(title: "notification".localizedString, message: "switchs_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
                        return
                    }
                    let newSwitch = DeviceSwitchData.default()
                    newSwitch.enabled = switchData.enabled
                    newSwitch.bindGroupAddresses = switchData.bindGroupAddresses
                    newSwitch.sceneANumber = switchData.sceneANumber
                    newSwitch.sceneBNumber = switchData.sceneBNumber
                    newSwitch.sceneCNumber = switchData.sceneCNumber
                    newSwitch.sceneDNumber = switchData.sceneDNumber
                    newSwitch.panelType = switchData.panelType
                    newSwitch.enOceanMacAddress = data.macAddress
                    newSwitch.enOceanSecurityKey = data.securityKey
                    newSwitch.proxyNodeAddress = selectProxy?.primaryUnicastAddress
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
        cell.iconImageView.image = UIImage(named: node.iconName)
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
        
        cell.enabledSwitch.isEnabled = editable && (macAddress == nil || macAddress == switchData.enOceanMacAddress)
//       && node.supportEnOceanProxy  && !MeshNetworkManager.instance.switchs.contains(where: { $0.id != switchData.id && $0.deleteProxyNodeAddress == node.primaryUnicastAddress })
        
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(13), weight: .light)
        cell.contentLabel.isHidden = false
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.contentHorizontalPriority = .required
        cell.selectionStyle = .none
        cell.iconImageClickCallback = {
            MeshAPI.identify(address: node.primaryUnicastAddress)
        }
        cell.switchActionCallback = {[weak self] isOn in
            guard let self = self else { // , node.enOceanMacAddress == nil || macAddress == self.switchData.enOceanMacAddress
                return
            }
            guard node.isKeybindComplete else {
                XWHUDManager.showTipHUD("switch_proxy_repair_message".localizedString, isLineFeed: true, afterDelay: 2)
                return
            }
            guard node.supportEnOceanProxy else {
                XWHUDManager.showTipHUD("switch_proxy_notsupport_message".localizedString, isLineFeed: true, afterDelay: 2)
                return
            }
            // 判断不是待删除代理设备
            guard !self.switchs.contains(where: { $0.id != self.switchData.id && $0.deleteProxyNodeAddress == node.primaryUnicastAddress }) else {
                XWHUDManager.showTipHUD("switch_proxy_notcleared_message".localizedString, isLineFeed: true, afterDelay: 2)
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
