//
//  DaylightSensorInstructionsController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

class DaylightSensorInstructionsController: UIViewController {

    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    
    private lazy var itemDatas: [(name: String, imageName: String)] = {
        var array: [(name: String, imageName: String)] = []
        for i in 1...7 {
            array.append(("\("scheme".localizedString) \(i)", "daylight_scheme\(i)"))
        }
        return array
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        title = "daylight_sensor_control_instruction".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
    }
    
    @objc private func back() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumInteritemSpacing = SCRXFrom(23)
        flowLayout.minimumLineSpacing = SCRYFrom(12)
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(20), bottom: SCRYFrom(20), right: SCRXFrom(20))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        
        collectionView.register(DaylightSensorInstructionsHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collectionView.register(DaylightSensorInstructionsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        
        collectionView.snp.makeConstraints { make in
            let navHeight = navigationController?.navigationBar.height ?? kNavigationHeight
            make.top.equalTo(navHeight)
            make.left.right.bottom.equalToSuperview()
        }
    }

}

extension DaylightSensorInstructionsController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return itemDatas.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DaylightSensorInstructionsViewCell
        let data = itemDatas[indexPath.row]
        cell.nameLabel.text = data.name
        cell.imageView.image = UIImage(named: data.imageName)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing) / 2.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW , height: SCRYFrom(142))
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header", for: indexPath)
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        return CGSize(width: collectionView.width, height: SCRYFrom(227))
    }
    
}
