//
//  GroupViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/12.
//

import UIKit
import NordicSigMeshSDK

class GroupViewController: UIViewController {
    
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var onoffBtn: UIButton!
    private var autoBtn: UIButton!
    private var lightnessSlider: BuoySliderView!
    private var cctSlider: BuoySliderView!
    private var pageControl: UIPageControl!
    
    private var calibrateLabel: UILabel!
    private var calibrateBtn: UIButton!
    private var sensorView: GroupSensorView?
    
    private var automationTimer: Timer?
    private lazy var testBtn: UIButton = {
        let btn = UIButton(title: "Start", titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, fit: false, target: self, action: #selector(test))
        btn.setTitle("Stop", for: .selected)
        return btn
    }()
    
    let space: SpaceData
    let group: Group
    
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
        
        MeshLibManager.manager.addObserver(self, forKeyPath: "isMeshNetworkConnected", context: nil)
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
            
            //            let appearance = UINavigationBarAppearance()
            //            appearance.configureWithOpaqueBackground()
            //            appearance.backgroundColor = .clear
            //            appearance.shadowImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .clear)
            ////            appearance.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 18, weight: .light)]
            //            navigationController?.navigationBar.standardAppearance = appearance
            //            navigationController?.navigationBar.scrollEdgeAppearance = appearance
            
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        
        
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        
        setupUI()
        bindSliderAciton()
        
        //        for i in 1...30 {
        //            devices.append("ID \(i)")
        //        }
        
        
        addNotificationObserver()
        
        if let sensor = self.group.info.ambientLightSensorNode {
            MeshAPI.getAmbientSensorValue(node: sensor, result: nil)
        }
        // 刷新设备状态
        refresh()
    }
    
    @objc private func test(sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
            automationTimer = LCWeakTimer.scheduledTimer(timeInterval: 10, aTarget: self, selector: #selector(automationTimerAction), userInfo: nil, repeats: true)
            RunLoop.current.add(automationTimer!, forMode: .common)
        }else {
            automationTimer?.invalidate()
            automationTimer = nil
        }
    }
    
    @objc private func automationTimerAction() {
        group.isOn = !group.isOn
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: group.isOn)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        collectionView.reloadData()
//        updateEmptyUI()
        updateUI()
        
        MeshLibManager.manager.messageDelegate = self
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
//        sensorPublishCheck()
    }
    deinit {
        automationTimer?.invalidate()
        automationTimer = nil
        
        MeshLibManager.manager.removeObserver(self, forKeyPath: "isMeshNetworkConnected")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
//        if isGroupUpdateData {
            NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: group)
