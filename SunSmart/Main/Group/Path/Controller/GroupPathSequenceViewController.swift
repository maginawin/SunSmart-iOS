//
//  GroupPathSequenceViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/14.
//

import UIKit
import NordicSigMeshSDK

class GroupPathSequenceViewController: UIViewController {

    let group: Group
    
    /// 路径list
    let paths: [GroupProximityLightingSequencePath]
    private var tableView: UITableView!
    private var deviceAddView: GroupPathSequenceDeviceAddView!
    
    var setPaths: [GroupProximityLightingSequencePath] = []
    private var selectPathData: GroupPathSequenceSelectData!
    
    private var deviceAddMode: PathSequenceDeviceAddMode = .quickAdd
    /// 快速添加状态
    private var quickAddState: QuickAddState = .stop
    /// 是否展示已添加的设备（启用后使用过的设备可能重复使用）
    private var showAddedDevices: Bool = false
    /// 触发的设备list
    private var triggerDevices: [Node] = []
    
    init(group: Group, paths: [GroupProximityLightingSequencePath]) {
        self.group = group
        self.paths = paths
        super.init(nibName: nil, bundle: nil)
        
        setPaths = paths.map({ $0.copy() })
        selectPathData = GroupPathSequenceSelectData()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
//        if setPaths.isEmpty {
//            setPaths = GroupProximityLightingSequencePath.default(count: 2)
//        }
        
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
    
    private func updateEmptyUI() {
        if setPaths.isEmpty {
//            view.layoutIfNeeded()
            tableView.showEmptyDataView(title: "no_sequences".localizedString, backgroundColor: Background_Color, buttonText: "add_sequence".localizedString, buttomWidth: SCRXFrom(216), position: .center) {[weak self] in
                self?.addPath()
            }
            tableView.isScrollEnabled = false
        }else {
            tableView.hideEmptyDataView()
            tableView.isScrollEnabled = true
        }
        
    }
    
    private func updateDeviceAddViewUI() {
        if selectPathData.isSelect {
            deviceAddView.canAddDevice = true
        }else {
            deviceAddView.canAddDevice = false
        }
    }
    
    func addPath() {
        
        let remainingPathCount = GroupProximityLightingSequencePath.maxPathCount - setPaths.count
        
         guard remainingPathCount > 0 else {
            XWHUDManager.showTipHUD("not_paths_remaining", isLineFeed: true)
            return
        }
        
        let range = 1...remainingPathCount
        
        SRAlertView(title: "add_sequence".localizedString, message: String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), messageColor: Message_Color, inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 2, textAlignment: .center, showClear: true), actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)], textValueChangedBack: nil) {[weak self] text in
            guard let self = self, let number = Int(text), range.contains(number) else {
                XWHUDManager.showTipHUD(String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), isLineFeed: true)
                return
            }
            let list = GroupProximityLightingSequencePath.default(count: number)
            self.setPaths.append(contentsOf: list)
//            let indexPaths = list.enumerated().map({ self.setPaths.count + $0.offset - 1 })
            self.tableView.reloadData()
//            self.tableView.insertSections(IndexSet(indexPaths), with: .automatic)
            
