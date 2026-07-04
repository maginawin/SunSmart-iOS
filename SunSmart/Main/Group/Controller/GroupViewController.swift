//
//  GroupViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/12.
//

import UIKit
import NordicSigMeshSDK

class GroupViewController: UIViewController {
    /// Auto状态
    enum AutoButtonState {
        case normal
        case progress
    }
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var deviceCountLabel: UILabel!
    private var onoffBtn: UIButton!
    private var autoBtn: UIButton!
    private let controlButtonsStackView = UIStackView()
    private var upDownRatioModeBtn: UIButton!
    private var upDownRatioControlView: DeviceUpDownRatioControlView!
    private var isUpDownRatioModeSelected = false
    private var groupUpRatioValue = 50
    private var lastShowsUpDownRatioControl: Bool?
    private let refreshUIInterval: TimeInterval = 1
    private var uiRefreshTimer: Timer?
    private var nextScheduledUIFlushDate: Date?
    private var pendingDeviceRefreshAddresses: Set<Address> = []
    private var pendingSensorRefreshEvents: [Address: [GroupSensorView.SensorType: GroupSensorView.SensorRefreshEvent]] = [:]
    private var isGroupSummaryRefreshPending = false
    private var isFullCollectionReloadPending = false
    private var isFullSensorReloadPending = false
    private var isSensorControlStateRefreshPending = false
    private var isDeviceCollectionScrolling = false
    private var isSensorTableScrolling = false
    private var controlPanelView: DeviceLightControlPanelView!
    private var pageControl: UIPageControl!
    
    private var calibrateLabel: UILabel!
    private var calibrateBtn: UIButton!
    
    private var setPathLabel: UILabel!
    private var setPathBtn: UIButton!
    
    private var profileTypeBtn: UIButton!
    
    private var sensorView: GroupSensorView?
    
    private var autoButtonState: AutoButtonState = .normal
    
