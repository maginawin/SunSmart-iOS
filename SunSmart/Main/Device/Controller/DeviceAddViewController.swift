//
//  DeviceAddViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/28.
//

import UIKit
import NordicSigMeshSDK

class DeviceAddViewController: UIViewController {

    private var navigationBackBtn: UIButton!
    /// header
    private var scanAnimationView: UIImageView!
    private var headerView: UIView!
    private var nearLabel: UILabel!
    private var rssiSlider: CustomDeviceSlider!
    private var farLabel: UILabel!
    private var addDeviceToLabel: UILabel!
    private var addDeviceTargetBtn: UIButton!
    private var scanBtn: UIButton!
    /// 设备列表
    private var tableView: UITableView!
    /// 添加设备结果
    private var addResultView: UIView!
    private var addResultLabel: UILabel!
    private var successCountLabel: UILabel!
    private var failedLabel: UILabel!
    private var failedCountLabel: UILabel!
    private var closeBtn: UIButton!
    private var stopAddBtn: UIButton!
    
    /// 底部全选
    private var footerView: UIView!
    private var selectAllBtn: UIButton!
    private var selectAllLabel: UILabel!
    private var selectCountLabel: UILabel!
    private var addSelectedBtn: UIButton!
    
    /// 搜索设备定时器
    private var scanTimer: Timer?
    /// 找到的设备list
    private var scanDevices: [ProvisioningDevice] = []
    /// 展示的设备list（信号值筛选）
    private var showDevices: [ProvisioningDevice] = []
    /// 筛选的信号值
    private var filterRSSI: Int = 0
    /// 筛选信号值范围
    private let filterRSSIRange: ClosedRange<Int> = -80 ... -40
    /// 添加设备页面状态
    private var state: State = .none
    /// identify中的设备
    private var identifyDevice: ProvisioningDevice?
    private var identifyBearer: PBGattBearer?
    /// 所属空间
    let space: SpaceData
    /// 设备添加完成回调
    var deviceAddCallback: (([Node])->Void)?
    /// 添加成功的节点
    private var addSuccessNodes: [Node] = []
    /// 设备添加到的对应组
    private var addToGroup: Group?
    /// 外部传入指定添加该到group
    var appointGroup: Group?
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "add_device".localizedString
        view.backgroundColor = Background_Color
        
