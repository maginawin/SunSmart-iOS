//
//  DeviceParameterDevicesViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/11.
//

import UIKit
import NordicSigMeshSDK

class DeviceParameterDevicesViewController: UIViewController {

    private var headerView: DeviceParameterPromptView!
    private var tableView: UITableView!
    private var groupsView: DeviceGroupsView!
    private var bottomView: DeviceParameterBottomView!
    
    private var selectDevices: [Node] = []
    private var groupDatas: [DeviceGroupsSelectData] = []
    
    /// pwm参数list
    private var pwmValues: [UInt16] = []
    /// 筛选的pwm值
    private var filterPwmValue: UInt16?
    /// 额定功率list
    private var ratedPowers: [[NodePhaseEnergyConsumption]] = []
    /// 筛选的额定功率
    private var filterRatedPower: [NodePhaseEnergyConsumption]?
    private var showDevices: [Node] = []
    /// 设置pwm失败设备list
    private var settingPwmFailedNodes: [(node: Node, type: DeviceParameterType)] = []
    /// 设置额定功率失败设备list
    private var settingRatedPowerFailedNodes: [(node: Node, type: DeviceParameterType)] = []
    /// 设置失败的设备list
//    private var settingFailedNodes: [(Node, [DeviceParameterType])] = []
    
    /// 设备参数list
//    private var deviceParameterDatas: [Address: (pwm: UInt16?, ratedPower: Int?)] = [:]
    
    let devices: [Node]
    
    init(devices: [Node]) {
        self.devices = devices
        super.init(nibName: nil, bundle: nil)
        self.showDevices = devices
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "device_parameter_settings".localizedString
        view.backgroundColor = Background_Color
        
        devices.forEach { node in
            node.selectOn = false
            node.selectOff = false
            node.tempPwm = node.pwmPeriod
            node.tempRatedPowerPhases = node.phaseEnergyConsumptions
            if let group = node.group {
                if let data = groupDatas.first(where: { $0.groupAddress == group.address.address }) {
                    data.addresss.append(node.primaryUnicastAddress)
                }else {
                    let data = DeviceGroupsSelectData(name: group.name, groupAddress: group.address.address, addresss: [node.primaryUnicastAddress], isSelected: false)
                    groupDatas.append(data)
                }
            }else { // 不在组内
                if let data = groupDatas.first(where: { $0.groupAddress == 0 }) {
                    data.addresss.append(node.primaryUnicastAddress)
                }else {
                    let data = DeviceGroupsSelectData(name: "not_in_group".localizedString, groupAddress: 0, addresss: [node.primaryUnicastAddress], isSelected: false)
                    groupDatas.insert(data, at: 0)
                }
            }
        }
        
        groupDatas.sort(by: { $0.groupAddress < $1.groupAddress })
        
        MeshLibManager.manager.addObserver(self, forKeyPath: "isMeshNetworkConnected", context: nil)
        
        setupFilterData()
        
        setupUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: groupsView.height, right: 0)
    }
    
    /// 初始化筛选参数
    private func setupFilterData() {
//        deviceParameterDatas.removeAll()
        pwmValues.removeAll()
        ratedPowers.removeAll()
        
        devices.forEach({ node in
            
//            node.tempPwm = node.pwmPeriod
            
//            deviceParameterDatas.updateValue((node.pwmPeriod, nil), forKey: node.primaryUnicastAddress)
            if let pwm = node.tempPwm, !pwmValues.contains(pwm) {
                pwmValues.append(pwm)
            }
            // 功率
            if node.tempRatedPowerPhases.count > 0 {
                if !ratedPowers.contains(node.tempRatedPowerPhases) {
                    ratedPowers.append(node.tempRatedPowerPhases)
                }
            }else {
                if !ratedPowers.contains([]) {
                    ratedPowers.insert([], at: 0)
                }
            }
           
        })
        
    }
    
    deinit {
        MeshLibManager.manager.removeObserver(self, forKeyPath: "isMeshNetworkConnected")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        updateUI()
    }
    
    private func updateUI() {
        
        if MeshLibManager.manager.isMeshNetworkConnected {
            bottomView.leftBtn.isEnabled = true
        }else {
            bottomView.leftBtn.isEnabled = false
        }
        tableView.reloadData()
        
        if settingPwmFailedNodes.count > 0 || settingRatedPowerFailedNodes.count > 0 {
            headerView.settingFailedBtn.isHidden = false
            headerView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(62))
            }
        }else {
            headerView.settingFailedBtn.isHidden = true
            headerView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(44))
            }
        }
        
    }
    
    /// 读取数据
    @objc private func readAction() {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        let parameters: [DeviceReadParameterType] = [.pwmPeriod, .ratedPower]
        let vc = ReadDevicesDataViewController(type: .parameters(nodes: devices, parameters: parameters))
        vc.readSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            self.devices.forEach { node in
                if parameters.contains(.pwmPeriod) {
                    node.tempPwm = node.pwmPeriod
                }
                if parameters.contains(.ratedPower) {
                    node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                }
//                node.tempRatedPower = node.ratedPower
            }
            self.setupFilterData()
            self.tableView.reloadData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            
            
        }
        vc.backActionCallback = {[weak self] failedDatas in
            guard let self = self else { return }
            
            self.devices.forEach { node in
                // 失败的数据展示“--”
                if let data = failedDatas.first(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress }) {
                    data.parameterTypes.forEach { type in
                        switch type {
                        case .pwmPeriod:
                            node.tempPwm = nil
                        case .ratedPower:
                            node.tempRatedPowerPhases = []
                        default:
                            break
                        }
                    }
                }else {
                    if parameters.contains(.pwmPeriod) {
                        node.tempPwm = node.pwmPeriod
                    }
                    if parameters.contains(.ratedPower) {
                        node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                    }
                }
            }
            self.setupFilterData()