    /// 列数
    private var columnNum: Int = isIPad ? 4 : 3
    private var rowNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: SCRYFrom(44), left: SCRXFrom(40), bottom: SCRYFrom(44), right: SCRXFrom(40)) : UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFrom(36), right: SCRXFrom(24))
    
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(14)
    
    private var automationTimer: Timer?
    private lazy var testBtn: UIButton = {
        let btn = UIButton(title: "Start", titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, fit: false, target: self, action: #selector(test))
        btn.setTitle("Stop", for: .selected)
        return btn
    }()
    
    private var meshNetworkConnectedObservation: NSKeyValueObservation?
    
    private var fileWriteTimer: Timer?
    private var luxFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("luxs.json")
    
    struct LightLuxData {
        let name: String
        let address: Address
        let lux: UInt16
    }
    
    private var lightLuxPhaseDatas: [[LightLuxData]] = []
    private var currentPhaseLuxDatas: [LightLuxData] = []
    
    let space: SpaceData
    var group: Group
    private var nodeIndexByAddress: [Address: Int] = [:]
    private var cachedGroupControlCCTNodes: [Node] = []
    private var cachedUpDownRatioNodes: [Node] = []
    private var cachedShowsGroupControlLightness = false

    private var collapsedSensorViewHeight: CGFloat {
        SCRYFrom(40) + kSafeAreaBottomHeight
    }

    private var currentGroupBrightnessRange: ClosedRange<Int> {
        let data = group.info.profile.lightControlData
        return data.lowEndTrim...data.highEndTrim
    }

    private var groupControlCCTNodes: [Node] {
        cachedGroupControlCCTNodes
    }

    private var showsGroupControlCCT: Bool {
        !groupControlCCTNodes.isEmpty
    }

    private var currentGroupCCTRange: ClosedRange<Int> {
        let ranges = groupControlCCTNodes.map { $0.effectiveCctRange }
        guard let first = ranges.first else {
            return Int(NodeAbsoluteCctRange.defaultRange.lowerBound)...Int(NodeAbsoluteCctRange.defaultRange.upperBound)
        }
        let range = ranges.reduce(first) { result, range in
            min(result.lowerBound, range.lowerBound)...max(result.upperBound, range.upperBound)
        }
        return Int(range.lowerBound)...Int(range.upperBound)
    }

    private var showsGroupControlPanel: Bool {
        cachedShowsGroupControlLightness || showsGroupControlCCT
    }

    private var upDownRatioNodes: [Node] {
        cachedUpDownRatioNodes
    }

    private var showsUpDownRatioModeButton: Bool {
        !upDownRatioNodes.isEmpty
    }
    
    //    private var devices: [String] = []
    //    private var isGroupUpdateData = false
    /// 组更新回调
    //    var groupUpdateCallback: ((Group)->Void)?
    /// 组删除回调
    //    var groupDeleteCallback: ((Group)->Void)?
    
    init(space: SpaceData,group: Group) {
        self.space = space
        self.group = group
        super.init(nibName: nil, bundle: nil)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = group.name
        
        view.backgroundColor = Background_Color
        
        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
            
            navigationController?.setNavigationBarBackgroundColor(color: .clear)

            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        
        // 添加左滑手势
        let previousSwipe = UISwipeGestureRecognizer(target: self, action: #selector(groupPreviousSwipeAction))
        previousSwipe.direction = .right
        view.addGestureRecognizer(previousSwipe)
        // 添加右滑手势
        let nextSwipe = UISwipeGestureRecognizer(target: self, action: #selector(groupNextSwipeAction))
        nextSwipe.direction = .left
        view.addGestureRecognizer(nextSwipe)
        
        
//        navigationItem.rightBarButtonItems = [UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick)), UIBarButtonItem(customView: testBtn)]
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        
        setupUI()
        bindSliderAciton()
        
        //        for i in 1...30 {
        //            devices.append("ID \(i)")
        //        }
//        ToastStatusView.show(in: view, message: "Configuration Successful", type: .success, position: .bottom)
        
        addNotificationObserver()
        
        group.sensorNodes.forEach({ $0.occupancySettings = false })
        
        // 刷新设备状态
//        refresh()
    }
    
    /// 切换上一个group手势
    @objc private func groupPreviousSwipeAction() {
        
        guard !(sensorView?.isShow ?? false), let index = MeshNetworkManager.instance.groups.firstIndex(of: group) else {
            return
        }
        
        guard index > 0 else {
            XWHUDManager.showTipHUD("this_is_the_first_group".localizedString, isLineFeed: true)
            return
        }
        
        let previousGroup = MeshNetworkManager.instance.groups[index - 1]
        self.group = previousGroup
        resetGroupUpDownRatioState()
//        updateUI()
      
        view.layer.addMoveInAnimation(duration: 0.4, animationOrientation: .fromLeft)
        
//        UIView.transition(with: view, duration: 0.6, options: [.transitionFlipFromLeft, .curveEaseInOut], animations: {
        self.updateUI()
        self.pageControl.currentPage = 0
        self.collectionView.setContentOffset(CGPoint(x: 0, y: self.collectionView.contentOffset.y), animated: false)
//        }, completion: nil)
        
    }
    
    /// 切换下一个group手势
    @objc private func groupNextSwipeAction() {
        
        guard !(sensorView?.isShow ?? false), let index = MeshNetworkManager.instance.groups.firstIndex(of: group) else {
            return
        }
        
        guard index < MeshNetworkManager.instance.groups.count - 1 else {
            XWHUDManager.showTipHUD("this_is_the_last_group".localizedString, isLineFeed: true)
            return
        }
        
        let nextGroup = MeshNetworkManager.instance.groups[index + 1]
        self.group = nextGroup
        resetGroupUpDownRatioState()
        view.layer.addMoveInAnimation(duration: 0.4, animationOrientation: .fromRight)
//        UIView.transition(with: view, duration: 0.6, options: [.transitionCrossDissolve, .curveEaseInOut], animations: {
            self.updateUI()
//        }, completion: nil)
//        updateUI()
    }
    
    @objc private func test(sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
            lightLuxPhaseDatas.removeAll()
            loadCacheLuxsData()
            
            automationTimer = LCWeakTimer.scheduledTimer(timeInterval: 5, aTarget: self, selector: #selector(automationTimerAction), userInfo: nil, repeats: true)
            RunLoop.current.add(automationTimer!, forMode: .common)
            
            
            fileWriteTimer = LCWeakTimer.scheduledTimer(timeInterval: 5 * 60, aTarget: self, selector: #selector(fileWriteTimerAction), userInfo: nil, repeats: true)
            RunLoop.current.add(fileWriteTimer!, forMode: .common)
            
        }else {
            automationTimer?.invalidate()
            automationTimer = nil
            
            fileWriteTimer?.invalidate()
            fileWriteTimer = nil
            
            if lightLuxPhaseDatas.count > 0 {
                
                exportPhaseLuxFile()
            }
            
        }
    }
    
    @objc private func automationTimerAction() {
//        group.isOn = !group.isOn
//        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: group.isOn)
        
        if currentPhaseLuxDatas.count > 0 {
            currentPhaseLuxDatas.sort(by: { $0.address < $1.address })
            
            lightLuxPhaseDatas.append(currentPhaseLuxDatas)
        }
        
        currentPhaseLuxDatas.removeAll()
        
        group.ambientLightSensorNodes.forEach({
            if let model = $0.ambientLightSensorModel {
                MeshAPI.sendMessage(message: SensorGet(), model: model)
            }
        })
    }
    
    @objc private func fileWriteTimerAction() {
        guard lightLuxPhaseDatas.count > 0 else {
            return
        }
        let routeTables = lightLuxPhaseDatas.compactMap({ phaseData in
            return phaseData.map({ ["name": $0.name, "address": $0.address, "lux": $0.lux] })
        })
        guard let data = try? JSONSerialization.data(withJSONObject: routeTables) else {
            return
        }
        try? data.write(to: luxFileURL)
    }
    
    private func exportPhaseLuxFile() {
        guard lightLuxPhaseDatas.count > 0 else {
            XWHUDManager.showErrorTipHUD("未获取到光感数据")
            return
        }
        let routeTables = lightLuxPhaseDatas.compactMap({ phaseData in
            return phaseData.map({ ["name": $0.name, "address": $0.address, "lux": $0.lux] })
        })
        guard let data = try? JSONSerialization.data(withJSONObject: routeTables) else {
            XWHUDManager.showErrorTipHUD("导出数据失败")
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // 文件名称 网络名称_网络更新时间
            let date = Date()
            let formatter = DateFormatter.init()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            var timeStr = formatter.string(from: date)
            timeStr = timeStr.replacingOccurrences(of: " ", with: "T")
            timeStr = timeStr.replacingOccurrences(of: ":", with: "")
            
            let name = "luxs_\(timeStr)"
            
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
            try? data.write(to: fileURL)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                // 适配 iPad
                if let popoverController = controller.popoverPresentationController {
                    // 设置 sourceView（可以是按钮或视图）
                    popoverController.sourceView = self.view
                    
                    // 设置 sourceRect（浮层的锚点位置）
                    popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                    
                    // 或者设置 barButtonItem（如果是导航栏按钮）
                    // popoverController.barButtonItem = self.shareButton
                }
                controller.completionWithItemsHandler = { type, success, items, error in
                    if success {
                        try? FileManager.default.removeItem(at: self.luxFileURL)
                        XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    }
                }
                self.present(controller, animated: true)
                
                XWHUDManager.hide()
            }
        }
    }
    
    /// 加载缓存的lux数据
    private func loadCacheLuxsData() {
        
        if let luxsData = try? Data(contentsOf: luxFileURL), let jsonDatas = try? JSONSerialization.jsonObject(with: luxsData) as? [[[String: Any]]] {
            lightLuxPhaseDatas = jsonDatas.compactMap({ data in
               return data.compactMap { data in
                    if let name = data["name"] as? String, let address = data["address"] as? Address, let lux = data["lux"] as? UInt16 {
                        return LightLuxData(name: name, address: address, lux: lux)
                    }
                   return nil
                }
            })
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        collectionView.reloadData()
//        updateEmptyUI()
        updateUI()
        isDeviceCollectionScrolling = false
        isSensorTableScrolling = false
        startUIRefreshTimer()
        
        MeshLibManager.manager.messageDelegate = self
        
        // 检查连接的设备白名单有该组
        proxyFilterAddGroup()
        
        if let sensor = self.group.info.ambientLightSensorNode {
            MeshAPI.getAmbientSensorValue(node: sensor, result: nil)
            refreshAutoState()
        }
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
//        if pageControl.numberOfPages > 0 {
//            collectionView.flashScrollIndicators()
//        }
        
//        MeshAPI.sendMessage(message: SceneRecallUnacknowledged(group.info.profile.nightData!.sceneData.sceneNumber), address: group.address.address)
        var messageHandles: [MeshMessageHandle] = []
        // 检查校准后的光照传感器是否有上报
        if let publishAmbientLightSensor = self.group.info.ambientLightSensorNode, let sensorModel = publishAmbientLightSensor.ambientLightSensorModel, sensorModel.publish?.publicationAddress != group.address {
            let message = ConfigModelPublicationSet(Publish(to: group.address, using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: .disabled, retransmit: .disabled), to: sensorModel)!
            let messageHandle = MeshMessageHandle(message: message, address: publishAmbientLightSensor.primaryUnicastAddress)
            messageHandles.append(messageHandle)
        }
        
        if messageHandles.count > 0 {
            MeshLibManager.manager.messageDelegate = self
            
            MeshProxyMessageCommand.shared.stopSendMessage(finishedBack: nil)
            MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, finishedBack: nil)
        }
//        sensorPublishCheck()
    }
    deinit {
        automationTimer?.invalidate()
        automationTimer = nil
        stopUIRefreshTimer()
        
        proxyFilterRemoveGroup()
        meshNetworkConnectedObservation = nil
//        MeshLibManager.manager.removeObserver(self, forKeyPath: "isMeshNetworkConnected")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopUIRefreshTimer()
//        if isGroupUpdateData {
            NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: group)
//        }
    }
    
    /// 刷新Auto状态，仅daylight profile有效
    private func refreshAutoState() {
        if let sensor = self.group.info.ambientLightSensorNode, let lightLCModel = sensor.lightLCModel {
            MeshAPI.sendMessage(message: LightLCLightOnOffGet(), model: lightLCModel)
        }
    }
    
    
    private func addNotificationObserver() {
        
        // mesh网络连接观察者
        meshNetworkConnectedObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if MeshLibManager.manager.isMeshNetworkConnected {
                    self.onoffBtn.isEnabled = true
                    // 检查连接的设备白名单有该组
                    self.proxyFilterAddGroup()
                }else {
                    if self.group.nodes.count > 0 {
                        self.onoffBtn.isEnabled = false
                    }
                }
            }
        })
        
        NotificationCenter.default.addObserver(forName: .init(groupDataUpdateNotificationName), object: nil, queue: nil) {[weak self] notification in
            //            self?.refreshData = true
            guard let self = self, let group = notification.object as? Group else { return }
        
            self.title = group.name
            self.updateUI()
        }
        
        // 代理切换通知
        NotificationCenter.default.addObserver(forName: .init(meshNetworkProxyDidReplaceNotificationName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else {
                return
            }
            self.proxyFilterAddGroup()
        }

        NotificationCenter.default.addObserver(forName: .init(emergencyFireControllerManualControlStateDidChangeNotificationName), object: nil, queue: .main) {[weak self] _ in
            self?.updateUI()
        }

        NotificationCenter.default.addObserver(forName: .linkedEmerFireConfigDidChange, object: nil, queue: .main) {[weak self] _ in
            self?.updateUI()
        }
        
    }
    
    /// 添加组地址到代理白名单
    private func proxyFilterAddGroup() {
        // 检查连接的设备白名单有该组
        let proxyFilter = MeshNetworkManager.instance.proxyFilter
        if proxyFilter.proxy != nil, !proxyFilter.addresses.contains(group.address.address) {
            proxyFilter.add(address: group.address.address)
        }
    }
    
    /// 代理白名单删除组地址
    private func proxyFilterRemoveGroup() {
        // 检查连接的设备白名单有该组
        let proxyFilter = MeshNetworkManager.instance.proxyFilter
        if proxyFilter.proxy != nil, proxyFilter.addresses.contains(group.address.address) {
            proxyFilter.remove(address: group.address.address)
        }
    }
    
    @objc private func close() {

        if group.sensorNodes.contains(where: { $0.occupancySettings }) {
            return
        }
        
        self.dismissLikeSystem()
        
    }
    
    /// 传感器上报检查，未上报的传感器设置上报
    private func sensorPublishCheck() {
        if self.group.info.profile.type == .manualControl {
            return
        }
        
        var messageHandles: [MeshMessageHandle] = []
        
//        group.sensorNodes.forEach({ 
//            let  $0.getNeedSyncGroupData(group: self).syncProfile
//            
//        })
//        
//        let syncProfile = group.sensorNodes.getNeedSyncGroupData(group: self).syncProfile
//        syncProfile.forEach({
//            messages.append(contentsOf: $0.getMessageHandles(node: node))
//        })
        
        // 检查占用传感器是否有上报
        let publishPresenceDetectedSensors = self.group.presenceDetectedSensorNodes.filter({ $0.presenceDetectedSensorModel?.publish?.publicationAddress != group.address })
        
        publishPresenceDetectedSensors.forEach({
            let message = ConfigModelPublicationSet(Publish(to: group.address, using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: .disabled, retransmit: .disabled), to: $0.presenceDetectedSensorModel!)!
            let messageHandle = MeshMessageHandle(message: message, address: $0.primaryUnicastAddress)
            messageHandles.append(messageHandle)
        })
        // 检查校准后的光照传感器是否有上报
        if let publishAmbientLightSensor = self.group.info.ambientLightSensorNode, let sensorModel = publishAmbientLightSensor.ambientLightSensorModel, sensorModel.publish?.publicationAddress != group.address {
            let message = ConfigModelPublicationSet(Publish(to: group.address, using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: .disabled, retransmit: .disabled), to: sensorModel)!
            let messageHandle = MeshMessageHandle(message: message, address: publishAmbientLightSensor.primaryUnicastAddress)
            messageHandles.append(messageHandle)
        }
        
        if messageHandles.count > 0 {
            MeshLibManager.manager.messageDelegate = self
            
            MeshProxyMessageCommand.shared.stopSendMessage(finishedBack: nil)
            MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, finishedBack: nil)
        }
        
    }
    
    /// 启用/禁用占用感应功能
    private func sensorOccupancySettings(sensor: Node, enable: Bool, result: (@escaping (Result<Void, SensorOccupancySettingsError>)->Void)) {
        guard sensor.presenceDetectedSensorModel != nil, let vendorModel = sensor.sunricherVendorModel, sensor.capabilities.contains(.pirEnabled) else {
            result(.failure(.nonsupport))
            return
        }
        
        MeshAPI.sendMessage(message: SunricherVendorSet(function: .pirEnabled(enabled: enable)), model: vendorModel, timeout: 7) { response in
            guard let statusMessage = response as? SunricherVendorStatus else {
                result(.failure(.timeout))
                return
            }
            guard statusMessage.status.isSuccessful else {
                result(.failure(.configurationFailed))
                return
            }
            result(.success(()))
        }

    }

    private func resetGroupUpDownRatioState() {
        isUpDownRatioModeSelected = false
        groupUpRatioValue = 50
        lastShowsUpDownRatioControl = nil
    }

    private func rebuildGroupDerivedCache() {
        let nodes = group.nodes
        nodeIndexByAddress.removeAll(keepingCapacity: true)
        nodes.enumerated().forEach { index, node in
            nodeIndexByAddress[node.primaryUnicastAddress] = index
        }
        cachedGroupControlCCTNodes = nodes.filter { $0.rawSupportCct && $0.effectiveChangeControlPage == .tunableWhite }
        cachedUpDownRatioNodes = nodes.filter { $0.supportsUpDownRatioControl }
        cachedShowsGroupControlLightness = nodes.contains { $0.lightnessModel != nil }
    }

    private var hasPendingUIUpdates: Bool {
        isFullCollectionReloadPending ||
        isFullSensorReloadPending ||
        isGroupSummaryRefreshPending ||
        isSensorControlStateRefreshPending ||
        !pendingDeviceRefreshAddresses.isEmpty ||
        !pendingSensorRefreshEvents.isEmpty
    }

    private func startUIRefreshTimer() {
        guard uiRefreshTimer == nil else { return }
        uiRefreshTimer = LCWeakTimer.scheduledTimer(timeInterval: refreshUIInterval, aTarget: self, selector: #selector(uiRefreshTimerAction), userInfo: nil, repeats: true)
        RunLoop.current.add(uiRefreshTimer!, forMode: .common)
    }

    private func stopUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
    }

    @objc private func uiRefreshTimerAction() {
        flushPendingUIUpdates()
    }

    private func markDeviceDirty(_ node: Node, includeGroupSummary: Bool = true) {
        pendingDeviceRefreshAddresses.insert(node.primaryUnicastAddress)
        if includeGroupSummary {
            markGroupSummaryDirty()
        }
    }

    private func markSensorDirty(sensor: Node, sensorType: GroupSensorView.SensorType, isTransientPresenceTrigger: Bool = false) {
        let address = sensor.primaryUnicastAddress
        let existingEvent = pendingSensorRefreshEvents[address]?[sensorType]
        let shouldKeepTransientTrigger = isTransientPresenceTrigger || existingEvent?.isTransientPresenceTrigger == true
        var events = pendingSensorRefreshEvents[address] ?? [:]
        events[sensorType] = .init(sensor: sensor, sensorType: sensorType, isTransientPresenceTrigger: shouldKeepTransientTrigger)
        pendingSensorRefreshEvents[address] = events
    }

    private func markGroupSummaryDirty() {
        isGroupSummaryRefreshPending = true
    }

    private func markFullCollectionReloadDirty(includeGroupSummary: Bool = true) {
        isFullCollectionReloadPending = true
        if includeGroupSummary {
            markGroupSummaryDirty()
        }
    }

    private func markSensorControlStateDirty() {
        isSensorControlStateRefreshPending = true
    }

    private func deferNextScheduledUIFlush() {
        nextScheduledUIFlushDate = Date().addingTimeInterval(refreshUIInterval)
    }

    private func flushPendingUIUpdates() {
        flushPendingUIUpdates(ignoringSchedule: false)
    }

    private func flushPendingUIUpdatesImmediately() {
        deferNextScheduledUIFlush()
        flushPendingUIUpdates(ignoringSchedule: true)
    }

    private func flushPendingUIUpdates(ignoringSchedule: Bool) {
        guard view.window != nil else { return }
        if !ignoringSchedule, let nextScheduledUIFlushDate = nextScheduledUIFlushDate, Date() < nextScheduledUIFlushDate {
            return
        }
        guard !isDeviceCollectionScrolling, !isSensorTableScrolling else {
            return
        }
        guard hasPendingUIUpdates else { return }

        let shouldReloadCollection = isFullCollectionReloadPending
        let deviceAddresses = pendingDeviceRefreshAddresses
        let sensorEvents = pendingSensorRefreshEvents.values.flatMap { Array($0.values) }
        let shouldReloadSensors = isFullSensorReloadPending
        let shouldRefreshSummary = isGroupSummaryRefreshPending
        let shouldRefreshSensorControlState = isSensorControlStateRefreshPending

        pendingDeviceRefreshAddresses.removeAll(keepingCapacity: true)
        pendingSensorRefreshEvents.removeAll(keepingCapacity: true)
        isFullCollectionReloadPending = false
        isFullSensorReloadPending = false
        isGroupSummaryRefreshPending = false
        isSensorControlStateRefreshPending = false

        if shouldReloadCollection {
            collectionView.reloadData()
        }else {
            deviceAddresses.forEach { address in
                guard let index = nodeIndexByAddress[address], group.nodes.indices.contains(index) else { return }
                refreshDeviceCell(node: group.nodes[index])
            }
        }

        if shouldRefreshSummary {
            updateGroupControlSummaryIfNeeded()
        }

        if shouldReloadSensors {
            sensorView?.sensors = group.sensorNodes
        }
        if !sensorEvents.isEmpty {
            sensorView?.reloadSensorData(events: sensorEvents)
        }
        if shouldRefreshSensorControlState {
            updataSensorAutoStateUI()
        }
    }

    private func clearPendingUIUpdates() {
        pendingDeviceRefreshAddresses.removeAll(keepingCapacity: true)
        pendingSensorRefreshEvents.removeAll(keepingCapacity: true)
        isGroupSummaryRefreshPending = false
        isFullCollectionReloadPending = false
        isFullSensorReloadPending = false
        isSensorControlStateRefreshPending = false
    }

    private func applyGroupUpRatioValue(_ value: Int) {
        let clampedValue = max(0, min(100, value))
        groupUpRatioValue = clampedValue
        upDownRatioNodes.forEach { node in
            node.upRatio = clampedValue
        }
        if !upDownRatioControlView.isHidden {
            upDownRatioControlView.upValue = clampedValue
        }
        deferNextScheduledUIFlush()
    }

    private func saveGroupUpRatioValue(_ value: Int) {
        let clampedValue = max(0, min(100, value))
        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .upDownLightUpRatio(UInt8(clampedValue))),
            address: group.address.address
        )

        applyGroupUpRatioValue(clampedValue)
        upDownRatioNodes.forEach { node in
            if let meshUUID = node.network?.uuid.uuidString {
                node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
            }
        }
    }
    
    private func updateUI() {
        
        rebuildGroupDerivedCache()

        title = group.name
        
        pageControl.numberOfPages = Int(ceil(Double(group.nodes.count) / Double(columnNum * rowNum)))
        //        pageControl.currentPage = 0
        updateEmptyUI()
        
        onoffBtn.isEnabled = MeshLibManager.manager.isMeshNetworkConnected && group.nodes.contains(where: { $0.state })
        onoffBtn.isSelected = group.isOn
        
        updateControlPanel()
        updateUpDownRatioUI()
        
        let profileType = group.info.profile.type
        // 提示校准
        if group.info.ambientLightSensorNode == nil || !group.info.ambientLightSensorNode!.sensorCalibrated, group.ambientLightSensorNodes.count > 0, profileType == .occupancy_daylight || profileType == .vacancy_daylight || profileType == .daylight, space.groupOperates.contains(.edit) {
            calibrateBtn.isHidden = false
            calibrateLabel.isHidden = false
        }else {
            calibrateBtn.isHidden = true
            calibrateLabel.isHidden = true
        }
        
        // 临近照明提示路径设置
        if profileType == .proximityLighting || profileType == .proximityLightingWithPhotocell, group.info.proximityLightingPath?.isEmpty() ?? true, space.groupOperates.contains(.edit) {
            setPathBtn.isHidden = false
            setPathLabel.isHidden = false
        }else {
            setPathBtn.isHidden = true
            setPathLabel.isHidden = true
        }
        
        // 显示profile文件类型
        if calibrateBtn.isHidden && setPathBtn.isHidden {
            profileTypeBtn.isHidden = false
            let attStr = NSMutableAttributedString(string: "P.\(profileType.instruction.name)", attributes: [.underlineStyle: 1])
            profileTypeBtn.setAttributedTitle(attStr, for: .normal)
        }else {
            profileTypeBtn.isHidden = true
        }
        
        
        if profileType != .manualControl {
            sensorView?.isHidden = false
            sensorView?.sensors = group.sensorNodes
            switch profileType {
            case .occupancy_daylight, .vacancy_daylight:
                sensorView?.supportSensorType = .all
            case .occupancy, .vacancy, .proximityLighting, .proximityLightingWithPhotocell:
                sensorView?.supportSensorType = .presenceDetected
            case .daylight:
                sensorView?.supportSensorType = .ambientLight
            case .manualControl:
                sensorView?.supportSensorType = .none
            }
        }else {
            sensorView?.isHidden = true
        }
        
        deviceCountLabel.text = "(\(group.nodes.count))"
        
        collectionView.reloadData()
        clearPendingUIUpdates()
    }

    private func updateControlPanel() {
        controlPanelView.isHidden = !showsGroupControlPanel
        guard showsGroupControlPanel else {
            return
        }

        let brightnessValue = group.isOn ? Node.getLightness100(lightness: group.lightness) : 0
        let cctRange = currentGroupCCTRange
        controlPanelView.configure(.init(
            controlType: space.controlType,
            showCCTQuickButtons: space.showCCTQuickButtons,
            showsBrightness: cachedShowsGroupControlLightness,
            showsCCT: showsGroupControlCCT,
            brightnessValue: brightnessValue,
            brightnessRange: currentGroupBrightnessRange,
            cctValue: max(cctRange.lowerBound, min(cctRange.upperBound, group.cct)),
            cctRange: cctRange
        ))
    }
    
    private func updateEmptyUI() {
        if group.nodes.isEmpty {
            deviceCountLabel.isHidden = true
            if collectionView.frame == .zero {
                view.layoutIfNeeded()
            }
            if collectionView.emptyView == nil {
                collectionView.showEmptyDataView(title: "no_members".localizedString, buttonText: "add_member".localizedString, position: .center) {[weak self] in
                    self?.members()
                }
                if let emptyView = collectionView.emptyView {
                    if space.groupOperates.contains(.edit) {
                        emptyView.button.backgroundColor = .clear
                        //                    emptyView.button.setTitle("add_member".localizedString, for: .normal)
                        emptyView.button.setImage(UIImage(named: "member_add"), for: .normal)
                        emptyView.button.titleLabel?.font = FONTS(16)
                        emptyView.button.setTitleColor(Bar_Color, for: .normal)
                        emptyView.button.setImagePosition(position: .left, spacing: SCRXFrom(2))
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(24))
                        }
                    }else {
                        emptyView.button.isHidden = true
                    }
                }
            }
        }else {
            deviceCountLabel.isHidden = false
            collectionView.hideEmptyDataView()
        }
    }
    
    private func updateAutoBtnUI() {
        if autoButtonState == .normal {
            autoBtn.layer.removeAnimation(forKey: "loading")
            autoBtn.setImage(UIImage(named: isIPad ? "auto_big" : "auto"), for: .normal)
        }else {
            autoBtn.setImage(UIImage(named: isIPad ? "group_auto_progress_big" : "group_auto_progress")?.withTintColor(Bar_Color), for: .normal)
            autoBtn.layer.addRotationAnimation(duration: 1, repeatCount: 10, animationKey: "loading")
        }
    }
    
    private func updataSensorAutoStateUI() {
        sensorView?.controlStateImageView.isHidden = true
    }
    
    @objc private func moreClick() {
        
        if sensorView?.isShow ?? false {
            if group.sensorNodes.contains(where: { $0.occupancySettings }) {
                return
            }
        }
        
        var items: [MenuPopView.MenuItem] = []
        if space.deviceOperates.contains(.add) {
            items.append(.init(icon: UIImage(named: "group_device_add")?.withTintColor(.white), title: "group_add_device".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
                self?.addDevices()
            }))
        }
        
        if space.groupOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] item in
                self?.editGroup()
            }))
        }
        if space.groupOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] item in
                //                self?.deleteSite()
                self?.deleteGroup()
            }))
        }
        if space.groupOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "menu_members"), title: "members".localizedString, hideAnimation: false, tapItemBack: {[weak self] item in
                self?.members()
            }))
        }
        items.append(.init(icon: UIImage(named: "menu_profile"), title: "profile".localizedString, hideAnimation: false, tapItemBack: {[weak self] item in
            self?.groupProfile()
        }))
        
