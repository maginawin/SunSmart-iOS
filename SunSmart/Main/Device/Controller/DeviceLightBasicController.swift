//
//  DeviceLightBasicController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/16.
//

import UIKit
import NordicSigMeshSDK

class DeviceLightBasicController: UIViewController {

    private var tableView: UITableView!
    private var headerView: DeviceLightHeaderView!
    
    private var offlineView: UIView!
    private var offlineImageView: UIImageView!
    private var offlineLabel: UILabel!
    private var repairBtn: UIButton!
    
    private var sections: [SectionType] = []
    private var sectionShowMap: [SectionType: Bool] = [:]
    private var deviceInfoModels: [CustomCellModel] = []
    
    /// 是否锁住UI更新（操作时不更新UI）
//    private var lockUIUpdate: Bool = false
    /// 节点在线/离线状态
    private var onlineState: Bool = false
    /// 最后发送的亮度值
    private var lastSendLightness: UInt16 = 0
    /// 刷新
    private var refreshControl: UIRefreshControl!
    
    let node: Node
    
    init(node: Node) {
        self.node = node
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupTableView()
        
        sections = [.information, .deviceInfo, .group, .scene]
        sectionShowMap = [.deviceInfo: true, .scene: false]
        
        setupDeviceInfoDataSource()
        
        updateUI()
        
        getNodeState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        MeshLibManager.manager.messageDelegate = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if tableView.contentOffset.y + tableView.contentInset.top < 0 {
            tableView.contentOffset = .zero
            refreshControl.isHidden = true
        }
    }
    
    /// 设备名称更新
    func reloadNodeName(_ name: String) {
        setupDeviceInfoDataSource()
        if let index = self.sections.firstIndex(of: .deviceInfo) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
    }
    
    /// 获取设备数据
    @objc private func getNodeState() {
        
        MeshAPI.getNodeState(address: node.primaryUnicastAddress)
    
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 2) {[weak self] nodes in
            guard let self = self else { return }
            if self.refreshControl.isRefreshing {
                self.refreshControl.endRefreshing()
            }
            if !nodes.contains(where: { $0.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                self.node.rssi = nil
            }
            self.headerView.node = self.node
            let model = self.deviceInfoModels.last
            model?.content = self.node.rssi != nil ? "\(self.node.rssi!)dB" : "--"
            if let section = self.sections.firstIndex(of: .deviceInfo) {
                CATransaction.setDisableActions(true)
                self.tableView.reloadSections(IndexSet(integer: section), with: .none)
                CATransaction.commit()
            }
        }
        
    }
    
    /// 设备数据
    private func setupDeviceInfoDataSource() {
        
        let messageColor = RGB(13, 14, 28, 0.5)
        
        let nameModel = CustomCellModel(title: "name".localizedString, content: node.name, contentColor: messageColor, contentFont: FONTS(SCRYFrom(15)), style: .none)
        
        let macModel = CustomCellModel(icon: UIImage(named: "copy"), title: "MAC", content: node.macAddressResult, contentColor: messageColor, contentFont: FONTS(SCRYFrom(15)), style: .icon)
        
        let devModel = CustomCellModel(title: "model".localizedString, content: "--", contentColor: messageColor, contentFont: FONTS(SCRYFrom(15)), style: .none)
        
        let deviceTypeModel = CustomCellModel(title: "device_type".localizedString, content: "--", contentColor: RGB(156, 163, 175), contentFont: FONTS(SCRYFrom(14)), style: .none)
        
        let firmwareModel = CustomCellModel(title: "firmware".localizedString, content: String(format: "%04X", node.versionIdentifier ?? 0), contentColor: messageColor, contentFont: FONTS(SCRYFrom(15)), style: .none)
        
        let singleStrengthModel = CustomCellModel(title: "signal_strength".localizedString, content: node.rssi != nil ? "\(node.rssi!)dB" : "--", contentColor: messageColor, contentFont: FONTS(SCRYFrom(15)), style: .none)
        
        deviceInfoModels = [nameModel, macModel, devModel, deviceTypeModel, firmwareModel, singleStrengthModel]
    }

