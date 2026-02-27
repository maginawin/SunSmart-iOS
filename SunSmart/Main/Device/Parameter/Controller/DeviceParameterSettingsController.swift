//
//  DeviceParameterSettingsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/14.
//

import UIKit
import NordicSigMeshSDK


class DeviceParameterSettingsController: UIViewController {

    enum DisplayMode {
        case full
        case behaviorOnly
    }
    
    enum SectionType {
        case energyReporting
        case parameter
    }
    
    struct ParameterSettingsResultItem {
        let parameterType: DeviceParameterData.ParameterType
        let parameter: DeviceParameterType
        let successNodes: [Node]
        let failedNodes: [Node]
    }
    
    /// 设置完成回调
    typealias ParameterSettingsCompletionCallback = (([ParameterSettingsResultItem])->Void)
   
//    private var headerView: DeviceParameterPromptView!
    private var tableView: UITableView!
    private var bottomView: DeviceParameterBottomView!
    
    private var sections: [SectionType] = []
    private var parameterDatas: [DeviceParameterData] = []
    
    /// 额定功率阶段数据list
    private var ratedPowerPhaseDatas: [DeviceParameterRatedPowerPhaseData] = DeviceParameterRatedPowerPhaseData.default()
    private var behaviorMode: DeviceBlinkMode = .breathing
    private var behaviorDetailsExpanded = true
    
    let devices: [Node]
    let displayMode: DisplayMode
    
    var settingsCompletionCallback: ParameterSettingsCompletionCallback?
    /// 默认的传感器灵敏度
    private var defaultMotionSensitivityRange: ClosedRange<Double> = 0...100
    /// 默认过渡时间
    private var defaultTransitionTime: TransitionTime = .init(1)
    
