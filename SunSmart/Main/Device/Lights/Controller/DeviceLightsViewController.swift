//
//  DeviceLightsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/5.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth


class DeviceLightsViewController: UIViewController {

    // 设备列表
    private var flowLayout: AlignCenterFlowLayout!
    private var collectionView: UICollectionView!
    /// 全选
    private var groupsView: DeviceGroupsView!
//    private var allSelectBgView: UIView!
//    private var allSelectBtn: UIButton!
    /// 修复
    private var repairView: UIView!
    private var repairCountLabel: UILabel!
    private var repairBtn: UIButton!
    
    private var footerView: SpaceFunctionFooterView!
    
    /// 刷新
    private var refreshControl: UIRefreshControl!
    
    let site: SiteData
    let space: SpaceData
    
    /// 列数
    private var columnNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewMargin: CGFloat = isIPad ? SCRXFrom(24) : SCRXFrom(12)
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    
    var devices: [Node] = []
    /// 展示的组/全选
    private var showSelectDatas: [DeviceGroupsSelectData] = []
    /// 是否正在编辑
    private var isEdit: Bool = false
    /// 选中的设备地址
    private var selectedAddresss: [Address] = []
    /// 删除设备中
    private var isDeletingDevice: Bool = false
    
    /// 全开/全关状态（读取设备）
    private var allOnOffState: DeviceAllOnOffState = .disable
    /// 是否手动控制 全开/全关
    private var controlAllOn: Bool?
    
    lazy var lightControlView: DeviceLightControlView = {
        let view = DeviceLightControlView(frame: self.view.bounds)
        view.delegate = self
        return view
    }()
    
    init(site: SiteData,space: SpaceData) {
        self.site = site
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        
        addNotificationObserver()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        loadDevices()
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
//        devices.filter({ !$0.state }).count
        MeshLibManager.manager.register(self)
        MeshLibManager.manager.messageDelegate = self
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
        
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        updateDevicesEmptyUI()
    }
    
    private func addNotificationObserver() {
        NotificationCenter.default.addObserver(forName: .init(devicesAddNotificationName), object: nil, queue: nil) {[weak self] _ in
            //            self?.refreshData = true
            guard let self = self else { return }
//            if self.view.window != nil {
//                self.updateUI()
//            }
            self.loadDevices()
            self.getNodesState()
            self.collectionView.reloadData()
            self.updateAllOnOffItemUI()
        }
        
        // 设备列表更新通知
        NotificationCenter.default.addObserver(forName: .init(devicesUpdateNotificationName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            self.loadDevices()
        }
        
        // 设备状态更新通知
        NotificationCenter.default.addObserver(forName: .init(deviceStateUpdateNotificationName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self, let node = notification.object as? Node else { return }
            
            self.reloadCollectionItem(node: node)
        }
        
        // space编辑权限变更回调
        NotificationCenter.default.addObserver(forName: .init(spacePermissionChangedNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            self.updateUI(reloadTableView: false)
        }
    }
    
    private func loadDevices() {
     
        var reloadDevicesView = false
//        MeshNetworkManager.instance.realNodes.filter({ $0. })
        let lightNodes = MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }
        if devices.count != lightNodes.count {
            reloadDevicesView = true
        }
        
        devices = lightNodes
        
        // 读取缓存的设备信号值
//        if let rssiMap = LCPlistCacheTool.readDict(fileName: rssiFileName) {
//            rssiMap.forEach { (mac: String, rssi: Any) in
//                if let node = devices.first(where: { $0.macAddress == mac }) {
//                    node.rssi = rssi as? Int
//                }
//            }
//        }
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
        
        let realNodeCount = MeshNetworkManager.instance.realNodes.count
        if space.deviceCount != realNodeCount || space.luminairesCount != devices.count {
            space.deviceCount = realNodeCount
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
    
    @objc private func refreshControlAction() {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            if refreshControl.isRefreshing {
                refreshControl.endRefreshing()
            }
            return
        }
        
        if refreshControl.isRefreshing {
            let duration = max(2, min(Double(devices.count) *  0.3, 5))
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {[weak self] in
                guard let self = self else { return }
                self.refreshControl.endRefreshing()
            }
        }
        
        getNodesState()
    }
    
    /// 获取节点状态
    private func getNodesState() {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
//        if let view = self.wm_pageController?.view {
//            XWHUDManager.hideInView(with: view)
//        }else {
//            XWHUDManager.hide()
//        }
        
        MeshNodeHeartbeatManager.shared.refresh()
//        MeshAPI.sendMessage(message: LightLightnessGet(), address: .allNodes)
//        
//        if devices.contains(where: { $0.ctlModel != nil && $0.temperatureModel != nil }) {
//            MeshAPI.sendMessage(message: LightCTLGet(), address: .allNodes)
//        }
        
//        MeshAPI.sendMessage(message: LightCTLTemperatureRangeGet(), address: .allNodes)
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 10, finished: nil)
     
//        }
    }
    
    private func updateDevicesEmptyUI() {
        
        if devices.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }

            collectionView.showEmptyDataView(title: "no_devices".localizedString, tipText: "no_devices_message".localizedString, position: .center, bottomMargin: SCRYFit(30))
            if let emptyView = collectionView.emptyView {
                emptyView.titleLabel.font = FONTS(SCRYFrom(15))
                emptyView.tipLabel.font = UIFont.systemFont(ofSize: 15, weight: .light)
            }
           
//            headerView.isHidden = true
            footerView.sortBtn.isEnabled = false
            footerView.editBtn.isEnabled = false
        }else {
//            headerView.isHidden = false
            collectionView.hideEmptyDataView()
            footerView.sortBtn.isEnabled = true
//            footerView.editBtn.isEnabled = !isEdit
            footerView.editBtn.isEnabled = space.deviceOperates.contains(.edit)
        }
    }
    
