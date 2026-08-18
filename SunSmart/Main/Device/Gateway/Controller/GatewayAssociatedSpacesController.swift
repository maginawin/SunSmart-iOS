//
//  GatewayAssociatedSpacesController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit
import SwiftyJSON

enum GatewayAssociatedSpacesCandidateLoadResult {
    case available([GatewaySpaceData])
    case unavailable
}

class GatewayAssociatedSpacesController: UIViewController {

    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    private var bottomView: DeviceAddBottomView!
    private var headerView: UIView!
    private var messageLabel: UILabel!
    private var countLabel: UILabel!
//    private let maxNodesCount = 300
    
    private var selectSpaces: [GatewaySpaceData] = []
    /// 初始关联的spaces
    private var initAssociateSpaces: [GatewaySpaceData] = []
    
    /// 关联space选择回调
    var associatedSpacesSelectCallback: (([GatewaySpaceData])->())?
    
    let gateway: GatewayModel
    private let candidateProvider: () -> GatewayAssociatedSpacesCandidateLoadResult
    private var spaces: [GatewaySpaceData] = []
    
    init(
        gateway: GatewayModel,
        candidateProvider: @escaping () -> GatewayAssociatedSpacesCandidateLoadResult
    ) {
        self.gateway = gateway
        self.candidateProvider = candidateProvider
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
        let candidateDataUnavailable: Bool
        switch candidateProvider() {
        case .available(let spaces):
            self.spaces = spaces
            candidateDataUnavailable = false
        case .unavailable:
            self.spaces = []
            candidateDataUnavailable = true
        }

        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.gatewayAssociationSpaceList(siteId: gateway.siteId, gatewayId: gateway.mac)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else {
                return
            }
            self.view.hideEmptyDataView()
            
            switch result {
            case .success(let response):
                let list = JSON(response)["data"]["refSpaces"].arrayValue
                // 网关已绑定的space
                let bindSpaces: [GatewaySpaceData] = list.compactMap { spaceJson in
                    guard let spaceId = spaceJson["spaceId"].string, let spaceName = spaceJson["spaceName"].string, let deviceCount = spaceJson["deviceCount"].int, let appKeyIndex = spaceJson["appKey"]["index"].uInt16 else {
                        return nil
                    }
                    let gatewaySpace = GatewaySpaceData(spaceId: spaceId, spaceName: spaceName, deviceCount: deviceCount, appKeyIndex: appKeyIndex)
                    let space = SpaceData.load(
                        siteId: self.gateway.siteId,
                        spaceId: spaceId
                    ).first
                    gatewaySpace.updatePermission(from: space)
                    return gatewaySpace
                }
                bindSpaces.forEach { space in
                    if !self.spaces.contains(where: { $0.spaceId == space.spaceId }) {
                        self.spaces.append(space)
                    }
                }
                
                if self.spaces.count > 0 {
                    self.spaces.sort(by: { $0.appKeyIndex < $1.appKeyIndex })
                    let selectedSpaces = bindSpaces.sorted {
                        $0.appKeyIndex < $1.appKeyIndex
                    }
                    self.selectSpaces = selectedSpaces
                    self.initAssociateSpaces = selectedSpaces
                    
                    self.setupUI()
                    self.updateUI()
                }else if candidateDataUnavailable {
                    self.showDataLoadFailure()
                }else {
                    self.view.showEmptyDataView(title: "no_data".localizedString)
                }
                
            case .failure(let error):
                if error == .noNetwork {
                    view.showEmptyDataView(imageName: "internet_error", title: "gateway_associated_no_network_message".localizedString)
                }else {
                    showDataLoadFailure()
                }
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
   
        }
    }

    private func showDataLoadFailure() {
        view.showEmptyDataView(
            imageName: "internet_error",
            title: "failed_to_retrieve_data".localizedString,
            tipText: "network_problem_note".localizedString,
            buttonText: "RETRY".localizedString,
            position: .center,
            bottomMargin: SCRXFrom(60)
        ) { [weak self] in
            self?.loadAssociatedSpaces()
        }
    }
    