//            self.pwmValues.removeAll()
//            self.ratedPowers.removeAll()
//            self.deviceParameterDatas.values.forEach { (pwm: UInt16?, ratedPower: Int?) in
//                if let pwm = pwm, !self.pwmValues.contains(pwm) {
//                    self.pwmValues.append(pwm)
//                }
//                // 功率
//                if ratedPower == nil, !self.ratedPowers.contains(0) {
//                    self.ratedPowers.append(0)
//                }
//            }
            
            self.tableView.reloadData()
            self.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 下一步
    @objc private func nextAction() {
        guard selectDevices.count > 0 else {
            return
        }
        let vc = DeviceParameterSettingsController(devices: selectDevices)
        vc.settingsCompletionCallback = {[weak self] result in
            guard let self = self else { return }
            
            result.forEach { (key: DeviceParameterData.ParameterType, value: (value: Any, successNodes: [Node], failedNodes: [Node])) in

                switch key {
                case .pwmFrequency:
                    self.settingPwmFailedNodes.removeAll(where: { data in value.successNodes.contains(where: { $0.primaryUnicastAddress == data.node.primaryUnicastAddress }) })
                    
                    value.failedNodes.forEach({ node in
                        if let pwm = value.value as? Int {
                            if let index = self.settingPwmFailedNodes.firstIndex(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress }) {
                                self.settingPwmFailedNodes.replaceSubrange(index...index, with: [(node, .pwmPeriod(period: UInt16(pwm)))])
                            }else {
                                self.settingPwmFailedNodes.append((node, .pwmPeriod(period: UInt16(pwm))))
                            }
                        }
                    })
                    value.successNodes.forEach { node in
                        node.tempPwm = node.pwmPeriod
                    }
                    
                case .ratedPower:
                    self.settingRatedPowerFailedNodes.removeAll(where: { data in value.successNodes.contains(where: { $0.primaryUnicastAddress == data.node.primaryUnicastAddress }) })
                    
                    value.failedNodes.forEach({ node in
                        if let powerDatas = value.value as? [DeviceParameterRatedPowerPhaseData] {
                            
                            let nodePhaseEnergyDatas = powerDatas.map({ NodePhaseEnergyConsumption(percent: $0.lightLevel ?? 0, power: $0.power ?? 0) })
                            
                            if let index = self.settingRatedPowerFailedNodes.firstIndex(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress }) {
                                self.settingRatedPowerFailedNodes.replaceSubrange(index...index, with: [(node, .ratedPower(datas: nodePhaseEnergyDatas))])
                            }else {
                                self.settingRatedPowerFailedNodes.append((node, .ratedPower(datas: nodePhaseEnergyDatas)))
                            }
                        }
                    })
                    value.successNodes.forEach { node in
                        node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                    }
                    
                }
                
            }
            self.setupFilterData()
            self.updateUI()
