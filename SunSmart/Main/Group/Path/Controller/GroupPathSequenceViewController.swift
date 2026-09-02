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
    private let deviceNameFilterSession: DeviceNameFilterSession
    
    let groupPath: GroupProximityLightingPathData
    /// 路径list
//    let paths: [GroupProximityLightingSequencePath]
    private var tableView: UITableView!
    private var deviceAddView: GroupPathSequenceDeviceAddView!
    private var deviceAddViewHeightConstraint: NSLayoutConstraint?
    private var deviceAddContentHeight: CGFloat = 0
    private var allowDeviceAddAnimations = false
    private var didApplyInitialEmptyState = false
    
    var setPaths: [GroupProximityLightingSequencePath] = []
    private var selectPathData: GroupPathSequenceSelectData!
    
    private var deviceAddMode: PathSequenceDeviceAddMode = .quickAdd
    /// 快速添加状态
    private var quickAddState: QuickAddState = .stop
    /// 快速添加忙碌中，防止触发太频繁
    private var quickAddingBusy: Bool = false
    /// 是否展示已添加的设备（启用后使用过的设备可能重复使用）
    private var showAddedDevices: Bool = false
    /// 触发的设备list
    private var triggerDevices: [Node] = []
    
    init(
        group: Group,
        groupPath: GroupProximityLightingPathData,
        deviceNameFilterSession: DeviceNameFilterSession
    ) {
        self.group = group
        self.groupPath = groupPath
        self.deviceNameFilterSession = deviceNameFilterSession
//        self.paths = paths
        super.init(nibName: nil, bundle: nil)
        
        setPaths = groupPath.paths.map({ $0.copy() })
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
        view.layoutIfNeeded()
        updateEmptyUI()
        updateDeviceAddViewUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        MeshLibManager.manager.messageDelegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        allowDeviceAddAnimations = true
        
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        synchronizeDeviceAddViewHeight()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        synchronizeDeviceAddViewHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didApplyInitialEmptyState else {
            return
        }
        didApplyInitialEmptyState = true
        updateEmptyUI()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
    }
    
    private func updateEmptyUI() {
        if setPaths.isEmpty {
            tableView.layoutIfNeeded()
            UIView.performWithoutAnimation {
                view.showEmptyDataView(title: "no_sequences".localizedString, backgroundColor: Background_Color, buttonText: "add_sequence".localizedString, buttomWidth: SCRXFrom(216), position: .center, bottomMargin: SCRYFrom(100)) {[weak self] in
                    self?.addPath()
                }
                view.emptyView?.snp.makeConstraints { make in
                    make.edges.equalTo(tableView)
                }
            }
            tableView.isScrollEnabled = false
        }else {
            view.hideEmptyDataView()
            tableView.isScrollEnabled = true
        }
        updateDeviceAddViewUI()
    }
    
    private func updateDeviceAddViewUI() {
        let hasPaths = !setPaths.isEmpty
        let hasSelectedPath = selectPathData.path != nil
        let shouldAnimate = allowDeviceAddAnimations && view.window != nil
        updateDeviceAddViewHeader()
        if hasPaths {
            deviceAddView.isHidden = false
            deviceAddView.alpha = 1
            if hasSelectedPath {
                deviceAddView.setCollapsed(false, animated: shouldAnimate)
            }
            deviceAddView.canAddDevice = hasSelectedPath
            deviceAddView.refreshPreferredHeight()
        } else {
            deviceAddView.canAddDevice = false
            quickAddState = .stop
            updateDeviceAddViewHeight(0, animated: shouldAnimate)
            deviceAddView.alpha = 0
            deviceAddView.isHidden = true
        }
    }

    private func updateDeviceAddViewHeader() {
        let index = selectPathData.path.flatMap { setPaths.firstIndex(of: $0) }.map { $0 + 1 }
        deviceAddView.updateHeaderIndex(index)
    }

    private func updateDeviceAddViewHeight(_ contentHeight: CGFloat, animated: Bool) {
        deviceAddContentHeight = contentHeight
        let safeHeight = contentHeight <= 0
            ? 0
            : max(contentHeight, 44) + view.safeAreaInsets.bottom
        guard abs((deviceAddViewHeightConstraint?.constant ?? 0) - safeHeight) > 0.5 else {
            return
        }
        deviceAddViewHeightConstraint?.constant = safeHeight
        guard animated else {
            return
        }
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }

    private func synchronizeDeviceAddViewHeight() {
        updateDeviceAddViewHeight(deviceAddContentHeight, animated: false)
    }
    
    func deselectPath() {
        if let path = selectPathData.path, let section = setPaths.firstIndex(of: path) {
            selectPathData.path = nil
            selectPathData.item = nil
            tableView.reloadSections(IndexSet(integer: section), with: .none)
            updateDeviceAddViewUI()
        }
    }
    
    func addPath() {
        
        let remainingPathCount = GroupProximityLightingSequencePath.maxPathCount - setPaths.count
        
         guard remainingPathCount > 0 else {
            XWHUDManager.showTipHUD("not_paths_remaining".localizedString, isLineFeed: true)
            return
        }
        
        let range = 1...remainingPathCount
        
        SRAlertView(title: "add_sequence".localizedString, message: String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), messageColor: Message_Color, inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 2, textAlignment: .center, showClear: true), actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)], textValueChangedBack: nil) {[weak self] text in
            guard let self = self, let number = Int(text), range.contains(number) else {
                XWHUDManager.showTipHUD(String(format: "number_limited_range".localizedString, range.lowerBound, range.upperBound), isLineFeed: true)
                return
            }
            let list = GroupProximityLightingSequencePath.default(count: number)
            self.setPaths.append(contentsOf: list.map({ $0.copy() }))
//            let indexPaths = list.enumerated().map({ self.setPaths.count + $0.offset - 1 })
            self.tableView.reloadData()
//            self.tableView.insertSections(IndexSet(indexPaths), with: .automatic)
            
//            self.tableView.insertRows(at: indexPaths, with: .automatic)
            self.updateEmptyUI()
        }.show()
    }
    
    /// 停止设置路径
    func stopSetPath() {
        deselectPath()
    }
    
    /// 路径操作
    private func pathOperation(path: GroupProximityLightingSequencePath,type: GroupPathSequencePathHeaderView.OperationType) {
        
        switch type {
        case .save:
            break
//            groupPath.updatePath(path)
//            group.info.save()
            
//            SyncDevicesViewController(type: .proximityLightingSequencePath(sequencePath: path))
            
        case .test:
            
            GroupPathSequencePathTestView(group: group, addresses: path.items.compactMap({ $0.address })).show()
            
        case .reset:
            SRAlertView(title: "notification".localizedString, message: "path_reset_devices_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                if self.selectPathData.path == path {
                    self.selectPathData.item = nil
                }
                self.updateDeviceAddViewUI()
//                self.triggerDevices.removeAll()
//                if self.deviceAddMode == .triggerAdd {
//                    self.deviceAddView.manuallyAddView.reloadData(devices: self.triggerDevices, selectDevice: nil)
//                }
                path.items.forEach({ $0.address = nil })
                self.reloadPath(path)
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
//                    self.tableView.deleteSections(IndexSet(integer: index), with: .fade)
                    self.tableView.reloadData()
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
                nextItem = path.items[0..<itemIndex].last(where: { $0.address == nil || $0.node == nil })
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
//            tableView.reloadRows(at: [IndexPath(row: 0, section: section)], with: .none)
            tableView.reloadSections(IndexSet(integer: section), with: .none)
        }
      
        
    }
    
    private func setupUI() {
        
        deviceAddView = GroupPathSequenceDeviceAddView()
        deviceAddView.isHidden = true
        deviceAddView.contentHeightPolicy = .fixedBase
        deviceAddView.configureDeviceNameFilter(session: deviceNameFilterSession)
        deviceAddView.delegate = self
        deviceAddView.contentHeightChanged = { [weak self] contentHeight in
            guard let self = self else { return }
            let shouldAnimate = self.allowDeviceAddAnimations && self.view.window != nil
            self.updateDeviceAddViewHeight(contentHeight, animated: shouldAnimate)
        }
        view.addSubview(deviceAddView)
        deviceAddViewHeightConstraint = deviceAddView.heightAnchor.constraint(equalToConstant: 0)
        deviceAddViewHeightConstraint?.isActive = true
        deviceAddView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview()
        }
        
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
            make.bottom.equalTo(deviceAddView.snp.top)
        }
        view.bringSubviewToFront(deviceAddView)
        
      
        
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
        headerView.resetBtn.isEnabled = path.items.contains(where: { $0.address != nil })
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
    
    /// 选择路径
    func cell(_ cell: GroupPathSequencePathViewCell, didSelectPath path: GroupProximityLightingSequencePath) {
        guard let section = setPaths.firstIndex(of: path) else {
            return
        }
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
            
//            deviceAddView.quickAddView.updateQuickAddState(.stop)
        }
        reloadSections.append(section)
        
        
        selectPathData.path = setPaths[section]
        selectPathData.item = item
        selectPathData.direction = direction
        
        tableView.reloadSections(IndexSet(reloadSections), with: .none)
        
        let addedNodes = showAddedDevices ? selectPathData.path?.nodes ?? [] : setPaths.flatMap { $0.nodes }
        
        // 更新触发添加、手动添加可选设备列表
        if self.deviceAddMode == .triggerAdd {
            deviceAddView.triggerAddView.reloadData(devices: triggerDevices.filter({ !addedNodes.contains($0) }), selectDevice: deviceAddView.triggerAddView.selectDevice)
        }else if self.deviceAddMode == .manuallyAdd {
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: deviceAddView.manuallyAddView.selectDevice)
        }
        
        
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

        if deviceAddMode == .manuallyAdd {
            let addedNodes = showAddedDevices ? selectPathData.path?.nodes ?? [] : setPaths.flatMap { $0.nodes }
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
            deviceAddView.updateUnfoldState()
        }
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
        
        if deviceAddMode == .manuallyAdd {
            let addedNodes = setPaths.flatMap { $0.nodes }
            let showNodes = showAddedDevices ? group.nodes : group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
            deviceAddView.updateUnfoldState()
        }
        
        tableView.performBatchUpdates(nil)
    }
    
    func cell(_ cell: GroupPathSequencePathViewCell, bindDevice item: GroupProximityLightingSequencePath.GroupProximityLightingPathItem, address: Address) {
        
        guard let section = tableView.indexPath(for: cell)?.section else { return }
        
        if self.deviceAddMode == .manuallyAdd {
            
            //            if let selectPathData = selectPathData, let item = selectPathData.item {
            item.address = address
            
            let addedNodes = showAddedDevices ? selectPathData.path?.nodes ?? [] : setPaths.flatMap { $0.nodes }
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
            deviceAddView.updateUnfoldState()
            if let selectPathData = selectPathData, let selectItem = selectPathData.item, item == selectItem {
                setNextPathItem()
            }else {
//                cell.reloadPathItem(item: item)
                tableView.reloadSections(IndexSet(integer: section), with: .none)
            }
            //            }
            
        }
        
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
        
        // 手动控制
        if mode == .manuallyAdd {
            let addedNodes = showAddedDevices ? selectPathData.path?.nodes ?? [] : setPaths.flatMap { $0.nodes }
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
            deviceAddView.updateUnfoldState()
        }
        
        self.deviceAddMode = mode
        
    }
    
    /// 已使用设备是否可重复使用选项更新 enabled true：可重复使用 false: 忽略
    func deviceAddView(_ view: GroupPathSequenceDeviceAddView, showAddedDevices enabled: Bool) {
        self.showAddedDevices = enabled
        
        let addedNodes = showAddedDevices ? selectPathData.path?.nodes ?? [] : setPaths.flatMap { $0.nodes }
        // 更新触发添加、手动添加可选设备列表
        if self.deviceAddMode == .triggerAdd {
            deviceAddView.triggerAddView.reloadData(devices: triggerDevices.filter({ !addedNodes.contains($0) }), selectDevice: deviceAddView.triggerAddView.selectDevice)
        }else if self.deviceAddMode == .manuallyAdd {
            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: deviceAddView.manuallyAddView.selectDevice)
        }
        
        
        // 手动控制
