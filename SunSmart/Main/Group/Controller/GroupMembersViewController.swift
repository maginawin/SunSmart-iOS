//
//  GroupMembersViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/15.
//

import UIKit
import NordicSigMeshSDK

class GroupMembersViewController: UIViewController {

    private struct GroupMemberProxyRemovalPlan {
        let node: Node
        let switchData: DeviceSwitchData
        let decision: KineticSwitchGroupMemberRemovalDecision
    }

    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var functionView: GroupDevicesFunctionView!
    private var selectNodes: [Node] = []
    private let deviceNameFilterSession = DeviceNameFilterSession()
    private var deviceNameFilterObservation: UUID?
    /// 是否创建后添加设备
    var isAddDevices: Bool = false
    
    private var nodes: [Node] = []
    private var visibleNodes: [Node] = []
    /// 配置过程是否去创建场景
    private var configurationCreateScene: Bool = false
    
    /// 每行个数
    private var rowNum: Int = isIPad ? 5 : 3
    /// collectionview边距
    private var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: SCRYFrom(44), left: SCRXFrom(40), bottom: SCRYFrom(44), right: SCRXFrom(40)) : UIEdgeInsets(top: SCRYFrom(16), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
    
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    
    private var meshNetworkConnectedObservation: NSKeyValueObservation?
    
    let space: SpaceData
    var group: Group
    
    
    init(space: SpaceData, group: Group) {
        self.space = space
        self.group = group
        super.init(nibName: nil, bundle: nil)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "members".localizedString
        view.backgroundColor = Background_Color
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "save".localizedString, color: RGB(0, 0, 0, 0.85), font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(saveAction))
        
        setupUI()
        functionView.setDeviceFilterEnabled(true)
        deviceNameFilterObservation = deviceNameFilterSession.observe { [weak self] _ in
            self?.applyDeviceNameFilter()
        }
        
        if isAddDevices {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
            functionView.setSyncButtonHidden(true)
            navigationItem.rightBarButtonItem?.title = "done".localizedString
            if space.isConfiguring {
                title = group.name
            }
        }
        
        // mesh网络连接观察者
        meshNetworkConnectedObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if MeshLibManager.manager.isMeshNetworkConnected {
                    let inGroupNodes = self.nodes.filter({ $0.group?.address.address == self.group.address.address })
                    self.selectNodes.append(contentsOf: inGroupNodes.filter({ !self.selectNodes.contains($0) }))
            //        nodes.filter({ $0.group?.address.address == group.address.address })
                    self.collectionView.reloadData()
                    self.updateFunctionView()
                    
                }else {
                    self.functionView.selectAllBtn.isEnabled = false
                    self.functionView.sortBtn.isEnabled = false
                }
            }
        })
        
//        nodes = space.nodes.filter({ $0.group == nil || $0.group?.address.address == group.address.address })
//        selectNodes = nodes.filter({ $0.group?.address.address == group.address.address })
        