//            self.tableView.reloadData()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func reloadCell(device: Node) {
        if let index = self.showDevices.firstIndex(of: device) {
            if let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? DeviceParameterDeviceCell {
                cell.device = device
                if device.supportPwmFrequency {
                    var pwm = device.tempPwm
                    if let failedData = settingPwmFailedNodes.first(where: { $0.node.primaryUnicastAddress == device.primaryUnicastAddress }) {
                        cell.pwmFailedImageView.isHidden = false
                        if case .pwmPeriod(let period) = failedData.type {
                            pwm = period
                        }
                    }else {
                        cell.pwmFailedImageView.isHidden = true
                    }
                    
                    if let pwm = pwm {
                        cell.pwmLabel.text = "PWM: \(pwm) Hz"
                    }else {
                        cell.pwmLabel.text = "PWM: --"
                    }
                    cell.pwmLabel.isHidden = false
                }else {
                    cell.pwmFailedImageView.isHidden = true
                    cell.pwmLabel.isHidden = true
                }
                var ratedPowerPhases = device.tempRatedPowerPhases
                if let failedData = settingRatedPowerFailedNodes.first(where: { $0.node.primaryUnicastAddress == device.primaryUnicastAddress }) {
                    if case .ratedPower(let datas) = failedData.type {
                        ratedPowerPhases = datas
                    }
                    cell.ratedPowerFailedImageView.isHidden = false
                }else {
                    cell.ratedPowerFailedImageView.isHidden = true
                }
                cell.ratedPowerLabel.text = "\("reted_power".localizedString): \(getRatedPowerStr(list: ratedPowerPhases))"
                
                if MeshLibManager.manager.isMeshNetworkConnected {
                    cell.selectState = selectDevices.contains(device) ? .selected : .none
                }else {
                    cell.selectState = .disable
                }
            }
        }
    }
    
    /// 获取功耗描述字符串
    private func getRatedPowerStr(list: [NodePhaseEnergyConsumption]) -> String {
        guard list.count > 0 else {
            return "--"
        }
        var phaseStr = ""
        list.forEach({
            phaseStr.append(String(format: "%@%d%%,%@W", phaseStr.isEmpty ? "" : "/", $0.percent, (Float($0.power) * 0.1).toSimplifyStr(maxDigits: 1)))
        })
        return phaseStr
    }
    
    private func setupUI() {
        
        headerView = DeviceParameterPromptView()
        headerView.titleLabel.text = "device_parameter_step_1".localizedString
        headerView.delegate = self
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(SCRYFrom(44))
        }
        
        bottomView = DeviceParameterBottomView()
        bottomView.leftBtn.addTarget(self, action: #selector(readAction), for: .touchUpInside)
        bottomView.rightBtn.addTarget(self, action: #selector(nextAction), for: .touchUpInside)
        bottomView.rightBtn.isEnabled = false
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(DeviceParameterDeviceCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        groupsView = DeviceGroupsView()
        groupsView.sortBtn.isHidden = true
        groupsView.itemSize = CGSize(width: SCRXFrom(88), height: SCRYFrom(40))
        groupsView.selectCountLabel.isHidden = false
        groupsView.lineView.isHidden = true
        groupsView.datas = groupDatas
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        groupsView.delegate = self
        view.addSubview(groupsView)
        groupsView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(tableView)
//            make.bottom.equalToSuperview()
//            make.height.greaterThanOrEqualTo(SCRYFrom(64))
        }
        
    }

}