    init(devices: [Node], displayMode: DisplayMode = .full) {
        self.devices = devices
        self.displayMode = displayMode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "device_parameter_settings".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        if displayMode == .behaviorOnly {
            if let spaceBlinkMode = SpaceViewController.currentSpace()?.deviceBlinkMode,
               let mode = DeviceBlinkMode(rawValue: spaceBlinkMode.rawValue) {
                behaviorMode = mode
            }
            parameterDatas = [
                .init(type: .behaviorAfterSetupSuccess, data: behaviorMode.rawValue, enable: true)
            ]
            sections = [.parameter]
            setupUI()
            updateSetupBtnState()
            return
        }
        
//        var motionSensitivityRange: ClosedRange<Double>?
        // 获取设备配置的灵敏度
        if let device = devices.first(where: { $0.deviceConfigInfo?.sensitivityRange != nil }), let sensitivityValueRange = device.deviceConfigInfo?.sensitivityRange {
            defaultMotionSensitivityRange = Double(sensitivityValueRange.lowerBound.percentageFloat)...Double(sensitivityValueRange.upperBound.percentageFloat)
        }
        
        if let node = devices.first {
            
            if node.supportRealPowerMetering {
                sections.insert(.energyReporting, at: 0)
            }else {
                parameterDatas.append(.init(type: .ratedPower, data: ratedPowerPhaseDatas, enable: false))
            }
            
            if node.supportPwmFrequency {
                parameterDatas.append(.init(type: .pwmFrequency, data: 2940, enable: false))
            }
            if node.supportMotionSensitivity {
                parameterDatas.append(.init(type: .motionSensitivityRange, data: defaultMotionSensitivityRange, enable: false))
            }
            if node.supportDefaultTransitionTime {
                parameterDatas.append(.init(type: .defalutTransitionTime, data: defaultTransitionTime, enable: false))
            }
        }else {
            parameterDatas = [
                .init(type: .pwmFrequency, data: 2940, enable: false),
                .init(type: .ratedPower, data: ratedPowerPhaseDatas, enable: false),
                .init(type: .motionSensitivityRange, data: defaultMotionSensitivityRange, enable: false),
                .init(type: .defalutTransitionTime, data: defaultTransitionTime, enable: false)
            ]
        }
        if parameterDatas.count > 0 {
            sections.append(.parameter)
        }
        
        setupUI()
        
        updateSetupBtnState()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    @objc private func previousAction() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func setupAction() {
        
        if displayMode == .behaviorOnly {
            if let space = SpaceViewController.currentSpace(),
               let mode = DeviceBlinkMode(rawValue: behaviorMode.rawValue) {
                space.deviceBlinkMode = mode
                _ = space.save()
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            }
            navigationController?.popViewController(animated: true)
            return
        }
        
        // 未输入数据
        if let emptyParameterData = parameterDatas.first(where: { $0.enable && $0.data == nil }) {
            let title = emptyParameterData.type.data.title
            XWHUDManager.showTipHUD(String(format: "device_parameter_no_set_message".localizedString, title), isLineFeed: true)
            return
        }
        
        // 能耗数据
        if let ratedPowerData = parameterDatas.first(where: { $0.type == .ratedPower }), ratedPowerData.enable {
            ratedPowerData.data = ratedPowerPhaseDatas
            // 校验数据
            guard let phaseDatas = ratedPowerData.data as? [DeviceParameterRatedPowerPhaseData] else {
                XWHUDManager.showTipHUD("rated_power_no_set_message".localizedString, isLineFeed: true)
                return
            }
            if phaseDatas.contains(where: { $0.lightLevel == nil || $0.power == nil }) {
                XWHUDManager.showTipHUD("rated_power_no_set_message".localizedString, isLineFeed: true)
                return
            }
        }
        
        
        let setParameters: [DeviceParameterType] = parameterDatas.filter({ $0.enable }).compactMap({ parameterData in
            switch parameterData.type {
            case .pwmFrequency:
                if let value = parameterData.data as? Int, value >= UInt16.min && value <= UInt16.max {
                    return .pwmFrequency(frequency: UInt16(value))
                }
            case .ratedPower:
                if let phases = parameterData.data as? [DeviceParameterRatedPowerPhaseData] {
                    return .ratedPower(datas: phases.compactMap({ $0.toNodePhaseEnergyConsumption() }))
                }
            case .motionSensitivityRange:
                if let range = parameterData.data as? ClosedRange<Double> {
                    
                    let min = (range.lowerBound * 10).rounded() / 10.0
                    let max = (range.upperBound * 10).rounded() / 10.0
                    
                    return .motionSensitivityRange(range: min.value16...max.value16)
                }
            case .defalutTransitionTime:
                if let value = parameterData.data as? TransitionTime {
                    return .defaultTransitionTime(transitionTime: value)
                }
            case .behaviorAfterSetupSuccess:
//                if let value = parameterData.data as?
                break
            }
            return nil
        })
        guard devices.count > 0, setParameters.count > 0 else {
            return
        }
        
        var saveDevices: [Node] = []
        setParameters.forEach { type in
            switch type {
            case .pwmFrequency:
                devices.forEach({
                    if $0.restoreData?.pwmFrequency != nil {
                        $0.restoreData?.pwmFrequency = nil
                        if !saveDevices.contains($0) {
                            saveDevices.append($0)
                        }
                    }
                })
            case .ratedPower:
                devices.forEach({
                    if $0.restoreData?.phaseEnergyConsumptions != nil {
                        $0.restoreData?.phaseEnergyConsumptions = nil
                        if !saveDevices.contains($0) {
                            saveDevices.append($0)
                        }
                    }
                })
            case .motionSensitivityRange:
                devices.forEach({
                    if $0.restoreData?.motionSensitivityRange != nil {
                        $0.restoreData?.motionSensitivityRange = nil
                        if !saveDevices.contains($0) {
                            saveDevices.append($0)
                        }
                    }
                })
            case .defaultTransitionTime:
                devices.forEach {
                    if $0.restoreData?.defaultTransitionTime != nil {
                        $0.restoreData?.defaultTransitionTime = nil
                        if !saveDevices.contains($0) {
                            saveDevices.append($0)
                        }
                    }
                }
            default:
                break
            }
        }
        
        let vc = SyncDevicesViewController(type: .devicesParameter(devices.map({ ($0, setParameters) })))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                self?.navigationController?.popToViewController(vcClass: DeviceParameterDevicesViewController.classForCoder())
            }
            
            let result = setParameters.compactMap { parameter -> ParameterSettingsResultItem? in
                guard let type = self.parameterDataType(from: parameter) else { return nil }
                return ParameterSettingsResultItem(parameterType: type, parameter: parameter, successNodes: self.devices, failedNodes: [])
            }
            self.settingsCompletionCallback?(result)
        }
       
        vc.backActionCallback = {[weak self] resultDatas in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)

