//
//  DeviceParameterDevicesViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/11.
//

import UIKit
import NordicSigMeshSDK

class DeviceParameterDevicesViewController: UIViewController {

    enum FilterSelectionState {
        var rawValue: Int {
            switch self {
            case . unselected:
                return 0
            case .emptySelection:
                return 1
            case .selected:
                return 2
            }
        }
        
        case unselected       // 未点开
        case emptySelection   // 点开了，但没设置（显示 --）
        case selected(value: Any, name: String) // 设置了具体内容
    }
    
    private var headerView: DeviceParameterPromptView!
    private var tableView: UITableView!
    private var groupsView: DeviceGroupsView!
    private var bottomView: DeviceParameterBottomView!
    
    private var selectDevices: [Node] = []
    private var groupDatas: [DeviceGroupsSelectData] = []
    
    /// pwm参数list
    private var pwmValues: [UInt16] = []
    /// 筛选的pwm值
    private var filterPwmValue: FilterSelectionState = .unselected
    /// 额定功率list
    private var ratedPowers: [[NodePhaseEnergyConsumption]] = []
    /// 筛选的额定功率
    private var filterRatedPower: FilterSelectionState = .unselected
    /// 绝对灵敏度范围list
    private var absoluteSensitivitys: [ClosedRange<UInt16>] = []
    /// 筛选的绝对灵敏度范围
    private var filterAbsoluteSensitivityRange: FilterSelectionState = .unselected
    
    private var showDevices: [Node] = []
    /// 设置pwm失败设备list
//    private var settingPwmFailedNodes: [(node: Node, type: DeviceParameterType)] = []
    /// 设置额定功率失败设备list
//    private var settingRatedPowerFailedNodes: [(node: Node, type: DeviceParameterType)] = []
    
    /// 设置失败的设备及参数
    private var settingFailedDatas: [Address: [DeviceParameterType]] = [:]
    /// 设置失败的设备list
//    private var settingFailedNodes: [(Node, [DeviceParameterType])] = []
    
    private var meshNetworkConnectedObservation: NSKeyValueObservation?
    
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
        
        groupDatas = MeshNetworkManager.instance.groups.map({  DeviceGroupsSelectData(name: $0.name, groupAddress: $0.address.address, addresss: [], isSelected: false) })
        
        devices.forEach { node in
            node.selectOn = false
            node.selectOff = false
            node.tempPwm = node.pwmFrequency
            node.tempRatedPowerPhases = node.phaseEnergyConsumptions
            node.tempSensitivityRange = node.motionSensitivityRange
            if let group = node.group {
                if let data = groupDatas.first(where: { $0.groupAddress == group.address.address }) {
                    data.addresss.append(node.primaryUnicastAddress)
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
        
        
        // mesh网络连接观察者
        meshNetworkConnectedObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new], changeHandler: { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                self?.updateUI()
            }
        })
        
        
        setupFilterData()
        
        setupUI()
        