    private func setupTableView() {
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = Background_Color
        tableView.register(DeviceLightControlViewCell.classForCoder(), forCellReuseIdentifier: "controlCell")
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DeviceLightInfoSectionView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        headerView = DeviceLightHeaderView(frame: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(122)))
        headerView.onoffControlCallback = {[weak self] isOn in
            guard let self = self else { return }
            MeshAPI.setNodeOnOffState(address: self.node.primaryUnicastAddress, isOn: isOn)
            self.node.isOn = isOn
            if !isOn && self.node.lightness > 0 {
                // 记录关灯前亮度
                self.node.trunOffLightness = self.node.lightness
            }
            if self.tableView.numberOfSections > 0, let index = self.sections.firstIndex(of: .control) {
                if let levelCell = tableView.cellForRow(at: IndexPath(row: 0, section: index)) as? DeviceLightControlViewCell {
                    if isOn {
                        if let trunOffLightness = self.node.trunOffLightness, self.node.lightness == 0 {
                            levelCell.value = Node.getLightness100(lightness: trunOffLightness, range: self.node.lightnessRange)
                        }else {
                            levelCell.value = self.node.lightness100
                        }
                    }else {
                        levelCell.value = 0
                    }
                }
            }
            
            self.headerView.node = self.node
//            self.lockUIUpdateAction(duration: 2)
        }
//        tableView.tableHeaderView = headerView
        
        // 离线view
        offlineView = UIView(frame: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(44)))
        
        offlineImageView = UIImageView(image: UIImage(named: "device_offline"))
        offlineView.addSubview(offlineImageView)
        offlineImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        offlineLabel = UILabel(text: "device_offline_message".localizedString, textColor: RGB(143, 143, 143), fontSize: 14)
        offlineView.addSubview(offlineLabel)
        offlineLabel.snp.makeConstraints { make in
            make.left.equalTo(offlineImageView.snp.right).offset(SCRXFrom(6))
            make.centerY.equalToSuperview()
        }
        
        repairBtn = UIButton(title: "repair".localizedString, titleSize: 14, titleColor: .white, target: self, action: #selector(repairBtnClick))
        repairBtn.titleLabel?.font = Font_Medium_Size(SCRYFrom(14))
        repairBtn.layer.cornerRadius = SCRYFrom(5)
        repairBtn.backgroundColor = Bar_Color
        offlineView.addSubview(repairBtn)
        repairBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(80))
            make.height.equalTo(SCRYFrom(32))
        }
        
        tableView.tableHeaderView = offlineView
        
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.lightGray
        refreshControl.addTarget(self, action: #selector(getNodeState), for: .valueChanged)
//        tableView.addSubview(refreshControl)
    }
    
    /// 设置锁住UI更新
//    @objc private func lockUIUpdateAction(duration: TimeInterval = 3) {
//        
//        lockUIUpdate = true
//        DispatchQueue.main.async {
//            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.unlockUIUpdateAction), object: nil)
//            self.perform(#selector(self.unlockUIUpdateAction), with: nil, afterDelay: duration)
//        }
//    }
    
    /// 解锁UI更新
