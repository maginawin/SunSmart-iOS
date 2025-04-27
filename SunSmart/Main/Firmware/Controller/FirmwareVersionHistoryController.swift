//
//  FirmwareVersionHistoryController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/3.
//

import UIKit
import SwiftyJSON
import NordicSigMeshSDK

class FirmwareVersionHistoryController: UIViewController {

//    private lazy var flowLayout: UICollectionViewFlowLayout = {
//        let layout = UICollectionViewFlowLayout()
//        layout.minimumLineSpacing = SCRYFrom(16)
//        layout.minimumInteritemSpacing = 0
//        layout.scrollDirection = .vertical
//        return layout
//    }()
//    
//    private lazy var collectionView: UICollectionView = {
//        let navbarH = view.safeAreaLayoutGuide
//        let collectionV = UICollectionView(frame: .zero, collectionViewLayout: self.flowLayout)
//        collectionV.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
//        collectionV.register(FirmwareVersionHistoryViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
////        collectionV.dataSource = self
////        collectionV.delegate = self
//        collectionV.backgroundColor = .clear
//        return collectionV
//    }()
    
    lazy var tableView: UITableView = {
        let tableV = UITableView()
        tableV.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: 0, bottom: SCRYFrom(16), right: 0)
        tableV.register(FirmwareVersionHistoryViewCell.classForCoder(), forCellReuseIdentifier: "cell")
//        tableV.register(FirmwareVersionHistoryViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        tableV.dataSource = self
        tableV.delegate = self
        tableV.separatorStyle = .none
        tableV.backgroundColor = .clear
        return tableV
    }()
    
    let productId: UInt16
    
    private var versionDatas: [FirmwareServerData] = []
    
    /// 是否测试
    var isTesting: Bool = false
    
    init(productId: UInt16) {
        self.productId = productId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "firmware_version_history".localizedString
        view.backgroundColor = Background_Color
        
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
//        view.addSubview(collectionView)
//        collectionView.snp.makeConstraints { make in
//            make.left.right.bottom.equalToSuperview()
//            make.top.equalTo(view.safeAreaLayoutGuide)
//        }
//        view.layoutIfNeeded()

        tableView.estimatedRowHeight = SCRYFrom(160)
        
//        flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
//        flowLayout.itemSize = CGSize(width: collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right, height: UICollectionViewFlowLayout.automaticSize.height)
        
//        CGSize(width: collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right, height: SCRYFrom(212))
        
//        setupData()
        loadVersionHistoryRequest()
    }

    
    /// 获取历史版本list请求
    private func loadVersionHistoryRequest() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
        NetworkRequest.shared.request(.firmwareVersionList(deviceType: self.productId.hex, isTesting: self.isTesting)) {[weak self] result in
            guard let self = self else { return }
            XWHUDManager.hideInView(with: self.view)
            
            switch result {
            case .success(let response):
                let list = JSON(response)["data"].arrayValue
                var results: [FirmwareServerData] = list.compactMap { data in
                    guard let version = data["version"].string,
                          let companyId = data["manufacturerId"].string,
                          let customId = data["customerId"].string,
                          var releaseDate = data["releaseDate"].string,
                          let size = data["size"].int else {
                        return nil
                    }
                    
                    releaseDate = releaseDate.replacingOccurrences(of: "T", with: " ")
                    releaseDate = releaseDate.replacingOccurrences(of: "Z", with: "")
                    let timeInterval = String.dateConvert(timeStr: releaseDate, dateFormat: nil)
                    
                    let serverData = FirmwareServerData(productId: self.productId, version: version.replacingOccurrences(of: "v", with: ""), companyId: UInt16(companyId) ?? 0x0A78, customId: UInt16(customId) ?? 0, url: "", filename: data["filename"].stringValue, size: size, releaseDate: timeInterval, content: data["describe"].stringValue)
                    return serverData
                }
                results = results.sorted(by: { $0.releaseDate >= $1.releaseDate })
                self.versionDatas = results
                if self.versionDatas.isEmpty {
                    self.tableView.showEmptyDataView(title: "no_record".localizedString)
                }else {
                    self.tableView.reloadData()
                }
                
                
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
            
        }
    }
}

extension FirmwareVersionHistoryController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return versionDatas.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! FirmwareVersionHistoryViewCell
        cell.firmwareData = versionDatas[indexPath.row]
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let cell = tableView.cellForRow(at: indexPath) as? FirmwareVersionHistoryViewCell, !cell.isExpanded {
            cell.isExpanded.toggle()
            tableView.performBatchUpdates(nil)
        }
    }
    
}


//extension FirmwareVersionHistoryController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
//    
//    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
//        return versionDatas.count
//    }
//    
//    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
//        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! FirmwareVersionHistoryViewCell
//        cell.firmwareData = versionDatas[indexPath.item]
//        return cell
//    }
//    
//    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
//        if let cell = collectionView.cellForItem(at: indexPath) as? FirmwareVersionHistoryViewCell {
//            cell.isExpanded.toggle()
//            collectionView.performBatchUpdates(nil)
//        }
//    }
//    
//}
