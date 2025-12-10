//
//  DeviceRatedPowerCalibrationController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/6.
//

import UIKit
import NordicSigMeshSDK

class DeviceRatedPowerCalibrationController: UIViewController {

    enum SetMode {
        /// 单独设置
        case separately
        /// 全部设置
        case all
    }
    
    private var headerView: DeviceRatedPowerCalibrationHeaderView!
    private var tableView: UITableView!
    private var bottomView: UIView!
    private var calibrateBtn: UIButton!
    
    private var setAllPowerText: String?
    
    private var setMode: SetMode = .separately
    
    let devices: [Node]
    
    init(devices: [Node]) {
        self.devices = devices
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "calibration".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "help")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(helpAction))
        
        devices.forEach({
            $0.unfold = false
            $0.inputPower = nil
            $0.powerCalibrateError = nil
            $0.testCurrentPower = nil
            $0.powerCalibrateState = .none
        })
        
        setupUI()
    }
    

    @objc private func helpAction() {
        navigationController?.pushViewController(DevicePowerCalibrationInstructionsController(), animated: true)
    }
    
    @objc private func setAllDimSaveAction() {
        
        guard let pid = devices.first?.productIdentifier else { return }
        
        MeshAPI.sendMessage(message: SunricherVendorSet(function: .dimmerCollectRatedPower(pid: pid)), address: .allNodes)
        headerView.dimSaveBtn.setImage(UIImage(named: "sync_loading_small"), for: .normal)
        headerView.dimSaveBtn.imageView?.layer.addRotationAnimation(duration: 1, repeatCount: 999, animationKey: "loading")
        headerView.dimSaveBtn.setTitle(nil, for: .normal)
        headerView.dimSaveBtn.isUserInteractionEnabled = false
        
        view.endEditing(true)
        
        view.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {[weak self] in
            guard let self = self else { return }
            self.view.isUserInteractionEnabled = true
            self.headerView.dimSaveBtn.setImage(nil, for: .normal)
            self.headerView.dimSaveBtn.imageView?.layer.removeAnimation(forKey: "loading")
            self.headerView.dimSaveBtn.setTitle("Dim&Save".localizedString, for: .normal)
            self.headerView.dimSaveBtn.isUserInteractionEnabled = true
        }
        
    }
    
    @objc private func calibrateBtnAction() {
        
        if setMode == .separately {
            let canCalibrateDevices = devices.filter({ $0.inputPower != nil })
            if canCalibrateDevices.count > 0 {
                calibrate(deviceDatas: canCalibrateDevices.map({ ($0, $0.inputPower!) }))
            }
        }else {
            guard let text = setAllPowerText, let value = Double(text), Int(value * 100) < UInt32.max else { return }
            
            let power = UInt32(value * 100)
            calibrate(deviceDatas: devices.map({ ($0, power) }))
        }
        
    }
    
    /// 校准
    private func calibrate(deviceDatas: [(node: Node, value: UInt32)]) {
        
        let syncDatas = deviceDatas.map({ ($0.node, [DeviceParameterType.powerCalibration(calibrationValue: $0.value)]) })
        
        let vc = SyncDevicesViewController(type: .devicesParameter(syncDatas))
        vc.vcTitle = "Power Calibrate".localizedString
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            deviceDatas.map({ $0.node }).forEach({
                $0.inputPower = nil
                $0.powerCalibrateError = nil
                if self.setMode == .separately {
                    self.reloadDeviceCell(device: $0)
                }
            })
            if self.setMode == .all {
                self.setAllPowerText = nil
//                self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
                self.setMode = .separately
                self.headerView.segmentControl.selectedIndex = 0
                self.tableView.reloadData()
            }
           
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            deviceDatas.map({ $0.node }).forEach({
                self.reloadDeviceCell(device: $0)
            })
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    private func reloadDeviceCell(device: Node) {
        guard setMode == .separately else {
            return
        }
        if let index = devices.firstIndex(of: device), let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? DeviceRatedPowerCalibrationSetSeparatelyViewCell {
            cell.device = device
        }
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        calibrateBtn = UIButton(title: "CALIBRATE".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(calibrateBtnAction))
        bottomView.addSubview(calibrateBtn)
        calibrateBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.backgroundColor = Background_Color
//        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: <#T##CGFloat#>, bottom: <#T##CGFloat#>, right: <#T##CGFloat#>)
        tableView.register(DeviceRatedPowerCalibrationSetSeparatelyViewCell.classForCoder(), forCellReuseIdentifier: "setSeparatelyCell")
        tableView.register(DeviceRatedPowerCalibrationSetAllViewCell.classForCoder(), forCellReuseIdentifier: "setAllCell")
        tableView.estimatedRowHeight = UITableView.automaticDimension
        tableView.dataSource = self
        tableView.delegate = self
        tableView.enableKeyboardDismissal()
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        headerView = DeviceRatedPowerCalibrationHeaderView(frame: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(174)))
        headerView.dimSaveBtn.addTarget(self, action: #selector(setAllDimSaveAction), for: .touchUpInside)
        headerView.segmentControl.delegate = self
        tableView.tableHeaderView = headerView
        
    }
    
    

}

