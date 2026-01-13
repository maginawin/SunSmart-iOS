//
//  GroupPathSequenceTriggerZoneController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/21.
//

import UIKit
import NordicSigMeshSDK

class GroupPathSequenceTriggerZoneController: UIViewController {

    let group: Group
    
    /// 路径区域list
    let zones: [GroupProximityLightingPathZone]
    var setZones: [GroupProximityLightingPathZone] = []
    private var tableView: UITableView!
    private var deviceAddView: GroupPathSequenceDeviceAddView!
    
    private var selectZone: GroupProximityLightingPathZone?
    
    private var deviceAddMode: PathSequenceDeviceAddMode = .quickAdd
    /// 快速添加状态
    private var quickAddState: QuickAddState = .stop
    /// 快速添加忙碌中，防止触发太频繁
    private var quickAddingBusy: Bool = false
    /// 是否展示已添加的设备（启用后使用过的设备可能重复使用）
    private var showAddedDevices: Bool = false
    /// 触发的设备list
    private var triggerDevices: [Node] = []
    
    init(group: Group, zones: [GroupProximityLightingPathZone]) {
        self.group = group
        self.zones = zones
        super.init(nibName: nil, bundle: nil)
        
        setZones = zones.compactMap({  $0.copy() })
        setZones.forEach({ zone in
            // 设备地址缓存与网络内实际设备数量对不上时，清掉已被删除的设备地址
            if zone.addresses.count != zone.nodes.count {
                zone.addresses.removeAll(where: { address in !MeshNetworkManager.instance.realNodes.contains(where: { $0.contains(elementWithAddress: address) }) })
            }
        })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = Background_Color
     
        setupUI()
        DispatchQueue.main.async {
            self.updateEmptyUI()
        }
        updateDeviceAddViewUI()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        MeshLibManager.manager.messageDelegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if let zone = selectZone, let section = setZones.firstIndex(of: zone) {
            selectZone = nil
            tableView.reloadSections(IndexSet(integer: section), with: .none)
            updateDeviceAddViewUI()
        }
    }
    
    private func updateEmptyUI() {
        if setZones.isEmpty {
//            view.layoutIfNeeded()
            tableView.showEmptyDataView(title: "no_trigger_zones".localizedString, backgroundColor: Background_Color, buttonText: "add_trigger_zone".localizedString, buttomWidth: SCRXFrom(216), position: .center, bottomMargin: SCRYFrom(20)) {[weak self] in
                self?.addZone()
            }
            tableView.isScrollEnabled = false
        }else {
            tableView.hideEmptyDataView()
            tableView.isScrollEnabled = true
        }
        
    }
    
    private func updateDeviceAddViewUI() {
        quickAddState = .stop
        if selectZone != nil {
            deviceAddView.canAddDevice = true
        }else {
            deviceAddView.canAddDevice = false
        }
    }
    
    func addZone() {
        
        let remainingZoneCount = GroupProximityLightingPathZone.maxZoneCount - setZones.count
        
         guard remainingZoneCount > 0 else {
            XWHUDManager.showTipHUD("not_zones_remaining", isLineFeed: true)
            return
        }
        
        let range = 1...remainingZoneCount
        
        SRAlertView(title: "add_trigger_zone".localizedString, message: String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), messageColor: Message_Color, inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 2, textAlignment: .center, showClear: true), actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)], textValueChangedBack: nil) {[weak self] text in
            guard let self = self, let number = Int(text), range.contains(number) else {
                XWHUDManager.showTipHUD(String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), isLineFeed: true)
                return
            }
            let list = GroupProximityLightingPathZone.default(count: number)
            self.setZones.append(contentsOf: list)
//            let indexPaths = list.enumerated().map({ self.setPaths.count + $0.offset - 1 })
            self.tableView.reloadData()
//            self.tableView.insertSections(IndexSet(indexPaths), with: .automatic)
            
