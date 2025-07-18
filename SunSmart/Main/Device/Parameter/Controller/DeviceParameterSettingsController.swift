//
//  DeviceParameterSettingsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/14.
//

import UIKit
import NordicSigMeshSDK


class DeviceParameterSettingsController: UIViewController {

    /// 设置完成回调  参数：失败的类型及设备
    typealias ParameterSettingsCompletionCallback = (([DeviceParameterData.ParameterType: (value: Any, successNodes: [Node], failedNodes: [Node])])->Void)
   
    private var headerView: DeviceParameterPromptView!
    private var tableView: UITableView!
    private var bottomView: DeviceParameterBottomView!
    
    private var parameterDatas: [DeviceParameterData] = []
    /// 额定功率阶段数据list
    private var ratedPowerPhaseDatas: [DeviceParameterRatedPowerPhaseData] = DeviceParameterRatedPowerPhaseData.default()
    
    let devices: [Node]
    
    var settingsCompletionCallback: ParameterSettingsCompletionCallback?
    
    init(devices: [Node]) {
        self.devices = devices
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "device_parameter_settings".localizedString
        view.backgroundColor = Background_Color
        
        parameterDatas = [
            .init(type: .pwmFrequency, data: 2940, enable: false), .init(type: .ratedPower, data: ratedPowerPhaseDatas, enable: false), .init(type: .motionSensitivityRange, data: UInt8(0)...UInt8(80), enable: false)
        ]
        setupUI()
        
        updateSetupBtnState()
    }
    
    @objc private func previousAction() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func setupAction() {
        
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
                if let range = parameterData.data as? ClosedRange<UInt8> {
                    return .motionSensitivityRange(range: UInt8(Double(range.lowerBound) * 2.55)...UInt8(Double(range.upperBound) * 2.55))
                }
            }
            return nil
        })
        guard devices.count > 0, setParameters.count > 0 else {
            return
        }
        
        setParameters.forEach { type in
            switch type {
            case .pwmFrequency:
                devices.forEach({
                    if $0.restoreData?.pwmFrequency != nil {
                        $0.restoreData?.pwmFrequency = nil
                    }
                })
            case .ratedPower:
                devices.forEach({
                    if $0.restoreData?.phaseEnergyConsumptions != nil {
                        $0.restoreData?.phaseEnergyConsumptions = nil
                    }
                })
            case .motionSensitivityRange:
                devices.forEach({
                    if $0.restoreData?.motionSensitivityRange != nil {
                        $0.restoreData?.motionSensitivityRange = nil
                    }
                })
            }
        }
        
        let vc = SyncDevicesViewController(type: .devicesParameter(devices.map({ ($0, setParameters) })))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            
            var result: [DeviceParameterData.ParameterType: (Any, [Node], [Node])] = [:]
            
            setParameters.forEach { type in
                switch type {
                case .pwmFrequency(let frequency):
                    result.updateValue((frequency, self.devices, []), forKey: .pwmFrequency)
                case .ratedPower:
                    if let parameterData = self.parameterDatas.first(where: { $0.type == .ratedPower }), let data = parameterData.data {
                        result.updateValue((data, self.devices, []), forKey: .ratedPower)
                    }
                case .motionSensitivityRange(let range):
                    result.updateValue((range, self.devices, []), forKey: .motionSensitivityRange)
                }
            }
            self.settingsCompletionCallback?(result)
        }
       
        vc.backActionCallback = {[weak self] resultDatas in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)

            // 返回成功、失败的设备数据
            DispatchQueue.global().async {
                var pwmSuccessNodes: [Node] = []
                var pwmFailedNodes: [Node] = []
                
                var ratedPowerSuccessNodes: [Node] = []
                var ratedPowerFailedNodes: [Node] = []
                
                var sensitivityRangeSuccessNodes: [Node] = []
                var sensitivityRangeFailedNodes: [Node] = []

                resultDatas.forEach { data in
                    data.successOperationTypes.forEach { operationType in
                        switch operationType {
                        case .configuration(_, let type):
                            switch type {
                            case .deviceParameters(let parameterType):
                                switch parameterType {
                                case .pwmFrequency:
                                    pwmSuccessNodes.append(data.node)
                                case .ratedPower:
                                    ratedPowerSuccessNodes.append(data.node)
                                case .motionSensitivityRange:
                                    sensitivityRangeSuccessNodes.append(data.node)
                                }
                            default:
                                break
                            }
                        default:
                            break
                        }
                    }
                    
                    data.failedOperationTypes.forEach { operationType in
                        switch operationType {
                        case .configuration(_, let type):
                            switch type {
                            case .deviceParameters(let parameterType):
                                switch parameterType {
                                case .pwmFrequency:
                                    pwmFailedNodes.append(data.node)
                                case .ratedPower:
                                    ratedPowerFailedNodes.append(data.node)
                                case .motionSensitivityRange:
                                    sensitivityRangeFailedNodes.append(data.node)
                                }
                            default:
                                break
                            }
                        default:
                            break
                        }
                    }
                }
                
                var result: [DeviceParameterData.ParameterType: (Any, [Node], [Node])] = [:]
                if pwmSuccessNodes.count > 0 || pwmFailedNodes.count > 0 {
                    if let pwmData = self.parameterDatas.first(where: { $0.type == .pwmFrequency }) {
                        result.updateValue((pwmData.data!, pwmSuccessNodes, pwmFailedNodes), forKey: pwmData.type)
                    }
                }
                if ratedPowerSuccessNodes.count > 0 || ratedPowerFailedNodes.count > 0 {
                    if let ratedPowerData = self.parameterDatas.first(where: { $0.type == .ratedPower }) {
                        result.updateValue((ratedPowerData.data!, ratedPowerSuccessNodes, ratedPowerFailedNodes), forKey: ratedPowerData.type)
                    }
                }
                if sensitivityRangeSuccessNodes.count > 0 || sensitivityRangeFailedNodes.count > 0 {
                    if let sensitivityRangeData = self.parameterDatas.first(where: { $0.type == .motionSensitivityRange }) {
                        result.updateValue((sensitivityRangeData.data!, sensitivityRangeSuccessNodes, sensitivityRangeFailedNodes), forKey: sensitivityRangeData.type)
                    }
                }
                DispatchQueue.main.async {
                    self.settingsCompletionCallback?(result)
                }
            }
            
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    private func updateSetupBtnState() {
        bottomView.rightBtn.isEnabled = self.parameterDatas.contains(where: ({ $0.enable && $0.data != nil }) )
    }
    
    private func setupUI() {
        
        headerView = DeviceParameterPromptView()
        headerView.titleLabel.text = "device_parameter_step_2".localizedString
        headerView.filterBtn.isHidden = true
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(SCRYFrom(44))
        }
        
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
        tableView.showsVerticalScrollIndicator = false
        tableView.backgroundColor = Background_Color
        tableView.register(DeviceParameterSettingsViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DeviceParameterRetedPowerViewCell.classForCoder(), forCellReuseIdentifier: "retedPowerCell")
        tableView.register(DeviceParameterAbsoluteSensitivityViewCell.classForCoder(), forCellReuseIdentifier: "sensitivityCell")
        
        tableView.estimatedRowHeight = SCRYFrom(148)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }


}

