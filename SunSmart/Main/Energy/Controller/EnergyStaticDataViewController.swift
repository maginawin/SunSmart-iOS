//
//  EnergyStaticDataViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/27.
//

import UIKit
import NordicSigMeshSDK

/// 静态能耗数据通信通知
let energyStaticDataUpdateNotificationName = "EnergyStaticDataUpdateNotification"

class EnergyStaticDataViewController: UIViewController {
    
    /// 能耗数据显示类型
    enum EnergyViewType {
        
        var title: String {
            switch self {
            case .space:
                return "space".localizedString
            case .group:
                return "group".localizedString
            case .device:
                return "device".localizedString
            }
        }
        
        /// 空间
        case space
        /// 组
        case group
        /// 设备
        case device
    }
    
    /// 能耗类型
    enum StatisticsType {
        
        var title: String {
            switch self {
            case .all:
                return "all_statistics".localizedString
            case .realPower:
                return "true_power_meter".localizedString
            case .manualDataEnrty:
                return "manual_data_entry".localizedString
            }
        }
        
        /// 所有
        case all
        /// 真实功耗（dali）
        case realPower
        /// 手动输入功耗
        case manualDataEnrty
    }
    
    /// 设备能耗排序
    enum DeviceEnergySortType {
        /// 降序（从高到低）
        case descending
        /// 升序（从低到高）
        case ascending
    }
    
    private var energyReportLabel: UILabel!
    private var statisticsTypeBtn: UIButton!
    private var viewTypeBtn: UIButton!
    /// 空间
    private var energySpaceView: EnergyStaticDataSpaceView!
    /// 组
    private var energyGroupView: EnergyStaticDataGroupView!
    /// 设备
    private var devicesTableView: UITableView!
    private var deviceSortBtn: UIButton!
    private var deviceFilterBtn: UIButton!
    /// 显示类型
    private var viewType: EnergyViewType = .space
    /// 能耗数据过滤类型
    private var statisticsFilterType: StatisticsType = .all
    /// 设备筛选类型，Group / NotInGroup
    private var deviceFilterType: GroupFilterSelectView.FilterType?
    /// 设备排序类型
    private var deviceSortType: DeviceEnergySortType = .descending
    /// 有统计数据的组list
    private var groups: [Group] = []
    /// 统计数据设备list
    private var devices: [DeviceTotalEnergyData] = []
    /// 页面展示的设备list
    private var showDevices: [DeviceTotalEnergyData] = []
    /// 最近采集的数据
    private var latestHarvestData: EnergyStatisticsStaticData?
    /// 更早采集的数据
    private var previousHarvestData: EnergyStatisticsStaticData?
    /// 组能耗统计数据
    private var groupEnergyPieDatas: [EnergyPieData] = []
    
    let space: SpaceData
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
        
//        groups = MeshNetworkManager.instance.groups
//        devices = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .light })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if self.wm_pageController == nil {
            title = "static_data".localizedString
            navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        }
        
        view.backgroundColor = Background_Color
        
        setupData()
        
        setupUI()
        
        updateUI()
        
        // 更新能耗数据
        NotificationCenter.default.addObserver(forName: .init(energyStaticDataUpdateNotificationName), object: nil, queue: nil) {[weak self] _ in
            self?.setupData()
            self?.updateUI()
        }