extension DeviceRatedPowerCalibrationController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch setMode {
        case .separately:
            return devices.count
        case .all:
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch setMode {
        case .separately:
            let cell = tableView.dequeueReusableCell(withIdentifier: "setSeparatelyCell", for: indexPath) as! DeviceRatedPowerCalibrationSetSeparatelyViewCell
            cell.device = devices[indexPath.row]
            cell.delegate = self
            return cell
        case .all:
            let cell = tableView.dequeueReusableCell(withIdentifier: "setAllCell", for: indexPath) as! DeviceRatedPowerCalibrationSetAllViewCell
            cell.powerField.text = setAllPowerText
            cell.powerEditCallback = {[weak self] text in
                self?.setAllPowerText = text
            }
            return cell
        }
    }
    
    
//    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
//        
//        switch setMode {
//        case .separately:
//            return SCRYFrom(120)
//        case .all:
//            return
//        }
//    }
    
}

extension DeviceRatedPowerCalibrationController: DeviceRatedPowerCalibrationSetSeparatelyViewCellDelegate {

    
 
    func cell(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell, testShowStateChange show: Bool) {
        if let indexPath = tableView.indexPath(for: cell) {
            let device = devices[indexPath.row]
            device.unfold = !device.unfold
            cell.device = device
            tableView.reloadRows(at: [indexPath], with: .none)
//            tableView.performBatchUpdates(nil)
        }
    }
    