    private func updateUI(reloadTableView: Bool = true) {
        
        self.updateDevicesEmptyUI()
        
       
        
        footerView.countBtn.setTitle("\(self.devices.count)/\(space.maxDevicesCount)", for: .normal)
        
        var inset = self.collectionView.contentInset
        inset.bottom = SCRYFrom(16)
        if isEdit {
            self.groupsView.isHidden = false
            inset.bottom = SCRYFrom(16) + groupsView.height
            footerView.isEditing = true
            self.repairView.isHidden = true
            
            footerView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
            }
//            self.mainViewController?.footerView.switchCountBtn.isHidden = true
//            self.settingBtn.isEnabled = false
        }else {
            self.groupsView.isHidden = true
//            self.settingBtn.isEnabled = true
            footerView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
            }
            
            DispatchQueue.global().async {
                let existSync = self.devices.contains(where: { $0.needSync })
                DispatchQueue.main.async {
                    self.footerView.syncBtn.isHidden = !existSync
                }
            }
            
            footerView.isEditing = false
//            self.mainViewController?.footerView.switchCountBtn.isHidden = true
            // 判断是否有需要修复设备
            let notKeybindNodes = devices.filter({ !$0.isKeybindComplete })
            if notKeybindNodes.count > 0 && space.deviceOperates.contains(.edit) {
                inset.bottom = SCRYFrom(16) + repairView.height
                self.repairView.isHidden = false
                self.repairCountLabel.text = String(format: "device_repair_tip".localizedString, notKeybindNodes.count)
            }else {
                self.repairView.isHidden = true
            }
        }
        
        footerView.addBtn.isEnabled = space.deviceOperates.contains(.add)
        footerView.editBtn.isEnabled = space.deviceOperates.contains(.edit)
        footerView.syncBtn.isEnabled = space.deviceOperates.contains(.edit)
        
//        if !space.deviceOperates.contains(.add) {
//            footerView.addBtn.isEnabled = false
//        }
//        if !space.deviceOperates.contains(.edit) {
//            footerView.editBtn.isEnabled = false
//        }
        
        
        self.collectionView.contentInset = inset
//        CATransaction.setDisableActions(true)
        if reloadTableView {
//            self.collectionView.reloadData()
            reloadAllDevices()
        }
        
        updateAllOnOffItemUI()