//        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(2) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(3)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        let itemSize = CGSize(width: itemW, height: itemW)
        flowLayout.itemSize = itemSize
        
        collectionView.snp.updateConstraints { make in
            var height = itemSize.height * 3.0 + flowLayout.minimumLineSpacing * 2.0 + collectionView.contentInset.top + collectionView.contentInset.bottom + flowLayout.sectionInset.top + flowLayout.sectionInset.bottom
            height = CGFloat(ceil(Float(height)))
//            CGFloat(floorf(Float(height) * 100) / 100.0)
            make.height.equalTo(height)
        }
        
    }
    
    private func addNotificationObserver() {
        NotificationCenter.default.addObserver(forName: .init(groupDataUpdateNotificationName), object: nil, queue: nil) {[weak self] notification in
            //            self?.refreshData = true
            guard let self = self, let group = notification.object as? Group else { return }
        
            self.title = group.name
            self.updateUI()
        }
        
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if MeshLibManager.manager.isMeshNetworkConnected {
            onoffBtn.isEnabled = true
        }else {
            if group.nodes.count > 0 {
                onoffBtn.isEnabled = false
            }
        }
    }
    
    @objc private func close() {
        dismiss(animated: true)
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
    
    private func updateUI() {
        pageControl.numberOfPages = Int(ceil(Double(group.nodes.count) / 9.0))
        //        pageControl.currentPage = 0
        updateEmptyUI()
        
        onoffBtn.isEnabled = MeshLibManager.manager.isMeshNetworkConnected && group.nodes.contains(where: { $0.state })
        onoffBtn.isSelected = group.isOn
        
        let data = group.info.profile.lightData.data
        lightnessSlider.slider.limitRange = data.lowEndTrim...data.highEndTrim
        lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
        if group.nodes.contains(where: {$0.temperatureModel != nil }) {
            cctSlider.value = group.cct
            cctSlider.isHidden = false
        }else {
            cctSlider.isHidden = true
        }
        
        let profileType = group.info.profile.type
        // 提示校准
        if group.info.ambientLightSensorNode == nil || !group.info.ambientLightSensorNode!.sensorCalibrated, group.ambientLightSensorNodes.count > 0, profileType == .occupancy_daylight || profileType == .vacancy_daylight || profileType == .daylight, space.groupOperates.contains(.edit) {
            calibrateBtn.isHidden = false
            calibrateLabel.isHidden = false
        }else {
            calibrateBtn.isHidden = true
            calibrateLabel.isHidden = true
        }
        
        if profileType != .manualControl {
            sensorView?.isHidden = false
            sensorView?.sensors = group.sensorNodes
            switch profileType {
            case .occupancy_daylight, .vacancy_daylight:
                sensorView?.supportSensorType = .all
            case .occupancy, .vacancy:
                sensorView?.supportSensorType = .presenceDetected
            case .daylight:
                sensorView?.supportSensorType = .ambientLight
            case .manualControl:
                sensorView?.supportSensorType = .none
            }
        }else {
            sensorView?.isHidden = true
        }
        
        collectionView.reloadData()
    }
    
    private func updateEmptyUI() {
        if group.nodes.isEmpty {
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
            collectionView.hideEmptyDataView()
        }
    }
    
    @objc private func moreClick() {
        
        var items: [MenuPopView.MenuItem] = []
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
        
        if space.groupOperates.contains(.edit) {
            let profileType = group.info.profile.type
            if profileType == .occupancy_daylight || profileType == .vacancy_daylight || profileType == .daylight {
                items.append( .init(icon: UIImage(named: "menu_calibrate"), title: "calibrate".localizedString, hideAnimation: false, tapItemBack: {[weak self] item in
                    self?.calibrate()
                }))
            }
        }
        
        items.append( .init(icon: UIImage(named: "menu_switch"), title: "switch".localizedString, hideAnimation: false, tapItemBack: {[weak self] item in
            self?.pushToSwitch()
        }))
        
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
        
        
        let margin: CGFloat = SCRXFrom(15.5)
//        isIphoneX ? 18 : 15
        let touchCenterX = view.width - SCRXFrom(margin) - 15
        let touchCenterY = SCREEN_HEIGHT - view.height + view.safeAreaInsets.top - 15
        MenuPopView.show(items: items, anchorPoint: CGPoint(x: touchCenterX, y: touchCenterY))
        // (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight) + StatusBarManager.statusBarFrame.height
                         
        
    }
    
    @objc private func onoffBtnClick(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: sender.isSelected)
        group.isOn = sender.isSelected
        group.nodes.forEach({
            $0.isOn = group.isOn
        })
        lightnessSlider.value = group.isOn ? Node.getLightness100(lightness: group.lightness) : 0
        collectionView.reloadData()
//        isGroupUpdateData = true
    }
    
    @objc private func autoBtnAction(sender: UIButton) {
        
        btnTouchCancelAction(sender: sender)
        
        MeshAPI.sendMessage(message: LightLCLightOnOffSet(true, transitionTime: .default, delay: 0), address: group.address.address)
        
        // 更新本地数据
        let profile = group.info.profile
        let lightData = profile.lightData.data
        // daylight并且已校准则不更新本地数据，更新设备状态到第一阶段
        if !((profile.type == .occupancy_daylight || profile.type == .vacancy_daylight || profile.type == .daylight) && group.info.ambientLightSensorNode != nil) {
            let lightness = Node.getLightness(lightness100: lightData.occupancyLevel)
            group.lightnessNodes.forEach({
                $0.lightness = lightness
                $0.isOn = lightness > 0
            })
            collectionView.reloadData()
            
            if group.isOn != onoffBtn.isSelected {
                lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
            }
            onoffBtn.isSelected = group.isOn
        }
        
    }
    
    /// 按键按下回调
    @objc private func btnTouchDownAction(sender: UIButton) {
        sender.setImage(UIImage(named: "auto_press"), for: .normal)
    }
    
    /// 按键点击抬起回调
    @objc private func btnTouchCancelAction(sender: UIButton) {
//        UIView.animate(withDuration: 0.25) {
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.2) {
            sender.setImage(UIImage(named: "auto"), for: .normal)
        }