        updateUI()
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
        absoluteSensitivitys.removeAll()
        
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
            }
            // 灵敏度范围
            if let range = node.tempSensitivityRange, !absoluteSensitivitys.contains(range) {
                absoluteSensitivitys.append(range)
            }
           
        })
        
    }
    
    deinit {
        meshNetworkConnectedObservation = nil
//        MeshLibManager.manager.removeObserver(self, forKeyPath: "isMeshNetworkConnected")
    }
    
    private func updateUI() {
        
        if MeshLibManager.manager.isMeshNetworkConnected {
            bottomView.leftBtn.isEnabled = selectDevices.count > 0
        }else {
            bottomView.leftBtn.isEnabled = false
        }
        tableView.reloadData()
        
        if settingFailedDatas.count > 0 {
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
        
        let parameters: [DeviceReadParameterType] = [.pwmFrequency, .ratedPower, .motionSensitivityRange]
        let vc = ReadDevicesDataViewController(type: .parameters(nodes: selectDevices, parameters: parameters))
        vc.readSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            self.devices.forEach { node in
                if parameters.contains(.pwmFrequency) {
                    // 如果获取的pwm频率有精度问题，则获取pwm频率list中最接近的数值
                    if let pwmFrequency = node.pwmFrequency, !DeviceParameterData.pwmFrequencys.contains(Int(pwmFrequency)) {
                        node.pwmFrequency = UInt16(self.pwmFrequencyFindClosestValue(list: DeviceParameterData.pwmFrequencys, target: Int(pwmFrequency)))
                    }
                    node.tempPwm = node.pwmFrequency
                }
                if parameters.contains(.ratedPower) {
                    node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                }
                if parameters.contains(.motionSensitivityRange) {
                    node.tempSensitivityRange = node.motionSensitivityRange
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
                
                if parameters.contains(.pwmFrequency) {
                    // 如果获取的pwm频率有精度问题，则获取pwm频率list中最接近的数值
                    if let pwmFrequency = node.pwmFrequency, !DeviceParameterData.pwmFrequencys.contains(Int(pwmFrequency)) {
                        node.pwmFrequency = UInt16(self.pwmFrequencyFindClosestValue(list: DeviceParameterData.pwmFrequencys, target: Int(pwmFrequency)))
                    }
                    node.tempPwm = node.pwmFrequency
                }
                if parameters.contains(.ratedPower) {
                    node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                }
                if parameters.contains(.motionSensitivityRange) {
                    node.tempSensitivityRange = node.motionSensitivityRange
                }
                
                
                // 失败的数据展示“--”
                if let data = failedDatas.first(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress }) {
                    data.parameterTypes.forEach { type in
                        switch type {
                        case .pwmFrequency:
                            node.tempPwm = nil
                        case .ratedPower:
                            node.tempRatedPowerPhases = []
                        case .motionSensitivityRange:
                            node.tempSensitivityRange = nil
                        case .totalDeviceEnergyUse:
                            break
                        default:
                            break
                        }
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
    
    /// 读取pwm频率数值时可能因为周期=>频率换算精度问题，需要根据返回频率数值匹配频率list中最接近的值
    private func pwmFrequencyFindClosestValue(list: [Int], target: Int) -> Int {
        return list.min(by: { abs($0 - target) < abs($1 - target) }) ?? list[0]
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

                value.successNodes.forEach { node in
                    if var data = self.settingFailedDatas[node.primaryUnicastAddress] {
                        data.removeAll(where: { $0.rawValue == key.rawValue })
                        if data.isEmpty {
                            self.settingFailedDatas.removeValue(forKey: node.primaryUnicastAddress)
                        }else {
                            self.settingFailedDatas.updateValue(data, forKey: node.primaryUnicastAddress)
                        }
                    }
                    switch key {
                    case .pwmFrequency:
                        node.tempPwm = node.pwmFrequency
                    case .ratedPower:
                        node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                    case .motionSensitivityRange:
                        node.tempSensitivityRange = node.motionSensitivityRange
                    }
                }
                
                value.failedNodes.forEach({ node in
//                    if var data = self.settingFailedDatas[node.primaryUnicastAddress] {
                        var type: DeviceParameterType?
                        switch key {
                        case .pwmFrequency:
                            if let pwm = value.value as? Int {
                                type = .pwmFrequency(frequency: UInt16(pwm))
                            }
                        case .ratedPower:
                            if let powerDatas = value.value as? [DeviceParameterRatedPowerPhaseData] {
                                let nodePhaseEnergyDatas = powerDatas.map({ NodePhaseEnergyConsumption(percent: UInt8(Float($0.lightLevel ?? 0) * 2.55), power: $0.power ?? 0) })
                                type = .ratedPower(datas: nodePhaseEnergyDatas)
                            }
                        case .motionSensitivityRange:
                            if let range = value.value as? ClosedRange<Double> {
                                type = .motionSensitivityRange(range: range.lowerBound.value16...range.upperBound.value16)
                            }
                        }

                        if let type = type {
                            if var data = self.settingFailedDatas[node.primaryUnicastAddress] {
                                if let index = data.firstIndex(where: { $0.rawValue == key.rawValue }) {
                                    data.replaceSubrange(index...index, with: [type])
                                }else {
                                    data.append(type)
                                }
                                self.settingFailedDatas.updateValue(data, forKey: node.primaryUnicastAddress)
                            }else {
                                self.settingFailedDatas.updateValue([type], forKey: node.primaryUnicastAddress)
                            }
                        }
//                    }
                })
            }
            self.selectDevices.removeAll()
            self.setupFilterData()
            self.groupDatas.forEach({
                $0.isSelected = false
            })
            self.groupsView.datas = self.groupDatas
            self.groupsView.selectAllBtn.isSelected = self.selectDevices.count == self.devices.count
            self.groupsView.selectCountLabel.text = "\(self.selectDevices.count)/\(self.devices.count)"
            self.bottomView.rightBtn.isEnabled = self.selectDevices.count > 0
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
                    
                    if let failedData = settingFailedDatas[device.primaryUnicastAddress]?.first(where: { $0.rawValue == DeviceParameterData.ParameterType.pwmFrequency.rawValue }) {
                        cell.pwmFailedImageView.isHidden = false
                        if case .pwmFrequency(let frequency) = failedData {
                            pwm = frequency
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
                if let failedData = settingFailedDatas[device.primaryUnicastAddress]?.first(where: { $0.rawValue == DeviceParameterData.ParameterType.ratedPower.rawValue }) {
                    if case .ratedPower(let datas) = failedData {
                        ratedPowerPhases = datas
                    }
                    cell.ratedPowerFailedImageView.isHidden = false
                }else {
                    cell.ratedPowerFailedImageView.isHidden = true
                }
                cell.ratedPowerLabel.text = "\("rated_power".localizedString): \(getRatedPowerStr(list: ratedPowerPhases))"
                
                if device.supportMotionSensitivity {
                    var range = device.tempSensitivityRange
                    
                    if let failedData = settingFailedDatas[device.primaryUnicastAddress]?.first(where: { $0.rawValue == DeviceParameterData.ParameterType.motionSensitivityRange.rawValue }) {
                        cell.sensitivityImageView.isHidden = false
                        if case .motionSensitivityRange(let sensitivityRange) = failedData {
                            range = sensitivityRange
                        }
                    }else {
                        cell.sensitivityImageView.isHidden = true
                    }
                    if let range = range {
                        
                        cell.sensitivityLabel.text = "\("absolute_sensitivity".localizedString) :\(range.lowerBound.percentageFloat.toSimplifyStr(maxDigits: 1))%~\(range.upperBound.percentageFloat.toSimplifyStr(maxDigits: 1))%"
                    }else {
                        cell.sensitivityLabel.text = "\("absolute_sensitivity".localizedString) : --"
                    }
                    cell.sensitivityLabel.isHidden = false
                }else {
                    cell.sensitivityImageView.isHidden = true
                    cell.sensitivityLabel.isHidden = true
                }
                
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
            phaseStr.append(String(format: "%@%d%%,%@W", phaseStr.isEmpty ? "" : "/", $0.percent.percentage, (Float($0.power) * 0.1).toSimplifyStr(maxDigits: 1)))
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
        bottomView.leftBtn.isEnabled = false
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
            if let failedData = settingFailedDatas[device.primaryUnicastAddress]?.first(where: { $0.rawValue == DeviceParameterData.ParameterType.pwmFrequency.rawValue }) {
                cell.pwmFailedImageView.isHidden = false
                if case .pwmFrequency(let frequency) = failedData {
                    pwm = frequency
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
        if let failedData = settingFailedDatas[device.primaryUnicastAddress]?.first(where: { $0.rawValue == DeviceParameterData.ParameterType.ratedPower.rawValue }) {
            if case .ratedPower(let datas) = failedData {
                ratedPowerPhases = datas
            }
            cell.ratedPowerFailedImageView.isHidden = false
        }else {
            cell.ratedPowerFailedImageView.isHidden = true
        }
        cell.ratedPowerLabel.text = "\("rated_power".localizedString): \(getRatedPowerStr(list: ratedPowerPhases))"

        if device.supportMotionSensitivity {
            var range = device.tempSensitivityRange
            
            if let failedData = settingFailedDatas[device.primaryUnicastAddress]?.first(where: { $0.rawValue == DeviceParameterData.ParameterType.motionSensitivityRange.rawValue }) {
                cell.sensitivityImageView.isHidden = false
                if case .motionSensitivityRange(let sensitivityRange) = failedData {
                    range = sensitivityRange
                }
            }else {
                cell.sensitivityImageView.isHidden = true
            }
            if let range = range {
                
                cell.sensitivityLabel.text = "\("absolute_sensitivity".localizedString) :\(range.lowerBound.percentageFloat.toSimplifyStr(maxDigits: 1))%~\(range.upperBound.percentageFloat.toSimplifyStr(maxDigits: 1))%"
            }else {
                cell.sensitivityLabel.text = "\("absolute_sensitivity".localizedString) : --"
            }
            cell.sensitivityLabel.isHidden = false
        }else {
            cell.sensitivityImageView.isHidden = true
            cell.sensitivityLabel.isHidden = true
        }
        
        if MeshLibManager.manager.isMeshNetworkConnected && device.state {
            cell.selectState = selectDevices.contains(device) ? .selected : .none
        }else {
            cell.selectState = .disable
        }
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let device = showDevices[indexPath.row]
        
        var height = SCRYFrom(72)
        if device.supportPwmFrequency {
            var ratedPowerPhases = device.tempRatedPowerPhases
            if let failedData = settingFailedDatas[device.primaryUnicastAddress]?.first(where: { $0.rawValue == DeviceParameterData.ParameterType.ratedPower.rawValue }) {
                if case .ratedPower(let datas) = failedData {
                    ratedPowerPhases = datas
                }
            }
            if ratedPowerPhases.count > 2 {
                height += SCRYFrom(20)
            }
        }
        if device.supportMotionSensitivity {
            height += SCRYFrom(26)
        }
        return height
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let device = showDevices[indexPath.row]
        guard device.state else {
            XWHUDManager.showTipHUD("device_offline_message".localizedString, isLineFeed: true)
            return
        }
        if let index = selectDevices.firstIndex(of: device) {
            selectDevices.remove(at: index)
        }else {
            selectDevices.append(device)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        
        if let data = groupDatas.first(where: { $0.groupAddress == device.group?.address.address ?? 0 }) {
            let groupSelectDevices = selectDevices.filter({ device in data.addresss.contains(device.primaryUnicastAddress) })
            data.isSelected = groupSelectDevices.count == data.addresss.count
//            !selectDevices.contains(where: { device in !data.addresss.contains(device.primaryUnicastAddress) })
            groupsView.datas = groupDatas
        }
        groupsView.selectAllBtn.isSelected = selectDevices.count == devices.count
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        bottomView.rightBtn.isEnabled = selectDevices.count > 0
        bottomView.leftBtn.isEnabled = selectDevices.count > 0
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
            selectDevices = devices.filter({ $0.state })
        }else {
            selectDevices.removeAll()
        }
        tableView.reloadData()
        groupDatas.forEach({
            $0.isSelected = selectAll && $0.addresss.count > 0
        })
        groupsView.datas = groupDatas
        groupsView.selectAllBtn.isSelected = selectDevices.count == devices.filter({ $0.state }).count
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        bottomView.rightBtn.isEnabled = selectDevices.count > 0
        bottomView.leftBtn.isEnabled = selectDevices.count > 0
    }
    
    func view(_ view: DeviceGroupsView, didSelectData data: DeviceGroupsSelectData) {
        
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            data.isSelected = false
            view.reloadGroupData(data: data)
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
        bottomView.leftBtn.isEnabled = selectDevices.count > 0
    }
    
    func viewDidSortAction(_ view: DeviceGroupsView) {
        
    }
}

extension DeviceParameterDevicesViewController: DeviceParameterPromptViewDelegate {
    
    /// 筛选
    func promptViewFilterAction(_ view: DeviceParameterPromptView) {
        
        var pwmContents: [(name: String, value: UInt16?)] = pwmValues.map({ ("\($0) Hz", $0) })
        if devices.contains(where: { $0.tempPwm == nil }) {
            pwmContents.insert(("--", nil), at: 0)
        }
        var pwmSelectIndex: Int?
        switch self.filterPwmValue {
        case .emptySelection:
            pwmSelectIndex = 0
        case .selected(let value, _):
            if let pwm = value as? UInt16 {
                pwmSelectIndex = pwmContents.firstIndex(where: { $0.value == pwm })
            }
        default:
            break
        }
       
        var powerDatas: [(name: String, value: [NodePhaseEnergyConsumption])] = ratedPowers.map({ (getRatedPowerStr(list: $0), $0) })
        if devices.contains(where: { $0.tempRatedPowerPhases.isEmpty }) {
            powerDatas.insert(("--", []), at: 0)
        }
        var retedPowerSelectIndex: Int?
        switch self.filterRatedPower {
        case .emptySelection:
            retedPowerSelectIndex = 0
        case .selected(let value, _):
            if let powerData = value as? [NodePhaseEnergyConsumption] {
                retedPowerSelectIndex = powerDatas.firstIndex(where: { $0.value == powerData })
            }
        default:
            break
        }
     
        var sensitivityContents: [(name: String, value: ClosedRange<UInt16>?)] = absoluteSensitivitys.map({ range in ("\(range.lowerBound.percentageFloat)%~\(range.upperBound.percentageFloat)%", range) })
        if devices.contains(where: { $0.tempSensitivityRange == nil }) {
            sensitivityContents.insert(("--", nil), at: 0)
        }
        var sensitivitySelectIndex: Int?
        switch self.filterAbsoluteSensitivityRange {
        case .emptySelection:
            sensitivitySelectIndex = 0
        case .selected(let value, _):
            if let range = value as? ClosedRange<UInt16> {
                sensitivitySelectIndex = sensitivityContents.firstIndex(where: { $0.value == range })
            }
        default:
            break
        }
        
        var filterDatas: [ParameterFilterData] = []
        
        if pwmContents.count > 0 {
            filterDatas.append(.init(type: .pwm, isShow: pwmSelectIndex != nil, contents: pwmContents.map({ $0.name }), selectIndex: pwmSelectIndex))
        }
        if powerDatas.count > 0 {
            filterDatas.append(.init(type: .ratedPower, isShow: retedPowerSelectIndex != nil, contents: powerDatas.map({ $0.name }), selectIndex: retedPowerSelectIndex))
        }
        
        if sensitivityContents.count > 0 {
            filterDatas.append(.init(type: .absoluteSensitivity, isShow: sensitivitySelectIndex != nil, contents: sensitivityContents.map({ $0.name }), selectIndex: sensitivitySelectIndex))
        }
        
        DeviceParameterFilterView(filterDatas: filterDatas, doneCallback: {[weak self] filterDatas in
            guard let self = self else { return }
            
            self.filterPwmValue = .unselected
            self.filterRatedPower = .unselected
            self.filterAbsoluteSensitivityRange = .unselected
            var showDevices = self.devices
            
            filterDatas.forEach { (type: ParameterFilterData.ParameterType, content: String, selectIndex: Int) in
                switch type {
                case .pwm:
                    let data = pwmContents[selectIndex]
                    if let value = data.value {
                        self.filterPwmValue = .selected(value: value, name: data.name)
                        showDevices = showDevices.filter({ $0.tempPwm == data.value })
                    }else {
                        self.filterPwmValue = .emptySelection
                        showDevices = showDevices.filter({ $0.tempPwm == nil })
                    }
                case .ratedPower:
                    let data = powerDatas[selectIndex]
                    if data.value.isEmpty {
                        self.filterRatedPower = .emptySelection
                        showDevices = showDevices.filter({ $0.tempRatedPowerPhases.isEmpty })
                    }else {
                        self.filterRatedPower = .selected(value: data.value, name: data.name)
                        showDevices = showDevices.filter({ $0.tempRatedPowerPhases == data.value })
                    }
                case .absoluteSensitivity:
                    
                    let data = sensitivityContents[selectIndex]
                    if let value = data.value {
                        self.filterAbsoluteSensitivityRange = .selected(value: value, name: data.name)
                        showDevices = showDevices.filter({ $0.tempSensitivityRange == value })
                    }else {
                        self.filterAbsoluteSensitivityRange = .emptySelection
                        showDevices = showDevices.filter({ $0.tempSensitivityRange == nil })
                    }
                }
            }
            
            self.headerView.filterBtn.isSelected = self.filterPwmValue.rawValue != FilterSelectionState.unselected.rawValue || self.filterRatedPower.rawValue != FilterSelectionState.unselected.rawValue || self.filterAbsoluteSensitivityRange.rawValue != FilterSelectionState.unselected.rawValue
            self.showDevices = showDevices
            self.tableView.reloadData()
            
        }).show()
        
    }
    
    /// 重试
    func promptViewReSyncAction(_ view: DeviceParameterPromptView) {
//        var datas: [(Node, [DeviceParameterType])] = []
       
        let datas = settingFailedDatas.compactMap({ data in
            if let node = self.devices.first(where: { $0.primaryUnicastAddress == data.key }) {
                return (node, data.value)
            }
            return nil
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
                        case .pwmFrequency:
                            node.tempPwm = node.pwmFrequency
                        case .ratedPower:
                            node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                        case .motionSensitivityRange:
                            node.tempSensitivityRange = node.motionSensitivityRange
                        }
                    }
                }
            default:
                break
            }
            
            self.settingFailedDatas.removeAll()
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
                            case .pwmFrequency:
                                node.tempPwm = node.pwmFrequency
                            case .ratedPower:
                                node.tempRatedPowerPhases = node.phaseEnergyConsumptions
                            case .motionSensitivityRange:
                                node.tempSensitivityRange = node.motionSensitivityRange
                            }
                            if var data = self.settingFailedDatas[node.primaryUnicastAddress], let index = data.firstIndex(where: { $0.rawValue == parameterType.rawValue }) {
                                data.remove(at: index)
                                if data.isEmpty {
                                    self.settingFailedDatas.removeValue(forKey: node.primaryUnicastAddress)
                                }else {
                                    self.settingFailedDatas.updateValue(data, forKey: node.primaryUnicastAddress)
                                }
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
    static var tempSensitivityRangeKey = 5
    
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
    
    /// 临时的额定功率（仅在当前页面使用）
    var tempSensitivityRange: ClosedRange<UInt16>? {
        get {
            objc_getAssociatedObject(self, &Node.tempSensitivityRangeKey) as? ClosedRange<UInt16>
        }set {
            objc_setAssociatedObject(self, &Node.tempSensitivityRangeKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
