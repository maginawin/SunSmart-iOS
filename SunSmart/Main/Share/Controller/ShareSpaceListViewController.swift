//
//  ShareSpaceListViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/3.
//

import UIKit

class ShareSpaceListViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    let spaces: [SpaceData]
    
    init(spaces: [SpaceData]) {
        self.spaces = spaces
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "space_list".localizedString
        view.backgroundColor = Background_Color
        
        setupUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
    }

    private func setupUI() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(14)
        flowLayout.minimumInteritemSpacing = SCRXFrom(15)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.register(ShareAuthoritySpaceViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
    }
    
}

extension ShareSpaceListViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return spaces.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ShareAuthoritySpaceViewCell
        let space = spaces[indexPath.item]
        cell.nameLabel.text = space.name
        cell.iconImageView.image = UIImage(named: "space_picture_\(space.imageId)")
        cell.deviceCountLabel.text = "\(space.deviceCount)"
        if space.permission == .owner {
            cell.editorImageView.isHidden = space.editor == nil
        }else {
            cell.editorImageView.isHidden = true
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing) / 2.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW , height: SCRYFrom(156))
    }
}