//        energySpaceView.updateData(latestHarvestData: self.latestHarvestData, previousHarvestData: self.previousHarvestData)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if self.devicesTableView.firstShowFlashScrollIndicators {
            self.devicesTableView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    @objc private func back() {
        dismiss(animated: true)
    }
    
    private func setupData() {
        
        let staticDatas = EnergyStatisticsStaticData.load(spaceId: space.id)
        
        latestHarvestData = staticDatas.first
        if staticDatas.count > 1 {
            previousHarvestData = staticDatas[1]
        }
        
        // Group数据
        if let harvestData = latestHarvestData {
            groups.removeAll()
            // 未在组里的设备能耗数据list
            let notInGroupDeviceEnergyDatas = harvestData.deviceEnergyDatas.filter({ deviceEnergyData in deviceEnergyData.groupAddress == nil })
            
            let colors = UIColor.generateDistinctColors(count: harvestData.groups.count + (notInGroupDeviceEnergyDatas.count > 0 ? 1 : 0))
            
            var energyPieDatas: [EnergyPieData] = []
            
            
            for (index, group) in harvestData.groups.enumerated() {
                
                let deviceEnergyDatas = harvestData.deviceEnergyDatas.filter({ deviceEnergyData in deviceEnergyData.groupAddress == group.address.address })
                
                let total = deviceEnergyDatas.reduce(UInt64(0)) { partial, energyData in
                    partial + UInt64(energyData.preciseTotalEnergyUse ?? 0)
                }
                let percent = Double(total) / Double(max(harvestData.preciseTotalEnergyUse, 1))
                
                let data = EnergyPieData(name: group.name, color: colors[index], percent: percent, data: String(format: "%.3f kWh", Double(total) / 1000))
                energyPieDatas.append(data)
                if deviceEnergyDatas.count > 0 {
                    groups.append(group)
                }
            }
            
            // 不在组里面设备能耗数据
            if notInGroupDeviceEnergyDatas.count > 0 {
                
                let total = notInGroupDeviceEnergyDatas.reduce(UInt64(0)) { partial, energyData in
                    partial + UInt64(energyData.preciseTotalEnergyUse ?? 0)
                }
                let percent = Double(total) / Double(max(harvestData.preciseTotalEnergyUse, 1))
                
                let data = EnergyPieData(name: "not_in_group".localizedString, color: colors.last!, percent: percent, data: String(format: "%.3f kWh", Double(total) / 1000))
                energyPieDatas.append(data)
            }
            groupEnergyPieDatas = energyPieDatas
            
            groups = harvestData.groups
            devices = harvestData.deviceEnergyDatas
        }else {
            viewType = .space
            groupEnergyPieDatas = []
            groups = []
            devices = []
        }
        
    }
    
    
    private func convertDeviceTotalEnergyDatas(nodes: [Node], failedNodes: [Node]) {
        
        let timestamp = Int64(Date().timeIntervalSince1970)
        let enrtgyDatas = nodes.map({ node in
            // 状态
            var state: DeviceTotalEnergyData.State = failedNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) ? .failed : .success
            // 最大功率
            var maxRatedPower: UInt16?
            /// 最大功率下已使用总能耗 W/h
            var totalDeviceEnergyUse: UInt32?
            /// 准确的已使用总能耗 W/h
            var preciseTotalEnergyUse: UInt32?
            // 采集成功状态下才记录最新数据
            if state == .success {
                totalDeviceEnergyUse = node.totalDeviceEnergyUse
                preciseTotalEnergyUse = node.preciseTotalDeviceEnergyUse
            }
            
            if node.phaseEnergyConsumptions.isEmpty {
                state = .notSetPower
            }else {
                maxRatedPower = (node.phaseEnergyConsumptions.first(where: { $0.percent == 100 }) ?? node.phaseEnergyConsumptions.last)?.power
            }
            return DeviceTotalEnergyData(name: node.name ?? "", address: node.primaryUnicastAddress, productId: node.productIdentifier, groupAddress: node.group?.address.address, timestamp: timestamp, maxRatedPower: maxRatedPower, maxTotalEnergyUse: totalDeviceEnergyUse, preciseTotalEnergyUse: preciseTotalEnergyUse, state: state)
        })
        
        let staticData = EnergyStatisticsStaticData(timestamp: timestamp, incomplete: failedNodes.count > 0, deviceEnergyDatas: enrtgyDatas, groups: MeshNetworkManager.instance.groups)
        staticData.save(spaceId: space.id)
        
        setupData()
        // 更新数据
        updateUI()
    }
    
    /// 读取mesh设备能耗
    private func readMeshDevicesEnergy() {
        
        let nodes = MeshNetworkManager.instance.realNodes
        let vc = ReadDevicesDataViewController(type: .harvestData(nodes: nodes))
        vc.readSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            // 保存采集的设备总能耗
            self.convertDeviceTotalEnergyDatas(nodes: nodes, failedNodes: [])
        }
        vc.harvestEnergyUseIncompleteDataCallback = {[weak self] result in
            // 使用缺失的能耗数据
            var failedNodes: [Node] = []
            result.forEach { failedData in
                failedNodes.append(failedData.node)
            }
            // 保存采集的设备总能耗
            self?.convertDeviceTotalEnergyDatas(nodes: nodes, failedNodes: failedNodes)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func updateUI() {
        
        viewTypeBtn.setTitle(viewType.title, for: .normal)
        
        switch viewType {
        case .space:
            energySpaceView.isHidden = false
            energyGroupView.isHidden = true
            devicesTableView.isHidden = true
            deviceSortBtn.isHidden = true
            deviceFilterBtn.isHidden = true
            energySpaceView.updateData(latestHarvestData: self.latestHarvestData, previousHarvestData: self.previousHarvestData, statisticsType: self.statisticsFilterType)
        case .group:
            energySpaceView.isHidden = true
            energyGroupView.isHidden = false
            devicesTableView.isHidden = true
            deviceSortBtn.isHidden = true
            deviceFilterBtn.isHidden = true
            var groupEnergyPieDatas = self.groupEnergyPieDatas
            if statisticsFilterType == .realPower {
                groupEnergyPieDatas = self.groupEnergyPieDatas.map({ EnergyPieData(name: $0.name, color: $0.color, percent: 0, data: "0.00 kWh") })
            }
            energyGroupView.updateData(latestHarvestData: self.latestHarvestData, energyPieDatas: groupEnergyPieDatas, statisticsType: self.statisticsFilterType)
        case .device:
            energySpaceView.isHidden = true
            energyGroupView.isHidden = true
            devicesTableView.isHidden = false
            deviceSortBtn.isHidden = false
            deviceFilterBtn.isHidden = false
            deviceFilterBtn.isSelected = deviceFilterType != nil
            if devices.isEmpty {
                devicesTableView.showEmptyDataView(title: "no_devices".localizedString)
            }
            // 筛选条件
            if let filterType = deviceFilterType {
                switch filterType {
                case .notInGroup:
                    showDevices = devices.filter({ $0.groupAddress == nil })
                case .group(let group):
                    showDevices = devices.filter({ $0.groupAddress == group.address.address })
                }
            }else {
                showDevices = devices
            }
            
            switch statisticsFilterType {
            case .all:
                break
            case .realPower:
                showDevices = []
            case .manualDataEnrty:
                showDevices = showDevices.filter({ $0.state != .notSetPower })
            }
            
            // 排序
            if deviceSortType == .descending {
                showDevices.sort(by: { ($0.preciseTotalEnergyUse ?? 0) > ($1.preciseTotalEnergyUse ?? 0) })
            }else {
                showDevices.sort(by: { ($0.preciseTotalEnergyUse ?? 0) < ($1.preciseTotalEnergyUse ?? 0) })
            }
            devicesTableView.reloadData()
        }

    }
    
    /// 过滤数据类型
    @objc private func statisticsTypeBtnAction(sender: UIButton) {
        let types: [StatisticsType] = [.all, .realPower, .manualDataEnrty]
        let selectIndex = types.firstIndex(of: statisticsFilterType)
        let menuWidth = SCRXFrom(164)
        let touchPoint = CGPoint(x: view.width - menuWidth - SCRXFrom(16), y: sender.frame.maxY + SCRYFrom(2))
        let menuPoint = view.convert(touchPoint, to: UIApplication.shared.keyWindow())
        
        TitleSelectView.show(titles: types.map({ $0.title }), anchorPoint: menuPoint, selectIndex: selectIndex ?? 0, menuWidth: menuWidth) {[weak self] index in
            guard let self = self else { return }
            self.statisticsFilterType = types[index]
            sender.setTitle(types[index].title, for: .normal)
            sender.sizeToFit()
            sender.setImagePosition(position: .right, spacing: SCRXFrom(4))
            self.updateUI()
            
//            self.devicesTableView.reloadData()
        }
        
    }
    
    /// 显示类型
    @objc private func viewTypeBtnAction(sender: UIButton) {
        
        let types: [EnergyViewType] = [.space, .group, .device]
        let selectIndex = types.firstIndex(of: viewType)
        let touchPoint = CGPoint(x: sender.frame.origin.x, y: sender.frame.maxY + SCRYFrom(2))
        let menuPoint = view.convert(touchPoint, to: UIApplication.shared.keyWindow())
        
        TitleSelectView.show(titles: types.map({ $0.title }), anchorPoint: menuPoint, selectIndex: selectIndex ?? 0, menuWidth: sender.width) {[weak self] index in
            guard let self = self else { return }
            if self.latestHarvestData == nil, types[index] != .space {
                XWHUDManager.showTipHUD("no_data".localizedString, isLineFeed: true)
                return
            }
            self.viewType = types[index]
            self.updateUI()
        }
    }
    
    /// 设备筛选
    @objc private func deviceFilterBtnAction() {
        
        GroupFilterSelectView(filters: GroupFilterSelectView.FilterData.defalutFilters(groups: self.groups), selectFilterType: deviceFilterType, selectCallback: {[weak self] filterType in
            guard let self = self else { return }
            self.deviceFilterType = filterType
            self.updateUI()
            self.devicesTableView.reloadData()
        }).show()
    }
    
    /// 设备排序
    @objc private func deviceSortBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        deviceSortType = sender.isSelected ? .ascending : .descending
        updateUI()
    }
    
    private func setupUI() {
        
        energyReportLabel = UILabel(text: "energy_report".localizedString, textColor: TextBlack_Color, fontSize: 14)
        view.addSubview(energyReportLabel)
        energyReportLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(28))
            make.top.equalTo(SCRYFrom(24))
        }
        
        statisticsTypeBtn = UIButton(title: "all_statistics".localizedString, titleSize: 13, titleColor: TextBlack_Color, normalImageName: "arrow_down_black", target: self, action: #selector(statisticsTypeBtnAction))
        statisticsTypeBtn.setImagePosition(position: .right, spacing: SCRXFrom(4))
        view.addSubview(statisticsTypeBtn)
        statisticsTypeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(energyReportLabel)
        }
        
        viewTypeBtn = UIButton(title: "space".localizedString, titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "arrow_down", target: self, action: #selector(viewTypeBtnAction))
        viewTypeBtn.contentHorizontalAlignment = .left
        viewTypeBtn.layer.cornerRadius = SCRYFrom(5)
        viewTypeBtn.layer.borderWidth = 1
        viewTypeBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        viewTypeBtn.backgroundColor = .white
        view.addSubview(viewTypeBtn)
        viewTypeBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(energyReportLabel.snp.bottom).offset(SCRYFrom(16))
            make.width.equalTo(SCRXFrom(128))
            make.height.equalTo(SCRYFrom(32))
        }
        viewTypeBtn.layoutIfNeeded()
        viewTypeBtn.imageView?.sizeToFit()
        let imageW = viewTypeBtn.imageView?.image?.size.width ?? 0
        viewTypeBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: viewTypeBtn.width - imageW, bottom: 0, right: 0)
        viewTypeBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8) - imageW, bottom: 0, right: imageW + SCRXFrom(6))
        
        energySpaceView = EnergyStaticDataSpaceView()
        energySpaceView.delegate = self
        view.addSubview(energySpaceView)
        energySpaceView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(viewTypeBtn.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview()
        }
        
        energyGroupView = EnergyStaticDataGroupView()
        energyGroupView.isHidden = true
        view.addSubview(energyGroupView)
        energyGroupView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(-max(kSafeAreaBottomHeight, SCRYFrom(16)))
            make.top.equalTo(energySpaceView)
        }
        
        
        deviceFilterBtn = UIButton(normalImageName: "filter", selectedImageName: "filter_selected", target: self, action: #selector(deviceFilterBtnAction))
        deviceFilterBtn.isHidden = true
        view.addSubview(deviceFilterBtn)
        deviceFilterBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(viewTypeBtn)
        }
        
        deviceSortBtn = UIButton(normalImageName: "order_down", selectedImageName: "order_up", target: self, action: #selector(deviceSortBtnAction))
        deviceSortBtn.isHidden = true
        view.addSubview(deviceSortBtn)
        deviceSortBtn.snp.makeConstraints { make in
            make.right.equalTo(deviceFilterBtn.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(deviceFilterBtn)
        }
        
        devicesTableView = UITableView()
        devicesTableView.separatorStyle = .none
        devicesTableView.register(EnergyStaticDataDeviceViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        devicesTableView.rowHeight = SCRYFrom(72)
        devicesTableView.backgroundColor = .clear
        devicesTableView.dataSource = self
        devicesTableView.delegate = self
        devicesTableView.isHidden = true
        view.addSubview(devicesTableView)
        devicesTableView.snp.makeConstraints { make in
            make.left.right.top.equalTo(energyGroupView)
            make.bottom.equalToSuperview()
        }
        
        
        
    }


}

extension EnergyStaticDataViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return showDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! EnergyStaticDataDeviceViewCell
        let device = showDevices[indexPath.row]
//        cell.device = device
//        cell.selectState = .none
        cell.deviceImageView.image =  UIImage(named: device.iconName ?? "device_unknown")
        cell.nameLabel.text = device.name
        switch device.state {
        case .success:
            if let preciseTotalEnergyUse = device.preciseTotalEnergyUse {
                cell.energyLabel.text = String(format: "%.3f kWh", Double(preciseTotalEnergyUse) / 1000)
            }else {
                cell.energyLabel.text = "--"
            }
        case .failed:
            cell.energyLabel.text = "collection_failed".localizedString
        case .notSetPower:
            cell.energyLabel.text = "invalid_power_value".localizedString
        }
        
        cell.groupNameLabel.text = latestHarvestData?.groups.first(where: { $0.address.address == device.groupAddress })?.name ?? "not_in_group".localizedString
        cell.onBtn.isSelected = device.selectOn
        cell.offBtn.isSelected = device.selectOff
        cell.delegate = self
        cell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: 0) - 1)
        return cell
    }
    
}