//        CATransaction.commit()
    }
    
    private func updateEditUI() {
        
        // 可编辑的设备list
        
        let groups = MeshNetworkManager.instance.groups
//            .filter({ $0.nodes.count > 0 })
        showSelectDatas = groups.map({
            let nodes = $0.nodes
            let isSelected = nodes.count > 0 && !nodes.contains(where: { !self.selectedAddresss.contains($0.primaryUnicastAddress) })
            return DeviceGroupsSelectData(name: $0.name, groupAddress: $0.address.address,addresss: nodes.map({ $0.primaryUnicastAddress }), isSelected: isSelected)
        })
        let canEditDeviceAddresss = devices.map({ $0.primaryUnicastAddress })
        // 全选
//        showSelectDatas.insert(DeviceGroupsSelectData(name: "ALL".localizedString, addresss: canEditDeviceAddresss, isSelected: canEditDeviceAddresss.count == selectedAddresss.count && canEditDeviceAddresss.count > 0), at: 0)
        self.groupsView.datas = showSelectDatas
        self.groupsView.selectAllBtn.isSelected = canEditDeviceAddresss.count > 0 && canEditDeviceAddresss.count == selectedAddresss.count
//        if canEditDevices.count > 0 { // self.selectedAddresss.count >= canEditDevices.count
//
////            self.allSelectBtn.isSelected = true
////            self.allSelectBtn.backgroundColor = Bar_Color
//        }else {
////            self.allSelectBtn.isSelected = false
////            self.allSelectBtn.backgroundColor = RGB(238, 238, 239)
//        }
        footerView.deleteBtn.isEnabled = selectedAddresss.count > 0
    }
    
    /// 更新全开全关状态
    private func updateAllOnOffItemUI() {
        
        if devices.contains(where: { $0.state }) {
            allOnOffState = devices.contains(where: { $0.isOn }) ? .on : .off
        }else {
            allOnOffState = .disable
        }
        if let item = collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? DeviceAllOnOffViewCell {
            if allOnOffState != .disable, let isOn = controlAllOn {
                item.state = isOn ? .on : .off
            }else {
                item.state = allOnOffState
            }
        }
    }
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.enableTestDelete = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.itemRowCount = columnNum
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: collectionViewMargin, right: 0)
//        UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: <#T##CGFloat#>, right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(50 + (isIPad ? 22 : 10)), left: collectionViewMargin, bottom: 0, right: collectionViewMargin)
        collectionView.backgroundColor = Background_Color
        collectionView.register(DevicesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.register(DeviceAllOnOffViewCell.classForCoder(), forCellWithReuseIdentifier: "allControlCell")
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.top.right.equalToSuperview()
//            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(footerView.snp.top)
//            make.bottom.equalToSuperview()
        }
        
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.lightGray
        refreshControl.addTarget(self, action: #selector(refreshControlAction), for: .valueChanged)
        
        
        groupsView = DeviceGroupsView()
        groupsView.isHidden = true
        groupsView.delegate = self
        view.addSubview(groupsView)
        groupsView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(collectionView)
//            make.bottom.equalToSuperview()
//            make.height.greaterThanOrEqualTo(SCRYFrom(64))
        }

        repairView = UIView()
//        repairView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: SCRYFrom(8), height: SCRYFrom(8)), rect: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(60)))
        repairView.layer.cornerRadius = SCRYFrom(8)
        repairView.layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        repairView.layer.shadowOpacity = 1
        repairView.layer.shadowRadius = 6
        repairView.layer.shadowOffset = CGSize(width: 0, height: -2)
        repairView.layer.shadowPath = UIBezierPath(rect: CGRect(x: 0, y: -2, width: view.width, height: SCRYFrom(11))).cgPath
        repairView.isHidden = true
        repairView.backgroundColor = .white
        view.addSubview(repairView)
        repairView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(groupsView).offset(-1)
//            make.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
        }
        
        repairCountLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        repairView.addSubview(repairCountLabel)
        repairCountLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        repairBtn = UIButton(title: "repair".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(repairBtnClick))