        navigationBackBtn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backClick))
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: navigationBackBtn)
        
        scanAnimationView = UIImageView(image: UIImage(named: "loading"))
        scanAnimationView.isHidden = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: scanAnimationView)
        
        filterRSSI = filterRSSIRange.lowerBound
        
        addToGroup = appointGroup
        setupUI()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if state == .scanning { // 退出页面/切换停止扫描
            stopScan()
        }
    }
    
    @objc private func backClick() {
        navigationController?.popViewController(animated: true)
    }
    
    deinit {
//        if state == .scanning {
//            stopScan()
//        }else {
            if state == .adding {
                MeshAPI.stopFastAddDevice(finishBack: nil)
            }
            if self.addSuccessNodes.count > 0 {
                // 找出未命名的设备
                let unnamedNodes = addSuccessNodes.filter({ !($0.name?.contains("ID") ?? true) })
                if unnamedNodes.count > 0 {
                    unnamedNodes.forEach({
                        $0.name = self.space.getNextNodeName()
                    })
                    _ = self.space.meshManager?.save()
                }
                self.deviceAddCallback?(self.addSuccessNodes)
            }
        // 关闭设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = false
//        }
    }
    
    // MARK: - Scan
    
    private func startScan() {
        
        state = .scanning
        
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        scanAnimationView.isHidden = false
        scanAnimationView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "scan")
        startScanTimer()

        scanDevices.removeAll()
        showDevices.removeAll()
        tableView.reloadData()
        
        updateUIState()
        // 扫描中设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = true
        
        MeshAPI.startScanDevice(.max, deviceScan: {[weak self] device in
            guard let self = self else { return }
            self.stopScanTimer()
            // 新发现设备
            if !self.scanDevices.contains(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) {
                self.scanDevices.append(device)
                device.selectedState = .selected
                device.addState = .scaning
//                print(device.rssi)
                
                if self.filterRSSI == self.filterRSSIRange.lowerBound || device.rssi.intValue >= self.filterRSSI { // 当前设备信号值在筛选范围内可展示
                    self.showDevices.append(device)
                    self.tableView.insertRows(at: [IndexPath(row: self.showDevices.count - 1, section: 0)], with: .automatic)
                }
                DispatchQueue.main.async {
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopScan), object: nil)
                    self.perform(#selector(self.stopScan), with: nil, afterDelay: 5)
                }
            }
            
        }, deviceScanFinish: nil)
    }
    
    @objc private func stopScan() {
        scanAnimationView.isHidden = true
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        scanBtn.isSelected = false
        MeshAPI.stopScan()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        // 停止扫描设备状态设置为空状态
        scanDevices.forEach({ 
            $0.addState = .none
            reloadDeviceState($0)
        })
        
        updateUIState()
        
        stopScanTimer()
    }
    // MARK: - Scan Timer
    private func startScanTimer() {
        scanTimer = LCWeakTimer.scheduledTimer(timeInterval: 10, aTarget: self, selector: #selector(showDeviceNotFound), userInfo: nil, repeats: true)
        RunLoop.current.add(scanTimer!, forMode: .common)
    }
    
    private func stopScanTimer() {
        scanTimer?.invalidate()
        scanTimer = nil
        hideDeviceNotFound()
    }
    
    /// 显示找不到设备提示
    @objc private func showDeviceNotFound() {
        
        view.showEmptyDataView(imageName: "device_found_empty", title: "device_scan_notfound_title".localizedString, tipText: "device_scan_notfound_message".localizedString)
        
        if let emptyView = view.emptyView {
            emptyView.contentView.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
            }
            emptyView.contentView.layer.cornerRadius = SCRYFrom(20)
            emptyView.contentView.backgroundColor = .white
            emptyView.tipLabel.textAlignment = .left
//            emptyView.tipLabel.lineBreakMode = .byClipping
            emptyView.tipLabel.textColor = RGB(148, 163, 184)
            emptyView.tipLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(20))
                make.right.equalTo(SCRXFrom(-20))
                make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(16))
                make.bottom.equalTo(SCRYFrom(-28))
            }
            let shadeView = UIView(frame: view.bounds)
            shadeView.backgroundColor = RGB(0, 0, 0, 0.4)
            emptyView.insertSubview(shadeView, belowSubview: emptyView.contentView)
        }
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
            self.perform(#selector(self.hideDeviceNotFound), with: nil, afterDelay: 5)
        }
        
    }
    
    /// 隐藏找不到设备提示
    @objc private func hideDeviceNotFound() {
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
        }
        view.hideEmptyDataView()
    }
    
    // MARK: - Action
    /// 扫描
    @objc private func scanBtnClick(sender: UIButton) {
        
        if self.state == .adding || self.state == .identifying {
            // 提示设备正在操作中，不能扫描
//            XWHUDManager.showTipHUD(inView: "scan_disable_adding".localizedString, isLineFeed: true)
            return
        }
//        if self.state == .identifying {
//            // 提示设备正在操作中，不能扫描
//            XWHUDManager.showTipHUD(inView: "scan_disable_identify".localizedString, isLineFeed: true)
//            return
//        }
        
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
//            sender.setTitle("stop".localizedString, for: .normal)
            startScan()
        }else {
//            sender.setTitle("scan".localizedString, for: .normal)
            stopScan()
            DispatchQueue.main.async {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopScan), object: nil)
            }
        }
    }
    
    /// 全选/取消全选
    @objc private func selectAllBtnClick(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        let devices = showDevices.filter({ $0.selectedState != .disabled })
        if sender.isSelected {
            devices.forEach({ $0.selectedState = .selected })
//            selectCountLabel.text = "\(devices.count)/\(devices.count)"
        }else {
            devices.forEach({ $0.selectedState = .unselected })
//            selectCountLabel.text = "0/\(devices.count)"
        }
        updateFooterViewState()
        tableView.reloadData()
    }
    
    /// 批量添加
    @objc private func addSelectedBtnClick() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        selectDevices.forEach { device in
            addDevice(device)
        }
    }
    
    /// 隐藏添加结果view
    @objc private func closeBtnClick() {
        addResultView.isHidden = true
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
    }
    
    /// 停止添加（取消正在排队的设备）
    @objc private func stopAddBtnClick() {
        guard state == .adding else {
            return
        }
        MeshAPI.cancelFastAddAwaitOperations()
        let waitDevices = showDevices.filter({ $0.addState == .wait })
        waitDevices.forEach({
            $0.addState = .none
            $0.selectedState = .selected
        })
        tableView.reloadData()
        updateUIState()
    }
    
    /// 添加目标选择事件
    @objc private func addDeviceTargetBtnClick(sender: UIButton) {
        
        if state == .adding || appointGroup != nil {
            return
        }
        
        var titles: [String] = [space.name]
        for group in space.groups {
            titles.append(group.name)
        }
        var selectIndex = 0
        if let selectGroup = addToGroup, let index = space.groups.firstIndex(where: { $0.address == selectGroup.address }) {
            selectIndex = index + 1
        }
        
        TitleSelectView.show(titles: titles, anchorPoint: CGPoint(x: sender.x, y: sender.frame.maxY + kNavigationHeight + SCRYFrom(2)), selectIndex: selectIndex) {[weak self] index in
            guard let self = self else { return }
            if index == 0 {
                self.addToGroup = nil
            }else {
                self.addToGroup = space.groups[index - 1]
            }
            sender.setTitle(titles[index], for: .normal)
        }
    }
    
    // MARK: - Mesh API
    
    /// 设备identify
    private func identify(_ device: ProvisioningDevice) {
        
        // 判断连接量是否达到上限
        let bleConnectCount = max(showDevices.filter({ $0.addState == .adding || $0.addState == .addConnecting }).count, MeshLibManager.manager.getConnectedPeripherals().count)
        guard bleConnectCount < 5 else {
            device.addState = .identifyWait
            reloadDeviceState(device)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                if device.addState == .identifyWait {
                    device.addState = .none
                    self?.reloadDeviceState(device)
                }
            }
            return
        }
        if identifyDevice != nil {
            stopDeviceIdentify()
        }
        
        device.addState = .identifyConnecting
        reloadDeviceState(device)
        identifyDevice = device
        
        identifyBearer = PBGattBearer(target: device.peripheral)
        identifyBearer?.delegate = self
        identifyBearer?.open()
        
        if state == .none || state == .addFineshed {
            state = .identifying
            updateUIState()
        }
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.identifyConnectTimeout), object: nil)
            self.perform(#selector(self.identifyConnectTimeout), with: nil, afterDelay: 10)
        }
    }
    
    /// identify连接设备超时
    @objc private func identifyConnectTimeout() {
        if let device = identifyDevice {
            identifyDevice?.addState = .identifyFail
            reloadDeviceState(device)
            identifyBearer?.close()
            identifyBearer = nil
            
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                self?.stopDeviceIdentify()
            }
        }else {
            stopDeviceIdentify()
        }
    }
    
    /// 停止设备identify
    private func stopDeviceIdentify(close: Bool = true) {
        if let device = identifyDevice {
            device.addState = .none
            reloadDeviceState(device)
            identifyDevice = nil
        }
        if close {
            identifyBearer?.close()
        }
        identifyBearer = nil
        if state == .identifying {
            updateUIState()
        }
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.identifyConnectTimeout), object: nil)
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.identifyFinnished), object: nil)
        }
    }
    /// identify完成
    @objc private func identifyFinnished() {
        stopDeviceIdentify()
    }
    
    /// 添加设备
    private func addDevice(_ device: ProvisioningDevice) {
        
        // 设备identify中添加不需要再闪烁
        if device.addState == .identifyConnecting || device.addState == .identifyWait || device.addState == .failed || device.addState == .identifying {
            if device.addState == .identifying {
                device.identifyAttentionTimer = 0
            }
            if device == identifyDevice {
//                if let bearer = identifyBearer { // 将identify连接的设备数据传入添加设备操作，避免二次连接
//                    device.gattBearer = PBGattBearer(bearer: bearer)
//                    stopDeviceIdentify(close: false)
//                }else {
                    stopDeviceIdentify()
//                }
            }
        }
       
        device.addState = .wait
        device.selectedState = .disabled
        reloadDeviceState(device)
        updateUIState()
        
        MeshAPI.startFastAddDevices(devices: [device]) { [weak self] addDevice in
            addDevice.addState = .addConnecting
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } connectingBack: {[weak self] addDevice in
            addDevice.addState = .adding
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } appendMessagesBack: {[weak self] addDevice in
            guard let self = self, let group = self.addToGroup, let node = self.space.meshManager?.meshNetwork?.node(withAddress: addDevice.address) else { return [] }
            // 需要追加发送的消息
            var appendMessages: [MeshMessageHandle] = []
            // 设备入组
            node.getSubscribeToGroupMessages(group).forEach({
                appendMessages.append(MeshMessageHandle(message: $0, address: node.primaryUnicastAddress))
            })
            // 设备绑定场景
            group.info.bindSceneDatas.forEach { (sceneId: SceneNumber, data: SceneExecuteData) in
                // 设备是否支持场景model及亮度model
                if let sceneModel = node.sceneModel, let lightnessModel = node.lightnessModel {
                    // 设备是否支持色温model
                    let lightness = Node.getLightness(lightness100: data.lightness)
                    if let ctlModel = node.ctlModel {
                        appendMessages.append(MeshMessageHandle(message: LightCTLSet(lightness: lightness, temperature: UInt16(data.cct), deltaUV: 0), model: ctlModel))
                    }else { // 不支持则设置亮度
                        appendMessages.append(MeshMessageHandle(message: LightLightnessSet(lightness: lightness), model: lightnessModel))
                    }
                    // 保存场景
                    appendMessages.append(MeshMessageHandle(message: SceneStore(sceneId), model: sceneModel))
                }
            }
            // 设备绑定日程
            group.info.bindSchedules.forEach { schedule in
                if let timeModel = node.timeModel, let schedulerSetupModel = node.schedulerSetupModel {
                    // 设置时区
                    appendMessages.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
                    // 设置日程
                    appendMessages.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: SchedulerRegistryEntry(year: .any(), month: .any(of: [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December]), day: .any(), hour: .specific(hour: schedule.hour), minute: .specific(minute: schedule.minute), second: .specific(second: 0), dayOfWeek: .any(of: schedule.weekDays), action: schedule.action, transitionTime: .init(steps: UInt8(schedule.fadeTime), stepResolution: .seconds), sceneNumber: schedule.actionSceneId)), model: schedulerSetupModel))
                }
            }
            
            return appendMessages
        } addSuccess: {[weak self] addDevice in
            addDevice.addState = .success
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
            if let node = self?.space.meshManager?.meshNetwork?.node(withAddress: addDevice.address) {
                node.rssi = addDevice.rssi.intValue
//                self?.space.getNextNodeName(resultCallback: { name in
//                    node.name = name
//                    print("address:\(node.primaryUnicastAddress), name:\(name)")
//                })
//                if let name = self?.space.getNextNodeName() {
//                    node.name = name
//                }
                self?.addSuccessNodes.append(node)
            }
        } addFail: {[weak self] addDevice, error in
            addDevice.addState = .failed
            addDevice.selectedState = .selected
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } addFinish: {[weak self] successList, failList in
            guard let self = self else { return }
            let successNodes = self.space.nodes.filter { node in
                successList.contains(where: { $0.address == node.primaryUnicastAddress })
            }
            successNodes.forEach { node in
                node.name = self.space.getNextNodeName()
            }
            _ = self.space.meshManager?.save()
//            self.addSuccessNodes.append(contentsOf: successNodes)
        }
        
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice) {
        if let index = showDevices.firstIndex(of: device) {
            if let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? DeviceAddViewCell {
                cell.device = device
            }else {
                tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
        }else {
            tableView.reloadData()
        }
    }
    
    /// 更新底部view数量状态
    private func updateFooterViewState() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        let enableDevices = showDevices.filter({ $0.selectedState != .disabled })
        selectCountLabel.text = "\(selectDevices.count)/\(enableDevices.count)"
        if !enableDevices.isEmpty && selectDevices.count >= enableDevices.count {
            selectAllBtn.isSelected = true
        }else {
            selectAllBtn.isSelected = false
        }
        addSelectedBtn.isEnabled = selectDevices.count > 0
    }
    
    /// 更新UI
    private func updateUIState() {
        navigationBackBtn.isHidden = false
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        // 添加设备中
        if showDevices.contains(where: { $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }) {
            state = .adding
            navigationBackBtn.isHidden = true
            self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }else if showDevices.contains(where: { $0.addState == .identifyConnecting || $0.addState == .identifying }) { // identify中
            state = .identifying
        }else if showDevices.contains(where: { $0.addState == .success || $0.addState == .failed }) { // 操作完成（add）
            state = .addFineshed
        }else if state != .scanning {
            state = .none
        }
        // 未操作、操作成功可以筛选信号
        rssiSlider.isEnabled = state == .none || state == .addFineshed
        scanBtn.isEnabled = state == .none || state == .scanning || state == .addFineshed
        
        if rssiSlider.isEnabled {
            rssiSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
            rssiSlider.minimumTrackTintColor = RGB(255, 167, 44)
        }else {
            rssiSlider.setThumbImage(UIImage(named: "slider_point_disable"), for: .normal)
            rssiSlider.minimumTrackTintColor = RGB(255, 167, 44, 0.5)
        }
        
        UIApplication.shared.isIdleTimerDisabled = false
        
        switch state {
        case .none:
            footerView.isHidden = false
            addResultView.isHidden = true
            updateFooterViewState()
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
        case .scanning:
            footerView.isHidden = true
            tableView.contentInset = .zero
            addResultView.isHidden = true
        case .identifying:
            break
        case .adding, .addFineshed:
            footerView.isHidden = false
            updateFooterViewState()
            if state == .adding {
                addResultView.isHidden = false
                tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: addResultView.height + footerView.height + SCRYFrom(8), right: 0)
                closeBtn.isHidden = true
                stopAddBtn.isHidden = !showDevices.contains(where: { $0.addState == .wait})
                // 添加中设置屏幕常亮
                UIApplication.shared.isIdleTimerDisabled = true
            }else {
                closeBtn.isHidden = false
                stopAddBtn.isHidden = true
            }
            let successCount = scanDevices.filter({ $0.addState == .success }).count
            let failedCount = scanDevices.filter({ $0.addState == .failed }).count
            successCountLabel.text = "\("successfully".localizedString) : \(successCount)"
            failedCountLabel.text = "\(failedCount)"
            
        }
        
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        headerView = UIView()
        view.addSubview(headerView)
        let navigationHeight = presentingViewController != nil ? (navigationController?.navigationBar.height ?? 0) : kNavigationHeight
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(navigationHeight)
//            make.top.equalTo(kNavigationHeight)
            make.height.equalTo(SCRYFrom(100))
        }
        
        nearLabel = UILabel(text: "near".localizedString, textColor: TextBlack_Color, fontSize: 15)
        headerView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24))
        }
        
        rssiSlider = CustomDeviceSlider()
        rssiSlider.minimumTrackTintColor = RGB(255, 167, 44)
        rssiSlider.maximumTrackTintColor = RGB(229, 229, 229)
        rssiSlider.layer.cornerRadius = 2.5
        rssiSlider.minimumValue = Float(abs(filterRSSIRange.upperBound))
        rssiSlider.maximumValue = Float(abs(filterRSSIRange.lowerBound))
        rssiSlider.value = Float(abs(filterRSSI))