//            self.tableView.insertRows(at: indexPaths, with: .automatic)
            self.updateEmptyUI()
        }.show()
    }
    
    /// 路径操作
    private func pathOperation(path: GroupProximityLightingSequencePath,type: GroupPathSequencePathHeaderView.OperationType) {
        
        switch type {
        case .save:
            break
        case .test:
            break
        case .reset:
            SRAlertView(title: "notification".localizedString, message: "path_reset_devices_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
                
                path.items.forEach({ $0.address = nil })
                self?.reloadPath(path)
            })]).show()
            
        case .delete:
            SRAlertView(title: "notification".localizedString, message: "path_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                if let index = self.setPaths.firstIndex(of: path) {
                    self.setPaths.remove(at: index)
                    if self.selectPathData.path == path {
                        self.selectPathData.path = nil
                        self.selectPathData.item = nil
                        self.updateDeviceAddViewUI()
                    }
                    self.updateEmptyUI()
                    self.tableView.deleteSections(IndexSet(integer: index), with: .fade)
                }
            })]).show()
            
            break
        }
    }
    
    /// 刷新路径数据
    private func reloadPath(_ path: GroupProximityLightingSequencePath) {
        if let index = self.setPaths.firstIndex(of: path) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
    }
    
    /// 设置路径下一个item
    private func setNextPathItem() {
        guard let selectPathData = self.selectPathData, let path = selectPathData.path, let item = selectPathData.item else { return }
        // 获取下一个空的point item
        var nextItem: GroupProximityLightingSequencePath.GroupProximityLightingPathItem?
        
        if let itemIndex = path.items.firstIndex(of: item) {
          
            if selectPathData.direction == .left { // 左边 ←
                nextItem = path.items[0..<itemIndex].first(where: { $0.address == nil || $0.node == nil })
            }else { // 右边 →
                if itemIndex < path.items.count - 1 {
                    nextItem = path.items[itemIndex + 1..<path.items.count].first(where: { $0.address == nil || $0.node == nil })
                }
            }
            selectPathData.item = nextItem
            
            if nextItem == nil {
                updateDeviceAddViewUI()
            }
        }
        if let section = setPaths.firstIndex(of: path) {
            tableView.reloadRows(at: [IndexPath(row: 0, section: section)], with: .none)
        }
      
        
    }
    
    private func setupUI() {
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = RGB(236, 238, 239)
        tableView.layer.cornerRadius = SCRYFrom(10)
        tableView.register(GroupPathSequencePathHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(GroupPathSequencePathViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.estimatedRowHeight = UITableView.automaticDimension
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
            make.bottom.equalTo(-SCRYFrom(178) - kSafeAreaBottomHeight)
        }
        
        deviceAddView = GroupPathSequenceDeviceAddView()
        deviceAddView.delegate = self
        view.addSubview(deviceAddView)
        deviceAddView.snp.makeConstraints { make in
            make.left.right.equalTo(tableView)
            make.bottom.equalTo(-max(kSafeAreaBottomHeight, SCRYFrom(16)))
            make.height.equalTo(SCRYFrom(163))
        }
        
    }

}

extension GroupPathSequenceViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return setPaths.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! GroupPathSequencePathViewCell
        cell.reloadData(pathIndex: indexPath.section, path: setPaths[indexPath.section], reloadCollectionView: false)
        cell.selectPathData = selectPathData
        cell.delegate = self
        return cell
    }
    
//    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
//        return SCRYFrom(82)
//    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupPathSequencePathHeaderView
        let path = setPaths[section]
        headerView.isSelect = selectPathData.path == path
        headerView.testBtn.isEnabled = path.items.contains(where: { $0.address != nil })
