//
//  DevicesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/28.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth

class DevicesViewController: UIViewController {

    /// 头部
    private var headerView: UIView!
    private var allOnBtn: UIButton!
    private var allOffBtn: UIButton!
    private var settingBtn: UIButton!
    
    // 设备列表
    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    
    /// 底部
    private var footerView: SpaceFunctionFooterView!
    /// 全选
    private var allSelectView: UIView!
    private var allSelectBgView: UIView!
    private var allSelectBtn: UIButton!
    /// 修复
    private var repairView: UIView!
    private var repairCountLabel: UILabel!
    private var repairBtn: UIButton!
    
    /// 刷新
    private var refreshControl: UIRefreshControl!
    
    let space: SpaceData
    
    var devices: [Node] = []
    
    /// 是否正在编辑
    private var isEdit: Bool = false
    /// 选中的设备地址
    private var selectedAddresss: [Address] = []
    /// 删除设备中
    private var isDeletingDevice: Bool = false

    
    private let rssiFileName: String
    
    lazy var lightControlView: DeviceLightControlView = {
        let view = DeviceLightControlView(frame: self.view.bounds)
        view.delegate = self
        return view
    }()
    
    init(space: SpaceData) {
        self.space = space
        rssiFileName = "\(self.space.id)_rssi"
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupUI()
        view.layoutIfNeeded()
        // 未连接上mesh网络
        if !MeshNetworkManager.instance.realNodes.isEmpty && !MeshLibManager.manager.isMeshNetworkConnected && (MeshLibManager.manager.bluetoothState == .poweredOn || MeshLibManager.manager.bluetoothState == .unknown) {
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 15)
            // 获取设备信号
            MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 3, result: nil)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        MeshLibManager.manager.register(self)
        
