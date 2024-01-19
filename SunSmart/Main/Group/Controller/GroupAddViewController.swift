//
//  GroupAddViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/11.
//

import UIKit
import NordicSigMeshSDK

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
    
    private var name: String?
    
    let space: SpaceData
//    var doneCallback: ((Group)->Void)?
    /// 传入组则编辑
    var group: Group?
    
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
        
        if presentationController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        setupUI()
        
        for i in 1...18 {
            if i == 2 {
                dataSource.append((type: .text, name: "A"))
            }else {
                dataSource.append((type: .image, name: "group_image_\(i)"))
            }
        }
        
        if let group = self.group {
            name = group.name
            title = "edit_group".localizedString
            
            doneBtn.setTitle("done".localizedString, for: .normal)
        }else {
            name = space.getNextGroupName()
            title = "create_group".localizedString
        }
//        if isAdd {
//            doneBtn.setTitle("add".localizedString, for: .normal)
//        }
//        nameField.text = name
    }
    
    @objc private func close() {
        if presentationController != nil {
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
            return
        }
        
        if self.group != nil { // 编辑
            self.group?.name = name
            _ = MeshNetworkManager.instance.save()
            finnished()
            close()
            NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: self.group!)
            
        }else { // 新增
            
            MeshAPI.createGroup(name: name) {[weak self] group in
                guard let self = self else { return }
                self.group = group
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self.finnished()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                    guard let self = self else { return }
                    let memberVc = GroupMembersViewController(space: self.space, group: group)
                    memberVc.isAddDevices = true
                    self.navigationController?.pushViewController(memberVc, animated: true)
                    
                    NotificationCenter.default.post(name: .init(groupsRefreshNotificationName), object: nil)
//                    self.navigationController?.removeVc(vc: self)
                }
                
            } fail: { _, error in
                XWHUDManager.showTipHUD("failed".localizedString)
                return
            }
        }
       
    }
    
    private func finnished() {
        
        guard let name = self.name, let group = self.group else {
            close()
            return
        }
        
        let source = self.dataSource[self.selectImageIndex]
        let groupInfo = GroupInfo(address: group.address.address, name: name, imageId: self.selectImageIndex + 1, imageText: source.type == .text ? source.name : nil)
        groupInfo.save(meshUUID: space.meshUUID)
        group.info = groupInfo
//        self.doneCallback?(group)
    }
    
    private func setupUI() {

        footerView = UIView()
        footerView.backgroundColor = .white
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
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
        
        doneBtn = UIButton(title: "create".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(doneBtnClick))
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
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(GroupAddHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collectionView.register(GroupImageViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
//            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
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
            currentCell.layer.borderWidth = 0.5
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
        header.nameEditChangedCallback = {[weak self] name in
            guard let self = self else { return nil }
            if name.count > 32 {
                self.doneBtn.isEnabled = false
                return "text_length_exceeded".localizedString
            }else if self.space.isGroupTautonym(name: name) && name != self.group?.name {
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
        if group != nil {
            header.profileLabel.isHidden = true
            header.profileBtn.isHidden = true
            header.profileEditBtn.isHidden = true
        }
        return header
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        
        return CGSize(width: collectionView.width, height: group != nil ? SCRYFrom(105) : SCRYFrom(186))
    }
    
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
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