//            self.tableView.insertRows(at: indexPaths, with: .automatic)
            self.updateEmptyUI()
        }.show()
        
    }
    
    /// 停止设置路径
    func stopSetZone() {
        selectZone = nil
        updateDeviceAddViewUI()
    }
    
    /// 区域操作
    private func zoneOperation(zone: GroupProximityLightingPathZone, type: GroupPathSequencePathHeaderView.OperationType) {
        
        switch type {
        case .save:
            break
        case .test:
            GroupPathSequencePathTestView(type: .zone, group: group, addresses: zone.addresses).show()
        case .reset:
          
            SRAlertView(title: "notification".localizedString, message: "path_reset_devices_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                zone.addresses.removeAll()
                if let section = self.setZones.firstIndex(of: zone), let cell = tableView.cellForRow(at: IndexPath(row: 0, section: section)) as? GroupPathSequenceTriggerZoneViewCell {
                    cell.reloadData(zoneIndex: section, zone: zone)
                }
//                self.reloadZone(zone)
                tableView.performBatchUpdates(nil)
                if self.deviceAddMode == .triggerAdd {
                    self.triggerDevices.removeAll()
                    deviceAddView.triggerAddView.reloadData(devices: self.triggerDevices, selectDevice: nil)
                    
                } else if self.deviceAddMode == .manuallyAdd {
                    let addedNodes = showAddedDevices ? zone.nodes : self.setZones.flatMap { $0.nodes }
                    let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
                    deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
                }
                
            })]).show()
            
        case .delete:
            SRAlertView(title: "notification".localizedString, message: "zone_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                if let index = self.setZones.firstIndex(of: zone) {
                    self.setZones.remove(at: index)
                    if self.selectZone == zone {
                        self.selectZone = nil
                        self.updateDeviceAddViewUI()
                    }
//                    if self.deviceAddMode == .manuallyAdd {
//                        let addedNodes = showAddedDevices ? zone.nodes : self.setZones.flatMap { $0.nodes }
//                        let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
//                        deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: deviceAddView.manuallyAddView.selectDevice)
//                    }
                    self.updateEmptyUI()
//                    self.tableView.deleteSections(IndexSet(integer: index), with: .fade)
                    self.tableView.reloadData()
                }
            })]).show()
        }
    }

    /// 刷新路径区域数据
    private func reloadZone(_ zone: GroupProximityLightingPathZone) {
        if let index = self.setZones.firstIndex(of: zone) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
    }
    
    private func setupUI() {
        
        deviceAddView = GroupPathSequenceDeviceAddView()
        deviceAddView.isSequence = false
        deviceAddView.quickAddView.guideView.steps = [
            .init(imageName: "proximity_lighting_step1", title: "zone_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "zone_add_step2".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "zone_quick_add_step3".localizedString, textColor: SubText_Color),
        ]
        
        deviceAddView.triggerAddView.guideView.steps = [
            .init(imageName: "proximity_lighting_step1", title: "zone_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "zone_add_step2".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "path_trigger_add_step3".localizedString, textColor: SubText_Color),
        ]
        
        deviceAddView.manuallyAddView.guideView.steps = [
            .init(imageName: "proximity_lighting_step1", title: "zone_add_step1".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step2", title: "path_trigger_add_step3".localizedString, textColor: SubText_Color),
            .init(imageName: "proximity_lighting_step3", title: "zone_manual_add_step3".localizedString, textColor: SubText_Color),
        ]
        
        deviceAddView.delegate = self
        view.addSubview(deviceAddView)
        deviceAddView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(-max(kSafeAreaBottomHeight, SCRYFrom(16)))
            make.height.greaterThanOrEqualTo(SCRYFrom(163))
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = RGB(236, 238, 239)
        tableView.layer.cornerRadius = SCRYFrom(10)
        tableView.register(GroupPathSequencePathHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(GroupPathSequenceTriggerZoneViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.estimatedRowHeight = isIPad ? SCRYFrom(90) : SCRYFrom(60)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
            make.bottom.equalTo(deviceAddView.snp.top)
        }
        
        
        
    }

}

extension GroupPathSequenceTriggerZoneController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return setZones.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! GroupPathSequenceTriggerZoneViewCell
        let zone = setZones[indexPath.section]
        cell.reloadData(zoneIndex: indexPath.section, zone: zone)
        cell.isSelect = zone == selectZone
        cell.delegate = self
        return cell
    }
    
//    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
//        return SCRYFrom(82)
//    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupPathSequencePathHeaderView
        let zone = setZones[section]
        headerView.isSelect = selectZone == zone
        headerView.nameLabel.text = "\("zone".localizedString) \(section + 1)"
        headerView.testBtn.isEnabled = zone.addresses.count > 0
        headerView.resetBtn.isEnabled = zone.addresses.count > 0
        headerView.operationActionCallback = {[weak self] type in
            guard let self = self else { return }
            self.zoneOperation(zone: setZones[section], type: type)
        }
        headerView.viewSelectActionCallback = {[weak self] in
            guard let self = self else { return }
            var reloadSections: [Int] = []
            if let zone = self.selectZone, let index = self.setZones.firstIndex(of: zone) {
                if index == section {
                    return
                }
                if let lastHeaderView = tableView.headerView(forSection: index) as? GroupPathSequencePathHeaderView {
                    lastHeaderView.isSelect = false
                }
                reloadSections.append(index)
            }
            reloadSections.append(section)
            self.selectZone = self.setZones[section]
            
            let addedNodes = showAddedDevices ? zone.nodes : self.setZones.flatMap { $0.nodes }
            // 更新触发添加、手动添加可选设备列表
            if self.deviceAddMode == .triggerAdd {
                deviceAddView.triggerAddView.reloadData(devices: triggerDevices.filter({ !addedNodes.contains($0) }), selectDevice: deviceAddView.triggerAddView.selectDevice)
            }else if self.deviceAddMode == .manuallyAdd {
                let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
                deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: deviceAddView.manuallyAddView.selectDevice)
            }
            
            self.tableView.reloadSections(IndexSet(reloadSections), with: .none)
            self.updateDeviceAddViewUI()
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(40)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
}

extension GroupPathSequenceTriggerZoneController: GroupPathSequenceTriggerZoneViewCellDelegate {
    
    
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, didSelectZone zone: GroupProximityLightingPathZone) {
        cell.isSelect = true
        
        // 选中当前section
        if let section = tableView.indexPath(for: cell)?.section, let headerView = tableView.headerView(forSection: section) as? GroupPathSequencePathHeaderView {
            headerView.isSelect = true
        }
        let lastSelectZone = self.selectZone
        
        self.selectZone = zone
        
        // 取消选中之前的section
        if let lastSelectZone = lastSelectZone, lastSelectZone != zone, let index = self.setZones.firstIndex(of: lastSelectZone) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
            
            // 更新触发添加、手动添加可选设备列表
            if self.deviceAddMode == .triggerAdd {
                triggerDevices.removeAll()
                deviceAddView.triggerAddView.reloadData(devices: triggerDevices, selectDevice: deviceAddView.triggerAddView.selectDevice)
            }else if self.deviceAddMode == .manuallyAdd {
                let addedNodes = showAddedDevices ? selectZone?.nodes ?? [] : setZones.flatMap { $0.nodes }
                let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
                deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: deviceAddView.manuallyAddView.selectDevice)
            }
        }
        
        updateDeviceAddViewUI()
    }
    
    /// 识别设备
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, deviceIdentify device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 删除设备
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, removeDevice device: Node) {
        guard let section = tableView.indexPath(for: cell)?.section else { return }
        let zone = setZones[section]
        zone.addresses.removeAll(where: { device.contains(elementWithAddress: $0) })
        cell.reloadData(zoneIndex: section, zone: zone)
        tableView.performBatchUpdates(nil)
    }
    
    /// 添加设备
    func cell(_ cell: GroupPathSequenceTriggerZoneViewCell, addDevice address: Address) {
        guard let section = tableView.indexPath(for: cell)?.section else { return }
        let zone = setZones[section]
        if !zone.addresses.contains(address) {
            zone.addresses.append(address)
//            cell.reloadData(zoneIndex: section, zone: zone)
//            tableView.performBatchUpdates(nil)
        }
        
        if self.deviceAddMode == .triggerAdd {
   
            if !zone.addresses.contains(address) {
                zone.addresses.append(address)
            }
            if let index = triggerDevices.firstIndex(where: { $0.contains(elementWithAddress: address) }) {
                triggerDevices.remove(at: index)
                deviceAddView.triggerAddView.reloadData(devices: triggerDevices, selectDevice: nil)
            }
            deviceAddView.refreshBtn.isHidden = triggerDevices.isEmpty
        }else if self.deviceAddMode == .manuallyAdd {
            let addedNodes = showAddedDevices ? selectZone?.nodes ?? [] : setZones.flatMap { $0.nodes }
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
            deviceAddView.updateUnfoldState()
        }
        tableView.reloadSections(IndexSet(integer: section), with: .none)
    }
}