            // 返回成功、失败的设备数据
            DispatchQueue.global().async {
                var successNodesMap: [DeviceParameterData.ParameterType: [Node]] = [:]
                var failedNodesMap: [DeviceParameterData.ParameterType: [Node]] = [:]
                
                resultDatas.forEach { data in
                    data.successOperationTypes.forEach { operationType in
                        if let parameterType = self.parameterDataType(fromOperationType: operationType) {
                            successNodesMap[parameterType, default: []].append(data.node)
                        }
                    }
                    
                    data.failedOperationTypes.forEach { operationType in
                        if let parameterType = self.parameterDataType(fromOperationType: operationType) {
                            failedNodesMap[parameterType, default: []].append(data.node)
                        }
                    }
                }
                
                let result = setParameters.compactMap { parameter -> ParameterSettingsResultItem? in
                    guard let parameterType = self.parameterDataType(from: parameter) else { return nil }
                    let successNodes = successNodesMap[parameterType, default: []]
                    let failedNodes = failedNodesMap[parameterType, default: []]
                    guard !successNodes.isEmpty || !failedNodes.isEmpty else { return nil }
                    return ParameterSettingsResultItem(parameterType: parameterType, parameter: parameter, successNodes: successNodes, failedNodes: failedNodes)
                }
                
                DispatchQueue.main.async {
                    self.settingsCompletionCallback?(result)
                }
            }
            
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    private func updateSetupBtnState() {
        if displayMode == .behaviorOnly {
            bottomView.rightBtn.isEnabled = true
            return
        }
        bottomView.rightBtn.isEnabled = self.parameterDatas.contains(where: ({ $0.enable && $0.data != nil }) )
    }
    
    private func parameterDataType(from parameter: DeviceParameterType) -> DeviceParameterData.ParameterType? {
        switch parameter {
        case .pwmFrequency:
            return .pwmFrequency
        case .ratedPower:
            return .ratedPower
        case .motionSensitivityRange:
            return .motionSensitivityRange
        case .defaultTransitionTime:
            return .defalutTransitionTime
        case .powerCalibration:
            return nil
        }
    }
    
    private func parameterDataType(fromOperationType operationType: DeviceOperationType) -> DeviceParameterData.ParameterType? {
        switch operationType {
        case .configuration(_, let type):
            switch type {
            case .deviceParameters(let parameterType):
                switch parameterType {
                case .pwmFrequency:
                    return .pwmFrequency
                case .ratedPower:
                    return .ratedPower
                case .motionSensitivityRange:
                    return .motionSensitivityRange
                case .defaultTransitionTime:
                    return .defalutTransitionTime
                case .powerCalibration:
                    return nil
                }
            default:
                return nil
            }
        default:
            return nil
        }
    }
    
