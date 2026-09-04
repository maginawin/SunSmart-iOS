//
//  GroupAddViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/11.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

class GroupAddViewController: UIViewController {
    /// 数据类型
    enum SourceType {
        // 图标
        case image
        // 文字
        case text
    }
    
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    private var footerView: UIView!
    private var doneBtn: UIButton!
    private var cancelBtn: UIButton!
    private var lineView: UIView!
    
    private var selectImageIndex: Int = 0
    private var dataSource: [(type: SourceType, name: String)] = []
    
    private var headerView: GroupAddHeaderView?
    
    private var name: String?
    
    let space: SpaceData
//    var doneCallback: ((Group)->Void)?
    /// 传入组则编辑
    var group: Group?
    /// 配置数据
    private var profiles: [Profile] = Profile.defaultGroupProfiles()
    private var selectProfile: Profile!
    /// 创建完成回调
    var addFinishedCallback: ((Group)->Void)?
    
    init(space: SpaceData, group: Group? = nil) {
        self.space = space
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        if presentingViewController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        setupUI()
        
        for i in 1...18 {
            if i == 2 {
                dataSource.append((type: .text, name: self.group?.info.imageText ?? "A"))
            }else {
                dataSource.append((type: .image, name: "group_image_\(i)"))
            }
        }
        
        if let group = self.group {
            name = group.name
            title = "edit_group".localizedString
            selectProfile = group.info.profile
            doneBtn.setTitle("done".localizedString, for: .normal)
            selectImageIndex = max(0, group.info.imageId - 1)
        }else {
            name = MeshNetworkManager.instance.getNextGroupName()
            title = "create_group".localizedString
            selectProfile = profiles.first!
        }
        
        
//        if isAdd {
//            doneBtn.setTitle("add".localizedString, for: .normal)
//        }
//        nameField.text = name
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    deinit {
        // 首次进入引导创建流程，手动退出后停止配置
        if space.isConfiguring && group == nil {
            space.isConfiguring = false
        }
    }
    
    @objc private func close() {
        if presentingViewController != nil {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func cancelBtnClick() {
        close()
    }
    
    @objc private func doneBtnClick() {
        
        guard let name = self.name, !name.isAllInputTextEmpty() else {
//            showEmptyState
            headerView?.showEmptyState()
            return
        }
        
        if let group = self.group { // 编辑
            var transaction = ProximityLightingLifecycleCoordinator.begin(space: space)
            transaction.updateProfile(group: group, profile: selectProfile)
            let preparation = transaction.prepare()
            guard preparation.isValid
                    || preparation.doesNotIntroduceHardErrors,
                  let lifecycleResult = ProximityLightingLifecycleCoordinator.commit(
                    preparation,
                    allowExistingHardErrors: true,
                    hasAdditionalLogicalChange: true,
                    applyAdditionalChanges: {
                        group.name = name
                        group.save()
                        self.applyGroupInfoEdits(to: group)
                    }
                  ) else {
                XWHUDManager.showTipHUD(
                    "proximity_lighting_topology_invalid".localizedString,
                    isLineFeed: true
                )
                return
            }
            finishGroupEdit(group, lifecycleResult: lifecycleResult)
        }else { // 新增
            // 判断组地址是否足够创建
            guard MeshAPI.getAvailableGroupAddresses(meshUUID: self.space.meshUUID, subnetworkId: self.space.meshNetworkId).count > 0 else {
                let applyAddressCount = 16
                // 地址不够
                // 手机是否联网
                guard NetworkRequest.shared.networkable else {
                    // 未联网提示联网以获取地址
                    SRAlertView(title: "notification".localizedString, message: "group_address_insufficient".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                        guard let self = self else { return }
                        if NetworkRequest.shared.networkable {
                            self.space.applyGroupAddressCount = nil
                            self.space.save()
                            self.applyGroupAddressesRequest(applyAddressCount: applyAddressCount)
                        }else {
                            self.space.applyGroupAddressCount = applyAddressCount
                            self.space.save()
                        }
                    })]).show()
                    return
                }
                self.applyGroupAddressesRequest(applyAddressCount: applyAddressCount)
                return
            }
            createGroup()
        }
    }
    
