//
//  ProfileDayNightLuxDevicesViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/25.
//

import UIKit
import NordicSigMeshSDK

class ProfileDayNightLuxDevicesViewController: UIViewController, KeyboardScrollable {

    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var sortBtn: UIButton!
    
    private var bottomView: DeviceAddBottomView!
    /// lux获取定时器
    private var luxGetTimer: Timer?
    /// 获取lux的设备
    private var luxGetNode: Node?
    /// 获取lux的持续时长
    private var luxGetDuration: TimeInterval = 30
    /// 获取lux的间隔
    private var luxGetInterval: TimeInterval = 1
    /// 选择的设备list
    private var selectDevices: [Node] = []
    
    private var sorting: Bool = false
    private var rssiSortTimer: Timer?
    
    let profile: Profile
    let groupNodes: [Node]
    let setMode: ProfileDayNightLuxSetMode
    private var nodes: [Node] = []
    
    var keyboardScrollView: UIScrollView {
        return collectionView
    }
    
    init(profile: Profile, groupNodes: [Node], setMode: ProfileDayNightLuxSetMode) {
        
        self.profile = profile
        self.groupNodes = groupNodes
        self.setMode = setMode
        super.init(nibName: nil, bundle: nil)
        
        // 已添加到模板的设备
        let templateNodes = profile.lightSensorTemplates.flatMap({ $0.devices })
        nodes = groupNodes.filter({ !templateNodes.contains($0) })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        sortBtn = UIButton(title: "Start".localizedString, titleSize: 14, titleColor: TextBlack_Color, normalImageName: "space_sort", target: self, action: #selector(sortBtnAction))
        sortBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        
        
        setupUI()
//        DispatchQueue.main.async {
//            self.updateEmptyUI()
//        }
//        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        registerForKeyboardNotifications()
        setupData()
        collectionView.reloadData()
        updateBottomViewUI()
        updateEmptyUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if nodes.count > 0 {
            wm_pageController?.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: sortBtn)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        unregisterFromKeyboardNotifications()
        
        wm_pageController?.navigationItem.rightBarButtonItem = nil
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        refreshNodesRSSIFinish()
        stopLuxGetTimer()
    }
    
    private func setupData() {
        // 已添加到模板的设备
        let templateNodes = profile.lightSensorTemplates.flatMap({ $0.devices })
        nodes = groupNodes.filter({ !templateNodes.contains($0) })
        nodes.forEach { node in
            if let nightLux = node.preConfiguration.nightProfileStartsBelowLux ?? profile.nightData?.startsBelowLux {
                node.tempNightLux = Int(nightLux)
            }else {
                node.tempNightLux = nil
            }
            
            if let dayLux = node.preConfiguration.dayProfileStartsAboveLux ?? profile.dayData?.startsBelowLux {
                node.tempDayLux = Int(dayLux)
            }else {
                node.tempDayLux = nil
            }
        }
        selectDevices.removeAll(where: { !nodes.contains($0) })
    }
    
    // MARK: - RSSI
    
    @objc private func sortBtnAction() {
        if sorting {
            refreshNodesRSSIFinish()
        }else {
            startRssiSort()
        }
    }
    
    private func startRssiSort() {
    
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.refreshNodesRSSIFinish), object: nil)
            self.perform(#selector(self.refreshNodesRSSIFinish), with: nil, afterDelay: 10)
        }
        self.sorting = true
        updateSortBtnState()