        loadDevices()
//        collectionView.reloadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        updateDevicesEmptyUI()
    }
    
    private func loadDevices() {
     
        var reloadDevicesView = false
        if devices.count != MeshNetworkManager.instance.realNodes.count {
            reloadDevicesView = true
        }
        devices = MeshNetworkManager.instance.realNodes
        // 读取缓存的设备信号值
        if let rssiMap = LCPlistCacheTool.readDict(fileName: rssiFileName) {
            rssiMap.forEach { (mac: String, rssi: Any) in
                if let node = devices.first(where: { $0.macAddress == mac }) {
                    node.rssi = rssi as? Int
                }
            }
        }
        if devices.count > 0 {
            collectionView.refreshControl = refreshControl
        }else {
            collectionView.refreshControl = nil
        }
        
        switch space.deviceSortType {
        case .rssi:
            devices.sort(by: { ($0.rssi ?? -99) > ($1.rssi ?? -99) })
        default:
            break
        }
        
        if space.deviceCount != devices.count {
            space.deviceCount = devices.count
            space.luminairesCount = devices.count
            space.save()
        }
        if reloadDevicesView {
            self.collectionView.reloadData()
        }else { // 只刷新数据
            devices.forEach({ reloadCollectionItem(node: $0) })
        }
        updateUI(reloadTableView: false)
    }
    
    private func updateDevicesEmptyUI() {
        
        if devices.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }

            collectionView.showEmptyDataView(title: "no_devices".localizedString, tipText: "no_devices_message".localizedString)
            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            headerView.isHidden = true
            footerView.sortBtn.isEnabled = false
            footerView.editBtn.isEnabled = false
        }else {
            headerView.isHidden = false
            collectionView.hideEmptyDataView()
            footerView.sortBtn.isEnabled = true
            footerView.editBtn.isEnabled = true
        }
    }
    
    private func updateUI(reloadTableView: Bool = true) {
        
        self.updateDevicesEmptyUI()
        
        self.footerView.countBtn.setTitle("\(self.devices.count)/100", for: .normal)
        
        var inset = self.collectionView.contentInset
        inset.bottom = SCRYFrom(16)
        if isEdit {
            self.allSelectView.isHidden = false
            inset.bottom = SCRYFrom(16) + allSelectView.height
            self.footerView.isEditing = true
            self.repairView.isHidden = true
            self.settingBtn.isEnabled = false
        }else {
            self.allSelectView.isHidden = true
            self.settingBtn.isEnabled = true
            self.footerView.isEditing = false
            // 判断是否有需要修复设备
            let notKeybindNodes = devices.filter({ !$0.isKeybindComplete })
            if notKeybindNodes.count > 0 {
                inset.bottom = SCRYFrom(16) + repairView.height
                self.repairView.isHidden = false
                self.repairCountLabel.text = String(format: "device_repair_tip".localizedString, notKeybindNodes.count)
            }else {
                self.repairView.isHidden = true
            }
        }
        
        self.collectionView.contentInset = inset
//        CATransaction.setDisableActions(true)
        if reloadTableView {
//            self.collectionView.reloadData()
            reloadAllDevices()
        }
//        CATransaction.commit()
    }
    
    private func updateEditUI() {
        
        // 可编辑的设备list
        let canEditDevices = devices.filter({ $0.state && $0.isKeybindComplete })
        if canEditDevices.count > 0 && self.selectedAddresss.count >= canEditDevices.count {
            self.allSelectBtn.isSelected = true
            self.allSelectBtn.backgroundColor = Bar_Color
        }else {
            self.allSelectBtn.isSelected = false
            self.allSelectBtn.backgroundColor = RGB(238, 238, 239)
        }
        self.footerView.deleteBtn.isEnabled = selectedAddresss.count > 0
    }
    
    private func setupUI() {
        
        // header
        headerView = UIView()
        headerView.backgroundColor = Background_Color
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(44))
        }
        
        allOffBtn = UIButton(title: "off".localizedString, titleSize: 15, titleColor: TextBlack_Color, target: self, action: #selector(allOffBtnClick))
        allOffBtn.setTitleColor(TextBlack_Color.withAlphaComponent(0.5), for: .highlighted)
        allOffBtn.setBackgroundImage(UIImage.image(size: CGSize(width: 1, height: 1), color: .white.withAlphaComponent(0.5)), for: .highlighted)
        allOffBtn.adjustsImageWhenHighlighted = true
        allOffBtn.titleLabel?.font = Font_Medium_Size(14)
        allOffBtn.layer.cornerRadius = 4
        allOffBtn.layer.borderWidth = 0.5
        allOffBtn.layer.borderColor = RGB(100, 136, 139).cgColor
        headerView.addSubview(allOffBtn)
        allOffBtn.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(SCRXFrom(40))
            make.height.equalTo(SCRYFrom(30))
        }
        
        allOnBtn = UIButton(title: "on".localizedString, titleSize: 15, titleColor: TextBlack_Color, target: self, action: #selector(allOnBtnClick))
        allOnBtn.setTitleColor(TextBlack_Color.withAlphaComponent(0.5), for: .focused)
        allOnBtn.setBackgroundImage(UIImage.image(size: CGSize(width: 1, height: 1), color: .white.withAlphaComponent(0.5)), for: .highlighted)
        allOnBtn.adjustsImageWhenHighlighted = true
        allOnBtn.titleLabel?.font = Font_Medium_Size(14)
        allOnBtn.layer.cornerRadius = 4
        allOnBtn.layer.borderWidth = 0.5
        allOnBtn.layer.borderColor = RGB(100, 136, 139).cgColor
        headerView.addSubview(allOnBtn)
        allOnBtn.snp.makeConstraints { make in
            make.centerY.width.height.equalTo(allOffBtn)
            make.right.equalTo(allOffBtn.snp.left).offset(SCRXFrom(-28))
        }
        
        settingBtn = UIButton(normalImageName: nil, target: self, action: #selector(settingBtnClick))
        settingBtn.setBackgroundImage(UIImage(named: "space_device_adjust"), for: .normal)
        settingBtn.setBackgroundImage(UIImage(named: "space_device_adjust_highlighted"), for: .highlighted)
        settingBtn.adjustsImageWhenHighlighted = true
        headerView.addSubview(settingBtn)
        settingBtn.snp.makeConstraints { make in
            make.centerY.width.height.equalTo(allOffBtn)
            make.left.equalTo(allOffBtn.snp.right).offset(SCRXFrom(28))
        }
        
        footerView = SpaceFunctionFooterView()
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(8), left: SCRXFrom(12), bottom: SCRYFrom(16), right: SCRXFrom(12))
        collectionView.backgroundColor = Background_Color
        collectionView.register(DevicesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(footerView.snp.top)
        }
        
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.lightGray
        refreshControl.addTarget(self, action: #selector(getNodesState), for: .valueChanged)
        
        
        allSelectView = UIView()
        allSelectView.layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
//        allSelectView.layer.shadowOffset = CGSizeMake(0, -2)
        allSelectView.layer.shadowOpacity = 1
        allSelectView.layer.shadowRadius = 6
        allSelectView.layer.shadowPath = UIBezierPath(rect: CGRect(x: 0, y: -2, width: view.width, height: SCRYFrom(11))).cgPath
        
        allSelectView.isHidden = true
        view.addSubview(allSelectView)
        allSelectView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(footerView.snp.top)
            make.height.equalTo(SCRYFrom(64))
        }
        
        allSelectBgView = UIView()
        allSelectBgView.backgroundColor = .white
        allSelectBgView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: 10, height: 10), rect: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(64)))
        allSelectView.addSubview(allSelectBgView)
        allSelectBgView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        
        allSelectBtn = UIButton(title: "all".localizedString, titleSize: 16, titleColor: RGB(49, 49, 93), target: self, action: #selector(allSelectBtnClick))
        allSelectBtn.layer.cornerRadius = SCRYFrom(6)
        allSelectBtn.backgroundColor = RGB(238, 238, 239)
        allSelectBtn.setTitleColor(.white, for: .selected)
        allSelectView.addSubview(allSelectBtn)
        allSelectBtn.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(88))
            make.height.equalTo(SCRYFrom(40))
        }
        
        repairView = UIView()
