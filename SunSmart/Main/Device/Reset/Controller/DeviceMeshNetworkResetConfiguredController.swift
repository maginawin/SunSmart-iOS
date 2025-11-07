//
//  DeviceMeshNetworkResetConfiguredController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/21.
//

import UIKit
import NordicSigMeshSDK

class DeviceMeshNetworkResetConfiguredController: UIViewController {

    /// 状态
    enum State {
        /// 无
        case none
        /// 扫描中
        case scanning
        /// 识别中
        case identifying
        /// 重置中
        case reseting
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
    private var networkSections: [DeviceMeshNetworkResetSectionData] = []
    /// 搜索到的设备
    private var scanDevices: [ProvisioningDevice] = []
    
    /// 重置操作
    private let resetHandle = DeviceMeshNetworkResetHandle()
    /// 排序类型
    private var sortType: SortType = .dynamic
    
    private var state: State = .none
    
    /// 刷新数据中
    private var reloadDataing: Bool = false
    
    private var rssiSortTimer: Timer?
    /// 是否首次扫描
    private var firstScan: Bool = true
    
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
    
    deinit {
        
    }
    
    // MARK: - Scan
    /// 开始扫描设备
    private func startScan() {
        state = .scanning
        scanDevices.removeAll()
        networkSections.removeAll()
        tableView.reloadData()
        updateUIState()
        
        resetHandle.reset()
        
        stateCallback?(state)
        
        MeshLibManager.manager.scanDevice(withServices: [MeshProxyService.uuid]) {[weak self] peripheral, advertisementData, rssi in
            
            guard let self = self,
                  let scanDevice = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi),
                  scanDevice.networkId != nil,
                  scanDevice.address > 0,
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
                scanDevice.icon = "device_\(info.iconCategory)"
                scanDevice.deviceType = Node.DeviceType(deviceCategory: info.deviceCategory)
                scanDevice.selectedState = .selected
            }
            scanDevice.resetState = .scanning
            
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
//        (self.wm_pageController as? DeviceMeshNetworkResetController)?.stopScanAnimation()
        
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        stateCallback?(state)
        // 停止扫描设备状态设置为空状态
        networkSections.forEach({ $0.resetState = .none })
        scanDevices.forEach({
            $0.resetState = .none
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
        
        if self.sortType == .dynamic {
            var networkSections: [DeviceMeshNetworkResetSectionData] = []
            let selectRSSIRange = headerView.selectRSSIRange
            
            scanDevices.forEach { device in
                // 判断是否已知网络内
                if let networkSection = networkSections.firstIndex(where: { $0.networkId == device.networkId }) {
                    let networkData = networkSections[networkSection]
                    networkData.devices.removeAll(where: { !selectRSSIRange.contains($0.rssi.intValue) })
                    if let index = networkData.devices.firstIndex(where: { $0.macAddress == device.macAddress }) {
                        networkData.devices.replaceSubrange(index...index, with: [device])
                        //                    self.tableView.reloadRows(at: [IndexPath(row: index, section: networkSection)], with: .none)
                    }else {
                        networkData.devices.append(device)
                    }
                }else {
                    // 防止设备存在多个网络内
                    if selectRSSIRange.contains(device.rssi.intValue) && !networkSections.contains(where: { networkData in networkData.devices.contains(where: { $0.macAddress == device.macAddress }) }) {
                        // 查询是否是本地的网络
                        let space = SpaceData.load(subNetworkId: device.networkId!)
                        let networkData = DeviceMeshNetworkResetSectionData(name: space?.name, networkId: device.networkId!, devices: [device])
                        if state == .scanning {
                            networkData.resetState = .scanning
                        }
                        if let oldNetworkData = self.networkSections.first(where: { $0.networkId == networkData.networkId }) {
                            networkData.unfold = oldNetworkData.unfold
                            //                        networkData.resetState = oldNetworkData.resetState
                        }
                        networkSections.append(networkData)
                    }
                }
            }
            networkSections.forEach({ $0.devices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue }) })
            
            self.networkSections = networkSections
            tableView.reloadData()
            updateUIState()
        }else {
            setupDataSource()
        }
        
        
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.5) {[weak self] in
            self?.reloadDataing = false
        }
        
    }
    
    private func setupDataSource() {
        
        var networkSections: [DeviceMeshNetworkResetSectionData] = []
        let selectRSSIRange = headerView.selectRSSIRange
        
        scanDevices.forEach { device in
            // 判断是否已知网络内
            if let networkSection = networkSections.firstIndex(where: { $0.networkId == device.networkId }) {
                let networkData = networkSections[networkSection]

                networkData.devices.removeAll(where: { !selectRSSIRange.contains($0.rssi.intValue) })
                if let index = networkData.devices.firstIndex(where: { $0.macAddress == device.macAddress }) {
                    networkData.devices.replaceSubrange(index...index, with: [device])
                }else if selectRSSIRange.contains(device.rssi.intValue) {
                    networkData.devices.append(device)
                }
            }else {
                // 防止设备存在多个网络内
                if selectRSSIRange.contains(device.rssi.intValue) && !networkSections.contains(where: { networkData in networkData.devices.contains(where: { $0.macAddress == device.macAddress }) }) {
                    // 查询是否是本地的网络
                    let space = SpaceData.load(subNetworkId: device.networkId!)
                    let networkData = DeviceMeshNetworkResetSectionData(name: space?.name, networkId: device.networkId!, devices: [device])
                    if state == .scanning {
                        networkData.resetState = .scanning
                    }
                    if let oldNetworkData = self.networkSections.first(where: { $0.networkId == networkData.networkId }) {
                        networkData.unfold = oldNetworkData.unfold
//                        networkData.resetState = oldNetworkData.resetState
                    }
                    networkSections.append(networkData)
                }
            }
        }
//        networkSections.forEach({ $0.devices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue }) })
        
        self.networkSections = networkSections
        tableView.reloadData()
        updateUIState()
    }
    
    /// 设备识别
    private func deviceIdenfity(device: ProvisioningDevice) {
        let identifyDevices = scanDevices.filter({ $0.resetState == .identifyWait || $0.resetState == .identifying })
        identifyDevices.forEach({ identifyDevice in
            identifyDevice.resetState = .none
            reloadDeviceState(identifyDevice)
        })
        
        if let identifyNetwork = networkSections.first(where: { $0.resetState == .identifyWait || $0.resetState == .identifying }) {
            identifyNetwork.resetState = .none
            reloadNetworkData(identifyNetwork)
        }
        device.resetState = .identifying
        reloadDeviceState(device)
        state = .identifying
        stateCallback?(state)
        updateUIState()
        resetHandle.startDeviceIdentify(device: device) {[weak self] result in
            guard let self = self else { return }
//            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {[weak self] in
                if device.resetState == .identifying {
                    device.resetState = .none
                    self.reloadDeviceState(device)
                }
            if self.state == .identifying {
                self.state = .none
                self.stateCallback?(self.state)
            }
            self.updateUIState()
//            }
        }
    }
    
    /// 设备重置
    private func deviceReset(device: ProvisioningDevice) {
        
        networkSections.forEach({ $0.resetState = .disable })
        scanDevices.forEach({ $0.resetState = .disable })
        
        device.resetState = .reseting
        tableView.reloadData()
        state = .reseting
        updateUIState()
        stateCallback?(state)
        
        resetHandle.startDeviceReset(device: device) {[weak self] result in
            guard let self = self else { return }
            self.networkSections.forEach({ $0.resetState = .none })
            self.scanDevices.forEach({ $0.resetState = .none })
            if self.state == .reseting {
                self.state = .none
                self.updateUIState()
                self.stateCallback?(self.state)
            }
            switch result {
            case .success(_):
                device.resetState = .success
                // 删除设备缓存
                if let index = self.scanDevices.firstIndex(where: { $0.macAddress == device.macAddress }) {
                    self.scanDevices.remove(at: index)
                }
                if let networkData = self.networkSections.first(where: { $0.networkId == device.networkId }) {
                    if let index = networkData.devices.firstIndex(where: { $0.macAddress == device.macAddress }) {
                        networkData.devices.remove(at: index)
                        if networkData.devices.isEmpty {
                            self.networkSections.remove(at: index)
                        }
                    }
                }
                self.updateUIState()
            case .failure(_):
                device.resetState = .failed
            }
            self.tableView.reloadData()
        }
        
    }
    
    /// 识别网络内设备
    private func meshNetworkIdenfity(networkData: DeviceMeshNetworkResetSectionData) {
        let identifyDevices = scanDevices.filter({ $0.resetState == .identifyWait || $0.resetState == .identifying })
        identifyDevices.forEach({ identifyDevice in
            identifyDevice.resetState = .none
            reloadDeviceState(identifyDevice)
        })
        
        if let identifyNetwork = networkSections.first(where: { $0.resetState == .identifyWait || $0.resetState == .identifying }) {
            identifyNetwork.resetState = .none
            reloadNetworkData(identifyNetwork)
        }
        
        networkData.resetState = .identifyWait
        reloadNetworkData(networkData)
        networkData.devices.forEach({
            $0.resetState = .identifyWait
            reloadDeviceState($0)
        })
        state = .identifying
        stateCallback?(state)
        updateUIState()
        
        resetHandle.startMeshNetworkIdentify(networkId: networkData.networkId, scanProxy: {[weak self] _ in
            guard let self = self else { return }
            networkData.resetState = .identifying
            self.reloadNetworkData(networkData)
            
            networkData.devices.forEach({
                $0.resetState = .identifying
                self.reloadDeviceState($0)
            })
            self.updateUIState()
        }) {[weak self] result in
            guard let self = self else { return }
            
            if self.state == .identifying {
                self.state = .none
                self.stateCallback?(self.state)
            }
//            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {[weak self] in
            if networkData.resetState == .identifyWait || networkData.resetState == .identifying {
                switch result {
                case .success(_):
                    networkData.resetState = .none
                    self.reloadNetworkData(networkData)
                    networkData.devices.forEach({
                        if $0.resetState == .identifyWait || $0.resetState == .identifying {
                            $0.resetState = .none
                            self.reloadDeviceState($0)
                        }
                    })
                case .failure(_):
                    networkData.resetState = .identifyFail
                    self.reloadNetworkData(networkData)
                    networkData.devices.forEach({
                        if $0.resetState == .identifyWait {
                            $0.resetState = .identifyFail
                            self.reloadDeviceState($0)
                        }
                    })
                    DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                        if networkData.resetState == .identifyFail {
                            networkData.resetState = .none
                            self?.reloadNetworkData(networkData)
                        }
                        networkData.devices.forEach({
                            if $0.resetState == .identifyFail {
                                $0.resetState = .none
                                self?.reloadDeviceState($0)
                            }
                        })
                    }
                }
            }
            self.updateUIState()
//            }
        }
    }
    
    /// 网络重置
    private func meshNetworkReset(networkData: DeviceMeshNetworkResetSectionData) {
        
        networkSections.forEach({ $0.resetState = .disable })
        scanDevices.forEach({ $0.resetState = .disable })
        
        networkData.resetState = .reseting
        tableView.reloadData()
        state = .reseting
        stateCallback?(state)
        updateUIState()
        
        resetHandle.startMeshNetworkReset(networkId: networkData.networkId, completion: {[weak self] result in
            guard let self = self else { return }
            self.networkSections.forEach({ $0.resetState = .none })
            self.scanDevices.forEach({ $0.resetState = .none })
            if self.state == .reseting {
                self.state = .none
                self.updateUIState()
                self.stateCallback?(self.state)
            }
            switch result {
            case .success(_):
                self.scanDevices.removeAll(where: { $0.networkId == networkData.networkId })
                if let index = self.networkSections.firstIndex(where: { $0.networkId == networkData.networkId }) {
                    self.networkSections.remove(at: index)
                }
                self.updateUIState()
            case .failure(_):
                networkData.resetState = .failed
            }
            self.tableView.reloadData()
        })
        
    }
    
    // MARK: - Action
    
    @objc private func bottomBtnAction() {
        switch state {
        case .none:
            startScan()
        case .scanning:
            stopScan()
        case .identifying, .reseting:
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
    
    /// 折叠
    @objc private func stretchBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        networkSections.forEach({ $0.unfold = sender.isSelected })
        tableView.reloadData()
    }
    
    /// 选择rssi范围
    private func selectRSSIRangeAction() {
        setupDataSource()
    }
    
    // MARK: - UI
    
    private func updateUIState() {
        
        headerView.devicesInfoView.isHidden = networkSections.isEmpty
        headerView.totalNumbersLabel.text = "\("total_numbers".localizedString): \(networkSections.flatMap({ $0.devices }).count)"
        if !networkSections.contains(where: { $0.unfold }) {
            headerView.stretchBtn.isSelected = false
        }else {
            headerView.stretchBtn.isSelected = true
        }
        
        switch state {
        case .none:
            headerView.sortBtn.isHidden = true
            headerView.rssiSlider.isEnabled = !scanDevices.contains(where: { $0.resetState == .identifyWait || $0.resetState == .identifying })
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
        case .identifying, .reseting:
            headerView.sortBtn.isHidden = true
            headerView.rssiSlider.isEnabled = false
            bottomView.button.setTitle("RESTART".localizedString, for: .normal)
            bottomView.button.isEnabled = false
            bottomView.noteLabel.isHidden = true
            (self.wm_pageController as? DeviceMeshNetworkResetController)?.scrollEnable = false
        }
        
    }
    
    /// 刷新网络UI状态
    private func reloadNetworkData(_ networkData: DeviceMeshNetworkResetSectionData) {
        if let index = networkSections.firstIndex(where: { $0.networkId == networkData.networkId }) {
//            if let headerView = tableView.headerView(forSection: index) as? DeviceMeshNetworkResetSecitonHeaderView {
//                headerView.networkData = networkData
//            }
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice) {
        
        if let section = networkSections.firstIndex(where: { $0.devices.contains(device) }), let index = networkSections[section].devices.firstIndex(of: device) {
            if let cell = tableView.cellForRow(at: IndexPath(row: index, section: section)) as? DeviceForceResetViewCell {
                cell.device = device
            }
        }
    }
    
    private func setupUI() {
        
        
        headerView = DeviceMeshNetworkResetHeaderView()
        headerView.noteLabel.text = "mesh_network_reset_range_message".localizedString
        headerView.sortBtn.addTarget(self, action: #selector(sortBtnAction), for: .touchUpInside)
        headerView.stretchBtn.addTarget(self, action: #selector(stretchBtnAction), for: .touchUpInside)
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
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = SCRYFrom(70)
        tableView.register(DeviceMeshNetworkResetSecitonHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(DeviceForceResetViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
//            make.left.right.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }
}

extension DeviceMeshNetworkResetConfiguredController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return networkSections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let netwrokData = networkSections[section]
        if netwrokData.unfold {
            return netwrokData.devices.count
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let netwrokData = networkSections[indexPath.section]
        let device = netwrokData.devices[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceForceResetViewCell
        cell.selectImageView.isHidden = true
        cell.device = device
        cell.delegate = self
        cell.configureCell(isFirst: false, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceMeshNetworkResetSecitonHeaderView
        let netwrokData = networkSections[section]
        headerView.networkData = netwrokData
        headerView.delegate = self
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(68)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return SCRYFrom(8)
    }
    
}

extension DeviceMeshNetworkResetConfiguredController: DeviceForceResetViewCellDelegate {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceForceResetViewCell, identify device: ProvisioningDevice) {
        
//        resetBroadcasterCentral.cancelIdentifyBroadcaster()
        
        deviceIdenfity(device: device)
    }
    
    /// 设备添加重置事件回调
    func cell(_ cell: DeviceForceResetViewCell, deviceReset device: ProvisioningDevice) {
        if state == .scanning {
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_reset".localizedString)
            return
        }
        deviceReset(device: device)
    }
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceForceResetViewCell, deviceStateImageClick device: ProvisioningDevice) {
        
        guard device.resetState == .failed else {
            return
        }
        // 设备状态回归为默认状态
        device.resetState = .none
        device.selectedState = .selected
        reloadDeviceState(device)
        
        updateUIState()
        
    }
    
}

extension DeviceMeshNetworkResetConfiguredController: DeviceMeshNetworkResetSecitonHeaderViewDelegate {
    
    /// 点击section事件
    func sectionHeaderDidClick(_ headerView: DeviceMeshNetworkResetSecitonHeaderView) {
        guard let networkData = networkSections.first(where: { $0.networkId == headerView.networkData.networkId }) else {
            return
        }
        networkData.unfold = !networkData.unfold
        reloadNetworkData(networkData)
//        headerView.networkData = networkData
        reloadDataing = true
        updateUIState()
    }
    
    /// identity事件
    func sectionHeaderIdentifyAction(_ headerView: DeviceMeshNetworkResetSecitonHeaderView) {
        guard let networkData = networkSections.first(where: { $0.networkId == headerView.networkData.networkId }) else {
            return
        }
        meshNetworkIdenfity(networkData: networkData)
    }
    
    /// 重置事件
    func sectionHeaderResetAction(_ headerView: DeviceMeshNetworkResetSecitonHeaderView) {
        guard let networkData = networkSections.first(where: { $0.networkId == headerView.networkData.networkId }) else {
            return
        }

        SRAlertView(title: "notification".localizedString, message: "mesh_network_reset_confirm_message".localizedString,  messageFont: UIFont.systemFont(ofSize: 14), inputFieldStyle: .init(keyboardType: .default, textAlignment: .center), showPrompt: false, actions: [SRAlertAction(title: "cancel".localizedString, style: .cancel, actionHandler: nil), SRAlertAction(title: "Reset".localizedString, style: .default)], textValueChangedBack: { text, _ in
            if text == "RESET" {
                return nil
            }
            return " "
        }, inputDoneBack: {[weak self] _ in
            guard let self = self else { return }
            print("删除网络")
            self.meshNetworkReset(networkData: networkData)
        }).show()
        
    }
    
    /// 重置状态图标点击
    func sectionHeaderResetStateImageAction(_ headerView: DeviceMeshNetworkResetSecitonHeaderView) {
        guard let networkData = networkSections.first(where: { $0.networkId == headerView.networkData.networkId }) else {
            return
        }
        networkData.resetState = .none
        reloadNetworkData(networkData)
        updateUIState()
//        reloadNetworkData(networkData)
    }
    
}

