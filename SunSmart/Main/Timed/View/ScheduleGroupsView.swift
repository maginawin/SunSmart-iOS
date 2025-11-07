//
//  ScheduleGroupsView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/16.
//

import UIKit
import NordicSigMeshSDK

class ScheduleGroupsView: UIView {

    /// 组选择完成回调
    typealias GroupsSelectFinishedCallback = (([Group])->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var topBarView: UIView!
    private var titleLabel: UILabel!
    private var selectAllBtn: UIButton!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var bottomView: UIView!
    private var cancelBtn: UIButton!
    private var lineView: UIView!
    private var confirmBtn: UIButton!
    
    /// 组list
    let groups: [Group]
    /// 选中的组list
    var selectGroups: [Group]
    /// 日程（编辑时传入）
    let schedule: Schedule?
    /// 选择组完成回调
    private let selectCallback: GroupsSelectFinishedCallback?
    
    private var meshNetworkConnectedObservation: NSKeyValueObservation?
    
    init(groups: [Group], selectGroups: [Group], schedule: Schedule? = nil, selectBack: GroupsSelectFinishedCallback?) {
        self.groups = groups
        self.selectGroups = selectGroups
        self.schedule = schedule
        self.selectCallback = selectBack
        super.init(frame: UIScreen.main.bounds)
        
        setupUI()
        addObserver()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        meshNetworkConnectedObservation = nil
    }
    
    private func addObserver() {
        
        // mesh网络连接观察者
        meshNetworkConnectedObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                self?.collectionView.reloadData()
            }
        })
    }
    
    func show() {
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
            layoutIfNeeded()
            if groups.isEmpty {
                showEmptyUI()
            }
        }
        self.shadeView.alpha = 0
        self.contentView.y = height
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = self.height - self.contentView.height
            self.shadeView.alpha = 1
        } completion: { _ in
            if self.collectionView.firstShowFlashScrollIndicators {
                self.collectionView.flashScrollIndicatorsIfNeeded()
            }
        }
    }
    
    private func hide() {
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.y = self.height
        } completion: { _ in
            self.removeFromSuperview()
        }

    }
    
    private func showEmptyUI() {
        
        collectionView.showEmptyDataView(title: "no_groups".localizedString, tipText: "scene_not_groups_message".localizedString, position: .center, bottomMargin: SCRYFit(45))
    }
    
    
    /// 全选
    @objc private func selectAllBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            self.selectGroups = self.groups
        }else {
            self.selectGroups.removeAll()
        }
        collectionView.reloadData()
    }
    
    /// 取消
    @objc private func cancelBtnAction() {
        hide()
    }
    
    /// 确认
    @objc private func confirmBtnAction() {
        hide()
        selectGroups.sort(by: { $0.address.address < $1.address.address })
        selectCallback?(selectGroups)
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancelBtnAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(SCRYFrom(24) + kNavigationHeight)
        }
        
        bottomView = UIView()
        bottomView.backgroundColor = Background_Color
        bottomView.layer.cornerRadius = SCRYFrom(15)
        contentView.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(-34)
            make.height.equalTo(SCRYFrom(60))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(216, 216, 216)
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(24))
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 16, titleWeight: .light, titleColor: RGB(72, 72, 74), target: self, action: #selector(cancelBtnAction))
        bottomView.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.right.equalTo(lineView.snp.left)
        }
        
        confirmBtn = UIButton(title: "confirm".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bottom_Done_Color, target: self, action: #selector(confirmBtnAction))
        bottomView.addSubview(confirmBtn)
        confirmBtn.snp.makeConstraints { make in
            make.left.equalTo(lineView.snp.right)
            make.top.bottom.right.equalToSuperview()
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(8)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
//        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(60), left: SCRXFrom(16), bottom: SCRXFrom(16), right: SCRXFrom(16))
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = Background_Color
        collectionView.layer.cornerRadius = SCRYFrom(15)
        collectionView.alwaysBounceVertical = true
        collectionView.register(ScheduleGroupsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top).offset(SCRYFrom(-8))
        }
        
        topBarView = UIView()
        topBarView.backgroundColor = Background_Color
        topBarView.layer.cornerRadius = SCRYFrom(15)
        contentView.addSubview(topBarView)
        topBarView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(53))
        }
        
        titleLabel = UILabel(text: "groups".localizedString, textColor: RGB(72, 72, 74), fontSize: 18)
        topBarView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        selectAllBtn = UIButton(title: "select_all".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(39, 37, 54), normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        selectAllBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        selectAllBtn.isHidden = groups.isEmpty
        topBarView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-23))
            make.centerY.equalTo(titleLabel)
        }
        
    }
    
    
}

