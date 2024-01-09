//
//  GroupsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/11.
//

import UIKit
import NordicSigMeshSDK

class GroupsViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    
    let space: SpaceData
    /// 底部
    private var footerView: SpaceFunctionFooterView!
    // 编辑
    private var editView: UIView!
    private var doneBtn: UIButton!
    /// 是否需要更新数据源
    private var refreshData: Bool = false
    
    private var isEdit: Bool = false
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupUI()
        
        footerView.countBtn.setTitle("\(space.groups.count)/16", for: .normal)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if refreshData {
            refreshData = false
            collectionView.reloadData()
            updateGroupesEmptyUI()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        updateGroupesEmptyUI()
    }
    
    /// 长按事件，跳转到组详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < space.groups.count {
            let group = space.groups[indexPath.item]
            
            let groupVc = GroupViewController(space: space, group: group)
            groupVc.groupDeleteCallback = {[weak self] _ in
    //            self?.refreshData = true
                self?.collectionView.reloadData()
            }
            groupVc.groupUpdateCallback = {[weak self] _ in
    //            self?.refreshData = true
                self?.collectionView.reloadData()
                self?.updateGroupesEmptyUI()
            }
            let navVc = NavigationViewController(rootViewController: groupVc)
            present(navVc, animated: true)
        }
    }
    
    private func deleteGroup(group: Group) {
        
        SRAlertView(title: "notification".localizedString, message: "group_delete_message".localizedString, messageFont: FONTS(15), actions: [.cancelAction, SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
         
            guard group.nodes.isEmpty || group.nodes.contains(where: { $0.state }) else { // 设备是否都在线
                SRAlertView(title: "notification".localizedString, message: "group_delete_message".localizedString, actions:[SRAlertAction(title: "confirm".localizedString, actionHandler: nil)]).show()
                return
            }
            
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            GroupServer.deleteGroup(group: group, progress: nil) {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self?.collectionView.reloadData()
                
            } failed: {[weak self] _ in
                
                XWHUDManager.showErrorTipHUD("group_delete_failed".localizedString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    XWHUDManager.hide()
                    // 跳转到检查页面
                    self?.deleteFailedCheck(group: group)
                }
            }
            
        })]).show()
    }
    
    /// 删除失败检查设备
    private func deleteFailedCheck(group: Group) {
        
        let checkVc = GroupCheckViewController(group: group, nodes: group.nodes)
        navigationController?.pushViewController(checkVc, animated: true)
    }
    
    /// 编辑完成
    @objc private func doneBtnAction() {
        isEdit = false
        updateUI()
    }
    
    /// 刷新UI
    private func updateUI() {
        
        if isEdit {
            editView.isHidden = false
            footerView.isHidden = true
        }else {
            editView.isHidden = true
            footerView.isHidden = false
        }
        collectionView.reloadData()
    }
  
    /// 更新空页面UI
    private func updateGroupesEmptyUI() {
        
        if space.groups.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }

//            collectionView.showEmptyDataView(title: "no_devices".localizedString, tipText: "no_devices_message".localizedString)
//            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            
            collectionView.showEmptyDataView(imageName: "group_empty", title: "no_groups".localizedString, tipText: nil)
            if let emptyView = collectionView.emptyView {
                emptyView.contentView.snp.remakeConstraints({ make in
                    make.top.equalTo(SCRYFrom(39))
                    make.left.equalTo(SCRXFrom(20))
                    make.right.equalTo(-SCRXFrom(20))
                })
                emptyView.imageView.snp.remakeConstraints { make in
                    make.top.equalToSuperview()
                    make.centerX.equalToSuperview()
                    make.left.equalTo(SCRXFrom(-11))
                    make.right.equalTo(SCRXFrom(11))
                    make.height.equalTo(emptyView.snp.width).multipliedBy(298.0 / 353)
                }
                emptyView.titleLabel.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.imageView.snp.bottom).offset(SCRYFrom(9))
                }
                
                let attStr = NSAttributedString(string: "no_groups_message".localizedString)
                emptyView.tipLabel.attributedText = attStr
            }
            
            
            footerView.editBtn.isHidden = true
        }else {
            collectionView.hideEmptyDataView()

            footerView.editBtn.isHidden = false
        }
    }
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        editView = UIView()
        editView.backgroundColor = .white
        editView.isHidden = true
        view.addSubview(editView)
        editView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }
        
        doneBtn = UIButton(title: "done".localizedString, titleSize: 16, titleColor: Title_Color, target: self, action: #selector(doneBtnAction))
        editView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
//        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: 0, right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: 0, right: SCRXFrom(12))
        collectionView.register(GroupsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(footerView.snp.top)
        }
    }
    
    
}

extension GroupsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return space.groups.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupsViewCell
        let group = space.groups[indexPath.item]
        if let text = group.info.imageText, text.count > 0 {
            cell.imageLabel.isHidden = false
            cell.imageLabel.text = text
            cell.imageView.isHidden = true
        }else {
            cell.imageLabel.isHidden = true
            cell.imageView.isHidden = false
            cell.imageView.image = UIImage(named: "group_image_\(group.info.imageId)") //device_light_offline
        }
        cell.nameLabel.text = group.name
        cell.deleteBtn.isHidden = !isEdit
        cell.deleteActionCallback = {[weak self] in
            self?.deleteGroup(group: group)
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * 2.0 - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / 3.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
//        let group = space.groups[indexPath.item]
//        if group.nodes.count > 0 {
//            MeshAPI.getGroupOnOffState(address: group.address.address)
//        }
        
    }
    
}

extension GroupsViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
        guard self.space.groups.count < 16 else { return }
        
        let vc = GroupAddViewController(space: space)
        vc.doneCallback = {[weak self] group in
            guard let self = self else { return }
            self.collectionView.reloadData()
            self.space.groupCount = self.space.groups.count
            self.space.save()
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        
        isEdit = editing
        view.isEditing = false
        updateUI()
    }
}

