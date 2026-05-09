//
//  DeviceMeshNetworkResetNotConfiguredController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/21.
//

import UIKit
import NordicSigMeshSDK

class DeviceMeshNetworkResetNotConfiguredController: UIViewController {

    /// 状态
    enum State {
        /// 无
        case none
        /// 扫描中
        case scanning
        /// 识别中
        case identifying
    }
    
    /// 排序类型
    enum SortType {
        /// 静态
        case `static`
        /// 动态
        case dynamic
    }
    
    private var headerView: DeviceMeshNetworkResetHeaderView!
    private var tableView: UITableView!
    private var bottomView: DeviceMeshNetworkResetBottomView!
    /// 搜索到的设备
    private var scanDevices: [ProvisioningDevice] = []
    /// 展示的设备
    private var showDevices: [ProvisioningDevice] = []
    
    /// 排序类型
    private var sortType: SortType = .dynamic
    
    private var state: State = .none
    
    /// 刷新数据中
    private var reloadDataing: Bool = false
    /// 是否首次扫描
    private var firstScan: Bool = true
    
    private var rssiSortTimer: Timer?
    
    var stateCallback: ((State)->Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if firstScan {
            firstScan = false
            startScan()
        }
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if state == .scanning  {
            stopScan()
        }
    }
    
    // MARK: - Scan
    /// 开始扫描设备
    private func startScan() {
        state = .scanning
        scanDevices.removeAll()
        showDevices.removeAll()
        tableView.reloadData()
        updateUIState()
        
        stateCallback?(state)
        
        MeshLibManager.manager.scanDevice(withServices: [MeshProvisioningService.uuid]) {[weak self] peripheral, advertisementData, rssi in
            
            guard let self = self,
                  let scanDevice = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi),
                  scanDevice.cid == CompanyId,
                  scanDevice.macAddress != nil else { return }
            
            if scanDevice.rssi.intValue > self.headerView.filterRSSIRange.upperBound {
                scanDevice.rssi = NSNumber(value: self.headerView.filterRSSIRange.upperBound)
            }
            
            if let node = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.macAddress == scanDevice.macAddress }) {
                
                scanDevice.deviceName = node.name
                scanDevice.icon = node.iconName
                scanDevice.address = node.primaryUnicastAddress
                scanDevice.deviceType = node.deviceType
                scanDevice.selectedState = .selected
                
            }else if let info = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.companyId == scanDevice.cid && $0.productId == scanDevice.pid }) {
                scanDevice.deviceName = info.categoryName
                scanDevice.deviceType = Node.DeviceType(deviceCategory: info.deviceCategory)
                scanDevice.icon = EmergencyFireControllerIconName.addListIconName(for: scanDevice.deviceType, fallback: info.iconName)
                scanDevice.selectedState = .selected
            }
            scanDevice.addState = .scaning
            
            if let index = scanDevices.firstIndex(where: { $0.macAddress == scanDevice.macAddress }) {
                scanDevices.replaceSubrange(index...index, with: [scanDevice])
            }else {
                scanDevices.append(scanDevice)
            }
            self.startRssiSortTimer()
        }
    }
    
    /// 停止扫描设备
    private func stopScan() {
        
        MeshLibManager.manager.stopScan()
        
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        stateCallback?(state)
        // 停止扫描设备状态设置为空状态
        
        scanDevices.forEach({
            $0.addState = .none
//            reloadDeviceState($0)
        })
        devicesRssiSort()
//        tableView.reloadData()
//        updateUIState()
    }

    
    // MARK: - 信号排序定时器
    private func startRssiSortTimer() {
        
        guard rssiSortTimer == nil || !rssiSortTimer!.isValid else {
            return
        }
        
        rssiSortTimer = LCWeakTimer.scheduledTimer(timeInterval: 1, aTarget: self, selector: #selector(devicesRssiSort), userInfo: nil, repeats: false)
        RunLoop.current.add(rssiSortTimer!, forMode: .common)
    }
    
    private func stopRssiSortTimer() {
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
    }
    
    /// 设备信号排序定时刷新，避免接收广播包后刷新频率过高
    @objc private func devicesRssiSort() {
        
        if reloadDataing {
            rssiSortTimer?.fireDate = Date(timeIntervalSinceNow: 1)
        }else {
            rssiSortTimer?.invalidate()
            rssiSortTimer = nil
        }
        
        var showDevices: [ProvisioningDevice] = self.showDevices
        let selectRSSIRange = headerView.selectRSSIRange
        showDevices.removeAll(where: { !selectRSSIRange.contains($0.rssi.intValue) })
        
        scanDevices.forEach { device in
            if let index = showDevices.firstIndex(where: { $0.macAddress == device.macAddress }) {
                showDevices.replaceSubrange(index...index, with: [device])
            }else {
                if selectRSSIRange.contains(device.rssi.intValue) {
                    showDevices.append(device)
                }
            }
        }
        if sortType == .dynamic {
            showDevices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue })
        }
        
        self.showDevices = showDevices
        tableView.reloadData()
        updateUIState()
        
