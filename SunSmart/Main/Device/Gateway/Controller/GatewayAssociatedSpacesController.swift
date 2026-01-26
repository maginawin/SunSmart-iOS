//
//  GatewayAssociatedSpacesController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit
import SwiftyJSON

class GatewayAssociatedSpacesController: UIViewController {

    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    private var bottomView: DeviceAddBottomView!
    private var headerView: UIView!
    private var messageLabel: UILabel!
    private var countLabel: UILabel!
    private let maxNodesCount = 300
    
    private var selectSpaces: [GatewaySpaceData] = []
    
    /// 关联space选择回调
    var associatedSpacesSelectCallback: (([GatewaySpaceData])->())?
    
    let gateway: GatewayModel
    var spaces: [GatewaySpaceData]
    
    init(gateway: GatewayModel, spaces: [GatewaySpaceData]) {
        self.gateway = gateway
        self.spaces = spaces
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "associated_spaces".localizedString
        
        view.backgroundColor = Background_Color
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "help")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(help))
        
        loadAssociatedSpaces()
    }
    
    private func loadAssociatedSpaces() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.gatewayAssociationSpaceList(siteId: gateway.siteId, gatewayId: gateway.mac)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else {
                return
            }
            switch result {
            case .success(let response):
                let list = JSON(response)["data"]["refSpaces"].arrayValue
                // 网关已绑定的space
                let bindSpaces: [GatewaySpaceData] = list.compactMap { spaceJson in
                    guard let spaceId = spaceJson["spaceId"].string, let spaceName = spaceJson["spaceName"].string, let deviceCount = spaceJson["deviceCount"].int, let appKeyIndex = spaceJson["appKey"]["index"].uInt16 else {
                        return nil
                    }
                    var gatewaySpace = GatewaySpaceData(spaceId: spaceId, spaceName: spaceName, deviceCount: deviceCount, appKeyIndex: appKeyIndex)
                    if let space = SpaceData.load(siteId: self.gateway.siteId, spaceId: spaceId).first, space.state == .normal, let permission = GatewaySpaceData.GatewaySpacePermission(rawValue: space.permission.rawValue) {
                        gatewaySpace.permission = permission
                    }
                    return gatewaySpace
                }
                bindSpaces.forEach { space in
                    if !self.spaces.contains(where: { $0.spaceId == space.spaceId }) {
                        self.spaces.append(space)
                    }
                }
                self.spaces.sort(by: { $0.appKeyIndex < $1.appKeyIndex })
                self.selectSpaces = bindSpaces
                
                self.setupUI()
                self.updateUI()
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
                
//                view.showEmptyDataView(title: "")
            }
   
        }
    }
    
    
    @objc private func help() {
        
        navigationController?.pushViewController(GatewayAssociatedSpacesInstructionsController(), animated: true)
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
            let total = spaces.reduce(0, { (result, space) -> Int in result + space.deviceCount })
            guard total <= maxNodesCount else {
                XWHUDManager.showTipHUD(String(format: "gateway_associated_nodes_limit_message".localizedString, maxNodesCount), isLineFeed: true)
                sender.isSelected = false
                return
            }
            selectSpaces = spaces
        }else {
            selectSpaces = []
        }
        collectionView.reloadData()
        updateUI()
    }
    
    @objc private func addSelectedBtnAction() {
        
        let newSpaces = self.setGatewayModel.associatedSpaces
        let oldSpaces = self.gateway.associatedSpaces
        // 新关联的spaces
        var addSpaces = newSpaces.filter({ space in !oldSpaces.contains(where: { $0.spaceId == $0.spaceId }) && (space.permission == .owner || space.permission == .editor) })
        // 解除关联的spaces
        var unbindSpaces = oldSpaces.filter({ space in !newSpaces.contains(where: { $0.spaceId == $0.spaceId }) && (space.permission == .owner || space.permission == .editor) })
        
        if addSpaces.count > 0 {
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            let associatedResult = await self.associatedSpacesRequest(addSpaces)
            self.gateway.associatedSpaces.append(contentsOf: associatedResult.successSpaces)
            self.gateway.save()
            guard associatedResult.failedSpaces.isEmpty else {
                XWHUDManager.hide()
                XWHUDManager.showTipHUD("\("associated_spaces".localizedString) \("failed".localizedString)", isLineFeed: <#T##Bool#>)
                return
            }
        }
        
        
        associatedSpacesSelectCallback?(selectSpaces)
        navigationController?.popViewController(animated: true)
    }
    
    private func updateUI() {
        
        let totalCount = selectSpaces.reduce(0, { (result, space) -> Int in result + space.deviceCount })
        
        let countAttStr = NSMutableAttributedString(string: "\(totalCount)/\(maxNodesCount)")
        countAttStr.addAttribute(.foregroundColor, value: TextBlack_Color, range: (countAttStr.string as NSString).range(of: "\(totalCount)"))
        countLabel.attributedText = countAttStr
        
        bottomView.selectAllBtn.isSelected = spaces.count > 0 && selectSpaces.count == spaces.count
        bottomView.selectCountLabel.text = "\(selectSpaces.count)/\(spaces.count)"
        
    }
    
    private func setupUI() {
        
        bottomView = DeviceAddBottomView()
        bottomView.selectAllBtn.setTitle("associated_selected".localizedString, for: .normal)
        bottomView.selectCountLabel.text = "\(selectSpaces.count)/\(spaces.count)"
        bottomView.addSelectedBtn.setTitle("associated_selected".localizedString, for: .normal)
        bottomView.selectAllBtn.addTarget(self, action: #selector(selectAllBtnAction), for: .touchUpInside)
        bottomView.addSelectedBtn.addTarget(self, action: #selector(addSelectedBtnAction), for: .touchUpInside)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        bottomView.addSelectedBtn.snp.updateConstraints { make in
            make.width.equalTo(SCRXFrom(156))
        }
        
        headerView = UIView()
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(7))
            make.height.equalTo(SCRYFrom(33))
        }
        
        messageLabel = UILabel(text: String(format: "associated_spaces_message".localizedString, spaces.count, maxNodesCount), textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        headerView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-88))
            make.centerY.equalToSuperview()
        }
        
        countLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        headerView.addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(messageLabel)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(8)
        flowLayout.minimumInteritemSpacing = 0
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: 0, right: SCRXFrom(16))
        collectionView.register(GatewayAssociatedSpacesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(bottomView.snp.top)
        }
    }
    

}

extension GatewayAssociatedSpacesController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return spaces.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GatewayAssociatedSpacesViewCell
        let space = spaces[indexPath.item]
        cell.nameLabel.text = space.spaceName
        cell.nodesLabel.text = "\("nodes".localizedString): \(space.deviceCount)"
        cell.selectImageView.image = selectSpaces.contains(where: { $0.spaceId == space.spaceId }) ? UIImage(named: "schedule_target_select") : UIImage(named: "schedule_target_select_un")
        return cell
    }
  
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let itemW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        return CGSize(width: itemW, height: SCRYFrom(44))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let space = spaces[indexPath.item]
        if let index = selectSpaces.firstIndex(where: { $0.spaceId == space.spaceId }) {
            selectSpaces.remove(at: index)
        }else {
            let total = selectSpaces.reduce(0, { (result, space) -> Int in result + space.deviceCount }) + space.deviceCount
            guard total <= maxNodesCount else {
                XWHUDManager.showTipHUD(String(format: "gateway_associated_nodes_limit_message".localizedString, maxNodesCount), isLineFeed: true)
                return
            }
            selectSpaces.append(space)
        }
        collectionView.reloadItems(at: [indexPath])
        updateUI()
    }
    
}
