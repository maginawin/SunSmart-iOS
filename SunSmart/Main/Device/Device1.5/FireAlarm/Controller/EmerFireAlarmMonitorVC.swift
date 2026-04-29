//
//  EmerFireAlarmMonitorVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

//应急火警设备监控页
import UIKit
import NordicSigMeshSDK

class EmerFireAlarmMonitorVC: UIViewController {
    private let space: SpaceData?
    private var currentConfig: LinkedEmerFireConfig?
    private var currentDevice: DeviceEmerFireData?
    
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var deviceCountLabel: UILabel!
    private var pageControl: UIPageControl!
    /// 列数
    private var columnNum: Int = isIPad ? 4 : 3
    private var rowNum: Int = isIPad ? 6 : 3
    
    /// collectionview边距
    private var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: SCRYFrom(44), left: SCRXFrom(40), bottom: SCRYFrom(44), right: SCRXFrom(40)) : UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFrom(36), right: SCRXFrom(24))
    
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(14)
    //操作按钮
    
    private var groups: [String] = []
    
    private lazy var moniView: EmerFireAlarmMoniView = {
        let view = EmerFireAlarmMoniView()
        return view
    }()

    private lazy var statusSetView: EmerFireAlarmStatusSetView = {
        let view = EmerFireAlarmStatusSetView()
        view.title = "Status Set".localizedString
        return view
    }()
    lazy var statusWarningView : EmerFireAlarmMoniHead = {
        var view = EmerFireAlarmMoniHead()
        view.frame = CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: SCRYFit(45))
        return view
    }()

    init(space: SpaceData? = nil, device: DeviceEmerFireData? = nil, config: LinkedEmerFireConfig? = nil) {
        self.space = space
        self.currentDevice = device
        currentConfig = config
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
        setTestData()
        applySavedConfig()
        NotificationCenter.default.addObserver(self, selector: #selector(handleConfigDidChange(_:)), name: .linkedEmerFireConfigDidChange, object: nil)
        
        statusWarningView.warningAction = {
            //Owner和Editor权限
            SRAlertView(title: "Warning".localizedString,message: "Emergency information was not reported to the gateway. If a gateway is in use, it must be properly configured to prevent security risks arising from devices being controlled through the gateway in an emergency.".localizedString, actions: [.cancelAction, SRAlertAction(title: "Go Setting".localizedString,actionHandler: { _ in
                XWHUDManager.showTipHUD("setting", isLineFeed: true)
            })
            ]).show()
            //visitor
//            SRAlertView(title: "Warning",message: "Emergency information was not reported to the gateway. If a gateway is in use, it must be properly configured to prevent security risks arising from devices being controlled through the gateway in an emergency.", actions: [.cancelAction,]).show()
            
            
        }
        
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func groupPreviousSwipeAction() {
        XWHUDManager.showTipHUD("dev1", isLineFeed: true)
    }
    
    @objc private func groupNextSwipeAction() {
        
    }
    
    @objc private func close() {

        self.dismissLikeSystem()
        
    }
    
    func setTestData(){
        moniView.configure(actions: [
            .init(
                image: UIImage(named: "Identify"),
                borderColor: nil,
                action: {
                    XWHUDManager.showTipHUD("Manual emergency", isLineFeed: false)
                }
            ),
            .init(
                image: UIImage(named: "Logout-2 Streamline Sharp1"),
                borderColor: nil,
                action: {
                    XWHUDManager.showTipHUD("Previous action", isLineFeed: false)
                }
            ),
            .init(
                image: UIImage(named: "Logout-2 Streamline Sharp"),
                borderColor: nil,
                action: {
                    XWHUDManager.showTipHUD("Next action", isLineFeed: false)
                }
            )
        ])
        statusSetView.headerActionHandler = { action in
            let message: String
            switch action {
            case .alert:
                message = "Alert action"
            case .statusGray:
                message = "Gray status action"
            case .fire:
                message = "Fire action"
            case .statusGreen:
                message = "Green status action"
            }
            XWHUDManager.showTipHUD(message, isLineFeed: false)
        }
        updateEmptyUI()
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
        view.addSubview(moniView)
        moniView.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(SCRYFrom(100))
            make.left.equalToSuperview().offset(SCRYFrom(56))
            make.right.equalToSuperview().offset(-SCRYFrom(56))
        }
        view.addSubview(statusSetView)
        statusSetView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }
        
    }
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: self.collectionView.contentOffset.y), animated: true)
    }
    
    @objc private func moreClick() {
        let config = currentConfig ?? currentDevice.map(makeConfig(from:))
        var items: [MenuPopView.MenuItem] = []
        if space?.deviceOperates.contains(.edit) ?? false {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] _ in
                guard let self else { return }
                let controller = LinkedEmerFireEditVC(config: config, isLinkedToRealDevice: self.currentDevice?.bindNode != nil, space: self.space)
                controller.editable = true
                let navigationController = NavigationViewController(rootViewController: controller)
                self.present(navigationController, animated: true)
            }))
        }
        if space?.deviceOperates.contains(.delete) ?? false {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] _ in
                self?.deleteDevice()
            }))
        }

        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: {[weak self] _ in
            let controller = EmerFireAlarmInformationVC(device: self?.currentDevice, config: config)
            let navigationController = NavigationViewController(rootViewController: controller)
            self?.present(navigationController, animated: true)
        }))

        items.append(.init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: {[weak self] _ in
            self?.refresh()
        }))
        
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10

        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
       
    }

    private func deleteDevice() {
        guard let currentDevice else { return }
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, actionHandler: { [weak self] _ in
            DeviceEmerFireStore.shared.delete(currentDevice)
            self?.closeOrBack()
        })]).show()
    }

    private func refresh() {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 1.0)
        reloadCurrentDevice()
        if currentConfig == nil, let currentDevice {
            currentConfig = makeConfig(from: currentDevice)
        }
        applySavedConfig()
    }

    private func updateEmptyUI() {
        if groups.isEmpty {
            deviceCountLabel.isHidden = true
            if collectionView.frame == .zero {
                view.layoutIfNeeded()
            }
            if collectionView.emptyView == nil {
                collectionView.showEmptyDataView(title: "Not associate with Group(s) !".localizedString, buttonText: "Setting".localizedString, position: .center) {
                    //
                    XWHUDManager.showTipHUD("Setting", isLineFeed: false)
                }
                if let emptyView = collectionView.emptyView {
                    
                        emptyView.button.backgroundColor = .clear
                        emptyView.button.titleLabel?.font = FONTS(16)
                        emptyView.button.setTitleColor(Bar_Color, for: .normal)
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(24))
                        }
                    
                      //  emptyView.button.isHidden = true
                    
                }
            }
        }else {
            deviceCountLabel.isHidden = false
            collectionView.hideEmptyDataView()
        }
    }

    @objc private func handleConfigDidChange(_ notification: Notification) {
        if let config = notification.object as? LinkedEmerFireConfig {
            currentConfig = config
        }
        reloadCurrentDevice()
        applySavedConfig()
    }

    private func applySavedConfig() {
        if currentConfig == nil, let currentDevice {
            currentConfig = makeConfig(from: currentDevice)
        }
        guard let config = currentConfig else {
            title = "EFC 1"
            groups = []
            deviceCountLabel.text = "(0)"
            collectionView?.reloadData()
            updateEmptyUI()
            return
        }

        title = config.deviceName
        groups = makeDisplayGroups(from: config)
        deviceCountLabel.text = "(\(groups.count))"
        collectionView?.reloadData()
        updateMonitorState()
    }

    private func reloadCurrentDevice() {
        guard let config = currentConfig,
              let deviceId = config.deviceId,
              let meshUUID = config.meshUUID,
              let meshNetworkId = config.meshNetworkId else {
            return
        }
        currentDevice = DeviceEmerFireStore.shared.device(id: deviceId, meshUUID: meshUUID, meshNetworkId: meshNetworkId)
    }

    private func updateMonitorState() {
        guard let currentDevice else {
            updateEmptyUI()
            return
        }

        switch currentDevice.displayStatus {
        case .offlineBoundDevice:
            setContentHidden(true)
            view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
        case .repairRequiredDevice:
            setContentHidden(true)
            view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) { [weak self] in
                self?.repairBtnClick()
            }
            if let emptyView = view.emptyView {
                if space?.deviceOperates.contains(.edit) ?? false {
                    emptyView.button.snp.updateConstraints { make in
                        make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                    }
                } else {
                    emptyView.button.isHidden = true
                }
            }
        default:
            view.hideEmptyDataView()
            setContentHidden(false)
            updateEmptyUI()
        }
    }

    private func setContentHidden(_ hidden: Bool) {
        collectionView?.isHidden = hidden
        pageControl?.isHidden = hidden
        deviceCountLabel?.isHidden = hidden || groups.isEmpty
        moniView.isHidden = hidden
        statusSetView.isHidden = hidden
        statusWarningView.isHidden = hidden
    }

    private func repairBtnClick() {
        guard !(XWHUDManager.currentHUD()?.isHidden == false) else {
            return
        }
        XWHUDManager.showCustomHUD(withMessage: "repairing".localizedString, view: view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            XWHUDManager.hideInView(with: self.view)
            XWHUDManager.showSuccessTipHUD("complete!".localizedString)
        }
    }

    private func closeOrBack() {
        if presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func makeDisplayGroups(from config: LinkedEmerFireConfig) -> [String] {
        var displayGroups: [String] = []
        let addresses = (config.powerLossGroupAddresses + config.fireAlarmGroupAddresses).sorted()

        addresses.forEach { address in
            guard let name = MeshNetworkManager.instance.groups.first(where: { $0.address.address == address })?.name else {
                return
            }
            if !displayGroups.contains(name) {
                displayGroups.append(name)
            }
        }

        return displayGroups
    }

    private func makeConfig(from device: DeviceEmerFireData) -> LinkedEmerFireConfig {
        LinkedEmerFireConfig(
            deviceId: device.id,
            spaceId: device.spaceId,
            meshUUID: device.meshUUID,
            meshNetworkId: device.meshNetworkId,
            deviceName: device.name,
            isSynced: device.isSynced,
            reportToGateway: device.reportToGateway,
            enablePowerLossEmergency: device.enablePowerLossEmergency,
            enableFireAlarmEmergency: device.enableFireAlarmEmergency,
            powerLossGroupIndex: device.powerLossGroupIndex,
            fireAlarmGroupIndex: device.fireAlarmGroupIndex,
            powerLossGroupAddresses: device.powerLossGroupAddresses,
            fireAlarmGroupAddresses: device.fireAlarmGroupAddresses,
            powerLossBrightness: device.powerLossBrightness,
            powerLossResuming: device.powerLossResuming,
            powerLossSendCount: device.powerLossSendCount,
            fireAlarmBrightness: device.fireAlarmBrightness,
            fireAlarmResuming: device.fireAlarmResuming,
            fireAlarmSendCount: device.fireAlarmSendCount
        )
    }
    
    /// 长按事件，跳转到组详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point) {
            XWHUDManager.showTipHUD("\(indexPath.row)", isLineFeed: true)
        }
    }
    
}


extension EmerFireAlarmMonitorVC: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return groups.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! EmerFireAlarmMoniCell
        cell.configure(title: groups[indexPath.row])
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        
    }
    

}
