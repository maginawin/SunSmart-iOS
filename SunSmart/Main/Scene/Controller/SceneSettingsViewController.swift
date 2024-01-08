//
//  SceneSettingsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/26.
//

import UIKit
import NordicSigMeshSDK

class SceneSettingsViewController: UIViewController {

    /// 模式
    enum Mode {
        /// 设置
        case settings
        /// 成员（创建场景后添加组）
        case members
    }
    
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    
    private var bottomView: UIView!
    private var syncBtn: UIButton!
    private var previewBtn: UIButton!
    
    let space: SpaceData
    let scene: Scene
    
    let mode: Mode
//    /// 场景更新回调
    var sceneUpdateCallback: ((Scene)->Void)?
//    /// 场景删除回调
//    var sceneDeleteCallback: ((Scene)->Void)?
    /// 选择的组
//    private var selectGroups: [Group] = []
    
    init(space: SpaceData, scene: Scene, mode: Mode = .settings) {
        self.space = space
        self.scene = scene
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()


        
        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        setupUI()
        updateEmptyUI()
        
        space.groups.forEach({
            if scene.info.groups.contains($0) {
                $0.isSelected = true
                $0.executeSceneData = $0.info.bindSceneDatas[scene.number]
//                    .first(where: { $0.key == scene.number })
            }else {
                $0.isSelected = false
                $0.executeSceneData = nil
            }
        })
        
        if mode == .members {
            title = "members".localizedString
            navigationItem.leftBarButtonItem = UIBarButtonItem()
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "done".localizedString, color: RGB(0, 0, 0, 0.85), font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(doneAction))
            bottomView.isHidden = true
        }else {
            
            title = "settings".localizedString
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "save".localizedString, color: RGB(0, 0, 0, 0.85), font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(saveAction))
//            selectGroups = scene.info.groups
            scene.info.groups.forEach({
//                if let group = space.groups.first(where: { $0.add })
                $0.isSelected = true
                $0.executeSceneData = $0.info.bindSceneDatas[scene.number]
            })
        }
        
    }
    
    /// 完成（添加成员模式）
    @objc private func doneAction() {
        
        // 获取已选择的组
        let selectGroups = space.groups.filter({ $0.isSelected && $0.executeSceneData != nil })
        // 有设备的组
        let existNodeGroups = selectGroups.filter({ $0.nodes.count > 0 })
        
        selectGroups.forEach({
            $0.info.bindSceneDatas.updateValue($0.executeSceneData!, forKey: scene.number)
            SceneExecuteData.save(meshUUID: space.meshUUID, address: $0.address.address, sceneId: Int(scene.number), sceneData: $0.executeSceneData!)
        })
        if existNodeGroups.isEmpty { // 都是空组
            scene.info.groups = selectGroups
            NotificationCenter.default.post(name: .init(scenesRefreshNotificationName), object: nil)
            dismiss(animated: true)
            
        }else { // 去同步
            
        }
        
    }
    
    /// 保存（设置模式）
    @objc private func saveAction() {
        
        // 获取已选择的组
        let selectGroups = space.groups.filter({ $0.isSelected && $0.executeSceneData != nil })
        // 有设备的组
        let existNodeGroups = selectGroups.filter({ $0.nodes.count > 0 })
       
        // 获取新增的组
        let addGroups = selectGroups.filter({ !scene.info.groups.contains($0) })
//        scene.info.groups.filter({ selectGroups.contains($0) })
        // 删除的组
        let deleteGroups = scene.info.groups.filter({ !selectGroups.contains($0) })
        // 修改数据的组
        let updateGroups = selectGroups.filter({ group in
            
            guard let oldData = group.info.bindSceneDatas[scene.number] else {
                return true
            }
            if scene.info.groups.contains(group), let newData = group.executeSceneData {
                return newData.lightness != oldData.lightness || newData.cct != oldData.cct
            }
            return false
        })
        
        addGroups.forEach({
            SceneExecuteData.save(meshUUID: space.meshUUID, address: $0.address.address, sceneId: Int(scene.number), sceneData: $0.executeSceneData!)
        })
        
        updateGroups.forEach({
            SceneExecuteData.save(meshUUID: space.meshUUID, address: $0.address.address, sceneId: Int(scene.number), sceneData: $0.executeSceneData!)
        })
        
        deleteGroups.filter({ $0.nodes.isEmpty }).forEach({
            SceneExecuteData.deleteData(meshUUID: space.meshUUID, address: $0.address.address, sceneId: Int(scene.number))
        })
        
        if existNodeGroups.isEmpty { // 都是空组
            scene.info.groups = selectGroups
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: scene)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
    }
    
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < space.groups.count {
            
            let group = space.groups[indexPath.item]
//            let data = group.info.bindSceneDatas.first(where: { $0.sceneId == scene.number })?.data
            updateGroupSceneExecuteData(group: group)
        }
        
    }
    
    /// 同步
    @objc private func syncBtnAction() {
        
        // 获取已选择的组
        let selectGroups = space.groups.filter({ $0.isSelected && $0.executeSceneData != nil })
        // 获取新增的组
        let addGroups = selectGroups.filter({ !scene.info.groups.contains($0) })
//        scene.info.groups.filter({ selectGroups.contains($0) })
        // 删除的组
        let deleteGroups = scene.info.groups.filter({ !selectGroups.contains($0) })
        // 修改数据的组
        let updateGroups = selectGroups.first { group in
            if scene.info.groups.contains(group), let oldData = group.info.bindSceneDatas[scene.number], let newDta = group.executeSceneData {
                return newDta.lightness != oldData.lightness || newDta.cct != oldData.cct
            }
            return false
        }

        
        
    }
    
    /// 预览
    @objc private func previewBtnAction() {
        // 有设备的组
        let controlGroups = space.groups.filter({ $0.isSelected && $0.nodes.count > 0 })
        if controlGroups.count > 0 {
            if MeshLibManager.manager.isMeshNetworkConnected {
                controlGroups.forEach({
                    if let data = $0.executeSceneData {
                        MeshAPI.setGroupCTLState(address: $0.address.address, lightness: Node.getLightness(lightness100: data.lightness), temperature: UInt16(data.cct))
                    }
                })
            }else {
                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            }
        }
    }
    
    /// 更新组的场景参数
    private func updateGroupSceneExecuteData(group: Group) {
        
        let data = group.executeSceneData
//        group.info.bindSceneDatas.first(where: { $0.sceneId == scene.number })?.data
        
        SceneExecuteDataPickerView.show(lightness: data?.lightness ?? 100, cct: data?.cct ?? 4500, showConfirm: false, showDelete: false) {[weak self] lightness, cct in
            guard let self = self else { return }
            if let sceneData = data { // 修改
                sceneData.lightness = lightness
                sceneData.cct = cct
            }else { // 新增
                group.executeSceneData = SceneExecuteData(lightness: lightness, cct: cct)
//                group.info.bindSceneDatas.append((self.scene.number, SceneExecuteData(lightness: lightness, cct: cct)))
            }
            group.isSelected = true
//            if !self.selectGroups.contains(group) {
//                self.selectGroups.append(group)
//            }
            if let index = self.space.groups.firstIndex(of: group) {
                CATransaction.setDisableActions(true)
                self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                CATransaction.commit()
            }else {
                self.collectionView.reloadData()
            }
        }
        
    }
    
    private func updateEmptyUI() {
        
        if space.groups.isEmpty {
            view.showEmptyDataView(title: "no_groups".localizedString, tipText: "scene_not_groups_message".localizedString, buttonText: "create_group".localizedString, buttomWidth: SCRXFrom(216), position: .center, bottomMargin: SCRYFit(50)) {
            }
            if let emptyView = view.emptyView {
                emptyView.tipLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
                emptyView.tipLabel.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(16))
                }
                
                emptyView.button.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
                emptyView.button.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                }
            }
            
            
        }else {
            view.hideEmptyDataView()
        }
        
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(44))
        }
        
        syncBtn = UIButton(title: "sync".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(30, 35, 41), normalImageName: "scene_sync", target: self, action: #selector(syncBtnAction))
        syncBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        bottomView.addSubview(syncBtn)
        syncBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(5))
        }
        
        previewBtn = UIButton(title: "preview".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(30, 35, 41), normalImageName: "scene_preview", target: self, action: #selector(previewBtnAction))
        previewBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        bottomView.addSubview(previewBtn)
        previewBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(SCRYFrom(5))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(13)
        flowLayout.minimumInteritemSpacing = SCRXFrom(13)
//        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: 0, right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(15), bottom: 0, right: SCRXFrom(15))
        collectionView.register(SceneMembersViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
     
        
    }


}

