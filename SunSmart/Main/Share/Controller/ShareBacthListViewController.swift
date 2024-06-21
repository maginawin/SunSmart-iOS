//
//  ShareBacthListViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/4.
//

import UIKit

class ShareBacthListViewController: UIViewController {

    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    
    let site: SiteData
    private var bacthDataList: [BatchSpaceData] = []
    
    init(site: SiteData) {
        self.site = site
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "bacth_shared_list".localizedString
        view.backgroundColor = Background_Color
        
        for _ in 0...3 {
            let nameId = arc4random_uniform(1000000)
            let shareId = arc4random_uniform(100000000)
           let data = BatchSpaceData(site: site, uuid: String(format: "%08d", shareId), name: "Bacth \(String(format: "%06d", nameId))", spaces: site.spaces)
            bacthDataList.append(data)
        }
        setupCollectionView()
        updateEmptyUI()
    }
    
    
    /// 撤回批量分享的数据
    private func withdrawBacthData(_ data: BatchSpaceData) {
        
        if let index = bacthDataList.firstIndex(where: { $0.uuid == data.uuid }) {
            bacthDataList.remove(at: index)
            collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        }
        updateEmptyUI()
    }
    
    private func updateEmptyUI() {
        
        if bacthDataList.isEmpty {
            collectionView.showEmptyDataView(title: "bacth_shared_no_data".localizedString)
        }else {
            collectionView.hideEmptyDataView()
        }
    }
    
    private func setupCollectionView() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(16)
        flowLayout.minimumInteritemSpacing = 0
        
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.register(ShareBacthListViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = Background_Color
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo((navigationController?.navigationBar.height ?? 0))
        }
        let itemW = view.width - collectionView.contentInset.left - collectionView.contentInset.right
        flowLayout.itemSize = CGSize(width: CGFloat(floor(itemW)), height: SCRYFrom(64))
    }
    
    
}

extension ShareBacthListViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return bacthDataList.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ShareBacthListViewCell
        let data = bacthDataList[indexPath.item]
        cell.nameLabel.text = data.name
        cell.shareIdLabel.text = data.uuid
        cell.withdrawCallback = {[weak self] in
            self?.withdrawBacthData(data)
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let data = bacthDataList[indexPath.item]
        let vc = SharingSettingViewController(type: .batchSpace(data: data))
        navigationController?.pushViewController(vc, animated: true)
    }
    
}