extension DeviceParameterDevicesViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return showDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceParameterDeviceCell
        let device = showDevices[indexPath.row]
        cell.device = device
        if device.supportPwmFrequency {
            
            var pwm = device.tempPwm
            if let failedData = settingPwmFailedNodes.first(where: { $0.node.primaryUnicastAddress == device.primaryUnicastAddress }) {
                cell.pwmFailedImageView.isHidden = false
                if case .pwmPeriod(let period) = failedData.type {
                    pwm = period
                }
            }else {
                cell.pwmFailedImageView.isHidden = true
            }
            
            if let pwm = pwm {
                cell.pwmLabel.text = "PWM: \(pwm) Hz"
            }else {
                cell.pwmLabel.text = "PWM: --"
            }
            cell.pwmLabel.isHidden = false
        }else {
            cell.pwmFailedImageView.isHidden = true
            cell.pwmLabel.isHidden = true
        }
        
        var ratedPowerPhases = device.tempRatedPowerPhases
        if let failedData = settingRatedPowerFailedNodes.first(where: { $0.node.primaryUnicastAddress == device.primaryUnicastAddress }) {
            if case .ratedPower(let datas) = failedData.type {
                ratedPowerPhases = datas
            }
            cell.ratedPowerFailedImageView.isHidden = false
        }else {
            cell.ratedPowerFailedImageView.isHidden = true
        }
        cell.ratedPowerLabel.text = "\("reted_power".localizedString): \(getRatedPowerStr(list: ratedPowerPhases))"
        
        if MeshLibManager.manager.isMeshNetworkConnected {
            cell.selectState = selectDevices.contains(device) ? .selected : .none
        }else {
            cell.selectState = .disable
        }
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let device = showDevices[indexPath.row]
        
        if device.supportPwmFrequency {
            var ratedPowerPhases = device.tempRatedPowerPhases
            if let failedData = settingRatedPowerFailedNodes.first(where: { $0.node.primaryUnicastAddress == device.primaryUnicastAddress }) {
                if case .ratedPower(let datas) = failedData.type {
                    ratedPowerPhases = datas
                }
            }
            if ratedPowerPhases.count > 2 {
                return SCRYFrom(92)
            }
        }
        return SCRYFrom(72)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let device = showDevices[indexPath.row]
        guard device.state else {
            return
        }
        if let index = selectDevices.firstIndex(of: device) {
            selectDevices.remove(at: index)
        }else {
            selectDevices.append(device)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        
        if let group = device.group, let data = groupDatas.first(where: { $0.groupAddress == group.address.address }) {
            let groupSelectDevices = selectDevices.filter({ device in data.addresss.contains(device.primaryUnicastAddress) })
            data.isSelected = groupSelectDevices.count == data.addresss.count
//            !selectDevices.contains(where: { device in !data.addresss.contains(device.primaryUnicastAddress) })
            groupsView.datas = groupDatas
        }
        groupsView.selectAllBtn.isSelected = selectDevices.count == devices.count
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        bottomView.rightBtn.isEnabled = selectDevices.count > 0
    }
    
}

extension DeviceParameterDevicesViewController: DeviceParameterDeviceCellDelegate {
    
    /// 设备identity事件
    func cell(_ cell: DeviceParameterDeviceCell, deviceIdentifyAction device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 设备onoff事件
    func cell(_ cell: DeviceParameterDeviceCell, deviceOnOffAction device: Node, isOn: Bool) {
        device.isOn = isOn
        device.selectOn = isOn
        device.selectOff = !isOn
        cell.device = device
        MeshAPI.setNodeOnOffState(address: device.primaryUnicastAddress, isOn: isOn)
    }
}

extension DeviceParameterDevicesViewController: DeviceGroupsViewDelegate {
    func view(_ view: DeviceGroupsView, didSelectAllAction selectAll: Bool) {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
        if selectAll {
            selectDevices = devices
        }else {
            selectDevices.removeAll()
        }
        tableView.reloadData()
        groupDatas.forEach({
            $0.isSelected = selectAll
        })
        groupsView.datas = groupDatas
        groupsView.selectAllBtn.isSelected = selectDevices.count == devices.count
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        bottomView.rightBtn.isEnabled = selectDevices.count > 0
    }
    
    func view(_ view: DeviceGroupsView, didSelectData data: DeviceGroupsSelectData) {
        
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
        
        let groupDevices = data.addresss.compactMap({ address in devices.first(where: { $0.primaryUnicastAddress == address }) })
        if data.isSelected {
            selectDevices.append(contentsOf: groupDevices)
        }else {
            selectDevices.removeAll(where: { device in groupDevices.contains(device) })
        }
        groupsView.selectAllBtn.isSelected = selectDevices.count == devices.count
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        tableView.reloadData()
        bottomView.rightBtn.isEnabled = selectDevices.count > 0
    }
    
    func viewDidSortAction(_ view: DeviceGroupsView) {
        
    }
}

extension DeviceParameterDevicesViewController: DeviceParameterPromptViewDelegate {
    