//        #if DEBUG
//        items.append(.init(icon: UIImage(named: "menu_share"), title: "Export file", tapItemBack: {[weak self] _ in
//            self?.lightLuxPhaseDatas.removeAll()
//            self?.loadCacheLuxsData()
//            self?.exportPhaseLuxFile()
//        }))
//        #endif
        
        if space.groupOperates.contains(.edit) {
            let profileType = group.info.profile.type
            if profileType == .occupancy_daylight || profileType == .vacancy_daylight || profileType == .daylight {
                items.append( .init(icon: UIImage(named: "menu_calibrate"), title: "calibrate".localizedString, hideAnimation: false, tapItemBack: {[weak self] item in
                    self?.calibrate()
                }))
            }
            
            if profileType == .proximityLighting || profileType == .proximityLightingWithPhotocell {
                items.append( .init(icon: UIImage(named: "menu_path"), title: "path".localizedString, hideAnimation: false, tapItemBack: {[weak self] item in
                    self?.setPath()
                }))
            }
        }
    
        
        items.append( .init(icon: UIImage(named: "menu_switch"), title: "switch".localizedString, hideAnimation: false, tapItemBack: {[weak self] item in
            self?.pushToSwitch()
        }))
        
//        items.append(.init(icon: UIImage(named: "menu_edit"), title: "pwm_period".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
//            self?.setPwmPeriod()
//        }))
        
        items.append( .init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: {[weak self] item in
            
            if self?.group.nodes.isEmpty ?? true {
                return
            }
            guard MeshLibManager.manager.isMeshNetworkConnected else {
                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                return
            }
            
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 3)
            self?.refresh()
        }))
        
        if space.groupOperates.contains(.edit), group.info.profile.type != .daylight && group.info.profile.type != .manualControl {
            items.append(.init(icon: UIImage(named: "menu_profile_test"), title: "test".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
                self?.groupTest()
            }))
        }
        