extension DeviceParameterSettingsController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return parameterDatas.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let parameterData = parameterDatas[indexPath.section]
        switch parameterData.type {
        case .ratedPower:
            let ratedPowerCell = tableView.dequeueReusableCell(withIdentifier: "retedPowerCell", for: indexPath) as! DeviceParameterRetedPowerViewCell
            ratedPowerCell.phases = ratedPowerPhaseDatas
            ratedPowerCell.delegate = self
            ratedPowerCell.updateParameterEnable(enable: parameterData.enable)
            return ratedPowerCell
        case .motionSensitivityRange:
            let sensitivityCell = tableView.dequeueReusableCell(withIdentifier: "sensitivityCell", for: indexPath) as! DeviceParameterAbsoluteSensitivityViewCell
            if let range = parameterData.data as? ClosedRange<UInt8> {
                sensitivityCell.selectRange = range
            }
            sensitivityCell.updateParameterEnable(enable: parameterData.enable)
            sensitivityCell.delegate = self
            return sensitivityCell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceParameterSettingsViewCell
            cell.parameterData = parameterData
            cell.delegate = self
            return cell
        }
        
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return SCRYFrom(16)
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
                    self.tableView.reloadSections(IndexSet(integer: index), with: .none)
                    
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
            let data = parameterDatas[indexPath.section]
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
        ratedPowerPhaseDatas.insert(DeviceParameterRatedPowerPhaseData(lightLevel: nil, power: nil, necessary: false), at: ratedPowerPhaseDatas.count - 1)
        cell.phases = ratedPowerPhaseDatas
        if let index = tableView.indexPath(for: cell)?.row {
            tableView.reloadRows(at: [IndexPath(row: 0, section: index)], with: .none)
        }
    }
    
    /// 删除阶段
    func cell(_ cell: DeviceParameterRetedPowerViewCell, deletePhase phase: DeviceParameterRatedPowerPhaseData) {
        if !phase.necessary, let index = ratedPowerPhaseDatas.firstIndex(of: phase) {
            ratedPowerPhaseDatas.remove(at: index)
            cell.phases = ratedPowerPhaseDatas
            if let index = tableView.indexPath(for: cell)?.row {
                tableView.reloadRows(at: [IndexPath(row: 0, section: index)], with: .none)
            }
        }
    }
    
    /// 启用/禁用编辑
    func cell(_ cell: DeviceParameterRetedPowerViewCell, parameterEnableStateChanged enable: Bool) {
        if let indexPath = tableView.indexPath(for: cell) {
            let data = parameterDatas[indexPath.section]
            data.enable = enable
//            tableView.reloadRows(at: [indexPath], with: .none)
            
            updateSetupBtnState()
        }
        tableView.performBatchUpdates(nil)
    }
    
}

extension DeviceParameterSettingsController: DeviceParameterAbsoluteSensitivityViewCellDelegate {
    
    /// 修改灵敏度范围
    func cell(_ cell: DeviceParameterAbsoluteSensitivityViewCell, changeSensitivityRange range: ClosedRange<UInt8>) {
        
        if let index = self.parameterDatas.firstIndex(where: { $0.type == .motionSensitivityRange }) {
            self.parameterDatas[index].data = range
            self.updateSetupBtnState()
        }
    }
    
    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterAbsoluteSensitivityViewCell, parameterEnableStateChanged enable: Bool) {
        if let indexPath = tableView.indexPath(for: cell) {
            let data = parameterDatas[indexPath.section]
            data.enable = enable
            updateSetupBtnState()
        }
        tableView.performBatchUpdates(nil)
    }
    
}