    @objc private func help() {
        
        navigationController?.pushViewController(GatewayAssociatedSpacesInstructionsController(), animated: true)
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
//            let total = spaces.reduce(0, { (result, space) -> Int in result + space.deviceCount })
//            guard total <= maxNodesCount else {
//                XWHUDManager.showTipHUD(String(format: "gateway_associated_nodes_limit_message".localizedString, maxNodesCount), isLineFeed: true)
//                sender.isSelected = false
//                return
//            }
            if spaces.count > gateway.maxAssociatedSpaces {
                sender.isSelected = false
                XWHUDManager.showTipHUD(String(format: "gateway_associated_spaces_limit_message".localizedString, gateway.maxAssociatedSpaces), isLineFeed: true, afterDelay: 1.5)
                return
            }
            selectSpaces = spaces
        }else {
            // 可编辑的space
            let editableSpaces = spaces.filter({ $0.permission == .editor })
            selectSpaces.removeAll(where: { space in editableSpaces.contains(where: { $0.spaceId == space.spaceId }) })
        }
        collectionView.reloadData()
        updateUI()
    }
    
    @objc private func addSelectedBtnAction() {
        
        
        let newSpaces = selectSpaces
        let oldSpaces = initAssociateSpaces
        // 新关联的spaces
        let addSpaces = newSpaces.filter({ space in !oldSpaces.contains(where: { $0.spaceId == space.spaceId }) && space.permission == .editor })
        // 解除关联的spaces
        let unbindSpaces = oldSpaces.filter({ space in !newSpaces.contains(where: { $0.spaceId == space.spaceId }) && space.permission == .editor })
        
        if addSpaces.count > 0 || unbindSpaces.count > 0 {
            associatedSpacesSelectCallback?(self.selectSpaces)
            navigationController?.popViewController(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    private func updateUI() {
        
//        let totalCount = selectSpaces.reduce(0, { (result, space) -> Int in result + space.deviceCount })
//        
//        let countAttStr = NSMutableAttributedString(string: "\(totalCount)/\(maxNodesCount)")
//        countAttStr.addAttribute(.foregroundColor, value: TextBlack_Color, range: (countAttStr.string as NSString).range(of: "\(totalCount)"))
//        countLabel.attributedText = countAttStr
        
        
        
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
        
        messageLabel = UILabel(text: String(format: "associated_spaces_message".localizedString, gateway.maxAssociatedSpaces), textColor: SubText_Color, fontSize: 14, fontWeight: .light)
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
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
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
        cell.nameLabel.textColor = TextBlack_Color
        cell.nodesLabel.text = "\("nodes".localizedString): \(space.deviceCount)"
        if selectSpaces.contains(where: { $0.spaceId == space.spaceId }) {
            if space.permission == .none || space.permission == .permissionLoss || space.permission == .permissionException {
                cell.nameLabel.textColor = Message_Color
                cell.selectImageView.image = UIImage(named: "schedule_target_select")?.withTintColor(Message_Color)
            }else {
                cell.selectImageView.image = UIImage(named: "schedule_target_select")
            }
        }else {
            cell.selectImageView.image = UIImage(named: "schedule_target_select_un")
        }
        return cell
    }
  
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let itemW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        return CGSize(width: itemW, height: SCRYFrom(44))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let space = spaces[indexPath.item]
        if space.permission == .none || space.permission == .permissionLoss || space.permission == .permissionException { // 其他人的space/无编辑权限space
            return
        }
        if let index = selectSpaces.firstIndex(where: { $0.spaceId == space.spaceId }) {
            selectSpaces.remove(at: index)
        }else {
            if selectSpaces.count >= gateway.maxAssociatedSpaces {
                XWHUDManager.showTipHUD(String(format: "gateway_associated_spaces_limit_message".localizedString, gateway.maxAssociatedSpaces), isLineFeed: true)
                return
            }
//            let total = selectSpaces.reduce(0, { (result, space) -> Int in result + space.deviceCount }) + space.deviceCount
//            guard total <= maxNodesCount else {
//                XWHUDManager.showTipHUD(String(format: "gateway_associated_nodes_limit_message".localizedString, maxNodesCount), isLineFeed: true)
//                return
//            }
            selectSpaces.append(space)
            selectSpaces.sort(by: { $0.appKeyIndex < $1.appKeyIndex })
        }
        collectionView.reloadItems(at: [indexPath])
        updateUI()
    }
    
}