//        DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.5) {[weak self] in
//            self?.reloadDataing = false
//        }
        
    }
    
    // MARK: - Device API
    /// 设备identify
    private func identify(_ device: ProvisioningDevice) {
        
        if let identifyDevice = showDevices.first(where: { $0.addState == .identifyConnecting || $0.addState == .identifyWait || $0.addState == .identifying || $0.addState == .identifyFail }) {
            identifyDevice.addState = .none
            reloadDeviceState(identifyDevice)
            MeshAPI.stopUnprovisionedDeviceIdentify()
        }
        
        device.addState = .identifyConnecting
        reloadDeviceState(device)
        if state == .none {
            state = .identifying
            updateUIState()
            stateCallback?(state)
        }
        
        MeshAPI.unprovisionedDeviceIdentify(device: device, attentionTimer: 6) {[weak self] _, _ in
            device.addState = .identifying
            self?.reloadDeviceState(device)
        } identifyFinished: {[weak self] _ in
            guard let self = self else { return }
            device.addState = .none
            self.reloadDeviceState(device)
            if self.state == .identifying {
                self.state = .none
                self.updateUIState()
                self.stateCallback?(self.state)
            }
        } identifyFail: {[weak self] _ in
            guard let self = self else { return }
            device.addState = .identifyFail
            self.reloadDeviceState(device)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                guard let self = self else { return }
                if device.addState == .identifyFail {
                    device.addState = .none
                    self.reloadDeviceState(device)
                }
                if self.state == .identifying {
                    self.state = .none
                    self.updateUIState()
                    self.stateCallback?(self.state)
                }
            }
        }
    }
    
    
    // MARK: - Action
    
    /// 选择rssi范围
    private func selectRSSIRangeAction() {
//        setupDataSource()
//        reloadDataing = true
        devicesRssiSort()
    }

    @objc private func bottomBtnAction() {
        switch state {
        case .none:
            startScan()
        case .scanning:
            stopScan()
        case .identifying:
            break
        }
    }
    
    /// 排序方式切换
    @objc private func sortBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            sortType = .static
        }else {
            sortType = .dynamic
        }
    }
    
    // MARK: - UI
    
    private func updateUIState() {
        
        headerView.devicesInfoView.isHidden = showDevices.isEmpty
        headerView.totalNumbersLabel.text = "\("total_numbers".localizedString): \(showDevices.count)"
        
        switch state {
        case .none:
            headerView.sortBtn.isHidden = true
            headerView.rssiSlider.isEnabled = !scanDevices.contains(where: { $0.addState == .identifyConnecting || $0.addState == .identifyWait || $0.addState == .identifying || $0.addState == .identifyFail })
            bottomView.button.setTitle("RESTART".localizedString, for: .normal)
            bottomView.button.isEnabled = true
            bottomView.noteLabel.isHidden = true
            (self.wm_pageController as? DeviceMeshNetworkResetController)?.scrollEnable = true
        case .scanning:
            headerView.sortBtn.isHidden = false
            headerView.rssiSlider.isEnabled = true
            bottomView.button.setTitle("STOP".localizedString, for: .normal)
            bottomView.button.isEnabled = true
            bottomView.noteLabel.isHidden = false
            (self.wm_pageController as? DeviceMeshNetworkResetController)?.scrollEnable = false
        case .identifying:
            headerView.sortBtn.isHidden = true
            headerView.rssiSlider.isEnabled = false
            bottomView.button.setTitle("RESTART".localizedString, for: .normal)
            bottomView.button.isEnabled = false
            bottomView.noteLabel.isHidden = true
            (self.wm_pageController as? DeviceMeshNetworkResetController)?.scrollEnable = false
        }
        
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice) {
        if let index = showDevices.firstIndex(of: device) {
            if let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? DeviceForceResetViewCell {
                cell.device = device
            }else {
                tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
        }
    }
    
    private func setupUI() {
        
        
        headerView = DeviceMeshNetworkResetHeaderView()
        headerView.noteLabel.text = "mesh_network_reset_range_message".localizedString
        headerView.sortBtn.isHidden = true
        headerView.sortBtn.addTarget(self, action: #selector(sortBtnAction), for: .touchUpInside)
        headerView.stretchBtn.isHidden = true
        headerView.selectRSSIRangeCallback = {[weak self] _ in
            self?.selectRSSIRangeAction()
        }
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(10))
            make.height.equalTo(SCRYFrom(109))
        }
        
        bottomView = DeviceMeshNetworkResetBottomView()
        bottomView.button.addTarget(self, action: #selector(bottomBtnAction), for: .touchUpInside)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + 34)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = SCRYFrom(70)
        tableView.register(DeviceAddViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
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

extension DeviceMeshNetworkResetNotConfiguredController: UITableViewDataSource, UITableViewDelegate {
    
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return showDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let device = showDevices[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceAddViewCell
        cell.selectImageView.isHidden = true
        cell.device = device
        cell.addBtn.isHidden = true
        cell.delegate = self
        cell.configureCell(isFirst: false, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
        cell.selectionStyle = .none
        return cell
    }
    
}

extension DeviceMeshNetworkResetNotConfiguredController: DeviceAddViewCellDelegate {
    
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceAddViewCell, identify device: ProvisioningDevice) {
        
        identify(device)
    }
    
    /// 设备添加重置事件回调
    func cell(_ cell: DeviceAddViewCell, deviceAdd device: ProvisioningDevice) {
        
    }
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceAddViewCell, deviceStateImageClick device: ProvisioningDevice) {

    }
    
}