    /// 申请地址请求
    private func applyGroupAddressesRequest(applyAddressCount: Int) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.applyAddress(siteId: self.space.siteId, type: .group, number: applyAddressCount)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let repsonsed):
                self.space.applyGroupAddressCount = nil
                self.space.save()
                // 新增地址
                if let site = SiteData.load(siteId: self.space.siteId), let provisionerData = JSON(repsonsed)["data"]["provisioner"].dictionaryObject {
                    site.setProvisioner(provisionerData: provisionerData)
                    // 继续添加组
                    self.createGroup()
                }else {
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    private func createGroup() {
        
        MeshAPI.createGroup(name: self.name) {[weak self] group in
            guard let self = self else { return }
            self.group = group
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            self.finnished()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                guard let self = self else { return }
                if self.addFinishedCallback != nil {
                    self.addFinishedCallback?(group)
                    close()
                }else {
                    let memberVc = GroupMembersViewController(space: self.space, group: group)
                    memberVc.isAddDevices = true
                    self.navigationController?.pushViewController(memberVc, animated: true)
                }
                NotificationCenter.default.post(name: .init(groupsRefreshNotificationName), object: nil)
            }
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        } fail: { _, error in
            // 没有地址
//                if let network = MeshNetworkManager.instance.meshNetwork, network.localProvisioner == nil || MeshNetworkManager.instance.meshNetwork?.nextAvailableGroupAddress(for: network.localProvisioner!) == nil {
//
//                }else {
            XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
//                }
        }
        
    }
    
    private func finnished() {
        
        guard let group = self.group else {
            close()
            return
        }
        
        applyGroupInfoEdits(to: group)
        group.updateGroupSyncState()
        
//        let groupInfo = GroupInfo(address: group.address.address, imageId: self.selectImageIndex + 1, imageText: source.type == .text ? source.name : nil)
//        groupInfo.profile = self.selectProfile
        
//        groupInfo.save()
//        groupInfo.profile.save()
//        group.info = groupInfo
        // 保存配置数据
//        self.selectProfile.save()
//        self.doneCallback?(group)
    }

    private func applyGroupInfoEdits(to group: Group) {
        let source = dataSource[selectImageIndex]
        group.info.imageId = selectImageIndex + 1
        group.info.imageText = source.type == .text ? source.name : nil
        group.info.profile.updateData(profile: selectProfile)
        group.info.save()
        group.info.profile.save(
            meshUUID: space.meshUUID,
            meshNetworkId: space.meshNetworkId
        )
        group.updateGroupSyncState()
    }

    private func finishGroupEdit(
        _ group: Group,
        lifecycleResult: ProximityLightingLifecycleResult
    ) {
        let finish = { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
                name: .init(groupDataUpdateNotificationName),
                object: group
            )
            NotificationCenter.default.post(
                name: .init(spaceDataChangedNotificaitonName),
                object: SpaceChangeDataType.common
            )
            if self.navigationController?.topViewController !== self {
                self.navigationController?.popToViewController(self, animated: false)
            }
            self.close()
        }
        guard group.needSync || !lifecycleResult.syncDatas.isEmpty else {
            finish()
            return
        }
        let vc = SyncDevicesViewController(
            type: .group(group, inNodes: nil, outNodes: nil)
        )
        vc.supplementaryProximityLightingSyncDatas = lifecycleResult.syncDatas
        vc.syncSuccessCallback = { _ in finish() }
        vc.backActionCallback = { _ in finish() }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func setupUI() {

        footerView = UIView()
        footerView.backgroundColor = .white
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        let bottomLineView = UIView()
        bottomLineView.backgroundColor = Line_Color
        footerView.addSubview(bottomLineView)
        bottomLineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
//        lineView = UIView()
//        lineView.backgroundColor = Line_Color
//        footerView.addSubview(lineView)
//        lineView.snp.makeConstraints { make in
//            make.centerX.equalToSuperview()
//            make.top.equalTo(SCRYFrom(8))
//            make.width.equalTo(1)
//            make.bottom.equalTo(-kSafeAreaTopHeight - SCRYFrom(8))
////            make.height.equalTo(SCRYFrom(40))
//        }
        
//        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 16, titleColor: TextBlack_Color, target: self, action: #selector(cancelBtnClick))
//        cancelBtn.titleLabel?.textAlignment = .center
//        footerView.addSubview(cancelBtn)
//        cancelBtn.snp.makeConstraints { make in
//            make.right.equalTo(lineView.snp.left).offset(SCRXFrom(-33))
//            make.centerY.equalTo(lineView)
//            make.width.equalTo(SCRXFrom(120))
//            make.height.equalTo(SCRYFrom(30))
//        }
        
        doneBtn = UIButton(title: "CREATE".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(doneBtnClick))
        doneBtn.setTitleColor(RGB(139, 139, 139), for: .disabled)
        doneBtn.titleLabel?.textAlignment = .center
        footerView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
//            make.left.equalTo(lineView.snp.left).offset(SCRXFrom(33))
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
//            make.centerY.height.width.equalTo(cancelBtn)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: flowLayout.minimumLineSpacing, right: 0)
//        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(GroupAddHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collectionView.register(GroupImageViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
//            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(footerView.snp.top)
        }
        
    }

}

