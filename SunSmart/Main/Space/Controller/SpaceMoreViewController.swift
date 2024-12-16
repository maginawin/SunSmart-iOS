//
//  SpaceMoreViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/22.
//

import UIKit

class SpaceMoreViewController: UIViewController {
    
    /// 固件升级方式
    enum FirmwareUpdateType {
        
        var data: (icon: String, title: String) {
            switch self {
            case .ble:
                return ("ota_ble", "ota_ble_title".localizedString)
            case .mesh:
                return ("ota_mesh", "ota_mesh_title".localizedString)
            }
        }
        
        /// ble直连
        case ble
        /// mesh分发
        case mesh
    }
    
    let space: SpaceData
    
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    private var options: [FirmwareUpdateType] = [.ble, .mesh]
    private weak var uploadStateView: FirmwareDistributeUpdateStateView?
    
    init(space: SpaceData) {
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
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(20), left: SCRXFrom(16), bottom: SCRYFrom(20), right: SCRXFrom(16))
        collectionView.register(SpaceMoreViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        var itemW = view.width - collectionView.contentInset.left - collectionView.contentInset.right
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        flowLayout.itemSize = CGSize(width: itemW, height: SCRYFrom(64))
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
            let vc = BleFirmwareUpdateViewController()
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .mesh:
            guard self.space.meshOTAOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            let vc = MeshFirmwareListViewController()
            present(NavigationViewController(rootViewController: vc), animated: true)
            return
            
//            MeshFirmwareUpgradeGuideView(title: "how_to_select_a_distributor".localizedString, message: "mesh_distributor_prompt_message".localizedString, steps: [.location, .signal, .identify, .distributor], contentHeight: SCRYFit(738)).show()
//            MeshFirmwareUpgradeGuideView(title: "how_to_mesh_upgrade".localizedString, message: "mesh_upgrade_prompt_message".localizedString, steps: [.selectDistributor, .selectDevices, .waiting], contentHeight: SCRYFit(660)).show()
            
            let stateView = FirmwareDistributeUpdateStateView(frame: UIScreen.main.bounds)
//            stateView.start(title: "upload_firmware".localizedString, message: "upload_firmware_message".localizedString, deviceName: "ID001", distributeVersion: "1.2.0")
            stateView.start(title: "notification".localizedString, message: "mesh_upgrade_inview_message".localizedString, distributeVersion: nil, isUpload: false)
            stateView.show()
            stateView.delegate = self
            uploadStateView = stateView
            
            DispatchQueue.global().async {
                DispatchQueue.main.async {
                    stateView.update(state: .connect)
                }
                Thread.sleep(forTimeInterval: 1)
                DispatchQueue.main.async {
                    stateView.update(state: .start)
                }
                Thread.sleep(forTimeInterval: 1)
                DispatchQueue.main.async {
                    stateView.update(state: .inProgress(progress: 20, estimatedTime: "1 minutes"))
                }
                Thread.sleep(forTimeInterval: 0.5)
                DispatchQueue.main.async {
                    stateView.update(state: .inProgress(progress: 50, estimatedTime: "1 minutes"))
                }
                Thread.sleep(forTimeInterval: 1)
                DispatchQueue.main.async {
                    stateView.update(state: .inProgress(progress: 100, estimatedTime: "0 minutes 10 sec"))
                }
                Thread.sleep(forTimeInterval: 1)
                if arc4random_uniform(2) == 1 {
                    DispatchQueue.main.async {
                        stateView.update(state: .completed)
                    }
                }else {
                    DispatchQueue.main.async {
                        stateView.update(state: .failure(message: "error"))
                    }
                }
            }
            
        }
        
    }
    
}

extension SpaceMoreViewController: FirmwareDistributeUpdateStateViewDelegate {
    
    /// 点击取消更新回调
    func firmwareUpdateCancelAction(_ view: FirmwareDistributeUpdateStateView) {
        uploadStateView?.hide()
    }
    
    /// 点击重试回调
    func firmwareUpdateRetryAction(_ view: FirmwareDistributeUpdateStateView) {
        uploadStateView?.hide()
    }
    
    /// 点击ok回调
    func firmwareUpdateOKAction(_ view: FirmwareDistributeUpdateStateView) {
        uploadStateView?.hide()
    }
    
}