//    @objc private func unlockUIUpdateAction() {
//        
//        lockUIUpdate = false
//    }
    
    /// 修复设备
    @objc private func repairBtnClick() {
        
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_repair_offline".localizedString, isLineFeed: true)
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: "repairing".localizedString, isWindow: true)
        MeshAPI.startKeyBind(node: node, startKeyBind: nil) {[weak self] node in
            XWHUDManager.hide()
            if MeshLibManager.manager.bluetoothState == .poweredOn {
                XWHUDManager.showSuccessTipHUD("complete!".localizedString)
            }
            self?.updateUI()
            self?.wm_pageController?.reloadData()
            MeshAPI.getNodeState(address: node.primaryUnicastAddress)
            
        } keyBindFail: {[weak self] _ in
            XWHUDManager.hide()
            self?.repairFailed()
        }
        
    }
    
    /// 修复失败
    private func repairFailed() {
        
        let alertView = SRAlertView(message: "repair_failed_message".localizedString, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "alert_failed"), actions: [.cancelAction, SRAlertAction(title: "repair".localizedString, style: .default, actionHandler: {[weak self] _ in
            self?.repairBtnClick()
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
    
    /// 更新UI
    private func updateUI() {
        
        print("light lightness: \(node.lightness100)")
        // 设备功能是否绑定完成
        if node.isKeybindComplete {
            if node.state != onlineState {
                onlineState = node.state
                if node.state {
                    sections = [.control, .information, .deviceInfo, .group, .scene]
                }else {
                    sections = [.information, .deviceInfo, .group, .scene]
                }
                if node.state {
                    headerView.node = node
                    tableView.tableHeaderView = headerView
                }else {
                    tableView.tableHeaderView = offlineView
                }
                
                tableView.reloadData()
            }else {
                if tableView.numberOfSections > 0, let index = sections.firstIndex(of: .control) {
                    headerView.node = node
                    if let levelCell = tableView.cellForRow(at: IndexPath(row: 0, section: index)) as? DeviceLightControlViewCell {
                        levelCell.value = node.lightness100
                    }
                    if let cctCell = tableView.cellForRow(at: IndexPath(row: 1, section: index)) as? DeviceLightControlViewCell {
                        cctCell.value = node.temperature100
                    }
    //                tableView.reloadSections(IndexSet(integer: index), with: .none)
                }
            }
            if node.state {
                tableView.refreshControl = refreshControl
            }else {
                tableView.refreshControl = nil
            }
            repairBtn.isHidden = true
            offlineLabel.text = "device_offline_message".localizedString
        }else { // 修复
            
            sections = [.information, .deviceInfo, .group, .scene]
            tableView.tableHeaderView = offlineView
            repairBtn.isHidden = false
            offlineLabel.text = "device_repair_message".localizedString
            tableView.reloadData()
            tableView.refreshControl = nil
        }
        
    }
    
}

extension DeviceLightBasicController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionType = sections[section]
        switch sectionType {
        case .control:
            return node.temperatureModel != nil ? 2 : 1
        case .deviceInfo:
            let isShow = sectionShowMap[sectionType] ?? false
            return isShow ? deviceInfoModels.count : 0
        case .scene:
            let sceneCount = node.scenes.count
            let isShow = sectionShowMap[sectionType] ?? false
            return (isShow && sceneCount > 0) ? sceneCount : 0
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionType = sections[section]
        if sectionType == .control {
            return nil
        }
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceLightInfoSectionView
        headerView.contentLabel.isHidden = true
        headerView.showImageView.isHidden = true
        switch sectionType {
        case .information:
            headerView.titleLabel.text = "information".localizedString
        case .deviceInfo:
            headerView.titleLabel.text = "device".localizedString
            headerView.showImageView.isHidden = false
            let isShow = sectionShowMap[sectionType] ?? false
            headerView.showImageView.image = UIImage(named: isShow ? "arrow_up": "arrow_down")
        case .group:
            headerView.titleLabel.text = "group".localizedString
            headerView.contentLabel.isHidden = false
            headerView.contentLabel.text = node.group?.name ?? "device_not_added_group".localizedString
        case .scene:
            headerView.titleLabel.text = "scene".localizedString
            if node.scenes.count > 0 {
                headerView.showImageView.isHidden = false
                let isShow = sectionShowMap[sectionType] ?? false
                headerView.showImageView.image = UIImage(named: isShow ? "arrow_up": "arrow_down")
            }else {
                headerView.contentLabel.isHidden = false
                headerView.contentLabel.text = "device_not_added_scene".localizedString
            }
        default:
            break
        }
        headerView.sectionViewClickCallback = {[weak self] in
            if sectionType == .deviceInfo || sectionType == .scene {
                let isShow = self?.sectionShowMap[sectionType] ?? false
                self?.sectionShowMap[sectionType] = !isShow
                self?.tableView.reloadSections(IndexSet(integer: section), with: .automatic)
            }
        }
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let sectionType = sections[section]
        return sectionType == .control ? 0.01 : SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        let sectionType = sections[indexPath.section]
        if sectionType == .control {
            return SCRYFrom(188)
        }else if sectionType == .deviceInfo && indexPath.row == 3 {
            return SCRYFrom(60)
        }
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let sectionType = sections[indexPath.section]
        
        if sectionType == .control {
            let cell = tableView.dequeueReusableCell(withIdentifier: "controlCell", for: indexPath) as! DeviceLightControlViewCell
            cell.selectionStyle = .none
            if indexPath.row == 0 {
                cell.value = node.lightness100
                cell.valueTags = cell.defaultLevelValueTags
                cell.limitRange = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
                cell.type = .level()
            }else if indexPath.row == 1 {
                cell.valueTags = [("3000K", node.getTemperature100(temperature: 3000)),
                                  ("4000K", node.getTemperature100(temperature: 4000)),
                                  ("4500K", node.getTemperature100(temperature: 4500)),
                                  ("5000K", node.getTemperature100(temperature: 5000)),
                                  ("6000K", node.getTemperature100(temperature: 6000))]
                cell.type = .cct(min: 0, max: 100, step: 1, unit: "%")
                cell.value = node.temperature100
            }
            
            cell.delegate = self
            return cell
        }else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
            cell.selectionStyle = .none
            if sectionType == .deviceInfo {
                let model = deviceInfoModels[indexPath.row]
                cell.cellStyle = model.style
                cell.titleLabel.text = model.title
                cell.titleLabel.textColor = model.titleColor
                cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
                cell.contentLabel.text = model.content
                cell.contentLabel.font = model.contentFont
                cell.contentLabel.textColor = model.contentColor
                cell.contentLabel.numberOfLines = 2
                if model.style == .icon {
                    cell.iconImageView.image = model.icon
                    cell.iconX = tableView.width - 30 - SCRXFrom(8)
                    cell.arrowImageView.isHidden = true
                }
                cell.lineView.isHidden = indexPath.row != deviceInfoModels.count - 1
//                tableView.numberOfRows(inSection: indexPath.section) - 1 != indexPath.row
            }else {
                let scene = node.scenes[indexPath.row]
                cell.cellStyle = .none
                cell.titleLabel.text = scene.name
                cell.titleLabel.textColor = TextBlack_Color.withAlphaComponent(0.5)
                cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
//                Font_Medium_Size(SCRYFrom(14))
                if let sceneData = node.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                    if sceneData.lightness == 0 {
                        cell.contentLabel.text = "off".localizedString
                    }else {
                        if node.temperatureModel != nil {
                            let cct100 = Node.getTemperature100(temperature: UInt16(sceneData.cct), range: node.lightCTLTemperatureRange ?? node.defalutLightCTLTemperatureRange)
                            cell.contentLabel.text = "\("brightness".localizedString)-\(sceneData.lightness)%.\("cct".localizedString)-\(cct100)%"
                        }else {
                            cell.contentLabel.text = "\("brightness".localizedString)-\(sceneData.lightness)%."
                        }
                    }
                }
//                "Brightness-20%."
                cell.contentLabel.textColor = RGB(13, 14, 28, 0.5)
                cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
                cell.lineView.isHidden = false
            }
//            cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let sectionType = sections[indexPath.section]
        if sectionType == .deviceInfo && indexPath.row == 1 { // 复制
            let model = deviceInfoModels[indexPath.row]
            if let content = model.content {
                let pasteboard = UIPasteboard.general
                pasteboard.string = content
                XWHUDManager.showTipHUD(inView: "copy_success".localizedString, isLineFeed: false)
            }
        }
    }
    
}

extension DeviceLightBasicController: DeviceLightControlViewCellDelegate {
    
    func cell(_ cell: DeviceLightControlViewCell, type: DeviceSliderFunctionView.FunctionType, throttleValueChanged value: Int, ended: Bool) {
        switch type {
        case .level:
            let lightness = Node.getLightness(lightness100: value, range: node.lightnessRange)
            MeshAPI.setNodeLightnessState(address: node.primaryUnicastAddress, lightness: lightness, ack: ended)
            if lightness == 0, lastSendLightness > 0 {
                node.trunOffLightness = lastSendLightness
            }
            lastSendLightness = lightness
        case .cct:
            let cct = node.getTemperature(temperature100: value)
            MeshAPI.setNodeColorTemperatureState(address: node.primaryUnicastAddress, temperature: cct)
        }
    }
    
    func cell(_ cell: DeviceLightControlViewCell, type: DeviceSliderFunctionView.FunctionType, valueChanged value: Int) {
        
        switch type {
        case .level:
            let lightness = Node.getLightness(lightness100: value, range: node.lightnessRange)
            node.lightness = lightness
            node.isOn = lightness > 0
        case .cct:
            let cct = node.getTemperature(temperature100: value)
            node.temperature = cct
        }
        headerView.node = node
        
//        lockUIUpdateAction()
    }
    
}

extension DeviceLightBasicController {
    
    /// 组类型
    enum SectionType {
        /// 控制（brightness+cct）
        case control
        /// info信息标题
        case information
        /// 设备信息
        case deviceInfo
        /// 组
        case group
        /// 场景
        case scene
    }
    
}

extension DeviceLightBasicController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
            // 离线->在线  在线->离线
            if node.state != onlineState {
//                // 获取设备最新状态
//                MeshAPI.getNodeState(address: node.primaryUnicastAddress)
//                (self.wm_pageController as? DeviceLightViewController)?.updateUI()
            }
            
//            if !lockUIUpdate { // 未在发送控制消息时才可更新UI
            lastSendLightness = node.lightness
                updateUI()
//            }
        }
    }
    
}