//        }
    }
    
    
    private func bindSliderAciton() {
        lightnessSlider.valueThrottleChangedCallback = {[weak self] (value, ended) in
            print("lightness: \(value)")
            guard let self = self else { return }
            let lightness = Node.getLightness(lightness100: value)
            self.group.lightness = lightness
            self.group.isOn = lightness > 0
            self.onoffBtn.isSelected = self.group.isOn
            MeshAPI.setGroupLightnessState(address: self.group.address.address, lightness: lightness)
            group.nodes.forEach({
                $0.isOn = lightness > 0
                $0.lightness = lightness
                self.reloadCollectionItem(node: $0)
            })
//            collectionView.reloadData()
//            self.isGroupUpdateData = true
        }
        
        cctSlider.valueThrottleChangedCallback = {[weak self] (value, ended) in
            print("cct: \(value)")
            guard let self = self else { return }
            self.group.cct = value
            MeshAPI.setGroupColorTemperatureState(address: self.group.address.address, temperature: UInt16(value))
            group.nodes.forEach({
                $0.temperature = UInt16(value)
                self.reloadCollectionItem(node: $0)
            })
//            collectionView.reloadData()
//            self.isGroupUpdateData = true
        }
    }
    
    /// 编辑组
    private func editGroup() {
        
        let editVc = GroupAddViewController(space: space, group: group)
//        editVc.doneCallback = {[weak self] group in
//            self?.title = group.name
//            self?.groupUpdateCallback?(group)
//        }
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
            
//            group.nodes.forEach({ node in
//                node.unsubscribe(from: self.group)
//                node.sceneDatas.removeAll()
//                // 删除设备场景数据
//                SceneExecuteData.deleteData(meshUUID: self.space.meshUUID, address: node.primaryUnicastAddress)
//                // 删除设备关联组的日程数据
//                self.group.info.bindSchedules.forEach{ schedule in
//                    Node.deleteSchedule(meshUUID: self.space.meshUUID, address: node.primaryUnicastAddress, scheduleId: schedule.id)
//                }
//            })
            
            GroupServer.deleteGroup(group: self.group, progress: nil) {[weak self] _ in
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
//             profile.type
            if profile.type == .occupancy || profile.type == .vacancy || profile.type == .manualControl {
                self.group.info.ambientLightSensorNodeAddress = nil
            }
            self.group.info.profile.updateData(profile: profile)
            self.group.info.save()
            self.group.info.profile.save(meshUUID: self.space.meshUUID, meshNetworkId: self.space.meshNetworkId)
            self.updateUI()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 校准
    @objc private func calibrate() {
        let vc = LightSensorCalibrationViewController(group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 刷新
    private func refresh() {
        
        guard group.nodes.count > 0 else {
            return
        }
        
        MeshAPI.sendMessage(message: LightLightnessGet(), address: group.address.address)
        
        if group.nodes.contains(where: { $0.temperatureModel != nil }) {
            MeshAPI.sendMessage(message: LightCTLGet(), address: group.address.address)
        }
        
    }
    
    /// 开关
    @objc private func pushToSwitch() {
        
        let vc = GroupSwitchsViewController(group: group)
        vc.editable = space.groupOperates.contains(.edit)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: 0), animated: true)
    }
    
    /// 刷新设备
    private func reloadCollectionItem(node: Node) {
        
        if let index = group.nodes.firstIndex(where: {$0.primaryUnicastAddress == node.primaryUnicastAddress}) {
            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? DevicesViewCell {
                item.device = node
            }
        }
        
        onoffBtn.isEnabled = MeshLibManager.manager.isMeshNetworkConnected && group.nodes.contains(where: { $0.state })
        if group.isOn != onoffBtn.isSelected {
            lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
        }
        onoffBtn.isSelected = group.isOn
//        cctSlider.value = group.cct
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
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(14)
        flowLayout.minimumInteritemSpacing = SCRXFrom(14)
        flowLayout.scrollDirection = .horizontal
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(24), bottom: 0, right: SCRXFrom(24))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(36), left: 0, bottom: SCRYFrom(36), right: 0)
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
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            make.top.equalTo(SCRYFit(40) + (navigationController?.navigationBar.frame.maxY ?? 0))
//            make.height.equalTo(collectionView.snp.width).multipliedBy(340.0 / 316)
            make.height.equalTo(SCRYFrom(340))
        }
        
        pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = Bar_Color
        pageControl.pageIndicatorTintColor = RGB(216, 216, 216)
        pageControl.addTarget(self, action: #selector(pageControlValueChanged), for: .valueChanged)
        pageControl.hidesForSinglePage = true
        view.addSubview(pageControl)
        pageControl.snp.makeConstraints { make in
            make.bottom.equalTo(collectionView)
            make.centerX.equalToSuperview()
//            make.width.equalTo(SCRXFrom(40))
//            make.height.equalTo(4)
        }
        
        onoffBtn = UIButton(normalImageName: "group_off", selectedImageName: "group_on", target: self, action: #selector(onoffBtnClick))
        onoffBtn.setImage(UIImage(named: "group_control_disable"), for: .disabled)
        view.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(32))
            make.centerX.equalToSuperview().offset(SCRXFrom(-40))
        }
        
        autoBtn = UIButton(normalImageName: "auto", target: self, action: #selector(autoBtnAction))
        autoBtn.addTarget(self, action: #selector(btnTouchDownAction), for: .touchDown)
        autoBtn.addTarget(self, action: #selector(btnTouchCancelAction), for: .touchCancel)
//        UIButton(title: "AUTO".localizedString, titleSize: 13, titleColor: Bar_Color, fit: false, target: self, action: #selector(autoBtnAction))
//        autoBtn.setBackgroundImage(UIImage(named: "auto_btn_border"), for: .normal)
        view.addSubview(autoBtn)
        autoBtn.snp.makeConstraints { make in
            make.centerY.equalTo(onoffBtn)
            make.left.equalTo(onoffBtn.snp.right).offset(SCRXFrom(40))
        }
        
        lightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
        lightnessSlider.slider.interval = 0.5
//        lightnessSlider.isHidden = !group.supportLightness
        view.addSubview(lightnessSlider)
        lightnessSlider.snp.makeConstraints { make in
            make.left.right.equalTo(collectionView)
            make.top.equalTo(onoffBtn.snp.bottom).offset(SCRYFit(8))
            make.height.equalTo(SCRYFrom(76))
        }
        
        cctSlider = BuoySliderView(frame: .zero, functionType: .cct())
        cctSlider.slider.interval = 0.5
        cctSlider.slider.step = 10
//        Node.getTemperature100(temperature: UInt16(group.cct))
//        cctSlider.isHidden = !group.supportCct
        view.addSubview(cctSlider)
        cctSlider.snp.makeConstraints { make in
            make.left.right.height.equalTo(lightnessSlider)
            make.top.equalTo(lightnessSlider.snp.bottom).offset(SCRYFit(2))
        }
        
        calibrateLabel = UILabel(text: "not_calibrated".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        calibrateLabel.isHidden = true
        view.addSubview(calibrateLabel)
        calibrateLabel.snp.makeConstraints { make in
            make.left.equalTo(collectionView)
            make.bottom.equalTo(collectionView.snp.top).offset(SCRYFit(-16))
        }
        
        calibrateBtn = UIButton(title: "CALIBRATE".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(calibrateBtnAction))
        calibrateBtn.backgroundColor = Bar_Color
        calibrateBtn.layer.cornerRadius = SCRYFrom(15)
        calibrateBtn.isHidden = true
        view.addSubview(calibrateBtn)
        calibrateBtn.snp.makeConstraints { make in
            make.right.equalTo(collectionView)
            make.centerY.equalTo(calibrateLabel)
            make.width.equalTo(SCRXFrom(88))
            make.height.equalTo(SCRYFrom(32))
        }
        
        sensorView = GroupSensorView()
        sensorView?.isHidden = true
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
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let node = group.nodes[indexPath.item]
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
        MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        //            pageControl.setCurrentPage(page, animated: true)
    }
    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//
//    }
    
}

extension GroupViewController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if group.nodes.contains(node) {
            reloadCollectionItem(node: node)
        }
    }
    
    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: MeshMessage, sentFrom source: Address, to destination: Address) {
        // 传感器消息
        if let sensorNode = group.sensorNodes.first(where: { $0.contains(elementWithAddress: source) }), let sensorMessage = message as? SensorStatus {
            sensorMessage.values.forEach { (property: DeviceProperty, _) in
                // 人体存在传感器model
                if case .presenceDetected = property {
                    sensorView?.reloadSensorData(sensor: sensorNode, sensorType: .presenceDetected)
                }
                
                // 环境光传感器model
                if case .presentAmbientLightLevel = property, sensorNode.primaryUnicastAddress == group.info.ambientLightSensorNode?.primaryUnicastAddress {
                    sensorView?.reloadSensorData(sensor: sensorNode, sensorType: .ambientLight)
                }
            }
        }
        
        if let node = manager.meshNetwork?.node(withAddress: source), !node.isProvisioner {
            node.updateData(message: message)
            if group.nodes.contains(node) {
                if view.window != nil {
                    collectionView.reloadData()
                    if group.isOn != onoffBtn.isSelected {
                        lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
                    }
                    onoffBtn.isSelected = group.isOn
                }
//                reloadCollectionItem(node: node)
            }
        }
    }
    
}