//        #if DEBUG
//        if space.groupOperates.contains(.edit), group.info.profile.type == .proximityLightingWithPhotocell {
//            items.append(.init(icon: UIImage(named: "menu_profile_test"), title: "night".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
//                guard let self = self else { return }
//                if let night = self.group.info.profile.nightData {
//                    MeshAPI.sendMessage(message: SunricherVendorSet(function: .daylightConditionRecall(index: night.id)), address: self.group.address.address)
//                }
//            }))
//            
//            items.append(.init(icon: UIImage(named: "menu_profile_test"), title: "day".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
//                guard let self = self else { return }
//                if let day = self.group.info.profile.dayData {
//                    MeshAPI.sendMessage(message: SunricherVendorSet(function: .daylightConditionRecall(index: day.id)), address: self.group.address.address)
//                }
//            }))
//        }
//        
//        #endif
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
//        SCREEN_HEIGHT - view.height + view.safeAreaInsets.top - 15
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(128))
        // (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight) + StatusBarManager.statusBarFrame.height
                         
        
    }
    
    @objc private func onoffBtnClick(sender: UIButton) {
        guard !showEmergencyControlBlockedIfNeeded() else {
            return
        }
        sender.isSelected = !sender.isSelected
        
        LightGroupControlCommandSender.setGroupOnOff(address: group.address.address, isOn: sender.isSelected)
        group.isOn = sender.isSelected
        group.nodes.forEach({
            $0.isOn = group.isOn
        })
        controlPanelView.setBrightnessValue(group.isOn ? Node.getLightness100(lightness: group.lightness) : 0)
        updateUpDownRatioUI()
        collectionView.reloadData()
        deferNextScheduledUIFlush()
        
        refreshAutoState()
//        isGroupUpdateData = true
    }
    
    @objc private func autoBtnAction(sender: UIButton) {
        guard autoButtonState == .normal else {
            return
        }
        guard !showEmergencyControlBlockedIfNeeded() else {
            return
        }
        autoButtonState = .progress
        updateAutoBtnUI()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
            self?.autoButtonState = .normal
            self?.updateAutoBtnUI()
        }
        