//        selectNodes = nodes.filter({ $0.group?.address.address == group.address.address })
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        if space.nodes.filter({ $0.group == nil || $0.group?.address.address == group.address.address }).count != nodes.count || group.nodes.count != selectNodes.count {
        nodes = MeshNetworkManager.instance.realNodes.filter({ isVisibleGroupMemberNode($0) && ($0.group == nil || $0.group?.address.address == group.address.address) })
        selectNodes.removeAll()
        nodes.forEach { node in
            if node.group != nil {
                if !selectNodes.contains(node) {
                    selectNodes.append(node)
                }
            }else {
                if let index = selectNodes.firstIndex(of: node) {
                    selectNodes.remove(at: index)
                }
            }
        }
//        selectNodes.append(contentsOf: nodes.filter({ $0.group?.address.address == group.address.address }).filter({ !selectNodes.contains($0) && $0.group?.address.address == group.address.address }))
//        }
//        DispatchQueue.global().async {
//            let isSync = self.group.needSync
//            DispatchQueue.main.async {
                self.functionView.setSyncButtonHidden(self.isAddDevices || !self.group.needSync)
//            }
//        }
        MeshLibManager.manager.messageDelegate = self
        
//        if collectionView.frame != .zero {
            applyDeviceNameFilter()
//        }
        
        updateFunctionView()
    }

    private func isVisibleGroupMemberNode(_ node: Node) -> Bool {
        return node.deviceType == .light
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isAddDevices {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
 
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
//        updateEmptyUI()
    }
    
    deinit {
        if !configurationCreateScene { // 退出配置流程关闭配置中状态
            if space.isConfiguring {
                space.isConfiguring = false
            }
        }
        
        meshNetworkConnectedObservation = nil
        if let deviceNameFilterObservation {
            deviceNameFilterSession.removeObserver(deviceNameFilterObservation)
        }
    }
    
    
    @objc private func backAction() {
        if parent != nil && isAddDevices {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func saveAction() {
        
        if selectNodes.isEmpty && nodes.isEmpty {
            backAction()
            return
        }
        let exitNodes = group.nodes.filter({ !selectNodes.contains($0) })
        let addNodes = selectNodes.filter({ !group.nodes.contains($0) })
        guard exitNodes.count > 0 || addNodes.count > 0 else {
            backAction()
            return
        }
        guard let proxyRemovalPlans = groupMemberProxyRemovalPlans(for: exitNodes) else {
            return
        }
        let continueSave = { [weak self] in
            self?.performSave(
                exitNodes: exitNodes,
                addNodes: addNodes,
                proxyRemovalPlans: proxyRemovalPlans
            )
        }
        guard !proxyRemovalPlans.isEmpty else {
            continueSave()
            return
        }

        SRAlertView(
            message: "group_remove_switch_proxy_confirmation".localizedString,
            actions: [
                .cancelAction,
                SRAlertAction(
                    title: "alert_item_continue".localizedString,
                    actionHandler: { _ in continueSave() }
                )
            ]
        ).show()
    }

    private func groupMemberProxyRemovalPlans(
        for exitNodes: [Node]
    ) -> [GroupMemberProxyRemovalPlan]? {
        let groupAddress = group.address.address
        let switches = MeshNetworkManager.instance.switchs.filter {
            $0.bindGroupAddresses.contains(groupAddress)
                || $0.unbindGroupAddresses.contains(groupAddress)
        }
        var plans: [GroupMemberProxyRemovalPlan] = []

        for node in exitNodes {
            for switchData in switches {
                let decision = KineticSwitchBindingPolicy.groupMemberRemovalDecision(
                    node: node.primaryUnicastAddress,
                    current: switchData.proxyNodeAddress,
                    pendingRemoval: switchData.deleteProxyNodeAddress
                )
                switch decision {
                case .unaffected:
                    continue
                case .rejectPendingRemovalConflict:
                    XWHUDManager.showTipHUD(
                        "switch_proxy_notcleared_message".localizedString,
                        isLineFeed: true,
                        afterDelay: 2
                    )
                    return nil
                case .markPendingRemoval, .reusePendingRemoval:
                    plans.append(
                        GroupMemberProxyRemovalPlan(
                            node: node,
                            switchData: switchData,
                            decision: decision
                        )
                    )
                }
            }
        }
        return plans
    }

    private func performSave(
        exitNodes: [Node],
        addNodes: [Node],
        proxyRemovalPlans: [GroupMemberProxyRemovalPlan]
    ) {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        DispatchQueue.global().async {
            let pendingRemovalSnapshots = proxyRemovalPlans.map {
                ($0.switchData, $0.switchData.deleteProxyNodeAddress)
            }
            for plan in proxyRemovalPlans where plan.decision == .markPendingRemoval {
                plan.switchData.deleteProxyNodeAddress = plan.node.primaryUnicastAddress
                guard plan.switchData.save() else {
                    pendingRemovalSnapshots.forEach { switchData, pendingRemoval in
                        switchData.deleteProxyNodeAddress = pendingRemoval
                        switchData.save()
                    }
                    DispatchQueue.main.async {
                        XWHUDManager.hide()
                        XWHUDManager.showErrorTipHUD("save_failure".localizedString)
                    }
                    return
                }
            }
            exitNodes.forEach({ node in
                node.groupState = .exitFailure
                node.preConfiguration.dayProfileStartsAboveLux = nil
                node.preConfiguration.nightProfileStartsBelowLux = nil
                node.preConfiguration.dayProfileLightData = nil
                node.preConfiguration.nightProfileLightData = nil
                if node.sensorCalibrationData?.isCalibration ?? false { // 退出组清空校准数据
                    node.preConfiguration.resetDaylightCalibration = true
                }
                if let meshUUD = node.network?.uuid.uuidString {
                    node.preConfiguration.save(meshUUID: meshUUD, nodeAddress: node.primaryUnicastAddress)
                }
                node.clearSyncStateCache()
            })
            // 退出组的设备，整理邻近照明路径关系
            if exitNodes.count > 0, self.group.info.profile.type == .proximityLighting || self.group.info.profile.type == .proximityLightingWithPhotocell, let path = self.group.info.proximityLightingPath {
    //            let proximityNodes = path.nodes
                exitNodes.forEach { node in
                    path.removeNode(node)
                }
                self.group.info.save()
                self.group.updateGroupSyncState()
            }
            
            addNodes.forEach({
                $0.groupState = .inGroup
                if self.group.info.profile.type == .proximityLightingWithPhotocell {
                    // 使用最新的profile功能需要绑定对应model
                    if !$0.requiredFunctionTypes.contains(.lightLCScene) {
                        $0.requiredFunctionTypes.append(.lightLCScene)
                    }
                }
            })
            
            DispatchQueue.main.async {
                XWHUDManager.hide()
                guard MeshLibManager.manager.isMeshNetworkConnected else {
                    XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                    return
                }
                let vc = SyncDevicesViewController(type: .group(self.group, inNodes: addNodes, outNodes: exitNodes))
                vc.syncSuccessCallback = {[weak self] _ in
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    guard let self = self else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                        guard let self = self else { return }
                        NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: self.group)
                        if self.isAddDevices {
                            self.backAction()
                        }else {
                            self.navigationController?.popToViewController(vcClass: GroupViewController.classForCoder(), animated: true)
                        }
                    }
                }
                vc.backActionCallback = {[weak self] _ in
                    guard let self = self else { return }
                    NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: self.group)
                    self.navigationController?.popToViewController(vcClass: GroupViewController.classForCoder())
                }
                self.navigationController?.pushViewController(vc, animated: true)
            }
           
            
        }
    }
    
    private func updateEmptyUI() {
        if deviceNameFilterSession.isActive, visibleNodes.isEmpty {
            view.hideEmptyDataView()
            collectionView.showEmptyDataView(
                title: "device_filter_no_matching_devices".localizedString,
                position: .center,
                bottomMargin: SCRYFit(50)
            )
            functionView.isHidden = false
        } else if nodes.isEmpty {
            collectionView.hideEmptyDataView()
            
            view.showEmptyDataView(title: "no_devices".localizedString, tipText: "group_not_devices_message".localizedString, buttonText: "group_add_device".localizedString, buttomWidth: SCRXFrom(216), position: .center, bottomMargin: SCRYFit(50)) {[weak self] in
                guard let self = self else { return }
                guard MeshNetworkManager.instance.realNodes.count < self.space.maxDevicesCount else {
                    XWHUDManager.showTipHUD(String(format: "devices_number_exceeds_message".localizedString, self.space.maxDevicesCount), isLineFeed: true)
                    return
                }
                
                let addVc = DeviceAddViewController(space: self.space)
                addVc.appointGroup = self.group
//                addVc.deviceAddCallback = {[weak self] _ in
//                    self?.updateEmptyUI()
//                    self?.collectionView.reloadData()
//                }
                self.navigationController?.pushViewController(addVc, animated: true)
            }
            if let emptyView = view.emptyView {
                emptyView.button.snp.updateConstraints({ make in
                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
//                    make.width.equalTo(SCRXFrom(216))
                })
                
                // 引导配置中
                if isAddDevices && space.isConfiguring {
                    
                    let guidanceBtn = UIButton(title: "configuration_flow_guidance".localizedString, titleSize: 15, titleWeight: .light, titleColor: SubText_Color, normalImageName: "help", target: self, action: #selector(guidanceBtnAction))
                    emptyView.addSubview(guidanceBtn)
                    guidanceBtn.snp.makeConstraints { make in
                        make.centerX.equalToSuperview()
                        make.bottom.equalTo(-kSafeAreaBottomHeight - SCRYFit(10))
                    }
                    
                    let createSceneBtn = UIButton(title: "create_scene".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(createSceneBtnAction))
                    createSceneBtn.backgroundColor = .white
                    createSceneBtn.layer.cornerRadius = SCRYFrom(10)
                    createSceneBtn.layer.borderWidth = 0.6
                    createSceneBtn.layer.borderColor = Bar_Color.cgColor
                    emptyView.addSubview(createSceneBtn)
                    createSceneBtn.snp.makeConstraints { make in
                        make.bottom.equalTo(guidanceBtn.snp.top).offset(SCRYFit(-12))
                        make.centerX.equalToSuperview()
                        make.width.equalTo(SCRXFrom(216))
                        make.height.equalTo(SCRYFrom(44))
                    }
                    
                    let createGroupsBtn = UIButton(title: "create_more_groups".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(createGroupsBtnAction))
                    createGroupsBtn.backgroundColor = .white
                    createGroupsBtn.layer.cornerRadius = SCRYFrom(10)
                    createGroupsBtn.layer.borderWidth = 0.6
                    createGroupsBtn.layer.borderColor = Bar_Color.cgColor
                    emptyView.addSubview(createGroupsBtn)
                    createGroupsBtn.snp.makeConstraints { make in
                        make.centerX.width.height.equalTo(createSceneBtn)
                        make.bottom.equalTo(createSceneBtn.snp.top).offset(SCRYFit(-15))
                    }
                    
                }
                
            }
            
            functionView.isHidden = true
        }else {
            collectionView.hideEmptyDataView()
            view.hideEmptyDataView()
            functionView.isHidden = false
        }
    }

    private func applyDeviceNameFilter() {
        visibleNodes = deviceNameFilterSession.filtered(nodes) { [space] node in
            var names = [node.name ?? ""]
            if space.displayDeviceNamePrefix, let group = node.group {
                names.append(group.name)
            }
            return names
        }
        functionView?.deviceFilterBtn.isSelected = deviceNameFilterSession.isActive
        updateEmptyUI()
        collectionView?.reloadData()
        updateFunctionView()
    }

    private func showDeviceNameFilterMenu() {
        DeviceNameFilterMenuView.show(
            from: functionView.deviceFilterBtn,
            onSearch: { [weak self] in
                guard let self else { return }
                DeviceNameFilterSearchView.show(
                    initialText: self.deviceNameFilterSession.query,
                    onSubmit: { [weak self] text in
                        self?.deviceNameFilterSession.submit(text)
                    }
                )
            },
            onReset: { [weak self] in
                self?.deviceNameFilterSession.reset()
            }
        )
    }
    

    private func setupUI() {
        
        functionView = GroupDevicesFunctionView()
        functionView.delegate = self
        functionView.syncBtn.isHidden = true
        view.addSubview(functionView)
        functionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.itemRowCount = rowNum
//        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(16), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        //        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFit(36), right: SCRXFrom(24))
        collectionView.contentInset = collectionViewInsets
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(DevicesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(functionView.snp.top)
            make.top.equalTo((navigationController?.navigationBar.frame.maxY ?? 0))
        }
    }
    
    // MARK: - Action
    /// 引导帮助
    @objc private func guidanceBtnAction() {
        
        ConfigurationFlowGuidanceView().show()
    }
    /// 创建更多组
    @objc private func createGroupsBtnAction() {
        
//        guard MeshNetworkManager.instance.groups.count < 16 else {
//            XWHUDManager.showTipHUD("groups_overrun_message".localizedString, isLineFeed: true)
//            return
//        }
        
        let vc = GroupAddViewController(space: space)
        space.isConfiguring = true
        vc.addFinishedCallback = {[weak self] newGroup in
            guard let self = self else { return }
            self.group = newGroup
            self.title = newGroup.name
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 创建场景
    @objc private func createSceneBtnAction() {
        
        self.configurationCreateScene = true
        self.dismiss(animated: false)
        space.isConfiguring = true
//        let vc = SpaceNewCreationProcessController(space: space, showCreateScene: true)
        let vc = SceneAddViewController(space: space)
//        UIViewController.getVisibleVc()?.presentingViewController?.present(NavigationViewController(rootViewController: vc), animated: true)
        NotificationCenter.default.post(name: .init(spaceModalViewControllerNotificaitonName), object: NavigationViewController(rootViewController: vc))
        
        NotificationCenter.default.post(name: .init(spaceMenuIndexChangeNotificaitonName), object: 2)
    }
    
    /// 检查设备
    private func checkDevices() {
        
        let vc = GroupCheckViewController(group: self.group, nodes: [])
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func updateFunctionView() {
        
        let canEditDevices = visibleNodes.filter({ $0.state || $0.group?.address == self.group.address })
        let selectedVisibleCount = canEditDevices.filter({ selectNodes.contains($0) }).count
        
        functionView.selectAllBtn.isSelected = canEditDevices.count > 0 && selectedVisibleCount == canEditDevices.count
        if MeshLibManager.manager.isMeshNetworkConnected {
            functionView.selectAllBtn.isEnabled = true
            functionView.sortBtn.isEnabled = true
        }else {
            functionView.selectAllBtn.isEnabled = false
            functionView.sortBtn.isEnabled = false
        }
    }
    
    private func reloadCollectionItem(node: Node) {
        
        if let index = visibleNodes.firstIndex(where: {$0.primaryUnicastAddress == node.primaryUnicastAddress}) {
            //            CATransaction.setDisableActions(true)
            //            collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
//            if !node.state { // 离线
//                if selectNodes.contains(node) { // 是否编辑选中
//                    // 离线时清空选中地址数据
//                    selectNodes.removeAll(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress })
//                }
//            }
            
            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? DevicesViewCell {
                item.device = node
                item.displayDeviceNamePrefix = space.displayDeviceNamePrefix
//                if node.state && node.isKeybindComplete {
//                    item.selectImageView.isHidden = false
//                }else {
//                    item.selectImageView.isHidden = true
//                }
                if selectNodes.contains(node) {
                    item.selectImageView.isHidden = false
                    if node.state && node.isKeybindComplete {
                        item.selectImageView.image = UIImage(named: "device_select")
                    }else {
                        item.selectImageView.image = UIImage(named: "device_select_disable")
                    }
                }else {
                    item.selectImageView.isHidden = !(node.state && node.isKeybindComplete)
                    item.selectImageView.image = UIImage(named: "device_select_un")
                }
//                item.selectImageView.image = selectNodes.contains(node) ? UIImage(named: "device_select") : UIImage(named: "device_select_un")
                if node.state && node.isKeybindComplete && node.needSyncGroupData {
                    item.iconImageView.image = UIImage(named: node.unsyncIconName)
                }
            }
            updateFunctionView()
        }
    }
    
    /// 开始修复节点
    private func repair(node: Node) {
        
        XWHUDManager.showCustomHUD(withMessage: "repairing".localizedString, isWindow: true)
        MeshAPI.startKeyBind(node: node, startKeyBind: nil) {[weak self] node in
            XWHUDManager.hide()
            guard let self = self else { return }
            if node.isKeybindComplete {
                if MeshLibManager.manager.bluetoothState == .poweredOn {
                    XWHUDManager.showSuccessTipHUD("complete!".localizedString)
                }
//                if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
//                    node.saveNodeInfo(meshUUID: uuid, networkKey: MeshNetworkManager.instance.currentNetworkKey)
//                }
                if node.group?.address.address == group.address.address, !selectNodes.contains(node) {
                    selectNodes.append(node)
                }
                if let index = self.visibleNodes.firstIndex(of: node), let cell = collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? DevicesViewCell {
                    cell.device = node
                    cell.displayDeviceNamePrefix = space.displayDeviceNamePrefix
                    cell.selectImageView.isHidden = false
                    cell.selectImageView.image = selectNodes.contains(node) ? UIImage(named: "device_select") : UIImage(named: "device_select_un")
                }
            }else {
                self.repairFailed(node: node)
            }
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//                MeshAPI.getNodeCTLState(address: node.primaryUnicastAddress)
        } keyBindFail: {[weak self] _ in
            XWHUDManager.hide()
            self?.repairFailed(node: node)
        }
        
    }
    
    /// 修复失败
    private func repairFailed(node: Node) {
        
        let alertView = SRAlertView(message: "repair_failed_message".localizedString, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "alert_failed"), actions: [.cancelAction, SRAlertAction(title: "repair".localizedString, style: .default, actionHandler: {[weak self] _ in
            self?.repair(node: node)
        })])
        alertView.stateImageView.snp.remakeConstraints { make in
            make.top.equalTo(SCRYFrom(24))
            make.centerX.equalToSuperview()
        }
        alertView.messageLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(27))
            make.right.equalTo(SCRXFrom(-27))
            make.top.equalTo(alertView.stateImageView.snp.bottom).offset(SCRYFrom(16))
        }
        alertView.hLineView.snp.remakeConstraints { make in
            make.left.right.equalTo(0)
            make.height.equalTo(0.5)
            make.top.equalTo(alertView.messageLabel.snp.bottom).offset(SCRYFrom(16))
        }
        alertView.show()
    }
    
    /// collectionview长按事件（跳转到设备控制页面）
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point) {
            let node = visibleNodes[indexPath.item]
            let deviceVc = DeviceLightViewController(space: space, node: node)
            navigationController?.pushViewController(deviceVc, animated: true)
        }
    }
    
}