extension EnergyStaticDataViewController: EnergyStaticDataDeviceViewCellDelegate {
  
    /// 设备identity事件
    func deviceCellIdentifyAction(_ cell: EnergyStaticDataDeviceViewCell) {
        guard let index = devicesTableView.indexPath(for: cell)?.row else { return }
        MeshAPI.identify(address: showDevices[index].address)
    }
    
    /// 设备onoff事件
    func cell(_ cell: EnergyStaticDataDeviceViewCell, deviceOnOffAction isOn: Bool) {
        guard let index = devicesTableView.indexPath(for: cell)?.row else { return }
        let device = showDevices[index]
        device.selectOn = isOn
        device.selectOff = !isOn
        
        cell.onBtn.isSelected = device.selectOn
        cell.offBtn.isSelected = device.selectOff
        MeshAPI.setNodeOnOffState(address: device.address, isOn: isOn, ack: true)
    }

    
}

extension EnergyStaticDataViewController: EnergyStaticDataSpaceViewDelegate {
    
    /// 采集新的能耗数据事件
    func spaceViewHarvestNewEnergyDataAction(_ view: EnergyStaticDataSpaceView) {
        // 网络是否已连接
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        // 有能耗统计设备
//        if MeshNetworkManager.instance.dongles.count > 0 {
//            let selectView = EnergyHarvestSelectView(frame: UIScreen.main.bounds)
//            selectView.delegate = self
//            selectView.show()
//        }else { // 无能耗统计设备
            readMeshDevicesEnergy()
//        }
        
    }
    