//        repairBtn.titleLabel?.font = Font_Medium_Size(SCRYFrom(14))
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
     private func allOffAction() {
         if !routeTest {
             devices.forEach({
                 $0.isOn = false
                 // 关灯，记录关灯前的亮度值
                 if $0.lightness > 0 {
                     $0.trunOffLightness = $0.lightness
                 }
             })
             collectionView.reloadData()
         }
        MeshAPI.setAllOnOffState(isOn: false)
    }
    
    /// 全开
    private func allOnAction() {
        if !routeTest {
            devices.forEach({ $0.isOn = true })
            collectionView.reloadData()
        }
        MeshAPI.setAllOnOffState(isOn: true)
    }
    
    /// 设备调节
    @objc func deviceAllSetting() {
        if lightControlView.superview == nil {
            (self.wm_pageController?.view ?? view).addSubview(lightControlView)
//            view.addSubview(lightControlView)
        }
//        self.wm_pageController?.scrollEnable = false
        NotificationCenter.default.post(name: .init(spacePageDisableScrollNotificaitonName), object: 0)
        // 是否有设备支持cct控制
        let supportCct = devices.contains(where: { $0.temperatureModel != nil })
        lightControlView.supportOptions = supportCct ? [.level, .cct] : [.level]
        lightControlView.show()
        // 禁用侧滑返回手势
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
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
        if let indexPath = collectionView.indexPathForItem(at: point) {
            if indexPath.item == 0 { // 全部设备调节
                deviceAllSetting()
                
            }else if indexPath.item <= devices.count {
                let node = devices[indexPath.item - 1]
                if isEdit { // 不在编辑状态可以进入设备控制页
                    return
                }
                var deviceVc: UIViewController?
                switch node.deviceType {
                case .gateway:
//                    guard let gateway = GatewayModel.load(node: node) else {
//                        return
//                    }
//                    deviceVc = GatewayViewController(site: site, gateway: gateway)
                    break
//                    deviceVc = GatewayViewController(space: space, node: node)
                default:
                    deviceVc = DeviceLightViewController(space: space, node: node)
                }

//                let deviceVc = DaliMasterViewController(space: space, node: node)
                if let vc = deviceVc {
                    if isIPad {
                        vc.preferredContentSize = iPadPreferredContentSize
                    }
                    present(NavigationViewController(rootViewController: vc), animated: true)
                }
//                navigationController?.pushViewController(deviceVc, animated: true)
            }
        }
    }
    
    /// 更新全部设备UI状态
    private func reloadAllDevices() {
        devices.forEach({
            if let index = devices.firstIndex(of: $0), let item = collectionView.cellForItem(at: IndexPath(item: index + 1, section: 0)) as? DevicesViewCell {
                item.device = $0
                item.displayDeviceNamePrefix = space.displayDeviceNamePrefix
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
//            if isEdit {
//                if !node.state { // 离线
//                    if selectedAddresss.contains(node.primaryUnicastAddress) { // 是否编辑选中
//                        // 离线时清空选中地址数据
//                        selectedAddresss.removeAll(where: { $0 == node.primaryUnicastAddress })
//                        updateEditUI()
//                    }
//                }
//            }
            
            if let item = collectionView.cellForItem(at: IndexPath(item: index + 1, section: 0)) as? DevicesViewCell {
//                if isEdit {
//                    if node.state { // 离线->在线
//                        if item.selectImageView.isHidden {
//                            item.selectImageView.isHidden = false
//                            item.selectImageView.image = UIImage(named: selectedAddresss.contains(node.primaryUnicastAddress) ? "select" : "select_un")
//                        }
//                    }else { // 在线->离线
//                        item.selectImageView.isHidden = true
//                    }
//                }
                item.device = node
                item.displayDeviceNamePrefix = space.displayDeviceNamePrefix
            }
            
        }
        
        updateAllOnOffItemUI()
    }
    
    /// 筛选
    private func sort() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 10) {[weak self] nodes in
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
        }
        
    }
    
    private func deleteNodes() {
        
        guard selectedAddresss.count > 0 else {
            return
        }
//        guard MeshLibManager.manager.isMeshNetworkConnected else {
//            return
//        }
        
        
        let selectDevices = devices.filter({ node in selectedAddresss.contains(where: { $0 == node.primaryUnicastAddress }) })
        
        guard selectDevices.count > 0 else {
            return
        }
        
//        let alertView = SRAlertView(message: "devices_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, style: .destructive, actionHandler: {[weak self] _ in
//            guard let self = self else { return }
//            
//            // 提供重置的设备地址+超时时长list数据
//            var addressDataList: [(address: Address, timeout: TimeInterval)] = selectDevices.map({ ($0.primaryUnicastAddress, $0.state ? 10 : 2) })
//            // 如果重置节点中存在代理节点，将代理节点放到最后重置
//            if let proxyNode = selectDevices.first(where: { $0.isProxy }) {
//                addressDataList.removeAll(where: { $0.address == proxyNode.primaryUnicastAddress })
//                addressDataList.append((proxyNode.primaryUnicastAddress, 10))
//            }
//            isDeletingDevice = true
//            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
//            MeshAPI.resetNodes(addressDataList: addressDataList, resetSuccess: nil, resetFail: nil) {[weak self] successAddressList, failAddressList in
//                guard let self = self else { return }
//                self.isDeletingDevice = false
//                XWHUDManager.hide()
//                XWHUDManager.showSuccessTipHUD("done!".localizedString)
//                let networkManager = MeshNetworkManager.instance
//                selectDevices.forEach({
//                    networkManager.meshNetwork?.remove(node: $0)
//                    $0.deleteExtension()
//                })
//                self.isEdit = false
//                self.loadDevices()
//                // 通知space数据修改
//                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
//            }
//            
//        })])
//        // 存在离线设备
//        if selectDevices.contains(where: { !$0.state }) {
//            let messageAttStr = NSMutableAttributedString(string: "devices_force_delete_message".localizedString, attributes: [.foregroundColor: TextBlack_Color])
//            messageAttStr.append(NSAttributedString(string: "devices_force_delete_note".localizedString, attributes: [.foregroundColor: Message_Color]))
//            alertView.messageLabel.attributedText = messageAttStr
//        }
//        alertView.show()
        
        
        
        SRAlertView(title: "notification".localizedString, message: "devices_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            
            // 提供重置的设备地址+超时时长list数据
            var addressDataList: [(address: Address, timeout: TimeInterval)] = selectDevices.map({ ($0.primaryUnicastAddress, $0.state ? 10 : 2) })
            // 如果重置节点中存在代理节点，将代理节点放到最后重置
            if let proxyNode = selectDevices.first(where: { $0.isProxy }) {
                addressDataList.removeAll(where: { $0.address == proxyNode.primaryUnicastAddress })
                addressDataList.append((proxyNode.primaryUnicastAddress, 10))
            }
            
//            var resetAddressList = self.selectedAddresss
//            // 如果重置节点中存在代理节点，将代理节点放到最后重置
//            if let proxyNode = self.devices.first(where: { $0.isProxy }), self.selectedAddresss.contains(proxyNode.primaryUnicastAddress) {
//                resetAddressList.removeAll(where: { $0 == proxyNode.primaryUnicastAddress })
//                resetAddressList.append(proxyNode.primaryUnicastAddress)
//            }
            isDeletingDevice = true
            MeshAPI.resetNodes(addressDataList: addressDataList, resetSuccess: nil, resetFail: nil) {[weak self] successAddressList, failAddressList in
                XWHUDManager.hide()
                guard let self = self else { return }
                
                successAddressList.forEach({ address in
                    if let index = self.devices.firstIndex(where: { $0.primaryUnicastAddress == address }) {
                        let node = self.devices[index]
                        node.deleteExtension()
                        self.devices.remove(at: index)
                    }
                })
                
//                self.devices.removeAll(where: { successAddressList.contains($0.primaryUnicastAddress) })
                self.selectedAddresss.removeAll(where: { successAddressList.contains($0) })
                self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                self.space.luminairesCount = self.devices.count
                self.space.save()
                
                if failAddressList.isEmpty { // 删除成功
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    self.isEdit = false
                    self.updateUI()
                    self.isDeletingDevice = false
                    self.collectionView.reloadData()
                    if MeshNetworkManager.instance.realNodes.isEmpty, MeshLibManager.manager.isMeshNetworkConnected {
                        MeshLibManager.manager.close()
                    }
                    
                    // 通知space数据修改
//                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                    
                }else { // 删除失败（提示是否强制删除这部分设备）
                    
                    let alertView = SRAlertView(title: "notification".localizedString, actions: [SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                        self?.devices.removeAll(where: { successAddressList.contains($0.primaryUnicastAddress) })
                        self?.updateUI(reloadTableView: false)
                        self?.updateEditUI()
                        self?.isDeletingDevice = false
                        self?.collectionView.reloadData()
                        if successAddressList.count > 0 {
                            // 通知space数据修改
//                            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                        }
                        
                    }), SRAlertAction(title: "force_delete".localizedString, actionHandler: {[weak self] _ in
                        guard let self = self else { return }
                        let forceDeleteNodes = self.devices.filter({ failAddressList.contains($0.primaryUnicastAddress) })
                        forceDeleteNodes.forEach({
                            $0.deleteExtension()
                            MeshNetworkManager.instance.meshNetwork?.remove(node: $0)
                        })
//                        _ = self.space.meshManager?.save()
                        self.devices.removeAll(where: { failAddressList.contains($0.primaryUnicastAddress) })
                        self.isEdit = false
                        self.isDeletingDevice = false
                        self.selectedAddresss.removeAll()
                        self.updateUI()
                        self.collectionView.reloadData()
                        
                        self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                        self.space.luminairesCount = self.devices.count
                        self.space.save()
                        
                        XWHUDManager.showSuccessTipHUD("done!".localizedString)
                        // 通知space数据修改
                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                        
                    })])
                    let messageAttStr = NSMutableAttributedString(string: "devices_force_delete_message".localizedString, attributes: [.foregroundColor: TextBlack_Color])
                    messageAttStr.append(NSAttributedString(string: "devices_force_delete_note".localizedString, attributes: [.foregroundColor: Message_Color]))
                    alertView.messageLabel.attributedText = messageAttStr
                    alertView.show()
                }
            }
        })]).show()
        
    }
    
    
    /// 修复设备
    func repairNodes(nodes: [Node]) {
        if nodes.isEmpty  {
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
                guard let self = self else { return }
//                successList.forEach({
//                    $0.saveNodeInfo(meshUUID: self.space.meshUUID, networkKey: self.space.meshNetworkKey)
//                })
                if failList.isEmpty { // 全部修复成功
                    if successList.count > 0 {
                        if MeshLibManager.manager.bluetoothState == .poweredOn {
                            XWHUDManager.showSuccessTipHUD("complete!".localizedString)
                        }
                        self.getNodesState()
                    }
                }else { // 全部/部分修复失败
                    self.repairFailed(nodes: failList)
                }
//                complete?(successList, failList)
                self.updateUI()
                
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
                self.updateUI()
                
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//                MeshAPI.getNodeCTLState(address: node.primaryUnicastAddress)
            } keyBindFail: {[weak self] _ in
                XWHUDManager.hide()
                self?.updateUI()
//                complete?([], nodes)
                self?.repairFailed(nodes: nodes)
                
                // 通知space数据修改
//                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
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


extension DeviceLightsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return devices.count + (devices.count > 0 ? 1 : 0)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == 0 {// 全开全关
            let allControlCell = collectionView.dequeueReusableCell(withReuseIdentifier: "allControlCell", for: indexPath) as! DeviceAllOnOffViewCell
            if allOnOffState != .disable, let isOn = controlAllOn {
                allControlCell.state = isOn ? .on : .off
            }else {
                allControlCell.state = allOnOffState
            }
            return allControlCell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DevicesViewCell
        let device = devices[indexPath.item - 1]
        if isEdit {
            cell.selectImageView.isHidden = false
            cell.selectImageView.image = UIImage(named: selectedAddresss.contains(device.primaryUnicastAddress) ? "select" : "select_un")
        }else {
            cell.selectImageView.isHidden = true
        }
        cell.device = device
        cell.displayDeviceNamePrefix = space.displayDeviceNamePrefix
        // 编辑选中点击
        cell.editClickCallback = {[weak self] node in
            guard let self = self else { return }
            let address = node.primaryUnicastAddress
            if self.selectedAddresss.contains(address) {
                self.selectedAddresss.removeAll(where: { $0 == address })
            }else {
                self.selectedAddresss.append(address)
            }
            cell.selectImageView.image = UIImage(named: selectedAddresss.contains(device.primaryUnicastAddress) ? "select" : "select_un")
//            collectionView.reloadItems(at: [indexPath])
            self.updateEditUI()
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing * CGFloat(columnNum - 1)) / CGFloat(columnNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        if indexPath.item == 0 { // 全开/全关
            if let isOn = controlAllOn {
                controlAllOn = isOn
            }else {
                controlAllOn = allOnOffState == .on
            }
            controlAllOn = !controlAllOn!
            if controlAllOn! {
                allOnAction()
            }else {
                allOffAction()
            }
        }else { // 设备点击
            let node = devices[indexPath.row - 1]
            // 未绑定完成功能则修复设备
            guard node.isKeybindComplete else {
                // 判断是否有设备编辑/配置权限，没有则无响应
//                if space.deviceOperates.contains(.edit) {
                    self.repairNodes(nodes: [node])
//                }
                return
            }
//            if let model = node.sunricherVendorModel {
//                let data = Data.init(hex: "000000000000000000000000000000000000000000000000000000000000000000000000000000")
//                let testMessage = ExternalVendorMessage(parameters: data)
//                MeshAPI.sendMessage(message: testMessage, model: model)
//                return
//            }
            
            if node.state { // 设备在线
                node.isOn = !node.isOn
                if node.isOn {
                    if let lightness = node.trunOffLightness {
                        node.lightness = lightness
                    }
                }else { // 关灯，记录关灯前的亮度值
                    if node.lightness > 0 { // 关灯，记录关灯前的亮度值
                        node.trunOffLightness = node.lightness
                    }
                    node.lightness = 0
                }
//                if !node.isOn, node.lightness > 0 { // 关灯，记录关灯前的亮度值
//                    node.trunOffLightness = node.lightness
//                }
                
                reloadCollectionItem(node: node)
                MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn, ack: true)
//                if let model = node.sunricherVendorModel {
//                    MeshAPI.sendMessage(message: SunricherVendorSet(code: .lightSensorCalibrate, parameters: .lightSensorCalibrate(214)), model: model)
//                }
                
                
            }else { // 设备离线
                MeshAPI.getNodeOnOffState(address: node.primaryUnicastAddress)
            }
        }
        updateAllOnOffItemUI()
    }
    
}

extension DeviceLightsViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击排序回调
    func functionDidClickSort(view: SpaceFunctionFooterView) {
        sort()
    }
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        guard space.deviceOperates.contains(.add) else {
            return
        }
        let point = CGPoint(x: view.addBtn.center.x, y: SCREEN_HEIGHT - footerView.height)
        
        (self.parent as? DevicesViewController)?.addAction(point: point)
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        guard space.deviceOperates.contains(.edit) else {
            view.isEditing = false
            return
        }
        
        isEdit = editing
        
        //        allSelectBtn.isSelected = false
        //        allSelectBtn.backgroundColor = RGB(238, 238, 239)
        
        selectedAddresss.removeAll()
        footerView.deleteBtn.isEnabled = false
        updateUI(reloadTableView: false)
        collectionView.reloadData()
        //        CATransaction.setDisableActions(true)
        //        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        //        CATransaction.commit()
        
        updateEditUI()
    }
    
    /// 点击删除回调
    func functionDidClickDelete(view: SpaceFunctionFooterView) {
        deleteNodes()
    }
    
    /// 点击同步
    func functionDidClickSync(view: SpaceFunctionFooterView) {
//        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        let syncDevices = devices.filter({ $0.needSync })
        let vc = SyncDevicesViewController(type: .devices(syncDevices))
        vc.syncSuccessCallback = {[weak self] _ in
//            syncDevices.forEach({
//                self?.reloadCollectionItem(node: $0)
//            })
            self?.navigationController?.popViewController(animated: true)
            self?.updateUI()
        }
        vc.backActionCallback = {[weak self] _ in
            self?.updateUI()
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 进入调试删除页面
    func functionEnterIntoTestDelete(view: SpaceFunctionFooterView) {
        
        let vc = DeviceForceResetDevicePageController()
//        vc.deviceResetCallback = { devices in
//            
//        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
}

extension DeviceLightsViewController: DeviceLightControlViewDelegate {
    
    func lightControl(_ view: DeviceLightControlView, levelValueChanged level: Int, ended: Bool) {
        print("level: \(level)")
        
//        let lightness = UInt16(round(Double(level) / 100.0) * Double(UInt16.max))
        let ligheness = Node.getLightness(lightness100: level)
        MeshAPI.setAllLightnessState(lightness: ligheness)
        
        self.devices.forEach({
            // 记录关灯前亮度
            if $0.isOn && ligheness == 0 && $0.lightness > 0 {
                $0.trunOffLightness = $0.lightness
            }
            $0.isOn = ligheness > 0
            $0.lightness = ligheness
            // self.reloadCollectionItem(node: $0)
        })
        controlAllOn = ligheness > 0
        updateAllOnOffItemUI()
        
        self.collectionView.reloadData()
    }
    
    func lightControl(_ view: DeviceLightControlView, cctValueChanged cct: Int, ended: Bool) {
        print("cct: \(cct)")
        
        MeshAPI.sendMessage(message: LightCTLTemperatureSetUnacknowledged(temperature: UInt16(cct), deltaUV: 0), address: .subElementBroadcastGroupAddress)
//        MeshAPI.setAllNodesCTLState(lightness: ligheness, temperature: UInt16(cct))
//        MeshAPI.setAllColorTemperatureState(temperature: UInt16(cct), ack: ended)
        devices.forEach({
            $0.temperature = UInt16(cct)
//            reloadCollectionItem(node: $0)
        })
        updateAllOnOffItemUI()
        self.collectionView.reloadData()
    }
    
    func lightControlDidHide(_ view: DeviceLightControlView) {
        NotificationCenter.default.post(name: .init(spacePageDisableScrollNotificaitonName), object: nil)
        /// 启用导航控制器侧滑手势
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
    
    /// Auto
    func lightControlAutoAction(_ view: DeviceLightControlView) {
        guard view.autoState == .normal else {
            return
        }
        view.updateAutoStateUI(autoState: .progress)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
            self?.lightControlView.updateAutoStateUI(autoState: .normal)
        }
        devices.forEach({
            // profile第一阶段亮度，如果profile是daylight harvesting无法估算亮度则为nil
            if let lightLCOnLightness = $0.lightLCOnLightness {
                $0.lightness = lightLCOnLightness
                $0.isOn = lightLCOnLightness > 0
            }
        })
        updateAllOnOffItemUI()
        collectionView.reloadData()
        // 所有灯Auto
        MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(true), address: .subElementBroadcastGroupAddress)
    }
}

extension DeviceLightsViewController: DeviceGroupsViewDelegate {
    /// 选择/取消选择所有回调
    func view(_ view: DeviceGroupsView, didSelectAllAction selectAll: Bool) {
        
        if selectAll {
            selectedAddresss = devices.map({ $0.primaryUnicastAddress })
        }else {
            selectedAddresss.removeAll()
        }
        updateEditUI()
        collectionView.reloadData()
    }
    
    /// 筛选
    func viewDidSortAction(_ view: DeviceGroupsView) {
        
        sort()
    }
    
    /// 选中/取消选中Group/ALL回调
    func view(_ view: DeviceGroupsView, didSelectData data: DeviceGroupsSelectData) {
        
        if data.isSelected {
            let appendAddresss = data.addresss.filter({ !selectedAddresss.contains($0) })
            selectedAddresss.append(contentsOf: appendAddresss)
        }else {
            selectedAddresss.removeAll(where: { data.addresss.contains($0) })
        }
        updateEditUI()
//        footerView.deleteBtn.isEnabled = selectedAddresss.count > 0
        collectionView.reloadData()
    }
}

extension DeviceLightsViewController: MeshLibManagerDelegate, MeshLibManagerMessageDelegate {
    
    /// 蓝牙状态发生变化回调
    /// - Parameters:
    ///   - state: 蓝牙状态
    func meshNetworkManager(bluetoothDidUpdateState state: CBManagerState) {
        if state == .poweredOn && devices.count > 0 {
            // 获取设备信号
            MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 10, finished: nil)
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
            if !MeshNodeHeartbeatManager.shared.autoHeartbeatLoop {
                getNodesState()
            }
        }
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
 
    /// mesh设备数据更新
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - node: 更新的设备节点
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if view.window != nil {
            reloadCollectionItem(node: node)
        }
    }
    
    /// 设备数据修改时间戳更新
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdateTimeChange node: Node, lastUpdate: Int64) {
//        if node.lastUpdateSyncTime != lastUpdate {
            node.clearSyncStateCache()
//        }
    }
    
    /// 代理节点切换回调
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - bearer: 切换的代理
    func meshNetworkManager(_ manager: MeshNetworkManager, proxyDidReplace bearer: Bearer) {
        if view.window != nil {
            collectionView.reloadData()
        }
        NotificationCenter.default.post(name: .init(meshNetworkProxyDidReplaceNotificationName), object: nil)
    }
    
    /// 收到消息回调
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - message: 消息体
    ///   - source: 来源设备地址
    ///   - destination: 接收设备地址
    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: MeshMessage, sentFrom source: Address, to destination: Address) {
        EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)

        if let node = manager.meshNetwork?.node(withAddress: source), !node.isProvisioner {
            node.updateData(message: message)
            // 动能开关事件
            if MeshNodeHeartbeatManager.shared.heartbeatMode == .general {
                if message is LightLCLightOnOffSetUnacknowledged || message is GenericOnOffSetUnacknowledged || message is SceneRecallUnacknowledged {
                    //                reloadCollectionItem(node: node)
                    if view.window != nil {
                        collectionView.reloadData()
                        updateAllOnOffItemUI()
                    }
                }else if message is GenericMoveSetUnacknowledged {
                    if let moveLevelMessage = message as? GenericMoveSetUnacknowledged, moveLevelMessage.deltaLevel == 0 { // 动能开关长按结束
                        
                        /// 动能开关组设备list
                        var groupNodes: [Node] = []
                        if let group = manager.meshNetwork?.group(withAddress: destination) {
                            if group.isVirtual { // 虚拟组（动能开关）
                                groupNodes = manager.realNodes.filter({ $0.levelModels.contains(where: { $0.isSubscribed(to: group) }) })
                            }else { // 真实组
                                groupNodes = group.nodes.filter({ $0.lightnessModel != nil })
                            }
                        }
                        // 获取动能开关更新的设备列表状态
                        MeshNodeHeartbeatManager.shared.refresh(nodes: groupNodes)
                    }
                }
            }
        }
    }
    
}