//        rssiSlider.maximumValue - Float(filterRSSI - filterRSSIRange.lowerBound) / Float(filterRSSIRange.upperBound - filterRSSIRange.lowerBound) * 100
        rssiSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
//        rssiSlider.setThumbImage(UIImage(named: "slider_point")?.withTintColor(RGB(220, 220, 220)), for: .normal)
//        rssiSlider.minimumTrackTintColor = RGB(229, 229, 229)
        rssiSlider.delegate = self
        headerView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(68))
            make.right.equalTo(SCRXFrom(-67))
            make.centerY.equalTo(nearLabel)
            make.height.equalTo(SCRYFrom(40))
        }
        
        farLabel = UILabel(text: "far".localizedString, textColor: TextBlack_Color, fontSize: 15)
        headerView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(nearLabel)
        }
        
        addDeviceToLabel = UILabel(text: "add_device_to".localizedString, textColor: TextBlack_Color, fontSize: 14)
        headerView.addSubview(addDeviceToLabel)
        addDeviceToLabel.snp.makeConstraints { make in
            make.left.equalTo(nearLabel)
            make.bottom.equalTo(SCRYFrom(-14))
        }
        
        addDeviceTargetBtn = UIButton(title: addToGroup?.info.name ?? addToGroup?.name ?? space.name, titleSize: 13, titleColor: TextBlack_Color, normalImageName: "space_arrow_down", target: self, action: #selector(addDeviceTargetBtnClick))
        addDeviceTargetBtn.imageView?.sizeToFit()
        let imageW = addDeviceTargetBtn.imageView?.image?.size.width ?? 0
        addDeviceTargetBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(103), bottom: 0, right: 0)
        addDeviceTargetBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8) - imageW, bottom: 0, right: imageW + SCRXFrom(6))
        addDeviceTargetBtn.contentHorizontalAlignment = .left
        addDeviceTargetBtn.layer.cornerRadius = SCRYFrom(5)
        addDeviceTargetBtn.layer.borderWidth = 1
        addDeviceTargetBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        addDeviceTargetBtn.backgroundColor = .white
        headerView.addSubview(addDeviceTargetBtn)
        addDeviceTargetBtn.snp.makeConstraints { make in
            make.left.equalTo(addDeviceToLabel.snp.right).offset(SCRXFrom(5))
            make.centerY.equalTo(addDeviceToLabel)
            make.width.equalTo(SCRXFrom(128))
            make.height.equalTo(SCRYFrom(32))
        }

        scanBtn = UIButton(title: "scan".localizedString, titleSize: 13, titleColor: Bar_Color, normalImageName: "device_scan", target: self, action: #selector(scanBtnClick))
        scanBtn.setTitle("stop".localizedString, for: .selected)
        scanBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        scanBtn.layer.cornerRadius = SCRYFrom(5)
        scanBtn.layer.borderWidth = 1
        scanBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        scanBtn.backgroundColor = .white
        scanBtn.contentHorizontalAlignment = .left
        scanBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 0)
        scanBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(10), bottom: 0, right: 0)
        
        headerView.addSubview(scanBtn)
        scanBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-18))
            make.centerY.equalTo(addDeviceTargetBtn)
            make.width.equalTo(SCRXFrom(80))
            make.height.equalTo(SCRYFrom(32))
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(60)
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(DeviceAddViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(8), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
        }
        
        footerView = UIView()
        footerView.backgroundColor = .white
        footerView.isHidden = true
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        
        selectAllBtn = UIButton(normalImageName: "select_un", selectedImageName: "select", target: self, action: #selector(selectAllBtnClick))
        footerView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(15))
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        selectAllLabel = UILabel(text: "select_all".localizedString, textColor: TextBlack_Color, fontSize: 16)
        footerView.addSubview(selectAllLabel)
        selectAllLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllBtn.snp.right).offset(SCRXFrom(4))
            make.bottom.equalTo(selectAllBtn.snp.centerY)
        }
        
        selectCountLabel = UILabel(text: "3/6", textColor: RGB(13, 14, 28, 0.5), fontSize: 14)
        footerView.addSubview(selectCountLabel)
        selectCountLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllLabel)
            make.top.equalTo(selectAllLabel.snp.bottom).offset(SCRYFrom(3))
        }
        
        addSelectedBtn = UIButton(title: "add_selected".localizedString, titleSize: 14, titleColor: .white, target: self, action: #selector(addSelectedBtnClick))
        addSelectedBtn.titleLabel?.font = Font_Medium_Size(14)
        addSelectedBtn.layer.cornerRadius = SCRYFrom(5)
        addSelectedBtn.clipsToBounds = true
        let btnSize = CGSize(width: SCRXFrom(114), height: SCRYFrom(40))
        addSelectedBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color), for: .normal)
        addSelectedBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color.withAlphaComponent(0.5)), for: .disabled)
        footerView.addSubview(addSelectedBtn)
        addSelectedBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
            make.size.equalTo(btnSize)
        }
        
        addResultView = UIView()
        addResultView.isHidden = true
        addResultView.backgroundColor = .white
        addResultView.layer.cornerRadius = SCRYFrom(8)
        addResultView.layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        addResultView.layer.shadowOffset = CGSizeMake(0,-2)
        addResultView.layer.shadowOpacity = 1
        addResultView.layer.shadowRadius = 6
        view.addSubview(addResultView)
        addResultView.snp.makeConstraints { make in
            make.bottom.equalTo(footerView.snp.top).offset(SCRYFrom(-1))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(72))
        }
        
        addResultLabel = UILabel(text: "add_result".localizedString, textColor: TextBlack_Color, fontSize: 16)
        addResultView.addSubview(addResultLabel)
        addResultLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(14))
        }
        
        successCountLabel = UILabel(text: "\("successfully".localizedString) : 0", textColor: Message_Color, fontSize: 14)
        addResultView.addSubview(successCountLabel)
        successCountLabel.snp.makeConstraints { make in
            make.left.equalTo(addResultLabel)
            make.bottom.equalTo(SCRYFrom(-14))
        }
        
        failedLabel = UILabel(text: "failed".localizedString + " : ", textColor: Message_Color, fontSize: 14)
        addResultView.addSubview(failedLabel)
        failedLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(141))
            make.centerY.equalTo(successCountLabel)
        }
        
        failedCountLabel = UILabel(text: "0", textColor: Red_Color, fontSize: 14)
        addResultView.addSubview(failedCountLabel)
        failedCountLabel.snp.makeConstraints { make in
            make.left.equalTo(failedLabel.snp.right)
            make.centerY.equalTo(failedLabel)
        }
        
        closeBtn = UIButton(normalImageName: "close", target: self, action: #selector(closeBtnClick))
        addResultView.addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(4))
        }
        
        stopAddBtn = UIButton(title: "stop_waiting".localizedString, titleSize: 14, titleColor: Red_Color, target: self, action: #selector(stopAddBtnClick))
        stopAddBtn.titleLabel?.font = Font_Medium_Size(SCRYFrom(14))
        stopAddBtn.isHidden = true
        stopAddBtn.layer.cornerRadius = SCRYFrom(5)
        stopAddBtn.layer.borderWidth = 1
        stopAddBtn.layer.borderColor = Red_Color.cgColor
        stopAddBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(11), bottom: 0, right: SCRXFrom(11))
        addResultView.addSubview(stopAddBtn)
        stopAddBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-18))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(32))
        }
    }
    
}