extension SceneSettingsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
   
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return space.groups.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SceneMembersViewCell
        let group = space.groups[indexPath.item]
        cell.updateData(group: group, sceneData: group.executeSceneData)
        if group.isSelected {
            cell.selectBtn.isSelected = true
            cell.progressView.isHidden = false
        }else {
            cell.selectBtn.isSelected = false
            cell.progressView.isHidden = true
        }
        
        cell.selectActionCallBack = {[weak self] isSelected in
            guard let self = self else { return }
            group.isSelected = isSelected
            if isSelected {
//                self.selectGroups.append(group)
                self.updateGroupSceneExecuteData(group: group)
//                cell.progressView.isHidden = false
            }else {
//                self.selectGroups.removeAll(where: { $0.address.address == group.address.address })
                cell.progressView.isHidden = true
            }
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * 2.0 - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / 3.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW + SCRYFrom(16))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
           
        let group = space.groups[indexPath.item]
        group.isOn = !group.isOn
        CATransaction.setDisableActions(true)
        collectionView.reloadItems(at: [indexPath])
        CATransaction.commit()
        if group.nodes.count > 0 {
            MeshAPI.getGroupOnOffState(address: group.address.address)
        }
        
    }
    
}

private extension Group {
    
    static var executeSceneDataKey = 1
    
    static var isSelectedKey = 2
    
    /// 赋值的场景数据
    var executeSceneData: SceneExecuteData? {
        get {
            objc_getAssociatedObject(self, &Group.executeSceneDataKey) as? SceneExecuteData
        }set {
            objc_setAssociatedObject(self, &Group.executeSceneDataKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否选中
    var isSelected: Bool {
        get {
            objc_getAssociatedObject(self, &Group.isSelectedKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &Group.isSelectedKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
