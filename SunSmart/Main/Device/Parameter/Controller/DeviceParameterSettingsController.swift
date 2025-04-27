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
    typealias ParameterSettingsCompletionCallback = (([ParameterType: (successNodes: [Node], failedNodes: [Node])])->Void)
   
    private var headerView: DeviceParameterPromptView!
    private var tableView: UITableView!
    private var bottomView: DeviceParameterBottomView!
    
    private var parameters: [ParameterType] = []
    
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
        
        parameters = [.pwmFrequency(value: nil), .ratedPower(value: nil)]
        setupUI()
    }
    
    @objc private func previousAction() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func setupAction() {
        
        let setParameters: [DeviceParameterType] = parameters.compactMap({ parameter in
            switch parameter {
            case .pwmFrequency(let value):
                if let value = value, value >= UInt16.min && value <= UInt16.max {
                    return .pwmPeriod(period: UInt16(value))
                }
            case .ratedPower(let value):
                if let value = value {
                    return .ratedPower(value: value)
                }
            }
            return nil
        })
        guard devices.count > 0, setParameters.count > 0 else {
            return
        }
        
        let vc = SyncDevicesViewController(type: .devicesParameter(devices.map({ ($0, setParameters) })))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            
            var result: [ParameterType: ([Node], [Node])] = [:]
            self.parameters.forEach { type in
                result.updateValue((self.devices, []), forKey: type)
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

                resultDatas.forEach { data in
                    data.successOperationTypes.forEach { operationType in
                        switch operationType {
                        case .configuration(_, let type):
                            switch type {
                            case .deviceParameters(let parameterType):
                                switch parameterType {
                                case .pwmPeriod:
                                    pwmSuccessNodes.append(data.node)
                                case .ratedPower:
                                    ratedPowerSuccessNodes.append(data.node)
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
                                case .pwmPeriod:
                                    pwmFailedNodes.append(data.node)
                                case .ratedPower:
                                    ratedPowerFailedNodes.append(data.node)
                                }
                            default:
                                break
                            }
                        default:
                            break
                        }
                    }
                }
                
                var result: [ParameterType: ([Node], [Node])] = [:]
                if let pwmType = self.parameters.first(where: { $0.rawValue == ParameterType.pwmFrequency(value: nil).rawValue }) {
                    result.updateValue((pwmSuccessNodes, pwmFailedNodes), forKey: pwmType)
                }
                if let ratedPowerType = self.parameters.first(where: { $0.rawValue == ParameterType.ratedPower(value: nil).rawValue }) {
                    result.updateValue((ratedPowerSuccessNodes, ratedPowerFailedNodes), forKey: ratedPowerType)
                }
                DispatchQueue.main.async {
                    self.settingsCompletionCallback?(result)
                }
            }
            
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    private func updateSetupBtnState() {
        bottomView.rightBtn.isEnabled = self.parameters.contains(where: ({ $0.data.value != nil }) )
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
        tableView.register(DeviceParameterSettingsViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.estimatedRowHeight = SCRYFrom(148)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }


}

extension DeviceParameterSettingsController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return parameters.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceParameterSettingsViewCell
        cell.parameterType = parameters[indexPath.row]
        cell.delegate = self
        return cell
    }
    
}

extension DeviceParameterSettingsController: DeviceParameterSettingsViewCellDelegate {
    
    /// 设置参数
    func cell(_ cell: DeviceParameterSettingsViewCell, settingParameters type: DeviceParameterSettingsController.ParameterType) {
        switch type {
        case .pwmFrequency(let value):
            DevicePwmFrequencySelectView(selectFrequency: value, selectCallback: {[weak self] frequency in
                guard let self = self else { return }
                if let index = self.parameters.firstIndex(where: { $0.rawValue == type.rawValue }) {
                    self.parameters[index] = .pwmFrequency(value: frequency)
                    self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                    
                    self.updateSetupBtnState()
                }
            }).show()
            
        case .ratedPower(let value):
            let data = type.data
            let range = data.range ?? 1...99999
            SRAlertView(title: "\(data.title) \("input".localizedString)", inputText: value != nil ? "\(value!)" : nil, inputFieldStyle: .init(placeholder: "\(range.lowerBound)~\(range.upperBound)", keyboardType: .numberPad, minInputLength: 1), actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString)]) { text, _ in
                guard let value = Int(text) else {
                    return nil
                }
                if !range.contains(value) {
                    return "\("limit_range".localizedString) \(range.lowerBound)~\(range.upperBound)"
                }
                return nil
            } inputDoneBack: {[weak self] text in
                guard let self = self, let value = Int(text) else { return }
                
                if let index = self.parameters.firstIndex(where: { $0.rawValue == type.rawValue }) {
                    self.parameters[index] = .ratedPower(value: value)
                    self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
                }
                self.updateSetupBtnState()
            }.show()

        }
    }
}

extension DeviceParameterSettingsController {
    
    /// 参数类型
    enum ParameterType: Hashable {
        
        var data: (title: String, message: String, value: Int?, range: ClosedRange<Int>?, unit: String) {
            switch self {
            case .pwmFrequency(let value):
                return ("pwm_frequency".localizedString, "pwm_frequency_message".localizedString, value, nil, "Hz")
            case .ratedPower(let value):
                return ("rated_power".localizedString, "rated_power_message".localizedString, value, 1...99999, "W")
            }
        }
        
        var rawValue: Int {
            switch self {
            case .pwmFrequency:
                return 1
            case .ratedPower:
                return 2
            }
        }
        
        /// pwm频率
        case pwmFrequency(value: Int?)
        /// 额定功率
        case ratedPower(value: Int?)
    }
    
}