extension GroupMembersViewController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if view.window != nil, nodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) {
            reloadCollectionItem(node: node)
        }
    }
    
    /// 设备数据修改时间戳更新
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdateTimeChange node: Node, lastUpdate: Int64) {
//        if node.lastUpdateSyncTime != lastUpdate {
            node.clearSyncStateCache()
//        }
    }
    
}

extension GroupMembersViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return visibleNodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DevicesViewCell
        let node = visibleNodes[indexPath.item]
        cell.device = node
        cell.displayDeviceNamePrefix = space.displayDeviceNamePrefix
//        if node.state && node.isKeybindComplete {
//            cell.selectImageView.isHidden = false
//        }else {
//            cell.selectImageView.isHidden = true
//        }
//        device_select_disable
        if selectNodes.contains(node) {
            cell.selectImageView.isHidden = false
            if node.state && node.isKeybindComplete {
                cell.selectImageView.image = UIImage(named: "device_select")
            }else {
                cell.selectImageView.image = UIImage(named: "device_select_disable")
            }
        }else {
            cell.selectImageView.isHidden = !(node.state && node.isKeybindComplete)
            cell.selectImageView.image = UIImage(named: "device_select_un")
        }
        
//        cell.selectImageView.image = selectNodes.contains(node) ? UIImage(named: "device_select") : UIImage(named: "device_select_un")
        
        if node.state && node.isKeybindComplete && node.needSyncGroupData {
            cell.iconImageView.image = UIImage(named: node.unsyncIconName)
        }
        cell.editClickCallback = {[weak self] node in
            guard let self = self else { return }
            guard node.state && node.isKeybindComplete else {
                return
            }
            if self.selectNodes.contains(node) {
                self.selectNodes.removeAll(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress })
                cell.selectImageView.image = UIImage(named: "device_select_un")
            }else {
                self.selectNodes.append(node)
                cell.selectImageView.image = UIImage(named: "device_select")
            }
            self.updateFunctionView()
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * CGFloat(rowNum - 1) - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(rowNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let node = visibleNodes[indexPath.item]
        guard !node.isEmergencySignController else {
            return
        }
        if !node.isKeybindComplete {
            repair(node: node)
            return
        }
        if !node.state {
            MeshAPI.getNodeOnOffState(address: node.primaryUnicastAddress)
            return
        }
        
        node.isOn = !node.isOn
        if !node.isOn, node.lightness > 0 { // 关灯，记录关灯前的亮度值
            node.trunOffLightness = node.lightness
        }
        MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn, ack: true)
        reloadCollectionItem(node: node)
    }
    
}

