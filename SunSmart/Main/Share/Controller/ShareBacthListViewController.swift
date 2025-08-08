//
//  ShareBacthListViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/4.
//

import UIKit
import SwiftyJSON

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

        title = "batch_shared_list".localizedString
        view.backgroundColor = Background_Color
        
//        for _ in 0...3 {
//            let nameId = String.generateRandomNumberString(length: 6)
//            let shareId = String.generateRandomNumberString(length: 8)
//            let data = BatchSpaceData(site: site, code: String(format: "%08d", shareId), name: "Bacth \(String(format: "%06d", nameId))", spaces: site.spaces, editorPassword: "123456")
//            bacthDataList.append(data)
//        }
        setupCollectionView()
//        updateEmptyUI()
        
        loadDataReqeust()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let itemW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        flowLayout.itemSize = CGSize(width: CGFloat(floor(itemW)), height: SCRYFrom(64))
    }
    
    // MARK: - Reqeust
    
    private func loadDataReqeust() {
        XWHUDManager.showCustomHUD(withMessage: nil, view: self.view)
        NetworkRequest.shared.request(.batchShareList(siteId: site.id)) {[weak self] result in
            guard let self = self else { return }
            XWHUDManager.hideInView(with: self.view)
            
            switch result {
            case .success(let response):
                if let batchList = JSON(response)["data"]["batchList"].arrayObject as? [[String: Any]] {
                    self.bacthDataList = batchList.map({ data in
                        
                        let name = JSON(data)["batchName"].stringValue
                        let code = JSON(data)["batchId"].stringValue
                        let password = JSON(data)["editorPasswd"].stringValue
                        
                        let spaces: [SpaceData] = JSON(data)["spaces"].arrayValue.compactMap({ spaceData in
                            guard let spaceId = spaceData["spaceId"].string,
                                  let spaceName = spaceData["spaceName"].string else { return nil }
                            // 本地有space记录直接返回本地数据
                            if let space = self.site.spaces.first(where: { $0.id == spaceId }) {
                                return space
                            }
                            
                            var permission: Permission = self.site.permission
                            // 权限
                            if let role = spaceData["role"].string {
                                switch role {
                                case "owner":
                                    permission = .owner
                                case "editor":
                                    permission = .editor
                                case "visitor":
                                    permission = .visitor
                                default:
                                    break
                                }
                            }
                            
                            let space = SpaceData(name: spaceName, id: spaceId, siteId: self.site.id, imageId: spaceData["imageId"].intValue, create: 0, isFavourite: false, permission: permission, sourceType: .create, meshUUID: self.site.meshUUID, meshNetworkId: spaceId)
                            space.deviceCount = spaceData["nodeCount"].intValue
                            if let password = spaceData["editorPasswd"].string, password.count > 0 {
                                space.editorPassword = password
                            }
                            if let password = spaceData["visitorPasswd"].string, password.count > 0 {
                                space.vistorPassword = password
                            }
                            if let editorUserId = spaceData["editor"]["userId"].string, let name = spaceData["editor"]["username"].string {
                                space.editor = .init(name: name, uuid: editorUserId)
                            }
                           return space
                        })
                        return BatchSpaceData(siteId: self.site.id, code: code, name: name, spaces: spaces, editorPassword: password)
                    })
                    self.collectionView.reloadData()
                }
                self.updateEmptyUI()
                
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
            
        }
    }
    
    
    
    /// 撤回批量分享的数据
    private func withdrawBacthData(_ data: BatchSpaceData) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.revocationBatchShare(siteId: site.id, batchId: data.code)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                if let index = self.bacthDataList.firstIndex(where: { $0.code == data.code }) {
                    self.bacthDataList.remove(at: index)
                    self.collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
                    self.updateEmptyUI()
                }
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
          
        }
    }
    
    private func updateEmptyUI() {
        view.layoutIfNeeded()
        if bacthDataList.isEmpty {
            collectionView.showEmptyDataView(title: "batch_shared_no_data".localizedString)
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
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
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
        cell.shareIdLabel.text = data.code
        cell.withdrawCallback = {
            SRAlertView(title: "notification".localizedString, message: "batch_share_revoked_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                self?.withdrawBacthData(data)
            })]).show()
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let data = bacthDataList[indexPath.item]
        let vc = SharingSettingViewController(type: .batchSpace(data: data))
        navigationController?.pushViewController(vc, animated: true)
    }
    
}