extension DeviceAddViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return showDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceAddViewCell
        cell.selectionStyle = .none
        let device = showDevices[indexPath.row]
        cell.device = device
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let device = showDevices[indexPath.row]
        guard device.selectedState == .unselected || device.selectedState == .selected else {
            return
        }
        if device.selectedState == .unselected {
            device.selectedState = .selected
        }else {
            device.selectedState = .unselected
        }
        if device.addState == .failed {
            device.addState = .none
            device.selectedState = .selected
            tableView.reloadRows(at: [indexPath], with: .none)
            updateUIState()
//            let successCount = scanDevices.filter({ $0.addState == .success }).count
//            let failedCount = scanDevices.filter({ $0.addState == .failed }).count
//            successCountLabel.text = "\("successfully".localizedString) : \(successCount)"
//            failedCountLabel.text = "\(failedCount)"
            
        }else {
            if let cell = tableView.cellForRow(at: indexPath) as? DeviceAddViewCell {
                switch device.selectedState {
                case .unselected:
                    cell.selectImageView.image = UIImage(named: "device_select_un")
                case .selected:
                    cell.selectImageView.image = UIImage(named: "device_select")
                case .disabled:
                    cell.selectImageView.image = UIImage(named: "device_select_disable")
                }
            }else {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
        
        updateFooterViewState()
    }
    
}