extension GroupPathSequenceTriggerZoneController: GroupPathSequenceDeviceAddViewDelegate {
   
     
    /// 设备添加模式切换
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, deviceAddModeChanged mode: PathSequenceDeviceAddMode) {
        
        if self.deviceAddMode == .triggerAdd {
            triggerDevices.removeAll()
            deviceAddView.triggerAddView.reloadData(devices: triggerDevices, selectDevice: nil)
            deviceAddView.refreshBtn.isHidden = true
        }
        
        // 手动控制
        if mode == .manuallyAdd {
            let addedNodes = showAddedDevices ? selectZone?.nodes ?? [] : setZones.flatMap { $0.nodes }
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
            deviceAddView.updateUnfoldState()
        }
        
        self.deviceAddMode = mode
    }
    
    /// 已使用设备是否可重复使用选项更新 enabled true：可重复使用 false: 忽略
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, showAddedDevices enabled: Bool) {
        self.showAddedDevices = enabled
        
        let addedNodes = showAddedDevices ? selectZone?.nodes ?? [] : setZones.flatMap { $0.nodes }
        // 更新触发添加、手动添加可选设备列表
        if self.deviceAddMode == .triggerAdd {
            deviceAddView.triggerAddView.reloadData(devices: triggerDevices.filter({ !addedNodes.contains($0) }), selectDevice: deviceAddView.triggerAddView.selectDevice)
        }else if self.deviceAddMode == .manuallyAdd {
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: deviceAddView.manuallyAddView.selectDevice)
        }
        
    }
    
    /// 快速添加状态更新
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, quickAddStateChanged state: QuickAddState) {
        self.quickAddState = state
    }
    
    /// 选择设备回调
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, selectDevice device: Node) {
        guard let zone = selectZone else {
            return
        }
        let address = device.sunricherVendorModel?.parentElement?.unicastAddress ?? device.primaryUnicastAddress
        
        if self.deviceAddMode == .triggerAdd {
   
            if !zone.addresses.contains(address) {
                zone.addresses.append(address)
            }
            if let index = triggerDevices.firstIndex(of: device) {
                triggerDevices.remove(at: index)
                view.triggerAddView.reloadData(devices: triggerDevices, selectDevice: nil)
            }
            view.refreshBtn.isHidden = triggerDevices.isEmpty
            
        }else if self.deviceAddMode == .manuallyAdd {
            
            if !zone.addresses.contains(address) {
                zone.addresses.append(address)
            }
            
            let addedNodes = showAddedDevices ? selectZone?.nodes ?? [] : setZones.flatMap { $0.nodes }
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            view.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
            view.updateUnfoldState()
        }
        
        if let section = setZones.firstIndex(of: zone) {
            tableView.reloadSections(IndexSet(integer: section), with: .none)
        }
    }
    
    /// 识别设备回调
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, identifyDevice device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 触发添加设备刷新设备
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, triggerDevicesRefresh triggerView: GroupPathSequenceTriggerAddView) {
        
        triggerDevices.removeAll()
        triggerView.reloadData(devices: triggerDevices, selectDevice: nil)
    }
    
}

