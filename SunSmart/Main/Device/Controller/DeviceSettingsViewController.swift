//
//  DeviceSettingsViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/15.
//

import UIKit

class DeviceSettingsViewController: UIViewController {

    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "settings".localizedString
        view.backgroundColor = Background_Color
    }
    
    private func setupUI() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(16)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        view.addSubview(collectionView)
    }
    


}