//        repairView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: SCRYFrom(8), height: SCRYFrom(8)), rect: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(60)))
        repairView.layer.cornerRadius = SCRYFrom(8)
        repairView.layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        repairView.layer.shadowOpacity = 1
        repairView.layer.shadowRadius = 6
        repairView.layer.shadowOffset = CGSize(width: 0, height: -2)
//        repairView.layer.shadowPath = UIBezierPath(rect: CGRect(x: 0, y: -2, width: view.width, height: SCRYFrom(11))).cgPath
        repairView.isHidden = true
        repairView.backgroundColor = .white
        view.addSubview(repairView)
        repairView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(footerView.snp.top)
            make.height.equalTo(SCRYFrom(60))
        }
        
        repairCountLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 16)
        repairView.addSubview(repairCountLabel)
        repairCountLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        repairBtn = UIButton(title: "repair".localizedString, titleSize: 14, titleColor: .white, target: self, action: #selector(repairBtnClick))
        repairBtn.titleLabel?.font = Font_Medium_Size(SCRYFrom(14))
        repairBtn.layer.cornerRadius = SCRYFrom(5)
        repairBtn.backgroundColor = Bar_Color
        repairView.addSubview(repairBtn)
        repairBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(80))
            make.height.equalTo(SCRYFrom(32))
        }
    }
    
    // MARK: - Action
    
    /// 全关
    @objc private func allOffBtnClick() {
        devices.forEach({
            $0.isOn = false
            // 关灯，记录关灯前的亮度值
            if $0.lightness > 0 {
                $0.trunOffLightness = $0.lightness
            }
        })
        collectionView.reloadData()
        MeshAPI.setAllOnOffState(isOn: false)
    }
    
    /// 全开
    @objc private func allOnBtnClick() {
        devices.forEach({ $0.isOn = true })
        collectionView.reloadData()
        MeshAPI.setAllOnOffState(isOn: true)
    }
    
    /// 设备调节
    @objc private func settingBtnClick() {
        if lightControlView.superview == nil {
            view.addSubview(lightControlView)
        }
        self.wm_pageController?.scrollEnable = false
        lightControlView.show()
    }
    
    /// 全选/取消全选
    @objc private func allSelectBtnClick(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            sender.backgroundColor = Bar_Color
            // 在线的设备才能选择
            selectedAddresss = devices.filter({ $0.state && $0.isKeybindComplete }).map({ $0.primaryUnicastAddress })
        }else {
            sender.backgroundColor = RGB(238, 238, 239)
            selectedAddresss.removeAll()
        }