    /// 筛选
    func promptViewFilterAction(_ view: DeviceParameterPromptView) {
        
        let powerDatas: [(name: String, value: [NodePhaseEnergyConsumption])] = ratedPowers.map({ (getRatedPowerStr(list: $0), $0) })
        
        var pwmSelectIndex: Int?
        if let value = self.filterPwmValue {
            pwmSelectIndex = pwmValues.firstIndex(of: value)
        }
        var retedPowerSelectIndex: Int?
        if let value = self.filterRatedPower {
            retedPowerSelectIndex = powerDatas.firstIndex(where: { $0.value == value })
        }
        
        var filterDatas: [ParameterFilterData] = []
        if pwmValues.count > 0 {
            filterDatas.append(.init(type: .pwm, isShow: pwmSelectIndex != nil, contents: pwmValues.map({ "\($0) Hz" }), selectIndex: pwmSelectIndex))
        }
        filterDatas.append(.init(type: .ratedPower, isShow: retedPowerSelectIndex != nil, contents: powerDatas.map({ $0.name }), selectIndex: retedPowerSelectIndex))
        
        DeviceParameterFilterView(filterDatas: filterDatas, doneCallback: {[weak self] filterDatas in
            guard let self = self else { return }
            
            self.filterPwmValue = nil
            self.filterRatedPower = nil
            var showDevices = self.devices
            
            filterDatas.forEach { (type: ParameterFilterData.ParameterType, selectIndex: Int) in
                switch type {
                case .pwm:
                    print("pwm: \(self.pwmValues[selectIndex])")
                    self.filterPwmValue = self.pwmValues[selectIndex]
                    showDevices = showDevices.filter({ $0.pwmPeriod == self.filterPwmValue })
                case .ratedPower:
                    let value = self.ratedPowers[selectIndex]
                    self.filterRatedPower = value
//                    showDevices = showDevices.filter({ $0. })
                }
            }
            self.headerView.filterBtn.isSelected = self.filterPwmValue != nil || self.filterRatedPower != nil
            self.showDevices = showDevices
            self.tableView.reloadData()
            
        }).show()
        
    }
    
    /// 重试
    func promptViewReSyncAction(_ view: DeviceParameterPromptView) {
//        var datas: [(Node, [DeviceParameterType])] = []
        var nodes: [Node] = []
        settingPwmFailedNodes.forEach {
            if !nodes.contains($0.node) {
                nodes.append($0.node)
            }
        }
        settingRatedPowerFailedNodes.forEach({
            if !nodes.contains($0.node) {
                nodes.append($0.node)
            }
        })
        let datas = nodes.map({ node in
            var types: [DeviceParameterType] = []
            if let data = settingPwmFailedNodes.first(where: { $0.node == node }) {
                types.append(data.type)
            }
            if let data = settingRatedPowerFailedNodes.first(where: { $0.node == node }) {
                types.append(data.type)
            }
            return (node, types)
        })
        
        let vc = SyncDevicesViewController(type: .devicesParameter(datas), reSync: true)
        vc.syncSuccessCallback = {[weak self] type in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            switch type {
            case.devicesParameter(let datas):
                datas.forEach { (node, types) in
                    types.forEach { type in
                        switch type {
                        case .pwmPeriod:
                            node.tempPwm = node.pwmPeriod
                        case .ratedPower:
                            node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                        }
                    }
                }
            default:
                break
            }
            
            self.settingPwmFailedNodes.removeAll()
            self.settingRatedPowerFailedNodes.removeAll()
            self.setupFilterData()
            self.updateUI()
        }
        vc.backActionCallback = {[weak self] resultDatas in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            resultDatas.forEach { data in
                data.successOperationTypes.forEach { operationType in
                    if case .configuration(let node, let type) = operationType {
                        switch type {
                        case .deviceParameters(let parameterType):
                            switch parameterType {
                            case .pwmPeriod:
                                node.tempPwm = node.pwmPeriod
                                self.settingPwmFailedNodes.removeAll(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress })
                            case .ratedPower:
                                node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                                self.settingRatedPowerFailedNodes.removeAll(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress })
                            }
                        default:
                            break
                        }
                    }
                }
            }
            
            self.setupFilterData()
            self.updateUI()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension Node {
    
    static var selectOnKey = 1
    static var selectOffKey = 2
    static var tempPwmKey = 3
    static var tempRatedPowerKey = 4
    
    /// 是否选中On
    var selectOn: Bool {
        get {
            objc_getAssociatedObject(self, &Node.selectOnKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &Node.selectOnKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否选中Off
    var selectOff: Bool {
        get {
            objc_getAssociatedObject(self, &Node.selectOffKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &Node.selectOffKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 临时的pwm（仅在当前页面使用）
    var tempPwm: UInt16? {
        get {
            objc_getAssociatedObject(self, &Node.tempPwmKey) as? UInt16
        }set {
            objc_setAssociatedObject(self, &Node.tempPwmKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 临时的额定功率（仅在当前页面使用）
    var tempRatedPowerPhases: [NodePhaseEnergyConsumption] {
        get {
            objc_getAssociatedObject(self, &Node.tempRatedPowerKey) as? [NodePhaseEnergyConsumption] ?? []
        }set {
            objc_setAssociatedObject(self, &Node.tempRatedPowerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