        nodes.forEach({
            $0.rssi = nil
        })
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.refreshNodesRSSIFinish), object: nil)
            self.perform(#selector(self.refreshNodesRSSIFinish), with: nil, afterDelay: 10)
        }
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 99999, nodeScan: {[weak self] data in
            
            guard let self = self, self.nodes.contains(where: { $0.primaryUnicastAddress == data.node.primaryUnicastAddress }) else { return }
            
            // 查找完所有设备后停止搜索
            if !self.nodes.contains(where: { $0.rssi == nil }) {
                DispatchQueue.main.async {
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.refreshNodesRSSIFinish), object: nil)
                    self.refreshNodesRSSIFinish()
                }
                devicesRssiSort()
            }else {
                if self.rssiSortTimer == nil {
                    self.startRssiSortTimer()
                }
            }
          
            
        }, finished: nil)
        
        
    }
    
    /// 刷新信号结束
    @objc private func refreshNodesRSSIFinish() {
        MeshLibManager.manager.stopRefreshNodesRSSI()
        sorting = false
        updateSortBtnState()
//        scanAnimationView.layer.removeAnimation(forKey: "loading")
//        scanAnimationView.isHidden = true
    }
    
    // MARK: - 信号排序定时器
    private func startRssiSortTimer() {
        
        rssiSortTimer = LCWeakTimer.scheduledTimer(timeInterval: 0.5, aTarget: self, selector: #selector(devicesRssiSort), userInfo: nil, repeats: false)
        RunLoop.current.add(rssiSortTimer!, forMode: .common)
    }
    
    /// 设备信号排序定时刷新，避免接收广播包后刷新频率过高
    @objc private func devicesRssiSort() {
        
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
        
        nodes.sort(by: { ($0.rssi ?? -99) >= ($1.rssi ?? -99) })
        collectionView.reloadData()
        
    }
    
    // MARK: - Action
    
    /// 开启获取lux定时器
    private func startLuxGetTimer() {
        guard let node = luxGetNode, node.ambientLightSensorModel != nil else {
            return
        }
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopLuxGetTimer), object: nil)
            self.perform(#selector(self.stopLuxGetTimer), with: nil, afterDelay: self.luxGetDuration)
        }
        
        luxGetTimer = LCWeakTimer.scheduledTimer(timeInterval: luxGetInterval, aTarget: self, selector: #selector(luxGetTimerEvent), userInfo: nil, repeats: true)
        RunLoop.current.add(luxGetTimer!, forMode: .common)
    }
    
    @objc private func luxGetTimerEvent() {
        
        guard let model = self.luxGetNode?.ambientLightSensorModel else {
            return
        }
        MeshAPI.sendMessage(message: SensorGet(), model: model, timeout: 5) {[weak self] response in
            guard let self = self else { return }
            if let node = self.luxGetNode, response is SensorStatus, let index = self.nodes.firstIndex(of: node), let cell = self.collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ProfileDeviceDayNightLuxViewCell {
//                self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                cell.reloadNodeLux()
            }
        }
    }
    
    @objc private func stopLuxGetTimer() {
        luxGetTimer?.invalidate()
        luxGetTimer = nil
        if let node = luxGetNode {
            luxGetNode = nil
            if let index = nodes.firstIndex(of: node) {
                collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
            }else {
                collectionView.reloadData()
            }
        }
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopLuxGetTimer), object: nil)
        }
    }
    
    @objc private func selectAllDevicesAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            let canSelectDevices = nodes.filter({ $0.ambientLightSensorModel != nil })
            selectDevices = canSelectDevices
        }else {
            selectDevices.removeAll()
        }
        updateBottomViewUI()
    }
    
    /// 恢复组设置的lux
    @objc private func restoreGroupLuxAction() {
   
        
        selectDevices.forEach { node in
            node.preConfiguration.dayProfileStartsAboveLux = nil
            node.preConfiguration.nightProfileStartsBelowLux = nil
            if let nightLux = profile.nightData?.startsBelowLux {
                node.tempNightLux = Int(nightLux)
            }
            if let dayLux = profile.dayData?.startsBelowLux {
                node.tempDayLux = Int(dayLux)
            }
            if setMode == .saveAndSync, let meshUUID = node.network?.uuid.uuidString {
                node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
            }
        }
        selectDevices.removeAll()
        collectionView.reloadData()
        syncDevices(selectDevices)
    }
    
    /// 同步设备
    private func syncDevices(_ devices: [Node]) {
        
        let datas: [(node: Node, profiles: [ProfileType])] = devices.compactMap { node in
            let luxProfiles = node.getSyncDayNightLuxProfiles()
            if luxProfiles.count > 0 {
                return (node, luxProfiles)
            }
            return nil
        }
     
        guard datas.count > 0 else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            return
        }
        
        let vc = SyncDevicesViewController(type: .profile(datas))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            self.collectionView.reloadData()
        }
        vc.backActionCallback = {[weak self] _ in
            self?.collectionView.reloadData()
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    // MARK: - UI

    private func updateEmptyUI() {
        if nodes.isEmpty {
            view.showEmptyDataView(title: "no_devices".localizedString, backgroundColor: Background_Color)
            view.emptyView?.titleLabel.font = UIFont.systemFont(ofSize: FontFit(15))
        }else {
            view.hideEmptyDataView()
        }
    }
    
    /// 更新排序按钮状态
    private func updateSortBtnState() {
        
        if sorting {
            sortBtn.setTitle("stop".localizedString, for: .normal)
            sortBtn.setImage(UIImage(named: "loading"), for: .normal)
            sortBtn.imageView?.layer.addRotationAnimation(duration: 1.2, repeatCount: 99999, animationKey: "loading")
        }else {
            sortBtn.setTitle("Start".localizedString, for: .normal)
            sortBtn.setImage(UIImage(named: "space_sort"), for: .normal)
            sortBtn.imageView?.layer.removeAnimation(forKey: "loading")
        }
    }
    
    private func updateBottomViewUI() {
        let canSelectDevices = nodes.filter({ $0.ambientLightSensorModel != nil })
        bottomView.selectAllBtn.isSelected = selectDevices.count == canSelectDevices.count
        bottomView.selectCountLabel.text = "\(selectDevices.count)/\(canSelectDevices.count)"
        bottomView.addSelectedBtn.isEnabled = selectDevices.count > 0
    }
    
    private func setupUI() {
        
        bottomView = DeviceAddBottomView()
        bottomView.selectAllBtn.addTarget(self, action: #selector(selectAllDevicesAction), for: .touchUpInside)
        bottomView.addSelectedBtn.setTitle("restore_to_group_start_lux".localizedString, for: .normal)
        bottomView.addSelectedBtn.titleLabel?.font = UIFont.systemFont(ofSize: FontFit(14), weight: .light)
        bottomView.addSelectedBtn.setImage(UIImage(named: "restore_20"), for: .normal)
        bottomView.addSelectedBtn.addTarget(self, action: #selector(restoreGroupLuxAction), for: .touchUpInside)
        bottomView.addSelectedBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        bottomView.addSelectedBtnSize = CGSize(width: SCRXFrom(196).rounded(), height: SCRYFrom(40).rounded())
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(60))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(12)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(4), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.register(ProfileDeviceDayNightLuxViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.register(DeviceResyncHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collectionView.register(UICollectionReusableView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "emptyHeader")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.enableKeyboardDismissal()
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top)
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(8))
        }
        
    }


}

extension ProfileDayNightLuxDevicesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return nodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ProfileDeviceDayNightLuxViewCell
        let device = nodes[indexPath.item]
        cell.device = device
        cell.deviceImageLeftMargin = SCRXFrom(38)
        // 支持光照传感器
        if device.ambientLightSensorModel != nil {
            cell.showLightSensorLuxUI()
            cell.selectedImageView.isHidden = false
            cell.selectedImageView.image = UIImage(named: selectDevices.contains(device) ? "schedule_target_select" : "schedule_target_select_un")
            if setMode == .saveAndSync && device.getSyncDayNightLuxProfiles().count > 0 {
                cell.syncFailBtn.isHidden = false
            }else {
                cell.syncFailBtn.isHidden = true
            }
            
            if let setNightLux = device.tempNightLux, let setDayLux = device.tempDayLux,
               let initNightLux = device.preConfiguration.nightProfileStartsBelowLux ?? profile.nightData?.startsBelowLux,
               let initDayLux = device.preConfiguration.dayProfileStartsAboveLux ?? profile.dayData?.startsBelowLux,
               Int(initNightLux) != setNightLux || Int(initDayLux) != setDayLux {
                
                cell.resetBtn.isHidden = false
                cell.modifyBtn.isHidden = false
            }else {
                cell.resetBtn.isHidden = true
                cell.modifyBtn.isHidden = true
            }
            if luxGetNode == device {
                cell.startGetLuxLoading()
            }else {
                cell.stopGetLuxLoading()
            }
        }else {
            cell.selectedImageView.isHidden = true
            cell.showLightSensorNonsupportUI()
        }
        cell.delegate = self
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right, height: SCRYFrom(104))
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let syncNodes = nodes.filter({ $0.getSyncDayNightLuxProfiles().count > 0 })
        guard setMode == .saveAndSync && syncNodes.count > 0 else {
            return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "emptyHeader", for: indexPath)
        }
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! DeviceResyncHeaderView
        headerView.retryActionCallback = {[weak self] in
            self?.syncDevices(syncNodes)
        }
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        let existSyncNodes = nodes.contains(where: { $0.getSyncDayNightLuxProfiles().count > 0 })
        let width = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        if setMode == .saveAndSync && existSyncNodes {
            return CGSize(width: width, height: SCRYFrom(32))
        }
        return CGSize(width: width, height: SCRYFrom(8))
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let device = nodes[indexPath.item]
        if let index = selectDevices.firstIndex(of: device) {
            selectDevices.remove(at: index)
        }else {
            selectDevices.append(device)
        }
        collectionView.reloadItems(at: [indexPath])
        updateBottomViewUI()
    }
    
}