//        btnTouchCancelAction(sender: sender)
        
        MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0), address: group.address.address)
        
        // 更新本地数据
//        let profile = group.info.profile
//        let lightData = profile.lightData.data
        // daylight并且已校准则不更新本地数据，更新设备状态到第一阶段
//        if !((profile.type == .occupancy_daylight || profile.type == .vacancy_daylight || profile.type == .daylight) && group.info.ambientLightSensorNode != nil) {
//            let lightness = Node.getLightness(lightness100: lightData.occupancyLevel)
//            group.lightnessNodes.forEach({
//                $0.lightness = lightness
//                $0.isOn = lightness > 0
//            })
//            collectionView.reloadData()
//            
//            onoffBtn.isSelected = group.isOn
//        }
        // daylight harvesting校准后无效
        let profile = group.info.profile
        if !((profile.type == .occupancy_daylight || profile.type == .vacancy_daylight || profile.type == .daylight) && group.info.ambientLightSensorNode != nil) {
            
            group.lightnessNodes.forEach({
                // profile第一阶段亮度，如果profile是daylight harvesting无法估算亮度则为nil
                if let lightLCOnLightness = $0.lightLCOnLightness {
                    $0.lightness = lightLCOnLightness
                    $0.isOn = lightLCOnLightness > 0
                }
            })
            collectionView.reloadData()
                
            if group.isOn != onoffBtn.isSelected {
                controlPanelView.setBrightnessValue(Node.getLightness100(lightness: group.lightness))
            }
            onoffBtn.isSelected = group.isOn
            updateUpDownRatioUI()
            deferNextScheduledUIFlush()
            
        }
        
        refreshAutoState()
        deferNextScheduledUIFlush()
       
    }

    @objc private func upDownRatioModeBtnClick(sender: UIButton) {
        isUpDownRatioModeSelected.toggle()
        updateUpDownRatioUI()
        deferNextScheduledUIFlush()
    }

    private func controlButtonImage(named imageName: String, matching size: CGSize) -> UIImage? {
        guard let image = UIImage(named: imageName) else {
            return nil
        }
        guard image.size != size else {
            return image
        }

        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private var upDownRatioUnselectedImageName: String {
        isIPad ? "up down ratio button - unselected" : "up down ratio button iphone - unselected"
    }

    private func updateUpDownRatioUI() {
        let showsModeButton = showsUpDownRatioModeButton
        if !showsModeButton {
            isUpDownRatioModeSelected = false
            groupUpRatioValue = 50
        }

        upDownRatioModeBtn.isHidden = !showsModeButton
        upDownRatioModeBtn.isSelected = showsModeButton && isUpDownRatioModeSelected

        let showsRatioControl = showsModeButton && isUpDownRatioModeSelected
        upDownRatioControlView.isHidden = !showsRatioControl
        if showsRatioControl {
            upDownRatioControlView.upValue = groupUpRatioValue
        }

        guard lastShowsUpDownRatioControl != showsRatioControl else {
            return
        }
        lastShowsUpDownRatioControl = showsRatioControl

        controlPanelView.snp.remakeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            }else {
                make.left.right.equalTo(collectionView)
            }
            if showsRatioControl {
                make.top.equalTo(upDownRatioControlView.snp.bottom).offset(SCRYFit(isIPad ? 16 : 8))
            }else {
                make.top.equalTo(controlButtonsStackView.snp.bottom).offset(SCRYFit(8))
            }
            make.bottom.equalToSuperview().offset(-(collapsedSensorViewHeight + SCRYFit(20)))
        }
    }
    
    /// 按键按下回调
    @objc private func btnTouchDownAction(sender: UIButton) {
        sender.setImage(UIImage(named: isIPad ? "auto_big" : "auto")?.withTintColor(RGB(156, 163, 175)), for: .normal)
    }
    
    /// 按键点击抬起回调
    @objc private func btnTouchCancelAction(sender: UIButton) {
//        UIView.animate(withDuration: 0.25) {
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.2) {
            sender.setImage(UIImage(named: isIPad ? "auto_big" : "auto"), for: .normal)
        }