//        collectionView.reloadData()
        footerView.deleteBtn.isEnabled = selectedAddresss.count > 0
        collectionView.reloadSections(IndexSet(integer: 0))
//        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
    }
    
    /// 修复设备
    @objc private func repairBtnClick() {
        let nodes = devices.filter({ !$0.isKeybindComplete })
        repairNodes(nodes: nodes)
    }
    
    /// collectionview长按事件（跳转到设备控制页面）
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < devices.count {
            let node = devices[indexPath.item]
            if isEdit && node.state { // 不在编辑状态/编辑状态+设备离线可以进入设备控制页
                return
            }
            let deviceVc = DeviceLightViewController(space: space, node: node)
            navigationController?.pushViewController(deviceVc, animated: true)
        }
    }
    
    /// 更新全部设备UI状态
    private func reloadAllDevices() {
        devices.forEach({
            if let index = devices.firstIndex(of: $0), let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? DevicesViewCell {
                item.device = $0
            }
        })
    }
    
    /// 更新设备UI状态
    private func reloadCollectionItem(node: Node) {
        // 删除设备中不更新状态
        if isDeletingDevice {
            return
        }
        
        if let index = devices.firstIndex(where: {$0.primaryUnicastAddress == node.primaryUnicastAddress}) {
//            CATransaction.setDisableActions(true)
//            collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
            if isEdit {
                if !node.state { // 离线
                    if selectedAddresss.contains(node.primaryUnicastAddress) { // 是否编辑选中
                        // 离线时清空选中地址数据
                        selectedAddresss.removeAll(where: { $0 == node.primaryUnicastAddress })
                    }
                }
            }
            
            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? DevicesViewCell {
                if isEdit {
                    if node.state { // 离线->在线
                        if item.selectImageView.isHidden {
                            item.selectImageView.isHidden = false
                            item.selectImageView.image = UIImage(named: selectedAddresss.contains(node.primaryUnicastAddress) ? "select" : "select_un")
                        }
                    }else { // 在线->离线
                        item.selectImageView.isHidden = true
                    }
                }
                item.device = node
            }
            updateEditUI()
//            CATransaction.commit()
        }
    }
    /// 获取节点状态
    @objc private func getNodesState() {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            if refreshControl.isRefreshing {
                refreshControl.endRefreshing()
            }
            return
        }
        if let view = self.wm_pageController?.view {
            XWHUDManager.hideInView(with: view)
        }else {
            XWHUDManager.hide()
        }
        // 检查是否有功能未绑定完成的节点
//        let notKeybindNodes = devices.filter({ !$0.isKeybindComplete })
//        if notKeybindNodes.count > 0 {
//            XWHUDManager.showCustomHUD(withMessage: nil, isWindiw: false)
//            MeshAPI.startKeyBind(nodes: notKeybindNodes, startKeyBind: nil, keyBindSuccess: nil, keyBindFail: nil) { successList, failList in
//                XWHUDManager.hide()
//                MeshAPI.sendMessage(message: LightCTLGet(), address: .allNodes)
//            }
//        }else {
        if devices.contains(where: { $0.ctlModel == nil }) {
            MeshAPI.sendMessage(message: LightLightnessGet(), address: .allNodes)
        }
        
        MeshAPI.sendMessage(message: LightCTLGet(), address: .allNodes)
        MeshAPI.sendMessage(message: LightCTLTemperatureRangeGet(), address: .allNodes)
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 3, result: nil)
        if refreshControl.isRefreshing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {[weak self] in
                guard let self = self else { return }
                self.refreshControl.endRefreshing()
            }
        }
