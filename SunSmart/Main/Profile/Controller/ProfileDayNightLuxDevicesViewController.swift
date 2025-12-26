//
//  ProfileDayNightLuxDevicesViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/25.
//

import UIKit
import NordicSigMeshSDK

class ProfileDayNightLuxDevicesViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    let nodes: [Node]
    
    init(nodes: [Node]) {
        self.nodes = nodes
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        DispatchQueue.main.async {
            self.updateEmptyUI()
        }
        
    }

    
//    override func viewDidLayoutSubviews() {
//        super.viewDidLayoutSubviews()
//        
//        updateEmptyUI()
//    }

    private func updateEmptyUI() {
        if nodes.isEmpty {
            view.showEmptyDataView(title: "no_devices".localizedString)
            view.emptyView?.titleLabel.font = UIFont.systemFont(ofSize: FontFit(15))
        }else {
            view.hideEmptyDataView()
        }
    }
    
    private func setupUI() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(12)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(4), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.register(ProfileDeviceDayNightLuxViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.top.bottom.equalToSuperview()
        }
        
    }


}

extension ProfileDayNightLuxDevicesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return nodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ProfileDeviceDayNightLuxViewCell
        cell.device = nodes[indexPath.item]
        cell.delegate = self
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right, height: SCRYFrom(104))
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
    
    /// 白天lux编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, dayLuxEditChanged dayLux: Int?) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
        node.tempDayLux = dayLux
    }
    
    /// 获取当前lux
    func deviceDayNightLuxViewCellGetLuxAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
        guard node.daylightLuxGetState == .none else {
            return
        }
        MeshAPI.getAmbientSensorValue(node: node) {[weak self] lux in
            guard let self = self else { return }
            self.collectionView.reloadItems(at: [indexPath])
        }
        
    }
    
    /// 恢复lux修改
    func deviceDayNightLuxViewCellResetAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let node = nodes[indexPath.item]
        let profile = node.group?.info.profile
        if let nightLux = node.preConfiguration.nightProfileStartsBelowLux ?? profile?.nightData?.startsBelowLux {
            node.tempNightLux = Int(nightLux)
        }
        if let dayLux = node.preConfiguration.dayProfileStartsAboveLux ?? profile?.dayData?.startsBelowLux {
            node.tempDayLux = Int(dayLux)
        }
        collectionView.reloadItems(at: [indexPath])
    }
    
    /// 确认修改回调
    func deviceDayNightLuxViewCellModifyAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        
    }
    
}

private extension Node {
    
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
    
    /// 光感lux获取状态
    var daylightLuxGetState: DaylightLuxGetState {
        get {
            objc_getAssociatedObject(self, &Node.daylightLuxGetStateKey) as? DaylightLuxGetState ?? .none
        }set {
            objc_setAssociatedObject(self, &Node.daylightLuxGetStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