//        }
    }
    
    private func bindSliderAciton() {
        controlPanelView.brightnessValueChanged = { [weak self] value in
            guard let self else { return }
            guard !self.showEmergencyControlBlockedIfNeeded() else {
                self.updateControlPanel()
                return
            }
            self.applyGroupBrightnessValue(value)
        }

        controlPanelView.brightnessThrottleValueChanged = { [weak self] value, ended in
            guard let self else { return }
            guard !self.showEmergencyControlBlockedIfNeeded() else {
                self.updateControlPanel()
                return
            }
            self.sendGroupBrightnessValue(value, ended: ended)
        }

        controlPanelView.cctValueChanged = { [weak self] value in
            guard let self else { return }
            guard !self.showEmergencyControlBlockedIfNeeded() else {
                self.updateControlPanel()
                return
            }
            _ = self.applyGroupCCTValue(value)
        }

        controlPanelView.cctThrottleValueChanged = { [weak self] value, ended in
            guard let self else { return }
            guard !self.showEmergencyControlBlockedIfNeeded() else {
                self.updateControlPanel()
                return
            }
            let temperature = self.applyGroupCCTValue(value)
            LightGroupControlCommandSender.setGroupColorTemperature(address: self.group.address.address, temperature: temperature)
            if ended {
                self.reloadVisibleGroupDeviceItems()
                self.showGroupCCTLimitMessageIfNeeded(target: value)
            }
            self.refreshAutoState()
        }

        controlPanelView.cctQuickButtonValueSelected = { [weak self] value in
            self?.applyGroupCCTQuickButtonValue(value)
        }

        controlPanelView.editBrightnessRequested = { [weak self] in
            self?.showGroupBrightnessInputAlert()
        }

        controlPanelView.editCCTRequested = { [weak self] in
            self?.showGroupCCTInputAlert()
        }

        upDownRatioControlView.valueChanging = { [weak self] value in
            guard let self else { return }
            self.applyGroupUpRatioValue(value)
        }

        upDownRatioControlView.valueChanged = { [weak self] value in
            guard let self else { return }
            self.saveGroupUpRatioValue(value)
        }
    }

    private func applyGroupBrightnessValue(_ value: Int) {
        let clampedValue = max(currentGroupBrightnessRange.lowerBound, min(currentGroupBrightnessRange.upperBound, value))
        let lightness = Node.getLightness(lightness100: clampedValue)
        group.lightness = lightness
        group.isOn = lightness > 0
        onoffBtn.isSelected = group.isOn
        group.nodes.forEach {
            $0.isOn = lightness > 0
            $0.lightness = lightness
        }
        updateUpDownRatioUI()
    }

    private func sendGroupBrightnessValue(_ value: Int, ended: Bool) {
        applyGroupBrightnessValue(value)
        let clampedValue = max(currentGroupBrightnessRange.lowerBound, min(currentGroupBrightnessRange.upperBound, value))
        let lightness = Node.getLightness(lightness100: clampedValue)
        LightGroupControlCommandSender.setGroupLightness(address: group.address.address, lightness: lightness)
        if ended {
            reloadVisibleGroupDeviceItems()
        }
        refreshAutoState()
    }

    private func sendGroupManualBrightnessValue(_ value: Int) {
        let clampedValue = max(currentGroupBrightnessRange.lowerBound, min(currentGroupBrightnessRange.upperBound, value))
        let lightness = Node.getLightness(lightness100: clampedValue)
        let address = group.address.address
        LightGroupControlCommandSender.setGroupLightness(address: address, lightness: lightness, ack: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            LightGroupControlCommandSender.setGroupLightness(address: address, lightness: lightness, ack: false)
        }
    }

    @discardableResult
    private func applyGroupCCTValue(_ value: Int) -> UInt16 {
        let range = currentGroupCCTRange
        let clampedValue = max(range.lowerBound, min(range.upperBound, value))
        let temperature = UInt16(clampedValue)
        group.cct = Int(temperature)
        groupControlCCTNodes.forEach {
            $0.temperature = $0.clampEffectiveCct(temperature)
        }
        updateUpDownRatioUI()
        deferNextScheduledUIFlush()
        return temperature
    }

    private func applyGroupCCTQuickButtonValue(_ value: Int) {
        guard !showEmergencyControlBlockedIfNeeded() else {
            updateControlPanel()
            return
        }
        let temperature = applyGroupCCTValue(value)
        controlPanelView.setCCTValue(Int(temperature))
        LightGroupControlCommandSender.setGroupColorTemperature(address: group.address.address, temperature: temperature)
        reloadVisibleGroupDeviceItems()
        showGroupCCTLimitMessageIfNeeded(target: value)
        refreshAutoState()
    }

    private func sendGroupManualCCTValue(_ temperature: UInt16) {
        let address = group.address.address
        LightGroupControlCommandSender.setGroupColorTemperature(address: address, temperature: temperature, ack: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            LightGroupControlCommandSender.setGroupColorTemperature(address: address, temperature: temperature, ack: false)
        }
    }

    private func showGroupCCTLimitMessageIfNeeded(target: Int) {
        let hasLimitedDevice = groupControlCCTNodes.contains { node in
            target < Int(node.effectiveCctRange.lowerBound) || target > Int(node.effectiveCctRange.upperBound)
        }
        guard hasLimitedDevice else {
            return
        }
        XWHUDManager.showTipHUD("group_cct_limit_reached_message".localizedString, isLineFeed: true)
    }

    private func reloadVisibleGroupDeviceItems() {
        CATransaction.setDisableActions(true)
        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        CATransaction.commit()
        deferNextScheduledUIFlush()
    }

    private func showGroupBrightnessInputAlert() {
        guard !showEmergencyControlBlockedIfNeeded() else {
            updateControlPanel()
            return
        }
        showIntegerInputAlert(
            title: "brightness".localizedString,
            range: currentGroupBrightnessRange
        ) { [weak self] _, clampedValue in
            guard let self else { return }
            self.controlPanelView.setBrightnessValue(clampedValue)
            self.applyGroupBrightnessValue(clampedValue)
            self.sendGroupManualBrightnessValue(clampedValue)
            self.reloadVisibleGroupDeviceItems()
            self.refreshAutoState()
        }
    }

    private func showGroupCCTInputAlert() {
        guard !showEmergencyControlBlockedIfNeeded() else {
            updateControlPanel()
            return
        }
        showIntegerInputAlert(
            title: "color_temp".localizedString,
            range: currentGroupCCTRange
        ) { [weak self] rawValue, _ in
            guard let self else { return }
            let normalizedValue = DeviceLightControlPanelView.normalizedCCTInputValue(rawValue, range: self.currentGroupCCTRange)
            let temperature = self.applyGroupCCTValue(normalizedValue)
            self.controlPanelView.setCCTValue(Int(temperature))
            self.sendGroupManualCCTValue(temperature)
            self.reloadVisibleGroupDeviceItems()
            self.showGroupCCTLimitMessageIfNeeded(target: Int(temperature))
            self.refreshAutoState()
        }
    }

    private func showIntegerInputAlert(title: String, range: ClosedRange<Int>, confirm: @escaping (_ rawValue: Int, _ clampedValue: Int) -> Void) {
        SRAlertView(
            title: title,
            inputText: nil,
            inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 5, textAlignment: .center, showClear: true),
            actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)],
            textValueChangedBack: nil
        ) { text in
            guard let value = Int(text) else {
                XWHUDManager.showTipHUD("illegal_input".localizedString, isLineFeed: true)
                return
            }
            let clamped = max(range.lowerBound, min(range.upperBound, value))
            confirm(value, clamped)
        }.show()
    }
    
    /// 添加设备
    private func addDevices() {
        guard MeshNetworkManager.instance.realNodes.count < space.maxDevicesCount else {
            XWHUDManager.showTipHUD(String(format: "devices_number_exceeds_message".localizedString, space.maxDevicesCount), isLineFeed: true)
            return
        }
        let addVc = DeviceAddViewController(space: space)
        addVc.appointGroup = group
        navigationController?.pushViewController(addVc, animated: true)
    }
    
    /// 编辑组
    private func editGroup() {
        
        let editVc = GroupAddViewController(space: space, group: group)
//        editVc.doneCallback = {[weak self] group in
//            self?.title = group.name
//            self?.groupUpdateCallback?(group)
//        }
        if isIPad {
            editVc.preferredContentSize = iPadPreferredContentSize
        }
        let navVc = NavigationViewController(rootViewController: editVc)
        present(navVc, animated: true)
    }
    
    /// 删除组
    private func deleteGroup() {
        
        SRAlertView(title: "notification".localizedString, message: "group_delete_message".localizedString, contentPadding: SCRXFrom(25), actions: [.cancelAction, SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            
            guard self.group.nodes.isEmpty || self.group.nodes.contains(where: { $0.state }) else { // 设备是否都在线
                SRAlertView(title: "notification".localizedString, message: "group_delete_offline".localizedString, actions:[SRAlertAction(title: "confirm".localizedString, actionHandler: nil)]).show()
                return
            }
            
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            let hud = XWHUDManager.currentHUD()
            if let loadingHud = hud, group.nodes.count > 0 {
                loadingHud.minSize = CGSizeMake(128, 128)
            }
            GroupServer.deleteGroup(group: self.group, progress: { current, total in
                if let loadingHud = hud {
                    loadingHud.detailsLabel.text = "\(current)/\(total)"
                }
            }) {[weak self] _ in
                XWHUDManager.hide()
                guard let self = self else { return }
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                NotificationCenter.default.post(name: .init(groupsRefreshNotificationName), object: nil)
//                self.groupDeleteCallback?(self.group)
                self.close()
                
            } failed: {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("group_delete_failed".localizedString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    XWHUDManager.hide()
                    // 跳转到检查页面
                    self?.deleteFailedCheck()
                }
            }
            
        })]).show()
        
    }
    
    /// 删除失败去手动同步
    private func deleteFailedCheck() {
        
        let vc = SyncDevicesViewController(type: .group(group, outNodes: group.nodes))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            GroupServer.deleteGroup(group: group, progress: nil, successful: nil, failed: nil)
//            self.isGroupUpdateData = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.close()
            }
        }
