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
    /// 初始关联的spaces
    private var initAssociateSpaces: [GatewaySpaceData] = []
    
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
            self.view.hideEmptyDataView()
            
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
                self.initAssociateSpaces = bindSpaces
                
                self.setupUI()
                self.updateUI()

                
            case .failure(let error):
                if error == .noNetwork {
                    view.showEmptyDataView(imageName: "internet_error", title: "requires_internet_message".localizedString)
                }else {
                    view.showEmptyDataView(imageName: "internet_error", title: "failed_to_retrieve_data".localizedString, tipText: "network_problem_note".localizedString, buttonText: "RETRY".localizedString, position: .center, bottomMargin: SCRXFrom(60)) {[weak self] in
                        self?.loadAssociatedSpaces()
                    }
                }
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
   
        }
    }
    
    /// 关联spaces请求
    private func associatedSpacesRequest(_ spaces: [GatewaySpaceData]) async -> (successSpaces: [GatewaySpaceData], failedSpaces: [GatewaySpaceData]) {
        var successSpaces: [GatewaySpaceData] = []
        var failedSpaces: [GatewaySpaceData] = []
        for space in spaces {
            let result = await NetworkRequest.shared.request(.gatewayBindSpace(spaceId: space.spaceId, gatewayId: gateway.mac))
            switch result {
            case .success:
                successSpaces.append(space)
            case .failure:
                failedSpaces.append(space)
            }
        }
        return (successSpaces, failedSpaces)
    }
    
    /// 解除关联spaces请求
    private func unbindAssociatedSpacesRequest(_ spaces: [GatewaySpaceData]) async -> (successSpaces: [GatewaySpaceData], failedSpaces: [GatewaySpaceData]) {
        var successSpaces: [GatewaySpaceData] = []
        var failedSpaces: [GatewaySpaceData] = []
        for space in spaces {
            let result = await NetworkRequest.shared.request(.gatewayUnbindSpace(spaceId: space.spaceId, gatewayId: gateway.mac))
            switch result {
            case .success(_):
                successSpaces.append(space)
            case .failure(_):
                failedSpaces.append(space)
            }
        }
        return (successSpaces, failedSpaces)
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
        
        
        let newSpaces = selectSpaces
        let oldSpaces = initAssociateSpaces
        // 新关联的spaces
        let addSpaces = newSpaces.filter({ space in !oldSpaces.contains(where: { $0.spaceId == $0.spaceId }) && (space.permission == .owner || space.permission == .editor) })
        // 解除关联的spaces
        let unbindSpaces = oldSpaces.filter({ space in !newSpaces.contains(where: { $0.spaceId == $0.spaceId }) && (space.permission == .owner || space.permission == .editor) })
        
        if addSpaces.count > 0 || unbindSpaces.count > 0 {
            spacesAssociatedHandle(associatedSpaces: addSpaces, disassociatedSpaces: unbindSpaces)
        }else {
            associatedSpacesSelectCallback?(selectSpaces)
            navigationController?.popViewController(animated: true)
        }
    }
    
    
    /// 关联/解除space关联操作
    /// - Parameters:
    ///   - associatedSpaces: 关联的spaces
    ///   - disassociatedSpaces: 解除关联的spaces
    private func spacesAssociatedHandle(associatedSpaces: [GatewaySpaceData], disassociatedSpaces: [GatewaySpaceData]) {
        guard associatedSpaces.count > 0 || disassociatedSpaces.count > 0 else {
            return
        }
        Task {
            var associatedResult: (successSpaces: [GatewaySpaceData], failedSpaces: [GatewaySpaceData])?
            var disassociatedResult: (successSpaces: [GatewaySpaceData], failedSpaces: [GatewaySpaceData])?
            
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            if associatedSpaces.count > 0 {
                associatedResult = await self.associatedSpacesRequest(associatedSpaces)
            }
            if disassociatedSpaces.count > 0 {
                disassociatedResult = await self.unbindAssociatedSpacesRequest(disassociatedSpaces)
            }
            XWHUDManager.hide()
            // 绑定成功的spaces
            if let addAssociatedSpaces = associatedResult?.successSpaces {
                addAssociatedSpaces.forEach {
                    if !self.gateway.associatedSpaces.contains(where: { $0.spaceId == $0.spaceId }) {
                        self.gateway.associatedSpaces.append($0)
                    }
                }
            }
            
            // 解除绑定成功的spaces
            if let disassociatedSpaces = disassociatedResult?.successSpaces {
                self.gateway.associatedSpaces.removeAll(where: { space in disassociatedSpaces.contains(where: { space.spaceId == $0.spaceId }) })
            }
            self.gateway.save()
            self.initAssociateSpaces = self.gateway.associatedSpaces
            
            // 绑定失败的spaces
            let associatedFailSpaces = associatedResult?.failedSpaces ?? []
            // 解除绑定失败的spaces
            let disassociatedFailSpaces = disassociatedResult?.failedSpaces ?? []
            
            guard associatedFailSpaces.isEmpty, disassociatedFailSpaces.isEmpty else {
                // 存在失败的space
                self.showAssociateFailedAlert(associatedFailSpaces: associatedFailSpaces, disassociatedFailSpaces: disassociatedFailSpaces)
                return
            }
            
            self.associatedSpacesSelectCallback?(self.selectSpaces)
            self.navigationController?.popViewController(animated: true)
        }
        
    }
    
    
    /// 提示关联/解除关联失败结果
    /// - Parameters:
    ///   - associatedFailSpaces: 关联失败的spaces
    ///   - disassociatedFailSpaces: 解除关联失败的spaces
    private func showAssociateFailedAlert(associatedFailSpaces: [GatewaySpaceData], disassociatedFailSpaces: [GatewaySpaceData]) {
        
        guard associatedFailSpaces.count > 0 || disassociatedFailSpaces.count > 0 else {
            return
        }
        
        var messageStr: String = ""
        
        if associatedFailSpaces.count > 0 {
            let associateFailStr = String(format: "associate_spaces_failed_message".localizedString, associatedFailSpaces.map({ $0.spaceName }).joined(separator: ", "))
            messageStr.append(associateFailStr)
        }
        if disassociatedFailSpaces.count > 0 {
            let disassociateFailStr = String(format: "disassociate_spaces_failed_message".localizedString, disassociatedFailSpaces.map({ $0.spaceName }).joined(separator: ", "))
            messageStr.append("\n" + disassociateFailStr)
        }
        
        let noteStr = "network_problem_note".localizedString
        
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineSpacing = 4
        style.lineBreakMode = .byCharWrapping
        
        let messageAttStr = NSMutableAttributedString(string: messageStr, attributes: [.paragraphStyle: style])
        messageAttStr.addAttributes([.foregroundColor: Message_Color], range: (messageAttStr.string as NSString).range(of: noteStr))
        
        SRAlertView(title: "notification".localizedString, messageAttStr: messageAttStr, messageFont: UIFont.systemFont(ofSize: SCRYFrom(13), weight: .light), actions: [SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: {[weak self] _ in
            guard let self = self else {
                return
            }
            // 失败的space恢复之前未选择状态
            associatedFailSpaces.forEach { space in
                self.selectSpaces.removeAll(where: { $0.spaceId == space.spaceId })
            }
            // 失败的space恢复之前选中状态
            disassociatedFailSpaces.forEach { space in
                if !self.selectSpaces.contains(where: { $0.spaceId == space.spaceId }) {
                    self.selectSpaces.append(space)
                }
            }
            self.collectionView.reloadData()
            self.updateUI()
            
        }), SRAlertAction(title: "RETRY".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else {
                return
            }
            self.spacesAssociatedHandle(associatedSpaces: associatedFailSpaces, disassociatedSpaces: disassociatedFailSpaces)
        })]).show()
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
        
        messageLabel = UILabel(text: String(format: "associated_spaces_message".localizedString, gateway.maxAssociatedSpaces, maxNodesCount), textColor: SubText_Color, fontSize: 14, fontWeight: .light)
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
        cell.nameLabel.textColor = TextBlack_Color
        cell.nodesLabel.text = "\("nodes".localizedString): \(space.deviceCount)"
        if selectSpaces.contains(where: { $0.spaceId == space.spaceId }) {
            if space.permission == .none || space.permission == .visitor {
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
        if space.permission == .none || space.permission == .visitor { // 其他人的space/无编辑权限space
            return
        }
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
