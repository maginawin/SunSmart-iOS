//
//  ProfileLightSensorTemplateListController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/22.
//

import UIKit

class ProfileLightSensorTemplateListController: UIViewController {

    private var bottomView: DeviceBottomBtnView!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupUI()
    }
    
    private func setupUI() {
        
        bottomView = DeviceBottomBtnView()
        bottomView.showCreateUI()
        bottomView.createBtn.setTitle("create_new_template".localizedString, for: .normal)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaTopHeight + SCRYFrom(56))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(12)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(4), left: 0, bottom: SCRYFrom(16), right: 0)
        
        view.addSubview(collectionView)
        
        
        
    }

}
