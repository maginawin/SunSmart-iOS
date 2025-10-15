//
//  ScheduleScenesView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/16.
//

import UIKit
import NordicSigMeshSDK

class ScheduleScenesView: UIView {

    /// 场景选择完成回调
    typealias SceneSelectFinishedCallback = ((Scene?)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var topBarView: UIView!
    private var titleLabel: UILabel!
    
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    private var bottomView: UIView!
    private var cancelBtn: UIButton!
    private var lineView: UIView!
    private var confirmBtn: UIButton!
    
    /// 场景list
    private let scenes: [Scene]
    /// 选中的场景
    private var selectScene: Scene?
    /// 日程（编辑时传入）
    private let schedule: Schedule?
    /// 选择场景完成回调
    private let selectCallback: SceneSelectFinishedCallback?
    /// 需要同步的场景list（编辑）
    private var syncScenes: [Scene] = []
    
    init(scenes: [Scene], selectScene: Scene?, schedule: Schedule? = nil, selectBack: SceneSelectFinishedCallback?) {
        self.scenes = scenes
        self.selectScene = selectScene
        self.schedule = schedule
        self.selectCallback = selectBack
        super.init(frame: UIScreen.main.bounds)
        
        if let schedule = self.schedule {
            if let scene = schedule.scene, scene.info.groups.contains(where: { $0.nodes.contains(where: { $0.schedulerActions[schedule.id] == nil || !($0.schedulerActions[schedule.id]! == schedule.schedulerEntry ) }) }) {
                syncScenes.append(scene)
            }
            syncScenes.append(contentsOf: schedule.needDeleteScenes)
        }
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
            layoutIfNeeded()
            if scenes.isEmpty {
                showEmptyUI()
            }
        }
        self.shadeView.alpha = 0
        self.contentView.y = height
        UIView.animate(withDuration: 0.3) {
            self.contentView.y = self.height - self.contentView.height
            self.shadeView.alpha = 1
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
        
        collectionView.showEmptyDataView(title: "no_scenes".localizedString, tipText: "no_scenes_message".localizedString, position: .center, bottomMargin: SCRYFit(45))
    }

    /// 取消
    @objc private func cancelBtnAction() {
        hide()
    }
    
    /// 确认
    @objc private func confirmBtnAction() {
        hide()
        selectCallback?(selectScene)
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
        collectionView.showsVerticalScrollIndicator = false
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
        
        titleLabel = UILabel(text: "scenes".localizedString, textColor: RGB(72, 72, 74), fontSize: 18)
        topBarView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
    }
    

}

extension ScheduleScenesView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return scenes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ScheduleGroupsViewCell
        let scene = scenes[indexPath.item]
        cell.nameLabel.text = scene.name
        cell.selectedImageView.image = UIImage(named: selectScene == scene ? "schedule_target_select" : "schedule_target_select_un")
        cell.onoffBtn.isHidden = true
        if schedule != nil {
            // 是否需要同步日程
            if syncScenes.contains(scene) {
                cell.failedImageView.isHidden = false
            }else {
                cell.failedImageView.isHidden = true
            }
        }else {
            cell.failedImageView.isHidden = true
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let itemW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        return CGSize(width: CGFloat(floorf(Float(itemW) * 100) / 100), height: SCRYFrom(44))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let scene = scenes[indexPath.item]
        selectScene = scene
        collectionView.reloadData()
    }
}
