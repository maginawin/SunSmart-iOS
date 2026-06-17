//
//  EmerFireAlarmMonitorVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

//应急火警设备监控页
import UIKit
import NordicSigMeshSDK
import SnapKit

class EmerFireAlarmMonitorVC: UIViewController, DeviceProtocol {

    let viewModel: EmerFireAlarmMonitorViewModel
    var lastMessageDelegate: MeshLibManagerMessageDelegate?
    var sceneEventObserver: NSObjectProtocol?
    var space: SpaceData? { viewModel.space }
    var currentConfig: LinkedEmerFireConfig? {
        get { viewModel.currentConfig }
        set { viewModel.currentConfig = newValue }
    }
    var currentDevice: DeviceEmerFireData? {
        get { viewModel.currentDevice }
        set { viewModel.currentDevice = newValue }
    }
    var requestGeneration: Int {
        get { viewModel.requestGeneration }
        set { viewModel.requestGeneration = newValue }
    }
    var currentState: EmerFireAlarmMonitorDisplayState {
        get { viewModel.currentState }
        set { viewModel.currentState = newValue }
    }
    let resumeTransitionCoordinator = EmerFireAlarmResumeTransitionCoordinator()
    
    var collectionView: UICollectionView!
    var flowLayout: AlignCenterFlowLayout!
    var deviceCountLabel: UILabel!
    var pageControl: UIPageControl!
    private var statusSetViewHeightConstraint: Constraint?
    /// 列数
    var columnNum: Int = isIPad ? 4 : 3
    var rowNum: Int = isIPad ? 6 : 3
    