extension GroupPathSequenceTriggerZoneController: MeshLibManagerMessageDelegate {
    
    /// 收到消息回调
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - message: 消息体
    ///   - source: 来源设备地址
    ///   - destination: 接收设备地址
    func meshNetworkManager(_ manager: MeshNetworkManager,
                            didReceiveMessage message: MeshMessage,
                            sentFrom source: Address, to destination: Address) {
        // 确保是占用传感器model发出的数据
        guard let zone = selectZone else {
            return
        }
        // 触发设备地址
        var triggerAddress = source
        // pir是否触发
        var pirTrigger = false
        if let sensorStatus = message as? SensorStatus,
           let pirSensorValue = sensorStatus.values.first(where: { $0.property.id == DeviceProperty.presenceDetected.id }), case .bool(let presenceDetected) = pirSensorValue.value {
            pirTrigger = presenceDetected
        }
        /// 邻近照明pir触发信号
        if let vendorSet = message as? SunricherVendorSet, case .proximityLightingTrigger(_, let source) = vendorSet.function {
            pirTrigger = true
            triggerAddress = source
        }
        
        // 判断是否感应及感应的设备
        guard pirTrigger, let node = manager.realNodes.first(where: { $0.contains(elementWithAddress: triggerAddress) }), group.nodes.contains(node), deviceAddMode == .quickAdd || deviceAddMode == .triggerAdd else {
            return
        }
        
        let address = node.sunricherVendorModel?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
        
        // 判断zone list内是否已经有感应的设备
        let sameZones = setZones.filter({ $0.addresses.contains(address) })
        // 重复的设备不让添加到同一个zone内
        if showAddedDevices {
            if sameZones.contains(zone) {
                return
            }
        }else {
            // 重复的设备不让添加到zone内
            if sameZones.count > 0 {
                return
            }
        }
        
        switch deviceAddMode {
        case .quickAdd:
            if quickAddState == .adding, !quickAddingBusy { // 判断是否在添加中
                if !zone.addresses.contains(address) {
                    self.quickAddingBusy = true
                    // 防止触发太快，间隔200ms生效
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {[weak self] in
                        // 获取下一个空的point item
                        zone.addresses.append(address)
                        self?.reloadZone(zone)
                        self?.quickAddingBusy = false
                    }
                }
            }
        case .triggerAdd:
            if !triggerDevices.contains(node) {
                triggerDevices.append(node)
                deviceAddView.triggerAddView.reloadData(devices: triggerDevices, selectDevice: deviceAddView.triggerAddView.selectDevice)
                deviceAddView.refreshBtn.isHidden = false
            }
        default:
            break
        }
        
        
    }
    
}