    func calibrationCellDimSaveAction(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell) {
        
        guard let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        let device = devices[indexPath.row]
        if let pid = device.productIdentifier, let model = device.sunricherVendorModel {
            
            device.powerCalibrateState = .dimSave
            reloadDeviceCell(device: device)
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .dimmerCollectRatedPower(pid: pid)), model: model)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {[weak self] in
                guard let self = self else { return }
                if device.powerCalibrateState == .dimSave {
                    device.powerCalibrateState = .none
                    self.reloadDeviceCell(device: device)
                }
            }
        }
        
    }
    
    func cell(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell, calibrationAction inputValue: UInt32) {
        
        guard let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        let device = devices[indexPath.row]
        calibrate(deviceDatas: [(device, inputValue)])
    }
    
    func calibrationCellTestGetAction(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        let device = devices[indexPath.row]
        if let model = device.sunricherVendorModel {
            
            MeshAPI.setNodeLightnessState(address: device.primaryUnicastAddress, lightness: Node.getLightness(lightness100: device.powerTestLightness))
            device.powerCalibrateState = .powerGet
            reloadDeviceCell(device: device)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {[weak self] in
                guard let self = self, device.powerCalibrateState == .powerGet else { return }
                MeshAPI.sendMessage(message: SunricherVendorGet(function: .dimmerRealPower), model: model) {[weak self] response in
                    if device.powerCalibrateState == .powerGet {
                        if let statusMessage = response as? SunricherVendorStatus, statusMessage.status.isSuccessful, case .dimmerRealPower(let power) = statusMessage.status.paramters {
                            device.testCurrentPower = power
                        }
                        device.powerCalibrateState = .none
                        self?.reloadDeviceCell(device: device)
                    }
                }
            }
            
         
        }
    }
    
    func cell(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell, lightnessValueChanged lightness: Int) {
        guard let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        let device = devices[indexPath.row]
        device.powerTestLightness = lightness
    }
    
    
    func calibrationCellReSyncAction(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else {
            return
        }
        let device = devices[indexPath.row]
        if let error = device.powerCalibrateError {
            switch error {
            case .noPowerValue:
                XWHUDManager.showTipHUD("power_calibrate_no_set_power_error".localizedString, isLineFeed: true)
            case .powerExceed:
                XWHUDManager.showTipHUD("power_calibrate_power_exceed".localizedString, isLineFeed: true)
            case .timeout:
                XWHUDManager.showTipHUD("power_calibrate_timeout".localizedString, isLineFeed: true)
            }
        }
        
    }
    
    func cell(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell, identifyDevice device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
}

extension DeviceRatedPowerCalibrationController: CustomSegmentedControlDelegate {
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        setMode = index == 0 ? .separately : .all
        switch setMode {
        case .separately:
            headerView.height = SCRYFrom(174)
            headerView.dimSaveNoteLabel.isHidden = false
        case .all:
            headerView.height = SCRYFrom(150)
            headerView.dimSaveNoteLabel.isHidden = true
        }
        tableView.tableHeaderView = headerView
        tableView.reloadData()
    }
    
}

extension Node {
    
    /// 功率校准错误
    enum PowerCalibrateError {
        /// 没有设置功率
        case noPowerValue
        /// 功率设置超过限制
        case powerExceed
        /// 超时
        case timeout
    }
    
    /// 功率校准状态
    enum PowerCalibrateState {
        // 无
        case none
        /// 调光并保存采集
        case dimSave
        /// 读取功率
        case powerGet
    }
    
    static var unfoldKey = 210
    static var inputPowerKey = 211
    static var powerCalibrateErrorKey = 212
    static var testCurrentPowerKey = 213
    static var powerCalibrateStateKey = 214
    static var powerTestLightness = 215
    
    /// 是否展开
    var unfold: Bool {
        get {
            objc_getAssociatedObject(self, &Node.unfoldKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &Node.unfoldKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 输入的功率
    var inputPower: UInt32? {
        get {
            objc_getAssociatedObject(self, &Node.inputPowerKey) as? UInt32
        }set {
            objc_setAssociatedObject(self, &Node.inputPowerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 功率校准错误
    var powerCalibrateError: PowerCalibrateError? {
        get {
            objc_getAssociatedObject(self, &Node.powerCalibrateErrorKey) as? PowerCalibrateError
        }set {
            objc_setAssociatedObject(self, &Node.powerCalibrateErrorKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 测试读取的当前功率
    var testCurrentPower: UInt32? {
        get {
            objc_getAssociatedObject(self, &Node.testCurrentPowerKey) as? UInt32
        }set {
            objc_setAssociatedObject(self, &Node.testCurrentPowerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 功率校准状态
    var powerCalibrateState: PowerCalibrateState {
        get {
            objc_getAssociatedObject(self, &Node.powerCalibrateStateKey) as? PowerCalibrateState ?? .none
        }set {
            objc_setAssociatedObject(self, &Node.powerCalibrateStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 功率测试亮度值
    var powerTestLightness: Int {
        get {
            objc_getAssociatedObject(self, &Node.powerTestLightness) as? Int ?? 50
        }set {
            objc_setAssociatedObject(self, &Node.powerTestLightness, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
