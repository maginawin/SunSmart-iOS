//
//  MeshFirmwareListViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/23.
//

import UIKit

class MeshFirmwareListViewController: UIViewController {

    /// 固件升级类型
    enum FirmwareUpdateType {
        
        var title: String {
            switch self {
            case .ble:
                return "ota_ble_title".localizedString
            case .mesh:
                return "ota_mesh_title".localizedString
            }
        }
        
        
        /// ble直连
        case ble
        /// mesh分发（一对多）
        case mesh
    }
    
    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    
    private var options: [FirmwareUpdateType] = [.ble, .mesh]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "firmware_update".localizedString
        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "help")?.withRenderingMode(.alwaysTemplate), style: .done, target: self, action: #selector(helpAction))
        
        setupCollectionView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarBackgroundColor(color: .white)
    }
    
    @objc private func helpAction() {
        
        let vc = BLEUpgradeInstructionsController()
        navigationController?.pushViewController(vc, animated: true)
    }
    

    private func setupCollectionView() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = .clear
        collectionView.register(MeshFirmwareListViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
        }
        
        flowLayout.itemSize = CGSize(width: self.view.width - collectionView.contentInset.left - collectionView.contentInset.right, height: SCRYFrom(64))
    }

}


extension MeshFirmwareListViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return options.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! MeshFirmwareListViewCell
        cell.titleLabel.text = options[indexPath.item].title
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch options[indexPath.item] {
        case .ble:
            let vc = BleFirmwareUpdateViewController()
            navigationController?.pushViewController(vc, animated: true)
        case .mesh:
            break
        }
        
    }
    
    
}