extension ScheduleGroupsView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return groups.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ScheduleGroupsViewCell
        let group = groups[indexPath.item]
        cell.nameLabel.text = group.name
        cell.selectedImageView.image = UIImage(named: selectGroups.contains(group) ? "device_select" : "device_select_un")
        if group.nodes.isEmpty || !group.nodes.contains(where: { $0.state }) {
//            cell.onoffBtn.isEnabled = false
            cell.onoffBtn.setImage(UIImage(named: "scene_group_disable"), for: .normal)
        }else {
//            cell.onoffBtn.isEnabled = true
            cell.onoffBtn.setImage(UIImage(named: "scene_group_off"), for: .normal)
            cell.onoffBtn.isSelected = group.isOn
        }
        if let schedule = schedule {
            let result = group.getNeedSyncScheduleDataNodes(schedule)
            cell.failedImageView.isHidden = result.syncNodes.isEmpty && result.deleteNodes.isEmpty
        }else {
            cell.failedImageView.isHidden = true
        }
        
        cell.onoffCallback = { isOn in
            if group.nodes.count > 0 && group.nodes.contains(where: { $0.state }) {
                cell.onoffBtn.isSelected = isOn
                group.isOn = isOn
                MeshAPI.setGroupOnOffState(address: group.address.address, isOn: isOn)
            }
        }
//        group.getNeedSyncDataNodes(scene: <#T##Scene#>)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let itemW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        return CGSize(width: CGFloat(floorf(Float(itemW) * 100) / 100), height: SCRYFrom(44))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let group = groups[indexPath.item]
        if selectGroups.contains(group) {
            selectGroups.removeAll(where: { $0.address.address == group.address.address })
        }else {
            selectGroups.append(group)
        }
        selectAllBtn.isSelected = selectGroups.count == groups.count
        if let cell = collectionView.cellForItem(at: indexPath) as? ScheduleGroupsViewCell {
            cell.selectedImageView.image = UIImage(named: selectGroups.contains(group) ? "device_select" : "device_select_un")
        }
    }
    
}


class ScheduleGroupsViewCell: UICollectionViewCell {
    
    var selectedImageView: UIImageView!
    var nameLabel: UILabel!
    var failedImageView: UIImageView!
    var onoffBtn: UIButton!
    /// onoff事件回调
    var onoffCallback: ((Bool)->Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func onoffBtnAction(sender: UIButton) {
        onoffCallback?(!sender.isSelected)
    }
    
    private func setupUI() {
        
        selectedImageView = UIImageView(image: UIImage(named: "device_select_un"))
        contentView.addSubview(selectedImageView)
        selectedImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "Group 0", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(selectedImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.width.lessThanOrEqualTo(SCRXFrom(220))
        }
        
        failedImageView = UIImageView(image: UIImage(named: "sync_failed"))
        contentView.addSubview(failedImageView)
        failedImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-56))
            make.centerY.equalToSuperview()
        }
        
        onoffBtn = UIButton(normalImageName: "scene_group_off", selectedImageName: "scene_group_on", target: self, action: #selector(onoffBtnAction))
        onoffBtn.setImage(UIImage(named: "scene_group_disable"), for: .disabled)
        contentView.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-10))
            make.centerY.equalToSuperview()
        }
        
    }
    
}