extension ProfileDayNightLuxDevicesViewController: ProfileDeviceDayNightLuxViewCellDelegate {
    
    /// 识别设备
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, identify device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 晚上lux编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, nightLuxEditChanged nightLux: Int?) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
        node.tempNightLux = nightLux
    }
    
    /// 晚上lux停止编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, nightLuxEditEnd nightLux: Int?) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        collectionView.reloadItems(at: [indexPath])
    }
    
    /// 白天lux编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, dayLuxEditChanged dayLux: Int?) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
        node.tempDayLux = dayLux
    }
    
    /// 白天lux停止编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, dayLuxEditEnd dayLux: Int?) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        collectionView.reloadItems(at: [indexPath])
    }
    
    /// 获取当前lux
    func deviceDayNightLuxViewCellGetLuxAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
        guard node != self.luxGetNode else {
            return
        }
        var reloadIndexPaths: [IndexPath] = [indexPath]
        if let lastNode = self.luxGetNode, let index = self.nodes.firstIndex(of: lastNode) {
            reloadIndexPaths.append(IndexPath(item: index, section: 0))
        }
        self.luxGetNode = node
        
        collectionView.reloadItems(at: reloadIndexPaths)
        
        self.startLuxGetTimer()
    }
    
    /// 恢复lux修改
    func deviceDayNightLuxViewCellResetAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
//        let profile = group.info.profile
        if let nightLux = node.preConfiguration.nightProfileStartsBelowLux ?? profile.nightData?.startsBelowLux {
            node.tempNightLux = Int(nightLux)
        }
        if let dayLux = node.preConfiguration.dayProfileStartsAboveLux ?? profile.dayData?.startsBelowLux {
            node.tempDayLux = Int(dayLux)
        }
        collectionView.reloadItems(at: [indexPath])
    }
    
    /// 确认修改回调
    func deviceDayNightLuxViewCellModifyAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
        guard let nightLux = node.tempNightLux, let dayLux = node.tempDayLux else {
            return
        }
        
        // lux必须小于5000
        let luxRange: ClosedRange<Int> = 0...5000
        
        guard luxRange.contains(nightLux) else {
            XWHUDManager.showErrorTipHUD("\("night_starts_below".localizedString) \("limit_range".localizedString) \(luxRange.lowerBound)~\(luxRange.upperBound)lux")
            return
        }
        guard luxRange.contains(dayLux) else {
            XWHUDManager.showErrorTipHUD("\("day_starts_above".localizedString) \("limit_range".localizedString) \(luxRange.lowerBound)~\(luxRange.upperBound)lux")
            return
        }
 
        // 白天lux-晚上lux必须大于等于5
        guard dayLux - nightLux >= 5 else {
            XWHUDManager.showErrorTipHUD("profile_night_startsbelow_greater_day_threshold".localizedString)
            return
        }
        
        node.preConfiguration.nightProfileStartsBelowLux = UInt16(nightLux)
        node.preConfiguration.dayProfileStartsAboveLux = UInt16(dayLux)
        collectionView.reloadItems(at: [indexPath])
        
        let profileTypes = node.getSyncDayNightLuxProfiles()
        
        guard profileTypes.count > 0, setMode == .saveAndSync else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            collectionView.reloadData()
            return
        }
        if let meshUUID = node.network?.uuid.uuidString {
            node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
        }
        syncDevices([node])
    }
    
    /// 重新同步
    func deviceDayNightLuxViewCellResyncAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
        syncDevices([node])
    }
    
}

extension Node {
    
    /// 光感lux读取状态
    enum DaylightLuxGetState {
        /// 无
        case none
        /// 读取中
        case loading
    }
    
    static var tempNightLuxKey = 10
    static var tempDayLuxKey = 11
    static var daylightLuxGetStateKey = 12
    
    /// 临时的晚上lux
    var tempNightLux: Int? {
        get {
            objc_getAssociatedObject(self, &Node.tempNightLuxKey) as? Int
        }set {
            objc_setAssociatedObject(self, &Node.tempNightLuxKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 临时的白天lux
    var tempDayLux: Int? {
        get {
            objc_getAssociatedObject(self, &Node.tempDayLuxKey) as? Int
        }set {
            objc_setAssociatedObject(self, &Node.tempDayLuxKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