//        if deviceAddMode == .manuallyAdd {
//            let addedNodes = showAddedDevices ? selectPathData.path?.nodes ?? [] : setPaths.flatMap { $0.nodes }
//            let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
//            deviceAddView.manuallyAddView.reloadData(devices: showNodes, selectDevice: view.triggerAddView.selectDevice)
//        }
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
        }else if self.deviceAddMode == .manuallyAdd {
            
            if let selectPathData = selectPathData, let item = selectPathData.item {
                item.address = device.sunricherVendorModel?.parentElement?.unicastAddress ?? device.primaryUnicastAddress
                
                let addedNodes = showAddedDevices ? selectPathData.path?.nodes ?? [] : setPaths.flatMap { $0.nodes }
                let showNodes = group.nodes.filter({ !addedNodes.contains($0) })
                view.manuallyAddView.reloadData(devices: showNodes, selectDevice: nil)
                view.updateUnfoldState()
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
        guard selectPathData.isSelect else {
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
        guard pirTrigger, let node = manager.realNodes.first(where: { $0.contains(elementWithAddress: triggerAddress) }), deviceAddMode == .quickAdd || deviceAddMode == .triggerAdd else {
            return
        }
        
        guard let path = selectPathData.path, let item = selectPathData.item, group.nodes.contains(node) else {
            return
        }
        
        // 判断路径list内是否已经有感应的设备
        let samePaths = setPaths.filter({ path in path.items.contains(where: { $0.address != nil && node.contains(elementWithAddress: $0.address!) }) })
        // 重复的设备不让添加到路径
        if showAddedDevices {
            if samePaths.contains(path) {
                return
            }
        }else {
            if samePaths.count > 0 {
                return
            }
        }
        
        
        switch deviceAddMode {
        case .quickAdd:
            if quickAddState == .adding, !quickAddingBusy { // 判断是否在添加中
                item.address = node.sunricherVendorModel?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
                self.quickAddingBusy = true
                // 防止触发太快，间隔200ms生效
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {[weak self] in
                    // 获取下一个空的point item
                    self?.setNextPathItem()
                    self?.quickAddingBusy = false
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