extension GroupAddViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataSource.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupImageViewCell
        let source = dataSource[indexPath.item]
        if source.type == .text {
            cell.imageView.isHidden = true
            cell.nameLabel.isHidden = false
            cell.nameLabel.text = source.name
        }else {
            cell.imageView.isHidden = false
            cell.imageView.image = UIImage(named: source.name)
            cell.nameLabel.isHidden = true
        }
        cell.layer.borderWidth = selectImageIndex == indexPath.item ? 0.5 : 0
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        var source = dataSource[indexPath.item]
        if source.type == .text {
            CharacterSelectView.show(selectText: source.name) {[weak self] (_, name) in
                source.name = name
                self?.dataSource.replaceSubrange(indexPath.item...indexPath.item, with: [(type: .text, name: name)])
                collectionView.reloadItems(at: [indexPath])
            }
        }
        
        guard selectImageIndex != indexPath.item else {
            return
        }
        
        if let lastCell = collectionView.cellForItem(at: IndexPath(item: selectImageIndex, section: 0)) {
            lastCell.layer.borderWidth = 0
        }
        
        if let currentCell = collectionView.cellForItem(at: indexPath) {
            currentCell.layer.borderWidth = 0.6
        }
        selectImageIndex = indexPath.item
        
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - flowLayout.minimumInteritemSpacing * CGFloat(3) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(4)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header", for: indexPath) as! GroupAddHeaderView
        header.nameField.text = name
        header.delegate = self
        if group != nil {
            header.profileLabel.isHidden = true
            header.profileBtn.isHidden = true
            header.profileEditBtn.isHidden = true
        }else {
            header.profileBtn.setTitle(selectProfile.type.instruction.name, for: .normal)
        }
        headerView = header
        return header
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        
        return CGSize(width: collectionView.width, height: group != nil ? SCRYFrom(105) : SCRYFrom(186))
    }
    
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
    
}
 
extension GroupAddViewController: GroupAddHeaderViewDelegate {
    
    /// 名称编辑回调
    /// - Parameters:
    ///   - view: view
    ///   - name: 名称
    /// - Returns: 返回错误提示（可选）
    func view(_ view: GroupAddHeaderView, nameEditChanged name: String) -> String? {
        if name.count > 32 {
            self.doneBtn.isEnabled = false
            return "text_length_exceeded".localizedString
        }else if MeshNetworkManager.instance.isGroupTautonym(name: name) && name != self.group?.name {
            self.doneBtn.isEnabled = false
            return "name_already_exists".localizedString
        }
        if name.count > 0 && !name.isAllInputTextEmpty() {
            self.doneBtn.isEnabled = true
        }else {
            self.doneBtn.isEnabled = false
        }
        self.name = name
        return nil
    }
    
    /// 选择配置文件回调
    func headerViewDidSelectProfile(_ view: GroupAddHeaderView, profileRect: CGRect) {
        
//        let profileTypes: [Profile.ProfileType] = [.occupancy_daylight, .vacancy_daylight, .occupancy, .vacancy, .daylight, .manualControl]
        let names = profiles.map({ $0.type.instruction.name })
        let selectIndex = profiles.firstIndex(where: { $0.type == selectProfile.type }) ?? 0
//        view
        let viewPoint = collectionView.convert(CGPoint(x: profileRect.minX, y: profileRect.maxY + 2), from: view)
        let windowPoint = view.convert(viewPoint, to: UIApplication.shared.keyWindow())
        TitleSelectView.show(titles: names, anchorPoint: windowPoint, selectIndex: selectIndex, menuWidth: profileRect.size.width, titleColor: SubText_Color, titleFont: FONTS(SCRXFrom(12)), backgroundColor: .white, selectBackgroundColor: .clear, shadowColor: RGB(0, 0, 0, 0.1)) {[weak self] index in
            guard let self = self else { return }
            
            self.selectProfile = profiles[index]
            view.profileBtn.setTitle(names[index], for: .normal)
        }
        
    }
    
    /// 编辑配置文件回调
    func headerViewDidEditProfile(_ view: GroupAddHeaderView) {
        
        let vc = ProfileSettingsViewController(group: nil, profile: selectProfile)
        vc.saveActionCallback = {[weak self] profile in
            guard let self = self else { return nil }
            self.selectProfile = profile
            view.profileBtn.setTitle(profile.type.instruction.name, for: .normal)
            if let index = self.profiles.firstIndex(where: { $0.type == profile.type }) {
                self.profiles.replaceSubrange(index...index, with: [profile])
            }
            return nil
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
}


class GroupImageViewCell: UICollectionViewCell {
    
    var imageView: UIImageView!
    var nameLabel: UILabel!
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        
        layer.borderColor = Bar_Color.cgColor
        layer.borderWidth = 0
        clipsToBounds = true
        
        imageView = UIImageView()
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "A", textColor: RGB(20, 46, 79), fontSize: 36)
        nameLabel.font = UIFont.systemFont(ofSize: SCRYFrom(36), weight: .thin)
        nameLabel.isHidden = true
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = height * 0.5
    }
    
}