    /// 查看历史采集的能耗数据事件
    func spaceViewViewHarvestHistoryAction(_ view: EnergyStaticDataSpaceView) {
        
        let vc = EnergyHarvestHistoryViewController(space: space)
        navigationController?.pushViewController(vc, animated: true)
    }
    
}

extension EnergyStaticDataViewController: EnergyHarvestSelectViewDelegate {
    
    /// 选择能耗采集设备获取能耗
    func view(_ view: EnergyHarvestSelectView, energyStorageDeviceHarvest device: Node) {
        
        let state = EnergyHarvestStateView(frame: UIScreen.main.bounds)
        DispatchQueue.global().async {
            DispatchQueue.main.async {
                state.update(state: .connect)
            }
            Thread.sleep(forTimeInterval: 1.5)
            
            DispatchQueue.main.async {
                state.update(state: .inProgress(progress: 20, estimatedTime: "5 minutes"))
            }
            Thread.sleep(forTimeInterval: 1.5)
            DispatchQueue.main.async {
                if arc4random_uniform(2) == 1 {
                    state.update(state: .completed)
                }else {
                    state.update(state: .failure(message: "unstable_signal".localizedString))
                }
            }
        }
        state.show()
        
    }
    
    /// 能耗采集设备识别
    func view(_ view: EnergyHarvestSelectView, energyStorageDeviceIdentify device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 刷新能耗采集设备
    func view(_ view: EnergyHarvestSelectView, energyStorageDevicesRefresh devices: [Node]) {
        
        devices.forEach({ $0.rssi = nil })
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 9.6) { _ in
            view.storageDevices = devices.sorted(by: { $0.rssi ?? -99 >= $1.rssi ?? -99 })
        }
        
    }
    
    /// 选择mesh设备获取能耗
    func meshDevicesEnergyHarvest(_ view: EnergyHarvestSelectView) {
        readMeshDevicesEnergy()
    }
    
}
 
fileprivate extension DeviceTotalEnergyData {
    
    static var selectOnKey: UInt8 = 0
    static var selectOffKey: UInt8 = 0
    
    /// 是否选中On
    var selectOn: Bool {
        get {
            objc_getAssociatedObject(self, &DeviceTotalEnergyData.selectOnKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &DeviceTotalEnergyData.selectOnKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否选中Off
    var selectOff: Bool {
        get {
            objc_getAssociatedObject(self, &DeviceTotalEnergyData.selectOffKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &DeviceTotalEnergyData.selectOffKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