//        present(NavigationViewController(rootViewController: vc), animated: true)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    /// 查看成员
    private func members() {
        
        let vc = GroupMembersViewController(space: space, group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 配置文件
    private func groupProfile() {
        
        let vc = ProfileSettingsViewController(group: group, profile: group.info.profile)
        vc.editable = space.groupOperates.contains(.edit)
        vc.saveActionCallback = {[weak self] profile in
            guard let self = self else {
                return
            }

            if !(profile.type == .occupancy_daylight || profile.type == .vacancy_daylight || profile.type == .daylight) {
                self.group.info.ambientLightSensorNodeAddress = nil
            }
            self.group.info.profile.updateData(profile: profile)
            self.group.info.save()
            self.group.info.profile.save(meshUUID: self.space.meshUUID, meshNetworkId: self.space.meshNetworkId)
            self.updateUI()
            self.group.updateGroupSyncState()
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 校准
    @objc private func calibrate() {
        let vc = LightSensorCalibrationViewController(group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 设置临近照明路径
    @objc private func setPath() {
        
        let vc = GroupPathSequencePageController(group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 组测试
    @objc private func groupTest() {
        guard !showEmergencyControlBlockedIfNeeded() else {
            return
        }
        MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(false), address: group.address.address)
    }
    
    /// 点击profile类型
    @objc private func profileTypeBtnAction() {
        groupProfile()
    }
    
    /// 刷新
    private func refresh() {
        
        guard group.nodes.count > 0 else {
            return
        }
        
        refreshAutoState()
        
        MeshNodeHeartbeatManager.shared.refresh(nodes: group.nodes)
        
    }
    
    /// 开关
    @objc private func pushToSwitch() {
        let controller = PJSwitchesTypesVC.makePopupViewController(
            onBack: nil,
            onKineticSwitch: { [weak self] in
                guard let self else { return }
                let vc = GroupSwitchsViewController(group: self.group)
                vc.editable = self.space.groupOperates.contains(.edit)
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onBatterySwitch: { [weak self] in
                guard let self else { return }
                let vc = GroupPowerSwitchesViewController(group: self.group, kind: .battery, editable: self.space.groupOperates.contains(.edit))
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onACSwitch: { [weak self] in
                guard let self else { return }
                let vc = GroupPowerSwitchesViewController(group: self.group, kind: .ac, editable: self.space.groupOperates.contains(.edit))
                self.navigationController?.pushViewController(vc, animated: true)
            }
        )
        present(controller, animated: false)
    }
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: self.collectionView.contentOffset.y), animated: true)
        deferNextScheduledUIFlush()
    }
    
    /// 刷新设备
    private func reloadCollectionItem(node: Node) {
        refreshDeviceCell(node: node)
        updateGroupControlSummaryIfNeeded()
        deferNextScheduledUIFlush()
    }

    private func refreshDeviceCell(node: Node) {
        if let index = nodeIndexByAddress[node.primaryUnicastAddress] {
            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? DevicesViewCell {
                item.device = node
                item.displayDeviceNamePrefix = space.displayDeviceNamePrefix
                if node.state && node.needSyncGroupData {
                    item.iconImageView.image = UIImage(named: node.unsyncIconName)
                }
            }
        }
    }

    private func updateGroupControlSummaryIfNeeded() {
        onoffBtn.isEnabled = MeshLibManager.manager.isMeshNetworkConnected && group.nodes.contains(where: { $0.state })
        if group.isOn != onoffBtn.isSelected {
            controlPanelView.setBrightnessValue(Node.getLightness100(lightness: group.lightness))
        }
        onoffBtn.isSelected = group.isOn
        updateControlPanel()
        updateUpDownRatioUI()
    }

    private func isSensorOnlyMessage(_ message: MeshMessage) -> Bool {
        if message is SensorStatus {
            return true
        }
        if let vendorSet = message as? SunricherVendorSet, case .proximityLightingTrigger = vendorSet.function {
            return true
        }
        return false
    }
    
    /// 长按事件，跳转到设备详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < group.nodes.count {
            let node = group.nodes[indexPath.item]
            let vc = DeviceLightViewController(space: space, node: node)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    /// 校准
    @objc private func calibrateBtnAction() {
        
        let vc = LightSensorCalibrationViewController(group: group)
        navigationController?.pushViewController(vc, animated: true)
    }

    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.alwaysBounceVertical = false
        scrollView.delaysContentTouches = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }

        scrollView.addSubview(contentView)
        contentView.clipsToBounds = false
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemRowCount = rowNum
        flowLayout.itmeColCount = columnNum
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: collectionViewInsets.left, bottom: 0, right: collectionViewInsets.right)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: collectionViewInsets.bottom, left: 0, bottom: collectionViewInsets.bottom, right: 0)
        collectionView.backgroundColor = RGB(0, 0, 0, 0.05)
        collectionView.layer.cornerRadius = SCRYFrom(40)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(GroupDeviceViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            if isIPad {
                make.top.equalToSuperview().offset(SCRYFit(60))
                make.height.equalTo(SCRYFrom(478))
            }else {
                make.top.equalToSuperview().offset(SCRYFit(40))
                make.height.equalTo(SCRYFrom(320))
            }
        }
        
        deviceCountLabel = UILabel(text: "", textColor: Bar_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(deviceCountLabel)
        deviceCountLabel.snp.makeConstraints { make in
            make.left.equalTo(collectionView).offset(SCRXFrom(20))
            make.top.equalTo(collectionView).offset(SCRYFrom(13))
        }
        
        pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = Bar_Color
        pageControl.pageIndicatorTintColor = RGB(216, 216, 216)
        pageControl.addTarget(self, action: #selector(pageControlValueChanged), for: .valueChanged)
        pageControl.hidesForSinglePage = true
        contentView.addSubview(pageControl)
        pageControl.snp.makeConstraints { make in
            make.bottom.equalTo(collectionView)
            make.centerX.equalToSuperview()
//            make.width.equalTo(SCRXFrom(40))
//            make.height.equalTo(4)
        }

        controlButtonsStackView.axis = .horizontal
        controlButtonsStackView.alignment = .center
        controlButtonsStackView.distribution = .equalSpacing
        controlButtonsStackView.spacing = isIPad ? SCRXFrom(60) : SCRXFrom(40)
        contentView.addSubview(controlButtonsStackView)
        controlButtonsStackView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(isIPad ? 64 : 20))
        }
        
        var offImageName = "group_off"
        var onImageName = "group_on"
//        var disableImageName = "group_control_disable"
        if isIPad {
            offImageName = "group_off_big"
            onImageName = "group_on_big"
//            disableImageName = "group_control_disable_big"
        }
        onoffBtn = UIButton(normalImageName: offImageName, selectedImageName: onImageName, target: self, action: #selector(onoffBtnClick))
        
//        onoffBtn.setImage(UIImage(named: offImageName), for: .disabled)
        controlButtonsStackView.addArrangedSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.width.height.equalTo(isIPad ? 56 : 40)
        }
        
        autoBtn = UIButton(normalImageName: isIPad ? "auto_big" : "auto", target: self, action: #selector(autoBtnAction))
//        autoBtn.addTarget(self, action: #selector(btnTouchDownAction), for: .touchDown)
//        autoBtn.addTarget(self, action: #selector(btnTouchCancelAction), for: .touchCancel)
//        UIButton(title: "AUTO".localizedString, titleSize: 13, titleColor: Bar_Color, fit: false, target: self, action: #selector(autoBtnAction))
//        autoBtn.setBackgroundImage(UIImage(named: "auto_btn_border"), for: .normal)
        controlButtonsStackView.addArrangedSubview(autoBtn)
        autoBtn.snp.makeConstraints { make in
            make.width.height.equalTo(isIPad ? 56 : 40)
        }

        upDownRatioModeBtn = UIButton(
            normalImageName: upDownRatioUnselectedImageName,
            selectedImageName: "up down ratio button - selected",
            target: self,
            action: #selector(upDownRatioModeBtnClick)
        )
        upDownRatioModeBtn.isHidden = true
        if let autoButtonImageSize = autoBtn.image(for: .normal)?.size {
            upDownRatioModeBtn.setImage(controlButtonImage(named: upDownRatioUnselectedImageName, matching: autoButtonImageSize), for: .normal)
            upDownRatioModeBtn.setImage(controlButtonImage(named: "up down ratio button - selected", matching: autoButtonImageSize), for: .selected)
        }
        controlButtonsStackView.addArrangedSubview(upDownRatioModeBtn)
        upDownRatioModeBtn.snp.makeConstraints { make in
            make.width.height.equalTo(isIPad ? 56 : 40)
        }

        controlPanelView = DeviceLightControlPanelView()
        controlPanelView.clipsToBounds = false
        contentView.addSubview(controlPanelView)

        upDownRatioControlView = DeviceUpDownRatioControlView()
        upDownRatioControlView.isHidden = true
        contentView.addSubview(upDownRatioControlView)
        upDownRatioControlView.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            }else {
                make.left.right.equalTo(collectionView)
            }
            make.top.equalTo(controlButtonsStackView.snp.bottom).offset(SCRYFit(20))
        }

        controlPanelView.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            }else {
                make.left.right.equalTo(collectionView)
            }
            make.top.equalTo(controlButtonsStackView.snp.bottom).offset(SCRYFit(8))
            make.bottom.equalToSuperview().offset(-(collapsedSensorViewHeight + SCRYFit(20)))
        }
        
        calibrateBtn = UIButton(title: "CALIBRATE".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(calibrateBtnAction))
        calibrateBtn.backgroundColor = Bar_Color
        calibrateBtn.layer.cornerRadius = SCRYFrom(15)
        calibrateBtn.isHidden = true
        contentView.addSubview(calibrateBtn)
        calibrateBtn.snp.makeConstraints { make in
            make.right.equalTo(collectionView)
            make.top.equalToSuperview()
            make.width.equalTo(SCRXFrom(88))
            make.height.equalTo(SCRYFrom(32))
        }
        
        calibrateLabel = UILabel(text: "not_calibrated".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        calibrateLabel.isHidden = true
        contentView.addSubview(calibrateLabel)
        calibrateLabel.snp.makeConstraints { make in
            make.left.equalTo(collectionView)
            make.top.equalToSuperview()
            make.centerY.equalTo(calibrateBtn)
//            make.bottom.equalTo(collectionView.snp.top).offset(SCRYFit(-16))
        }
        
        setPathBtn = UIButton(title: "SET".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(setPath))
        setPathBtn.backgroundColor = Bar_Color
        setPathBtn.layer.cornerRadius = SCRYFrom(15)
        setPathBtn.isHidden = true
        contentView.addSubview(setPathBtn)
        setPathBtn.snp.makeConstraints { make in
            make.right.equalTo(collectionView)
            make.width.height.centerY.equalTo(calibrateBtn)
        }
        
        setPathLabel = UILabel(text: "group_set_the_path_sequence".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        setPathLabel.isHidden = true
        contentView.addSubview(setPathLabel)
        setPathLabel.snp.makeConstraints { make in
            make.left.equalTo(collectionView)
            make.centerY.equalTo(setPathBtn)
//            make.bottom.equalTo(collectionView.snp.top).offset(SCRYFit(-16))
        }
        
        profileTypeBtn = UIButton(title: "", titleSize: 14, titleWeight: .light, titleColor: SubText_Color, fit: false, target: self, action: #selector(profileTypeBtnAction))
        profileTypeBtn.isHidden = true
        contentView.addSubview(profileTypeBtn)
        profileTypeBtn.snp.makeConstraints { make in
            make.centerY.equalTo(setPathLabel)
            make.centerX.equalToSuperview()
        }
        
        sensorView = GroupSensorView()
        sensorView?.isHidden = true
        sensorView?.delegate = self
        view.addSubview(sensorView!)
        sensorView!.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(40) + kSafeAreaBottomHeight)
        }
    }


}