//        }
    }
    
    /// 修复设备
    private func repairNodes(nodes: [Node]) {
        if nodes.isEmpty {
            return
        }
        // 是否连接网络
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_repair_offline".localizedString, isLineFeed: true)
            return
        }
        // 多设备配置
        if nodes.count > 1 {
            let alertView =  SRAlertView(title: "repairing".localizedString, titleFont: FONTS(SCRYFrom(15)), message: "0/\(nodes.count)", messageColor: TextBlack_Color, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "loading_big"), loadingState: true, btnText: "STOP".localizedString, btnTextColor: .white, btnTextFont: Font_Medium_Size(SCRYFrom(15))) {[weak self] in
                SRAlertView.hide()
                MeshAPI.stopKeyBind(keyBindFinish: nil)
                self?.updateUI()
                self?.getNodesState()
            }
            alertView.show()
            
            MeshAPI.startKeyBind(nodes: nodes, startKeyBind: { node in
                let index = (nodes.firstIndex(of: node) ?? 0) + 1
                alertView.messageLabel.text = "\(index)/\(nodes.count)"
            }, keyBindSuccess: nil, keyBindFail: nil) { [weak self] successList, failList in
                SRAlertView.hide()
                if failList.isEmpty { // 全部修复成功
                    if MeshLibManager.manager.bluetoothState == .poweredOn {
                        XWHUDManager.showSuccessTipHUD("complete!".localizedString)
                    }
                    self?.getNodesState()
                }else { // 全部/部分修复失败
                    self?.repairFailed(nodes: failList)
                }
                self?.updateUI()
            }
            
        }else { // 单设备配置
            XWHUDManager.showCustomHUD(withMessage: "repairing".localizedString, isWindow: true)
            MeshAPI.startKeyBind(node: nodes.first!, startKeyBind: nil) {[weak self] node in
                XWHUDManager.hide()
                if MeshLibManager.manager.bluetoothState == .poweredOn {
                    XWHUDManager.showSuccessTipHUD("complete!".localizedString)
                }
                self?.updateUI()
                MeshAPI.getNodeCTLState(address: node.primaryUnicastAddress)
            } keyBindFail: {[weak self] _, _ in
                XWHUDManager.hide()
                self?.updateUI()
                self?.repairFailed(nodes: nodes)
            }
        }
        
    }
    
    /// 修复失败
    private func repairFailed(nodes: [Node]) {
        
        let alertView = SRAlertView(message: "repair_failed_message".localizedString, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "alert_failed"), actions: [.cancelAction, SRAlertAction(title: "repair".localizedString, style: .default, actionHandler: {[weak self] _ in
            self?.repairNodes(nodes: nodes)
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

}


extension DevicesViewController: SpaceFunctionFooterViewDelegate {

    /// 点击排序回调
    func functionDidClickSort(view: SpaceFunctionFooterView) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 3) {[weak self] nodes in
            XWHUDManager.hide()
            guard let self = self else { return }
//            print("\() \()")
//            nodes.forEach({ print("\(String(describing: $0.name)) \($0.rssi)") })
            if nodes.isEmpty { // 未到节点信号
                XWHUDManager.showErrorTipHUD("device_sort_failed".localizedString)
                return
            }
            self.devices.sort(by: { ($0.rssi ?? -99) > ($1.rssi ?? -99) })
            self.devices.sort(by: { $0.state && !$1.state })
            self.collectionView.reloadData()
            // 节点信号map
            var rssiMap: [String: Int] = [:]
            self.devices.forEach { node in
                if let mac = node.macAddress, let rssi = node.rssi {
                    rssiMap.updateValue(rssi, forKey: mac)
                }
            }
            // 设备信号排序
            self.space.deviceSortType = .rssi
            self.space.save()
            LCPlistCacheTool.write(fileName: self.rssiFileName, value: rssiMap)
        }
    }
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        let vc = DeviceAddViewController(space: space)
        vc.deviceAddCallback = {[weak self] nodes in
            
            self?.loadDevices()
            self?.space.deviceCount = self?.devices.count ?? 0
            self?.space.luminairesCount = self?.devices.count ?? 0
            self?.space.save()
            self?.getNodesState()
        }
        navigationController?.pushViewController(vc, animated: true) 
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        isEdit = editing
        
        allSelectBtn.isSelected = false
        allSelectBtn.backgroundColor = RGB(238, 238, 239)
        selectedAddresss.removeAll()
        footerView.deleteBtn.isEnabled = false
        updateUI(reloadTableView: false)
        CATransaction.setDisableActions(true)
        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        CATransaction.commit()
    }
    
    /// 点击删除回调
    func functionDidClickDelete(view: SpaceFunctionFooterView) {
        
        guard selectedAddresss.count > 0 else {
            return
        }
//        guard MeshLibManager.manager.isMeshNetworkConnected else {
//            return
//        }
        SRAlertView(title: "notification".localizedString, message: "devices_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            
            var resetAddressList = self.selectedAddresss
            // 如果重置节点中存在代理节点，将代理节点放到最后重置
            if let proxyNode = self.devices.first(where: { $0.isProxy }), self.selectedAddresss.contains(proxyNode.primaryUnicastAddress) {
                resetAddressList.removeAll(where: { $0 == proxyNode.primaryUnicastAddress })
                resetAddressList.append(proxyNode.primaryUnicastAddress)
            }
            isDeletingDevice = true
            MeshAPI.resetNodes(addressList: resetAddressList, resetSuccess: nil, resetFail: nil) {[weak self] successAddressList, failAddressList in
                XWHUDManager.hide()
                guard let self = self else { return }
                
                self.devices.removeAll(where: { successAddressList.contains($0.primaryUnicastAddress) })
                self.selectedAddresss.removeAll(where: { successAddressList.contains($0) })
                self.space.deviceCount = self.devices.count
                self.space.luminairesCount = self.devices.count
                self.space.save()
                
                if failAddressList.isEmpty { // 删除成功
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    self.isEdit = false
                    self.updateUI()
                    self.isDeletingDevice = false
                    
                }else { // 删除失败（提示是否强制删除这部分设备）
                    
                    let alertView = SRAlertView(title: "notification".localizedString, actions: [SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                        self?.updateUI()
                        self?.updateEditUI()
                        self?.isDeletingDevice = false
                    }), SRAlertAction(title: "force_delete".localizedString, actionHandler: {[weak self] _ in
                        guard let self = self else { return }
                        let forceDeleteNodes = self.devices.filter({ failAddressList.contains($0.primaryUnicastAddress) })
                        forceDeleteNodes.forEach({
                            self.space.meshManager?.meshNetwork?.remove(node: $0)
                        })
                        _ = self.space.meshManager?.save()
                        self.devices.removeAll(where: { failAddressList.contains($0.primaryUnicastAddress) })
                        self.isEdit = false
                        self.isDeletingDevice = false
                        self.selectedAddresss.removeAll()
                        self.updateUI()
                        
                        self.space.deviceCount = self.devices.count
                        self.space.luminairesCount = self.devices.count
                        self.space.save()
                        
                        XWHUDManager.showSuccessTipHUD("done!".localizedString)
                        
                    })])
                    let messageAttStr = NSMutableAttributedString(string: "devices_force_delete_message".localizedString, attributes: [.foregroundColor: TextBlack_Color])
                    messageAttStr.append(NSAttributedString(string: "devices_force_delete_note".localizedString, attributes: [.foregroundColor: Message_Color]))
                    alertView.messageLabel.attributedText = messageAttStr
                    alertView.show()
                }
            }
        })]).show()
        
    }
    
}

