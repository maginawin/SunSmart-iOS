//
//  ProfileLightSensorTemplateDevicesController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/23.
//

import UIKit
import NordicSigMeshSDK

class ProfileLightSensorTemplateDevicesController: UIViewController {

    private var sortBtn: UIButton!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var bottomView: DeviceAddBottomView!
    
    private var sorting: Bool = false
    
    /// lux获取定时器
    private var luxGetTimer: Timer?
    /// 获取lux的设备
    private var luxGetNode: Node?
    /// 获取lux的持续时长
    private var luxGetDuration: TimeInterval = 30
    /// 获取lux的间隔
    private var luxGetInterval: TimeInterval = 1
    
    var profile: Profile
    
    var canAppliedDevices: [Node]
    
    private var rssiSortTimer: Timer?
    
    private var appliedDevices: [Node] = []

    var comfirmCallback: (([Node])->Void)?
    
    init(profile: Profile, canAppliedDevices: [Node], appliedDevices: [Node]) {
        
        canAppliedDevices.forEach { node in
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
        self.profile = profile
        self.canAppliedDevices = canAppliedDevices
        self.appliedDevices = appliedDevices
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "applied_to_device".localizedString
        view.backgroundColor = Background_Color
        
        sortBtn = UIButton(title: "Start".localizedString, titleSize: 14, titleColor: TextBlack_Color, normalImageName: "space_sort", target: self, action: #selector(sortBtnAction))
        sortBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: sortBtn)
        
        setupUI()
        updateBottomViewUI()
    }
    
    
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

        self.canAppliedDevices.forEach({
            $0.rssi = nil
        })
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.refreshNodesRSSIFinish), object: nil)
            self.perform(#selector(self.refreshNodesRSSIFinish), with: nil, afterDelay: 10)
        }
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 99999, nodeScan: {[weak self] data in
            
            guard let self = self, self.canAppliedDevices.contains(where: { $0.primaryUnicastAddress == data.node.primaryUnicastAddress }) else { return }
            
            // 查找完所有设备后停止搜索
            if !self.canAppliedDevices.contains(where: { $0.rssi == nil }) {
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
        
        canAppliedDevices.sort(by: { ($0.rssi ?? -99) >= ($1.rssi ?? -99) })
        collectionView.reloadData()
        
    }
    
    // MARK: - Lux Timer
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
            if let node = self.luxGetNode, response is SensorStatus, let index = self.canAppliedDevices.firstIndex(of: node), let cell = self.collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ProfileDeviceDayNightLuxViewCell {
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
            if let index = canAppliedDevices.firstIndex(of: node) {
                collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
            }else {
                collectionView.reloadData()
            }
        }
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopLuxGetTimer), object: nil)
        }
    }
    
    @objc private func comfirmAction() {
        comfirmCallback?(appliedDevices)
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func selectAllDevicesAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            appliedDevices = canAppliedDevices
        }else {
            appliedDevices.removeAll()
        }
        collectionView.reloadData()
        updateBottomViewUI()
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
        
        bottomView.selectAllBtn.isSelected = appliedDevices.count == canAppliedDevices.count
        bottomView.selectCountLabel.text = "\(appliedDevices.count)/\(canAppliedDevices.count)"
    }
    

    private func setupUI() {
        
        bottomView = DeviceAddBottomView()
        bottomView.selectAllBtn.addTarget(self, action: #selector(selectAllDevicesAction), for: .touchUpInside)
        bottomView.addSelectedBtn.setTitle("COMFIRM".localizedString, for: .normal)
        bottomView.addSelectedBtn.addTarget(self, action: #selector(comfirmAction), for: .touchUpInside)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(60))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(12)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(8), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.register(ProfileDeviceDayNightLuxViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top)
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
    }

}

extension ProfileLightSensorTemplateDevicesController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return canAppliedDevices.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ProfileDeviceDayNightLuxViewCell
        let device = canAppliedDevices[indexPath.item]
        cell.device = device
        cell.deviceImageLeftMargin = SCRXFrom(38)
        cell.selectedImageView.isHidden = false
       
        // 支持光照传感器
        if device.ambientLightSensorModel != nil {
            cell.showLightSensorLuxUI()
            cell.selectedImageView.isHidden = false
            cell.selectedImageView.image = UIImage(named: appliedDevices.contains(device) ? "schedule_target_select" : "schedule_target_select_un")
            cell.nightLuxField.backgroundColor = Background_Color
            cell.nightLuxField.isEnabled = false
            cell.dayLuxField.backgroundColor = Background_Color
            cell.dayLuxField.isEnabled = false
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
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let device = canAppliedDevices[indexPath.item]
        if let index = appliedDevices.firstIndex(of: device) {
            appliedDevices.remove(at: index)
        }else {
            appliedDevices.append(device)
        }
        collectionView.reloadItems(at: [indexPath])
        updateBottomViewUI()
    }
    
}

extension ProfileLightSensorTemplateDevicesController: ProfileDeviceDayNightLuxViewCellDelegate {
    
    /// 识别设备
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, identify device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 获取当前lux
    func deviceDayNightLuxViewCellGetLuxAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = canAppliedDevices[indexPath.item]
        guard node != self.luxGetNode else {
            return
        }
        var reloadIndexPaths: [IndexPath] = [indexPath]
        if let lastNode = self.luxGetNode, let index = self.canAppliedDevices.firstIndex(of: lastNode) {
            reloadIndexPaths.append(IndexPath(item: index, section: 0))
        }
        self.luxGetNode = node
        
        collectionView.reloadItems(at: reloadIndexPaths)
        
        self.startLuxGetTimer()
        
    }
    
}