extension GroupMembersViewController: GroupDevicesFunctionViewDelegate {
    
    /// 点击同步数据回调
    func functionDidSyncDataAction(view: GroupDevicesFunctionView) {
//        showFailedAlert()
        
        let vc = SyncDevicesViewController(type: .group(group), reSync: true)
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                guard let self = self else { return }
                NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: self.group)
                self.navigationController?.popViewController(animated: true)
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    func functionDidFilterDevicesAction(view: GroupDevicesFunctionView) {
        showDeviceNameFilterMenu()
    }
    
    /// 点击检查回调
//    func functionDidCheckAction(view: GroupDevicesFunctionView) {
//        checkDevices()
//    }
    
    /// 点击排序回调
    func functionDidSortAction(view: GroupDevicesFunctionView) {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5) {[weak self] nodes in
            XWHUDManager.hide()
            guard let self = self else { return }
//            print("\() \()")
//            nodes.forEach({ print("\(String(describing: $0.name)) \($0.rssi)") })
            if nodes.isEmpty { // 未到节点信号
                XWHUDManager.showErrorTipHUD("device_sort_failed".localizedString)
                return
            }
            self.nodes.sort(by: { ($0.rssi ?? -99) > ($1.rssi ?? -99) })
            self.nodes.sort(by: { $0.state && !$1.state })
            self.applyDeviceNameFilter()
//            // 设备信号排序
//            self.space.deviceSortType = .rssi
//            self.space.save()
//            LCPlistCacheTool.write(fileName: self.rssiFileName, value: rssiMap)
        }
    }
    
    /// 全选点击回调  selectAll：是否全选
    func function(view: GroupDevicesFunctionView, selectAllStateChanged selectAll: Bool) {
        let canEditDevices = visibleNodes.filter({ $0.state && $0.isKeybindComplete })
        if selectAll {
            selectNodes.append(contentsOf: canEditDevices.filter({ !selectNodes.contains($0) }))
//            selectNodes = canEditDevices
        }else {
            selectNodes.removeAll(where: { canEditDevices.contains($0) })
//            selectNodes.removeAll()
        }
        collectionView.reloadData()
        updateFunctionView()
    }

    
}