extension DevicesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return devices.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DevicesViewCell
        
        let device = devices[indexPath.item]
        if isEdit && device.state && device.isKeybindComplete {
//        if isEdit {
            cell.selectImageView.isHidden = false
            cell.selectImageView.image = UIImage(named: selectedAddresss.contains(device.primaryUnicastAddress) ? "select" : "select_un")
        }else {
            cell.selectImageView.isHidden = true
        }
        cell.device = device
        // 编辑选中点击
        cell.editClickCallback = {[weak self] node in
            guard let self = self else { return }
            let address = node.primaryUnicastAddress
            if self.selectedAddresss.contains(address) {
                self.selectedAddresss.removeAll(where: { $0 == address })
            }else {
                self.selectedAddresss.append(address)
            }
            collectionView.reloadItems(at: [indexPath])
            self.updateEditUI()
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(2)) / CGFloat(3)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // 编辑
        let node = devices[indexPath.row]
        // 未绑定完成功能则修复设备
        guard node.isKeybindComplete else {
            repairNodes(nodes: [node])
            return
        }
        if node.state { // 设备在线
            node.isOn = !node.isOn
            if !node.isOn, node.lightness > 0 { // 关灯，记录关灯前的亮度值
                node.trunOffLightness = node.lightness
            }
            reloadCollectionItem(node: node)
            MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn)
        }else { // 设备离线
            MeshAPI.getNodeOnOffState(address: node.primaryUnicastAddress)
        }
        
    }
    
}

