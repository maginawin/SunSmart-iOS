//
//  SpaceMoreViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/22.
//

import UIKit

class SpaceMoreViewController: UIViewController {
    
    enum Options {
        
        var data: (icon: String, title: String) {
            switch self {
            case .ble:
                return ("ota_ble", "ota_ble_title".localizedString)
            case .mesh:
                return ("ota_mesh", "ota_mesh_title".localizedString)
            case .deviceParameters:
                return ("device_parameter", "device_parameter_settings".localizedString)
            case .energyData:
                return ("space_energy_data", "energy_data".localizedString)
            case .triggerZone:
                return ("trigger_zone", "trigger_zone".localizedString)
            case .contentDisplay:
                return ("content_display", "content_display".localizedString)
            }
        }
        
        /// ble直连
        case ble
        /// mesh分发
        case mesh
        /// 设备参数
        case deviceParameters
        /// 能耗统计
        case energyData
        /// 触发区域
        case triggerZone
        /// 内容显示
        case contentDisplay
    }
    
    let site: SiteData
    let space: SpaceData
    
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    private var options: [Options] = [.ble, .deviceParameters, .energyData,
        //.triggerZone,
        .contentDisplay]
    
    init(site: SiteData, space: SpaceData) {
        self.site = site
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupCollectionView()
    }
    
    private func setupCollectionView() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(16), left: SCRXFrom(16), bottom: SCRYFrom(20), right: SCRXFrom(16))
        collectionView.register(SpaceMoreViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionViewLongPressAction))
        longPress.minimumPressDuration = 2
        collectionView.addGestureRecognizer(longPress)
        collectionView.alwaysBounceVertical = true
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        var itemW = view.width - collectionView.contentInset.left - collectionView.contentInset.right
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        
        flowLayout.itemSize = CGSize(width: itemW, height: SCRYFrom(isIPad ? 84 : 64))
    }
    
    /// collectionview长按事件，开启mesh升级测试功能
    @objc private func collectionViewLongPressAction(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point), options[indexPath.item] == .ble else {
            return
        }
        guard !options.contains(.mesh) else {
            return
        }
        options.insert(.mesh, at: 1)
        collectionView.insertItems(at: [IndexPath(item: 1, section: 0)])
    }

}

extension SpaceMoreViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return options.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SpaceMoreViewCell
        let option = options[indexPath.item]
        cell.iconImageView.image = UIImage(named: option.data.icon)
        cell.titleLabel.text = option.data.title
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch options[indexPath.item] {
        case .ble:
            guard self.space.bleOTAOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            
            let vc = BleFirmwareUpdateViewController(site: site, space: space)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .mesh:
            guard self.space.meshOTAOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            let vc = MeshFirmwareListViewController()
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .deviceParameters:
            guard self.space.deviceOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            let vc = DeviceCategorysViewController()
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .energyData:
            #if SylSmart
            let vc = EnergyStaticDataViewController(space: space)
            #else
            let vc = EnergyDataViewController(space: space)
            #endif
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .triggerZone:
            guard self.space.groupOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            let vc = SpacePathTriggerZoneController(site: site, space: space)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .contentDisplay:
            let vc = ContentDisplayViewController(space: space)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        }
        
    }
    
}