//        headerView.resetBtn
        headerView.nameLabel.text = "\("path".localizedString) \(section + 1)"
        headerView.operationActionCallback = {[weak self] type in
            guard let self = self else { return }
            self.pathOperation(path: self.setPaths[section], type: type)
        }
        headerView.viewSelectActionCallback = {[weak self] in
            guard let self = self else { return }
            var reloadSections: [Int] = []
            if let path = self.selectPathData.path, let index = self.setPaths.firstIndex(of: path) {
                if index == section {
                    return
                }
                if let lastHeaderView = tableView.headerView(forSection: index) as? GroupPathSequencePathHeaderView {
                    lastHeaderView.isSelect = false
                }
                reloadSections.append(index)
            }
            reloadSections.append(section)
            self.selectPathData.path = self.setPaths[section]
            self.selectPathData.item = nil
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

extension GroupPathSequenceViewController: GroupPathSequencePathViewCellDelegate {
    
    /// 选择item路径方向
    /// - Parameters:
    ///   - cell: cell
    ///   - item: 选择的item
    ///   - itemIndex: item索引
    ///   - direction: 方向
    func cell(_ cell: GroupPathSequencePathViewCell, didSelectDirection item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem, direction: PathDirection) {
        
        guard let section = tableView.indexPath(for: cell)?.section else { return }
        
        
        var reloadSections: [Int] = []
        if let path = selectPathData.path, let lastSection = setPaths.firstIndex(of: path), section != lastSection {
            reloadSections.append(lastSection)
            
            if let lastHeaderView = tableView.headerView(forSection: lastSection) as? GroupPathSequencePathHeaderView {
                lastHeaderView.isSelect = false
            }
        }
        reloadSections.append(section)
        
        selectPathData.path = setPaths[section]
        selectPathData.item = item
        selectPathData.direction = direction
        
        tableView.reloadSections(IndexSet(reloadSections), with: .none)
        
        updateDeviceAddViewUI()
    }
    
    /// 添加item
    /// - Parameters:
    ///   - cell: cell
    ///   - count: 添加item数量
    ///   - insertIndex: 在哪个位置插入
    func cell(_ cell: GroupPathSequencePathViewCell, didAddItem count: Int, insertIndex: Int) {
        guard let index = tableView.indexPath(for: cell)?.section else { return }
        
        let path = setPaths[index]
        guard GroupProximityLightingSequencePath.maxPathItemCount - path.items.count >= count else {
            XWHUDManager.showTipHUD("not_points_remaining", isLineFeed: true)
            return
        }
        
        let items = GroupProximityLightingSequencePath.GroupProximityLightingPathItem.default(count: count)
        
        path.items.insert(contentsOf: items, at: insertIndex)
        cell.reloadData(pathIndex: index, path: path)
        tableView.performBatchUpdates(nil)
    }
    
    /// 识别item内设备
    func cell(_ cell: GroupPathSequencePathViewCell, deviceIdentify item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem) {
        guard let address = item.address else { return }
        MeshAPI.identify(address: address)
    }
    
    /// 删除item内设备
    func cell(_ cell: GroupPathSequencePathViewCell, removeDevice item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem) {
//        guard let section = tableView.indexPath(for: cell)?.section else { return }
        item.address = nil
        cell.reloadPathItem(item: item)

    }
    
    /// 删除item
    func cell(_ cell: GroupPathSequencePathViewCell, deleteItem item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem) {
        
        guard let section = tableView.indexPath(for: cell)?.section, let itemIndex = setPaths[section].items.firstIndex(of: item) else { return }
        let path = setPaths[section]
        path.items.remove(at: itemIndex)
        cell.reloadData(pathIndex: section, path: path)
        
        // 删除选中的item
        if selectPathData.path == setPaths[section] && selectPathData.item == item {
            selectPathData.item = nil
            cell.selectPathData = selectPathData
            
            updateDeviceAddViewUI()
        }
        
        tableView.performBatchUpdates(nil)
    }
    
}

extension GroupPathSequenceViewController: GroupPathSequenceDeviceAddViewDelegate {
    
    /// 设备添加模式切换
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, deviceAddModeChanged mode: PathSequenceDeviceAddMode) {
        if self.deviceAddMode == .triggerAdd {
            triggerDevices.removeAll()
            deviceAddView.triggerAddView.reloadData(devices: triggerDevices, selectDevice: nil)
            deviceAddView.refreshBtn.isHidden = true
        }
        self.deviceAddMode = mode
        
    }
    
    /// 已使用设备是否可重复使用选项更新 enabled true：可重复使用 false: 忽略
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, showAddedDevices enabled: Bool) {
        self.showAddedDevices = enabled
    }
    
    /// 快速添加状态更新
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, quickAddStateChanged state: QuickAddState) {
        self.quickAddState = state
    }
    
    /// 选择设备回调
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, selectDevice device: Node) {
        if self.deviceAddMode == .triggerAdd {
            if let selectPathData = selectPathData, let item = selectPathData.item {
                item.address = device.sunricherVendorModel?.parentElement?.unicastAddress ?? device.primaryUnicastAddress
                if let index = self.triggerDevices.firstIndex(of: device) {
                    self.triggerDevices.remove(at: index)
                    view.triggerAddView.reloadData(devices: self.triggerDevices, selectDevice: nil)
                }
                setNextPathItem()
            }
        }
    }
    
    /// 识别设备回调
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, identifyDevice device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 触发添加设备刷新事件
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, triggerDevicesRefresh triggerView: GroupPathSequenceTriggerAddView) {
        
        triggerDevices.removeAll()
        triggerView.reloadData(devices: triggerDevices, selectDevice: nil)
    }
    
}

extension GroupPathSequenceViewController: MeshLibManagerMessageDelegate {
    
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
        guard selectPathData.isSelect,
            let sensorStatus = message as? SensorStatus,
              let pirSensorValue = sensorStatus.values.first(where: { $0.property.id == DeviceProperty.presenceDetected.id }), case .bool(let presenceDetected) = pirSensorValue.value else {
            return
        }
        
        // 判断是否感应及感应的设备
        guard presenceDetected, let node = manager.realNodes.first(where: { $0.contains(elementWithAddress: source) }), deviceAddMode == .quickAdd || deviceAddMode == .triggerAdd else {
            return
        }
        
        guard let path = selectPathData.path, let item = selectPathData.item, group.nodes.contains(node) else {
            return
        }
        
        // 判断路径list内是否已经有感应的设备
        if let samePath = setPaths.first(where: { path in path.items.contains(where: { $0.address != nil && node.contains(elementWithAddress: $0.address!)  }) }) {
            
            // 重复的设备不让添加到路径
            if !showAddedDevices || path == samePath {
                return
            }
        }
        
        switch deviceAddMode {
        case .quickAdd:
            if quickAddState == .adding { // 判断是否在添加中
                
                item.address = node.sunricherVendorModel?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
                // 获取下一个空的point item
                setNextPathItem()
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