    /// collectionview边距
    var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: SCRYFrom(44), left: SCRXFrom(40), bottom: SCRYFrom(44), right: SCRXFrom(40)) : UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFrom(36), right: SCRXFrom(24))
    
    /// item间距
    var itemMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(14)
    //操作按钮
    
    var groups: [EmerFireAlarmAssociatedGroupItem] = []
    
    lazy var moniView: EmerFireAlarmMoniView = {
        let view = EmerFireAlarmMoniView()
        return view
    }()

    lazy var statusSetView: EmerFireAlarmStatusSetView = {
        let view = EmerFireAlarmStatusSetView()
        view.title = "Status Set".localizedString
        view.expandedOverlayHeightProvider = { [weak self, weak view] in
            guard let self else { return view?.collapsedHeight ?? 0 }
            return self.view.bounds.height - self.view.safeAreaInsets.top
        }
        view.heightChangeHandler = { [weak self] height in
            self?.statusSetViewHeightConstraint?.update(offset: height)
        }
        view.expansionChangedHandler = { [weak self] expanded in
            self?.isModalInPresentation = expanded
        }
        return view
    }()
    lazy var statusWarningView : EmerFireAlarmMoniHead = {
        var view = EmerFireAlarmMoniHead()
        view.frame = CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: SCRYFit(45))
        return view
    }()

    init(space: SpaceData? = nil, device: DeviceEmerFireData, config: LinkedEmerFireConfig? = nil) {
        viewModel = EmerFireAlarmMonitorViewModel(space: space, device: device, config: config)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = currentDevice?.name ?? currentConfig?.deviceName ?? "EFC 1"
        
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
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        
        setupUI()
        configureActions()
        applySavedConfig()
        observeSceneEvents()
        refreshRealState()
        NotificationCenter.default.addObserver(self, selector: #selector(handleConfigDidChange(_:)), name: .linkedEmerFireConfigDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceStateDidUpdate(_:)), name: .init(deviceStateUpdateNotificationName), object: nil)
        
        statusWarningView.warningAction = { [weak self] in
            guard self?.shouldShowGatewayWarning == true else {
                return
            }
            //Owner和Editor权限
            SRAlertView(title: "Warning".localizedString,message: "Emergency information was not reported to the gateway. If a gateway is in use, it must be properly configured to prevent security risks arising from devices being controlled through the gateway in an emergency.".localizedString, actions: [.cancelAction, SRAlertAction(title: "Go Setting".localizedString,actionHandler: { _ in
                XWHUDManager.showTipHUD("setting", isLineFeed: true)
            })
            ]).show()
            //visitor
//            SRAlertView(title: "Warning",message: "Emergency information was not reported to the gateway. If a gateway is in use, it must be properly configured to prevent security risks arising from devices being controlled through the gateway in an emergency.", actions: [.cancelAction,]).show()
            
            
        }
        
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateEmptyViewLayout()
    }

    deinit {
        resumeTransitionCoordinator.cancel()
        if let sceneEventObserver {
            NotificationCenter.default.removeObserver(sceneEventObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lastMessageDelegate = MeshLibManager.manager.messageDelegate
        MeshLibManager.manager.messageDelegate = self
        refreshRealState()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        resumeTransitionCoordinator.cancel()
        requestGeneration += 1
        MeshLibManager.manager.messageDelegate = lastMessageDelegate
        if let node = currentDevice?.bindNode {
            NotificationCenter.default.post(name: .init(deviceStateUpdateNotificationName), object: node)
        }
    }
    
    @objc private func groupPreviousSwipeAction() {
    }
    
    @objc private func groupNextSwipeAction() {
        
    }
    
    @objc private func close() {

        self.dismissLikeSystem()
        
    }

    @objc private func handleDeviceStateDidUpdate(_ notification: Notification) {
        guard let node = notification.object as? Node else {
            return
        }
        renderNodeAvailabilityChange(node)
    }
    
    func configureActions() {
        let actions: [EmerFireAlarmMoniView.ActionItem] = [
            .init(
                image: UIImage(named: EmergencyFireControllerIconName.Monitor.Action.identify),
                borderColor: nil,
                action: { [weak self] in
                    self?.identifyAction() ?? false
                }
            ),
            .init(
                image: UIImage(named: EmergencyFireControllerIconName.Monitor.Action.mockFireAlarm),
                borderColor: nil,
                action: { [weak self] in
                    self?.mockFireAlarmAction() ?? false
                }
            ),
            .init(
                image: UIImage(named: EmergencyFireControllerIconName.Monitor.Action.mockPowerLoss),
                borderColor: nil,
                action: { [weak self] in
                    self?.mockPowerLossAction() ?? false
                }
            ),
            .init(
                image: UIImage(named: EmergencyFireControllerIconName.Monitor.Action.mockRestore),
                borderColor: nil,
                action: { [weak self] in
                    self?.mockRestoreAction() ?? false
                }
            )
        ]
        moniView.configure(actions: actions)
        statusSetView.headerActionHandler = { [weak self] action in
            guard let self else { return }
            switch action {
            case .powerLossTrigger:
                self.recallEmergencyScene(DeviceEmerFireData.powerLossTriggerSceneNumber)
            case .powerLossStatus:
                self.lightLCOnAction()
            case .fireTrigger:
                self.recallEmergencyScene(DeviceEmerFireData.fireAlarmTriggerSceneNumber)
            case .fireStatus:
                self.lightLCOnAction()
            }
        }
        updateEmptyUI()
    }

    var canOperateEmergencyActions: Bool {
        viewModel.canOperateEmergencyActions
    }

    var canConfigureDevice: Bool {
        viewModel.canConfigureDevice
    }

    func guardLinkedDeviceForAction() -> Bool {
        guard currentDevice?.bindNode != nil else {
            XWHUDManager.showTipHUD("Not executed. Please link a device first.".localizedString, isLineFeed: true)
            return false
        }
        return true
    }

    var isAllEmergencyFunctionsDisabled: Bool {
        viewModel.isAllEmergencyFunctionsDisabled
    }

    func setupUI(){
        
        view.addSubview(statusWarningView)
        statusWarningView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFit(10))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFit(45))
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
        collectionView.register(EmerFireAlarmMoniCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            if isIPad {
                make.top.equalTo(statusWarningView.snp.bottom).offset(SCRYFit(15))
                make.height.equalTo(SCRYFrom(498))
            }else {
                make.top.equalTo(statusWarningView.snp.bottom).offset(SCRYFit(12))
                make.height.equalTo(SCRYFrom(340))
            }
        }
        
        deviceCountLabel = UILabel(text: "", textColor: Bar_Color, fontSize: 14, fontWeight: .light)
        view.addSubview(deviceCountLabel)
        deviceCountLabel.snp.makeConstraints { make in
            make.left.equalTo(collectionView).offset(SCRXFrom(20))
            make.top.equalTo(collectionView).offset(SCRYFrom(13))
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
        }

        view.addSubview(statusSetView)
        statusSetView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            statusSetViewHeightConstraint = make.height.equalTo(statusSetView.collapsedHeight).constraint
        }

        view.addSubview(moniView)
        moniView.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(SCRYFrom(28))
            make.left.equalToSuperview().offset(SCRYFrom(56))
            make.right.equalToSuperview().offset(-SCRYFrom(56))
            make.bottom.lessThanOrEqualTo(statusSetView.snp.top).offset(-SCRYFit(20)).priority(.low)
        }
        view.bringSubviewToFront(statusSetView)
        
    }

    @discardableResult
    func identifyAction() -> Bool {
        guard guardLinkedDeviceForAction() else {
            return false
        }
        guard let healthModel = currentDevice?.bindNode?.healthModel else {
            XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
            return false
        }
        MeshAPI.sendMessage(message: AttentionSet(attentionTimer: 6), model: healthModel, timeout: 5) { response in
            if response == nil {
                DispatchQueue.main.async {
                    XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
                }
            }
        }
        return true
    }

    @discardableResult
    func triggerAction() -> Bool {
        guard canOperateEmergencyActions else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return false
        }
        guard currentDevice?.bindNode != nil else {
            XWHUDManager.showTipHUD("Not executed. Please link a device first.".localizedString, isLineFeed: true)
            return false
        }
        guard activeAssociatedGroupsContainDevices else {
            XWHUDManager.showTipHUD("Not executed. No devices in associated groups.".localizedString, isLineFeed: true)
            return false
        }
        return recallEmergencyScene(viewModel.activeTriggerSceneNumber())
    }

    @discardableResult
    func stopAction() -> Bool {
        guard canOperateEmergencyActions else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return false
        }
        guard currentDevice?.bindNode != nil else {
            XWHUDManager.showTipHUD("Not executed. Please link a device first.".localizedString, isLineFeed: true)
            return false
        }
        guard activeAssociatedGroupsContainDevices else {
            XWHUDManager.showTipHUD("Not executed. No devices in associated groups.".localizedString, isLineFeed: true)
            return false
        }
        return lightLCOnAction()
    }

    @discardableResult
    func recallEmergencyScene(_ sceneNumber: SceneNumber) -> Bool {
        guard canOperateEmergencyActions else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return false
        }
        guard let publishGroupAddress = publishGroupAddressForAction() else {
            return false
        }
        let message = SceneRecallUnacknowledged(sceneNumber)
        print("[EFC] recall scene=\(String(format: "0x%04X", sceneNumber)), publishGroup=\(String(format: "0x%04X", publishGroupAddress))")
        MeshAPI.sendMessage(message: message, address: publishGroupAddress)
        return true
    }

    @discardableResult
    func mockFireAlarmAction() -> Bool {
        guard guardLinkedDeviceForAction() else {
            return false
        }
        guard guardMockActionHasAssociatedGroup() else {
            return false
        }
        guard let configuration = currentEmergencyConfiguration() else {
            XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
            return false
        }
        return sendBrightness(configuration.fireAlarmSettings.triggerBrightness, logName: "mock fire alarm")
    }

    @discardableResult
    func mockPowerLossAction() -> Bool {
        guard guardLinkedDeviceForAction() else {
            return false
        }
        guard guardMockActionHasAssociatedGroup() else {
            return false
        }
        guard let configuration = currentEmergencyConfiguration() else {
            XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
            return false
        }
        return sendBrightness(configuration.powerLossSettings.triggerBrightness, logName: "mock power loss")
    }

    @discardableResult
    func mockRestoreAction() -> Bool {
        guard guardLinkedDeviceForAction() else {
            return false
        }
        guard guardMockActionHasAssociatedGroup() else {
            return false
        }
        guard let configuration = currentEmergencyConfiguration() else {
            XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
            return false
        }
        switch configuration.restoreSettings.actionType {
        case .restoreAuto:
            return lightLCOnAction(logName: "mock restore auto")
        case .setBrightness:
            return sendBrightness(configuration.restoreSettings.brightness, logName: "mock restore brightness")
        case .none:
            print("[EFC] mock restore none")
            return true
        }
    }

    private func guardMockActionHasAssociatedGroup() -> Bool {
        guard !groups.isEmpty else {
            XWHUDManager.showTipHUD("Not executed. Please link a group first.".localizedString, isLineFeed: true)
            return false
        }
        return true
    }

    @discardableResult
    func lightLCOnAction(logName: String = "light LC ON") -> Bool {
        guard canOperateEmergencyActions else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return false
        }
        guard let publishGroupAddress = publishGroupAddressForAction() else {
            return false
        }
        print("[EFC] \(logName) publishGroup=\(String(format: "0x%04X", publishGroupAddress))")
        MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(true), address: publishGroupAddress)
        return true
    }

    @discardableResult
    private func sendBrightness(_ brightness: Int, logName: String) -> Bool {
        guard canOperateEmergencyActions else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return false
        }
        guard let publishGroupAddress = publishGroupAddressForAction() else {
            return false
        }
        let clampedBrightness = min(max(brightness, 0), 100)
        let lightness = Node.getLightness(lightness100: clampedBrightness)
        print("[EFC] \(logName) brightness=\(clampedBrightness), lightness=\(lightness), publishGroup=\(String(format: "0x%04X", publishGroupAddress))")
        MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), address: publishGroupAddress)
        return true
    }

    private func currentEmergencyConfiguration() -> EmergencyFireControllerConfiguration? {
        currentConfig?.configuration ?? currentDevice?.configuration
    }

    private func publishGroupAddressForAction() -> Address? {
        guard let publishGroupAddress = currentDevice?.publishGroupAddress ?? currentConfig?.publishGroupAddress else {
            XWHUDManager.showTipHUD(EmergencyFireControllerPublishGroupError.missingSceneClientModel.errorDescription ?? "failed".localizedString, isLineFeed: true)
            return nil
        }
        return publishGroupAddress
    }

    var isEmergencySituation: Bool {
        viewModel.isEmergencySituation
    }

    func toggleAssociatedGroup(_ group: Group) {
        guard canOperateEmergencyActions else {
            return
        }
        guard !isEmergencySituation else {
            XWHUDManager.showTipHUD("Uncontrollable in emergency situations".localizedString, isLineFeed: true)
            return
        }
        guard group.nodes.contains(where: { $0.state }) else {
            XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
            return
        }
        group.isOn.toggle()
        group.nodes.forEach { node in
            node.isOn = group.isOn
            if !node.isOn, node.lightness > 0 {
                node.trunOffLightness = node.lightness
                node.lightness = 0
            } else if node.isOn {
                node.lightness = node.trunOffLightness ?? node.lightnessRange.upperBound
            }
        }
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: group.isOn)
        collectionView.reloadData()
    }

    @objc func collectionLongPressAction(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        guard canOperateEmergencyActions else {
            return
        }
        guard !isEmergencySituation else {
            XWHUDManager.showTipHUD("Uncontrollable in emergency situations".localizedString, isLineFeed: true)
            return
        }
        let point = sender.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < groups.count else {
            return
        }
        guard let space else { return }
        let controller = GroupViewController(space: space, group: groups[indexPath.item].group)
        navigationController?.pushViewController(controller, animated: true)
    }
    
}
