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
        guard self.space.deviceOperates.contains(.edit) else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        switch options[indexPath.item] {
        case .ble:
            let vc = BleFirmwareUpdateViewController()
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .mesh:
            break
        }
        
    }
    
}