extension GroupViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return group.nodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupDeviceViewCell
        let node = group.nodes[indexPath.item]
        cell.device = node
        cell.displayDeviceNamePrefix = space.displayDeviceNamePrefix
        if node.state && node.needSyncGroupData {
            cell.iconImageView.image = UIImage(named: node.unsyncIconName)
        }
//        let node = MeshNetworkManager.instance.localNode!
//        cell.nameLabel.text = node.name! + "\(indexPath.item + 1)"
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let node = group.nodes[indexPath.item]
        guard !node.isEmergencySignController else {
            return
        }
        guard !showEmergencyControlBlockedIfNeeded() else {
            return
        }
        guard node.state else {
            MeshAPI.getNodeOnOffState(address: node.primaryUnicastAddress)
            return
        }
        node.isOn = !node.isOn
        if !node.isOn, node.lightness > 0 { // 关灯，记录关灯前的亮度值
            node.trunOffLightness = node.lightness
        }
        if node.isOn {
            node.lightness = node.trunOffLightness ?? node.lightnessRange.upperBound
        }else {
            node.lightness = 0
        }
        reloadCollectionItem(node: node)
        LightGroupControlCommandSender.setNodeOnOff(address: node.primaryUnicastAddress, isOn: node.isOn, ack: true)
        if node == group.info.ambientLightSensorNode {
            refreshAutoState()
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        isDeviceCollectionScrolling = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === collectionView, !decelerate else { return }
        isDeviceCollectionScrolling = false
        updateCurrentCollectionPage()
        flushPendingUIUpdatesImmediately()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        isDeviceCollectionScrolling = false
        updateCurrentCollectionPage()
        flushPendingUIUpdatesImmediately()
    }

    private func updateCurrentCollectionPage() {
        let page = Int(collectionView.contentOffset.x / collectionView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        //            pageControl.setCurrentPage(page, animated: true)
    }
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//
//    }
    
}

extension GroupViewController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if view.window != nil, nodeIndexByAddress[node.primaryUnicastAddress] != nil {
            markDeviceDirty(node)
        }
    }
    
    /// 设备数据修改时间戳更新
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdateTimeChange node: Node, lastUpdate: Int64) {
//        if node.lastUpdateSyncTime != lastUpdate {
            node.clearSyncStateCache()
//        }
    }
    
    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: MeshMessage, sentFrom source: Address, to destination: Address) {
        // 传感器消息
        if let sensorNode = group.sensorNodes.first(where: { $0.contains(elementWithAddress: source) }) {
            if let sensorMessage = message as? SensorStatus {
                sensorMessage.values.forEach { (property: DeviceProperty, _) in
                    // 人体存在传感器model
                    if case .presenceDetected = property {
                        markSensorDirty(sensor: sensorNode, sensorType: .presenceDetected)
                    }
                    
                    if case .presentAmbientLightLevel = property, automationTimer != nil {
                        currentPhaseLuxDatas.append(LightLuxData(name: sensorNode.name ?? "", address: sensorNode.primaryUnicastAddress, lux: sensorNode.steadyDaylightLux ?? 0))
                    }
                    
                    // 环境光传感器model
                    if case .presentAmbientLightLevel = property, sensorNode.primaryUnicastAddress == group.info.ambientLightSensorNode?.primaryUnicastAddress {
                        markSensorDirty(sensor: sensorNode, sensorType: .ambientLight)
                    }
                }
            }else if let lightOnOffStatus = message as? LightLCLightOnOffStatus {
                sensorNode.lightControlOn = lightOnOffStatus.isOn
                markSensorControlStateDirty()
            }
        }
        
        /// 邻近照明pir触发信号
        if let vendorSet = message as? SunricherVendorSet, case .proximityLightingTrigger(_, let source) = vendorSet.function {
            if let sensorNode = group.sensorNodes.first(where: { $0.contains(elementWithAddress: source) }), sensorNode.presenceDetectedSensorModel != nil {
                markSensorDirty(sensor: sensorNode, sensorType: .presenceDetected, isTransientPresenceTrigger: true)
            }
        }
        
        
        if let node = manager.meshNetwork?.node(withAddress: source), !node.isProvisioner {
            node.updateData(message: message)
            if isSensorOnlyMessage(message) { return }
            
            // 动能开关事件
            let isSwitchAction = message is LightLCLightOnOffSetUnacknowledged || message is GenericOnOffSetUnacknowledged || message is SceneRecallUnacknowledged
            
            if nodeIndexByAddress[node.primaryUnicastAddress] != nil || destination == .allNodes || (isSwitchAction && group.info.switchs.contains(where: { $0.linkGroupAddress == destination })) {
                if view.window != nil {
                    if isSwitchAction {
                        markFullCollectionReloadDirty()
                    }else {
                        markDeviceDirty(node)
                    }
                }
            }
        }
    }
    
}

private extension GroupViewController {
    func showEmergencyControlBlockedIfNeeded() -> Bool {
        guard EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: group) else {
            return false
        }
        XWHUDManager.showTipHUD("Uncontrollable in emergency situations".localizedString, isLineFeed: true)
        return true
    }
}

extension GroupViewController: GroupSensorViewDelegate {

    
    func sensorViewDidShow(view: GroupSensorView) {
        
        self.isModalInPresentation = true
        flushPendingUIUpdatesImmediately()
    }
    
    func sensorViewDidHide(view: GroupSensorView) {
  
        self.isModalInPresentation = false
        isSensorTableScrolling = false
        flushPendingUIUpdatesImmediately()
    }

    func sensorViewDidBeginScrolling(view: GroupSensorView) {
        isSensorTableScrolling = true
    }

    func sensorViewDidEndScrolling(view: GroupSensorView) {
        isSensorTableScrolling = false
        flushPendingUIUpdatesImmediately()
    }
    
    func sensorViewShouldHide(_ view: GroupSensorView) -> Bool {
        if group.sensorNodes.contains(where: { $0.occupancySettings }) {
            return false
        }
        return true
    }
    
    /// 设备识别
    func sensorView(_ view: GroupSensorView, identifyAction sensor: Node) {
//        MeshAPI.identify(address: sensor.primaryUnicastAddress)
//        var period: UInt16 = 5000
        if let vendorModel = sensor.sunricherVendorModel {
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))), model: vendorModel)
//            if Bool.random() {
//                MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .default, frequency: .default)), model: vendorModel)
//            }else {
//                MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .breathe, frequency: .breathe)), model: vendorModel)
//            }
        }
    }
    
    /// 传感器设备占用功能点击
    func sensorView(_ view: GroupSensorView, occupancySensorTapAction sensor: Node) {
        
        guard space.groupOperates.contains(.edit) else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }
        
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        if sensor.occupancySettings {
            return
        }
        // 是否启用
        let enable = !sensor.pirEnabled
        sensor.occupancySettings = true
        view.reloadSensor(sensor: sensor)
        sensorOccupancySettings(sensor: sensor, enable: enable) {[weak self] result in
            guard let self = self else { return }
            sensor.occupancySettings = false
            switch result {
            case .success:
                sensor.pirEnabled = enable
                sensor.savePropertys()
                ToastStatusView.show(in: self.view, message: "configuration_successful".localizedString, type: .success)
                // 同步数据到服务器
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                sensor.reloadSyncStateCache()
                
            case .failure(let error):
                var errorMessage = "configuration_failed".localizedString
                switch error {
                case .timeout:
                    errorMessage = "device_offline".localizedString
                case .nonsupport:
                    errorMessage = "configuration_not_support".localizedString
                default:
                    break
                }
                ToastStatusView.show(in: self.view, message: errorMessage, type: .failure)
            }
            view.reloadSensor(sensor: sensor)
        }
        
    }
}

extension Node {
    static var lightControlOnKey: UInt8 = 0
    static var occupancySettingsKey: UInt8 = 0
    
    /// 是否在control on状态
    var lightControlOn: Bool {
        get {
            objc_getAssociatedObject(self, &Node.lightControlOnKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &Node.lightControlOnKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 占用功能设置中
    var occupancySettings: Bool {
        get {
            objc_getAssociatedObject(self, &Node.occupancySettingsKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &Node.occupancySettingsKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}

/// 传感器占用功能设置错误
enum SensorOccupancySettingsError: Error {
    /// 功能不支持
    case nonsupport
    /// 未知错误
    case unknown
    /// 配置失败
    case configurationFailed
    /// 超时
    case timeout
}