extension DevicesViewController: DeviceLightControlViewDelegate {
    
    func lightControl(_ view: DeviceLightControlView, levelValueChanged level: Int, ended: Bool) {
        print("level: \(level)")
        
//        let lightness = UInt16(round(Double(level) / 100.0) * Double(UInt16.max))
        let ligheness = Node.getLightness(lightness100: level)
        MeshAPI.setAllLightnessState(lightness: ligheness, ack: ended)
        devices.forEach({
            // 记录关灯前亮度
            if $0.isOn && ligheness == 0 && $0.lightness > 0 {
                $0.trunOffLightness = $0.lightness
            }
            $0.isOn = ligheness > 0
            $0.lightness = ligheness
            reloadCollectionItem(node: $0)
        })
    }
    
    func lightControl(_ view: DeviceLightControlView, cctValueChanged cct: Int, ended: Bool) {
        print("cct: \(cct)")
        
        MeshAPI.setAllColorTemperatureState(temperature: UInt16(cct), ack: ended)
        devices.forEach({
            $0.temperature = UInt16(cct)
            reloadCollectionItem(node: $0)
        })
        
    }
    
    func lightControlDidHide(_ view: DeviceLightControlView) {
        self.wm_pageController?.scrollEnable = true
    }
}

extension DevicesViewController: MeshLibManagerDelegate {
    
    /// 蓝牙状态发生变化回调
    /// - Parameters:
    ///   - state: 蓝牙状态
    func meshNetworkManager(bluetoothDidUpdateState state: CBManagerState) {
        if state == .poweredOn && devices.count > 0 {
            // 获取设备信号
            MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 3, result: nil)
        }
    }
    
    
    ///  mesh设备连接成功
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - bearer: 代理设备
    func meshNetworkManager(_ manager: MeshNetworkManager, bearerDidOpen bearer: Bearer) {
//       let addressList = space.meshManager?.realNodes.map({ $0.primaryUnicastAddress }) ?? []
//        MeshAPI.resetNodes(addressList: addressList, resetSuccess: nil, resetFail: nil, resetFinish: nil)
        
        if view.window != nil {
            getNodesState()
        }
    }
 
    ///  mesh设备断开连接
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - bearer: 代理设备
    func meshNetworkManager(_ manager: MeshNetworkManager, bearerDidClose bearer: Bearer) {
        
    }
 
    /// mesh设备数据更新
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - node: 更新的设备节点
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if view.window != nil {
            reloadCollectionItem(node: node)
        }
    }
    
    /// 代理节点切换回调
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - bearer: 切换的代理
    func meshNetworkManager(_ manager: MeshNetworkManager, proxyDidReplace bearer: Bearer) {
        if view.window != nil {
            collectionView.reloadData()
        }
    }
    
}