    private func reloadEnergyDevice(_ device: Node) {
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: sections.firstIndex(of: .energyReporting) ?? 0)) as? DeviceParameterEnergyReportViewCell {
            cell.reloadDevice(device: device)
        }
    }
    
    private func energyInhibit(devices: [Node]) {
        
        let vc = SyncDevicesViewController(type: .devicesParameter(devices.map({ ($0, [.ratedPower(datas: [])]) })))
        vc.vcTitle = "read_rated_power".localizedString
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            devices.forEach({
                self.reloadEnergyDevice($0)
            })
            
            self.settingsCompletionCallback?([
                .init(parameterType: .ratedPower, parameter: .ratedPower(datas: []), successNodes: devices, failedNodes: [])
            ])
        }
        vc.backActionCallback = {[weak self] result in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            devices.forEach({
                self.reloadEnergyDevice($0)
            })
            let nodes = result.map({ $0.node })
//                .compactMap({ $0.successOperationTypes.count > 0 ? $0.node : nil })
//            let failNodes = result.compactMap({ $0.failedOperationTypes.count > 0 ? $0.node : nil })
            self.settingsCompletionCallback?([
                .init(parameterType: .ratedPower, parameter: .ratedPower(datas: []), successNodes: nodes, failedNodes: [])
            ])
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func energyActivate(devices: [Node]) {
        
        let vc = ReadDevicesDataViewController(type: .readRatedPower(nodes: devices))
        vc.readSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            devices.forEach({
                self.reloadEnergyDevice($0)
            })
            self.settingsCompletionCallback?([
                .init(parameterType: .ratedPower, parameter: .ratedPower(datas: []), successNodes: devices, failedNodes: [])
            ])
        }
        vc.backActionCallback = {[weak self] result in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            devices.forEach({
                self.reloadEnergyDevice($0)
            })
//            let successNodes = result.compactMap({ $0.successOperationTypes.count > 0 ? $0.node : nil })
//            let nodes = result.map({ $0.node })
            self.settingsCompletionCallback?([
                .init(parameterType: .ratedPower, parameter: .ratedPower(datas: []), successNodes: devices, failedNodes: [])
            ])
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    private func setupUI() {
        
//        headerView = DeviceParameterPromptView()
//        headerView.titleLabel.text = "device_parameter_step_2".localizedString
//        headerView.filterBtn.isHidden = true
//        view.addSubview(headerView)
//        headerView.snp.makeConstraints { make in
//            make.left.right.equalToSuperview()
//            make.top.equalTo(view.safeAreaLayoutGuide)
//            make.height.equalTo(SCRYFrom(44))
//        }
        
        bottomView = DeviceParameterBottomView()
        bottomView.leftBtn.setTitle("PREVIOUS".localizedString, for: .normal)
        bottomView.leftBtn.addTarget(self, action: #selector(previousAction), for: .touchUpInside)
        bottomView.rightBtn.setTitle("SET_UP".localizedString, for: .normal)
        bottomView.rightBtn.addTarget(self, action: #selector(setupAction), for: .touchUpInside)
        bottomView.rightBtn.isEnabled = false
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.backgroundColor = Background_Color
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.register(DeviceParameterSettingsViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DeviceParameterRetedPowerViewCell.classForCoder(), forCellReuseIdentifier: "retedPowerCell")
        tableView.register(DeviceParameterAbsoluteSensitivityViewCell.classForCoder(), forCellReuseIdentifier: "sensitivityCell")
        tableView.register(DeviceParameterSliderViewCell.classForCoder(), forCellReuseIdentifier: "sliderCell")
        tableView.register(DeviceParameterBehaviorAfterSetupViewCell.classForCoder(), forCellReuseIdentifier: "behaviorCell")
        tableView.register(DeviceParameterEnergyReportViewCell.classForCoder(), forCellReuseIdentifier: "energyReportCell")
        tableView.register(DeviceParameterTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.estimatedRowHeight = SCRYFrom(148)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
//            make.right.equalTo(SCRXFrom(-16))
//            make.top.equalTo(headerView.snp.bottom)
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(7))
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }


}

extension DeviceParameterSettingsController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if sections[section] == .energyReporting {
            return 1
        }
        return parameterDatas.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        switch sections[indexPath.section] {
        case .energyReporting:
            let cell = tableView.dequeueReusableCell(withIdentifier: "energyReportCell", for: indexPath) as! DeviceParameterEnergyReportViewCell
            cell.devices = devices
            cell.delegate = self
            return cell
            
        case .parameter:
            let parameterData = parameterDatas[indexPath.row]
            switch parameterData.type {
            case .behaviorAfterSetupSuccess:
                let behaviorCell = tableView.dequeueReusableCell(withIdentifier: "behaviorCell", for: indexPath) as! DeviceParameterBehaviorAfterSetupViewCell
                behaviorCell.delegate = self
                behaviorCell.configure(mode: behaviorMode, detailsExpanded: behaviorDetailsExpanded, noteText: parameterData.type.data.message)
                return behaviorCell
            case .ratedPower:
                let ratedPowerCell = tableView.dequeueReusableCell(withIdentifier: "retedPowerCell", for: indexPath) as! DeviceParameterRetedPowerViewCell
                ratedPowerCell.phases = ratedPowerPhaseDatas
                ratedPowerCell.delegate = self
                ratedPowerCell.updateParameterEnable(enable: parameterData.enable)
                return ratedPowerCell
            case .motionSensitivityRange:
                let sensitivityCell = tableView.dequeueReusableCell(withIdentifier: "sensitivityCell", for: indexPath) as! DeviceParameterAbsoluteSensitivityViewCell
                if let range = parameterData.data as? ClosedRange<Double> {
                    sensitivityCell.selectRange = range
                }
                sensitivityCell.updateParameterEnable(enable: parameterData.enable)
                sensitivityCell.delegate = self
                return sensitivityCell
            case .defalutTransitionTime:
                let sliderCell = tableView.dequeueReusableCell(withIdentifier: "sliderCell", for: indexPath) as! DeviceParameterSliderViewCell
                let data = parameterData.type.data
                sliderCell.titleLabel.text = "\(data.title):"
                sliderCell.noteLabel.text = data.message
                let list = DeviceParameterData.transitionTimeDatas
                sliderCell.slider.minimumValue = 0
                sliderCell.slider.maximumValue = Float(list.count - 1)
                if let transitionTime = parameterData.data as? TransitionTime, let index = list.firstIndex(where: { $0.timeInterval == transitionTime.interval }) {
                    sliderCell.slider.value = Float(index)
                    sliderCell.valueLabel.text = list[index].timeStr
                }
                
                sliderCell.updateParameterEnable(enable: parameterData.enable)
                sliderCell.delegate = self
                return sliderCell
            default:
                let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceParameterSettingsViewCell
                cell.parameterData = parameterData
                cell.delegate = self
                return cell
            }
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if displayMode == .behaviorOnly {
            let clearView = UIView()
            clearView.backgroundColor = .clear
            return clearView
        }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceParameterTitleHeaderView
        switch sections[section] {
        case .energyReporting:
            header.titleLabel.text = "2.\("energy_reporting".localizedString)"
            header.bottomMargin = SCRYFrom(5)
        case .parameter:
            header.titleLabel.text = sections.contains(.energyReporting) ? "3.\("parameter_selection".localizedString)" : "2.\("parameter_selection".localizedString)"
            header.bottomMargin = SCRYFrom(8)
        }
        return header
    }
 
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if displayMode == .behaviorOnly {
            return .leastNormalMagnitude
        }
        return SCRYFrom(32)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
}

extension DeviceParameterSettingsController: DeviceParameterSettingsViewCellDelegate {
    
    /// 设置参数
    func cell(_ cell: DeviceParameterSettingsViewCell, settingParameters data: DeviceParameterData) {
        switch data.type {
        case .pwmFrequency:
            DevicePwmFrequencySelectView(selectFrequency: (data.data as? Int) ?? 2940, selectCallback: {[weak self] frequency in
                guard let self = self else { return }
                if let index = self.parameterDatas.firstIndex(where: { $0.type == data.type }) {
                    self.parameterDatas[index].data = frequency
                    self.tableView.reloadRows(at: [IndexPath(row: index, section: self.sections.firstIndex(of: .parameter) ?? 0)], with: .none)
//                    self.tableView.reloadSections(IndexSet(integer: index), with: .none)
                    
                    self.updateSetupBtnState()
                }
            }).show()
            
        default:
            break
        }
    }
    
    /// 启用/禁用编辑
    func cell(_ cell: DeviceParameterSettingsViewCell, parameterEnableStateChanged enable: Bool) {
        if let indexPath = tableView.indexPath(for: cell) {
            let data = parameterDatas[indexPath.row]
            data.enable = enable
//            tableView.reloadRows(at: [indexPath], with: .none)
            updateSetupBtnState()
        }
        tableView.performBatchUpdates(nil)
    }
    
}

extension DeviceParameterSettingsController: DeviceParameterRetedPowerViewCellDelegate {
    
    /// 添加阶段
    func ratedPowerCellAddPhase(_ cell: DeviceParameterRetedPowerViewCell) {
        guard ratedPowerPhaseDatas.count < 10 else {
            return
        }
        ratedPowerPhaseDatas.insert(DeviceParameterRatedPowerPhaseData(lightLevel: nil, power: nil, necessary: false), at: ratedPowerPhaseDatas.count - 1)
        cell.phases = ratedPowerPhaseDatas
        if let indexPath = tableView.indexPath(for: cell) {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
    
    /// 删除阶段
    func cell(_ cell: DeviceParameterRetedPowerViewCell, deletePhase phase: DeviceParameterRatedPowerPhaseData) {
        if !phase.necessary, let index = ratedPowerPhaseDatas.firstIndex(of: phase) {
            ratedPowerPhaseDatas.remove(at: index)
            cell.phases = ratedPowerPhaseDatas
            if let indexPath = tableView.indexPath(for: cell) {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
    }
    
    /// 启用/禁用编辑
    func cell(_ cell: DeviceParameterRetedPowerViewCell, parameterEnableStateChanged enable: Bool) {
        if let indexPath = tableView.indexPath(for: cell) {
            let data = parameterDatas[indexPath.row]
            data.enable = enable
//            tableView.reloadRows(at: [indexPath], with: .none)
            
            updateSetupBtnState()
            self.tableView.reloadRows(at: [indexPath], with: .automatic)
//            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
        }
      
//        tableView.performBatchUpdates(nil)
    }
    
}

extension DeviceParameterSettingsController: DeviceParameterAbsoluteSensitivityViewCellDelegate {
    
    /// 修改灵敏度范围
    func cell(_ cell: DeviceParameterAbsoluteSensitivityViewCell, changeSensitivityRange range: ClosedRange<Double>) {
        
        if let index = self.parameterDatas.firstIndex(where: { $0.type == .motionSensitivityRange }) {
            self.parameterDatas[index].data = range
            self.updateSetupBtnState()
        }
    }
    
    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterAbsoluteSensitivityViewCell, parameterEnableStateChanged enable: Bool) {
        if let indexPath = tableView.indexPath(for: cell) {
            let data = parameterDatas[indexPath.row]
            data.enable = enable
            updateSetupBtnState()
        }
        tableView.performBatchUpdates(nil)
    }
    
    /// 恢复默认值
    func sensitivityViewCellResetAction(_ cell: DeviceParameterAbsoluteSensitivityViewCell) {
        cell.selectRange = defaultMotionSensitivityRange
    }
    
}

extension DeviceParameterSettingsController: DeviceParameterSliderViewCellDelegate {
    
    /// 修改滑条数值
    func cell(_ cell: DeviceParameterSliderViewCell, sliderValueChange value: Int) {
        guard let index = tableView.indexPath(for: cell)?.row else {
            return
        }
        switch parameterDatas[index].type {
        case .defalutTransitionTime:
            let data = DeviceParameterData.transitionTimeDatas[value]
            cell.valueLabel.text = data.timeStr
            self.parameterDatas[index].data = TransitionTime(data.timeInterval)
            self.updateSetupBtnState()
        default:
            break
        }
        
    }
    
    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterSliderViewCell, parameterEnableStateChanged enable: Bool) {
        if let indexPath = tableView.indexPath(for: cell) {
            let data = parameterDatas[indexPath.row]
            data.enable = enable
            updateSetupBtnState()
        }
        tableView.performBatchUpdates(nil)
    }
    
    /// 恢复
    func sensitivityViewCellResetAction(_ cell: DeviceParameterSliderViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        parameterDatas[indexPath.row].data = defaultTransitionTime
        tableView.reloadRows(at: [indexPath], with: .none)
    }
    
}

extension DeviceParameterSettingsController: DeviceParameterEnergyReportViewCellDelegate {

    
    /// 校准点击事件
    func energyReportViewCellCalibrateAction(_ cell: DeviceParameterEnergyReportViewCell) {
        
        let vc = DeviceRatedPowerCalibrationController(devices: devices)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 禁用所有自动功耗设置
    func energyReportViewCellInhibitAllAction(_ cell: DeviceParameterEnergyReportViewCell) {
        
        SRAlertView(title: "notification".localizedString, message: "energy_inhibit_all_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "Reset".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            self.energyInhibit(devices: self.devices)
        })]).show()
        
    }
    
    /// 启用所有自动功耗设置
    func energyReportViewCellActivateAllAction(_ cell: DeviceParameterEnergyReportViewCell) {
        
        SRAlertView(title: "notification".localizedString, message: "energy_activate_all_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ACTIVATE".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            self.energyActivate(devices: self.devices)
        })]).show()
    }
    
    /// 启用/禁用自动功耗设置
    func cell(_ cell: DeviceParameterEnergyReportViewCell, deviceActivateAction device: Node, activate: Bool) {
        if activate {
            energyActivate(devices: [device])
        }else {
            energyInhibit(devices: [device])
        }
    }
    
    /// 识别设备
    func cell(_ cell: DeviceParameterEnergyReportViewCell, deviceIdentify device: NordicSigMeshSDK.Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
}

extension DeviceParameterSettingsController: DeviceParameterBehaviorAfterSetupViewCellDelegate {
    
    func cell(_ cell: DeviceParameterBehaviorAfterSetupViewCell, didSelect mode: DeviceBlinkMode) {
        behaviorMode = mode
        if let indexPath = tableView.indexPath(for: cell), indexPath.row < parameterDatas.count {
            parameterDatas[indexPath.row].data = mode.rawValue
        }
        updateSetupBtnState()
        
        switch mode {
        case .fast:
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .flash(count: 2))), address: .allNodes)
        case .none:
            break
        case .breathing:
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))), address: .allNodes)
        }
        
    }
    
    func cell(_ cell: DeviceParameterBehaviorAfterSetupViewCell, detailsExpandedChanged expanded: Bool) {
        behaviorDetailsExpanded = expanded
        tableView.performBatchUpdates(nil)
    }
}