extension DeviceAddViewController: CustomDeviceSliderDelegate {
    
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float) {
        
        let rssi = Int(-value)
//        filterRSSIRange.lowerBound + abs(Int(((value - 100) / 100.0) * Float(filterRSSIRange.upperBound - filterRSSIRange.lowerBound)))
        if filterRSSI != rssi {
            filterRSSI = rssi
//            print(rssi)
            // 筛选展示的设备
            if rssi == filterRSSIRange.lowerBound {
                showDevices = scanDevices
            }else {
                showDevices = scanDevices.filter({ $0.rssi.intValue >= rssi })
            }
            updateFooterViewState()
            tableView.reloadData()
        }
    }
}

extension DeviceAddViewController: DeviceAddViewCellDelegate {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceAddViewCell, identify device: ProvisioningDevice) {
        if device.addState == .identifying {
            return
        }
        if state == .scanning {
            
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_identify".localizedString)
            return
        }
        identify(device)
    }
    
    /// 设备添加点击事件回调
    func cell(_ cell: DeviceAddViewCell, deviceAdd device: ProvisioningDevice) {
        if state == .scanning {
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_add".localizedString)
            return
        }
        addDevice(device)
    }
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceAddViewCell, deviceStateImageClick device: ProvisioningDevice) {
        
        guard device.addState == .wait || device.addState == .failed else {
            return
        }
        if device.addState == .wait { // 等待添加
            MeshAPI.cancelFastAddAwaitOperations(devices: [device])
        }
        
        // 设备状态回归为默认状态
        device.addState = .none
        device.selectedState = .selected
        reloadDeviceState(device)
        
        updateUIState()
    }
}

extension DeviceAddViewController: BearerDelegate {
    
    func bearerDidOpen(_ bearer: Bearer) {
        identifyBearer?.identify()
        if let device = identifyDevice {
            device.addState = .identifying
            reloadDeviceState(device)
        }
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.identifyConnectTimeout), object: nil)
            self.perform(#selector(self.identifyFinnished), with: nil, afterDelay: 5)
        }
    }
    
    func bearer(_ bearer: Bearer, didClose error: Error?) {
        if (bearer as? PBGattBearer) == identifyBearer {
            stopDeviceIdentify()
        }
    }
    
}

extension DeviceAddViewController {
    /// 设备添加页面状态
    enum State {
        /// 无状态
        case none
        /// 扫描设备中
        case scanning
        /// identify中
        case identifying
        /// 添加设备中
        case adding
        /// 设备添加完成
        case addFineshed
    }
}
