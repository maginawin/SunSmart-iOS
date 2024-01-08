//
//  SceneAddViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/20.
//

import UIKit
import NordicSigMeshSDK

class SceneAddViewController: UIViewController {

    /// 创建方式
    enum CreateMode {
        /// 自定义
        case custom
        /// 模板
        case template
    }
    
    private var menuView: WMMenuView!
    private var scrollView: UIScrollView!
    private var customView: SceneAddCustomView!
    // 模板选择列表
    private var templatesTableView: UITableView!
    
    //***** 数据设置UI *****/
    private var templateLabel: UILabel!
    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    private var bottomView: UIView!
    private var saveBtn: UIButton!
    private var previewBtn: UIButton!
    /// 创建场景回调
    var createSceneCallback: ((Scene)->Void)?
    
    private var createMode: CreateMode = .custom
    
    private let titles = ["custom".localizedString, "templates".localizedString]
    private var iconImageNames: [String] {
        var imageNames: [String] = []
        for i in 1...16 {
            imageNames.append("scene_image_\(i)")
        }
        return imageNames
    }
    
    private var templates: [String] = [
        "Office", "School", "Medical treatment", "Industry", "Supermarket", "Warehouse", "Others"
    ]
    
    private var subTemplates : [String] = [
        "PPT", "Lecture", "Conference", "Work", "Lunch break", "Vacant", "Get off work", "Normal", "Focus"
    ]
    
    private var templateShowMap: [Int: Bool] = [:]
    
    let space: SpaceData
    var doneCallback: ((Group)->Void)?
    
    /// 场景执行数据list
    private var sceneDatas: [SceneExecuteData] = []
    private var sceneDataSelectIndex: Int?
    /// 模板默认场景执行数据list
    private var defalutSceneDatas: [SceneExecuteData] = [
        SceneExecuteData(lightness: 0, cct: 2200),
        SceneExecuteData(lightness: 50, cct: 4500),
        SceneExecuteData(lightness: 100, cct: 3000)
    ]
    
    private var imageId: Int = 1
    private var name: String?
    
    private var groups: [Group] = []
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "create_scene".localizedString
        
        view.backgroundColor = Background_Color
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        
        groups = space.groups
        
        groups.forEach({
            $0.executeSceneData = nil
            $0.isSelected = false
            $0.sceneDataIndex = nil
        })
        
        self.name = space.getNextSceneName()
        
        setupUI()
//        setupTemplateDataUI()

        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        for index in 0..<templates.count {
            templateShowMap.updateValue(false, forKey: index)
        }
        sceneDatas = defalutSceneDatas
        
    }
    
    @objc private func close() {
        
        dismiss(animated: true)
    }
    
    /// 预览
    @objc private func previewBtnAction() {
        
        groups.forEach({
            if let data = $0.executeSceneData {
                MeshAPI.setGroupCTLState(address: $0.address.address, lightness: Node.getLightness(lightness100: data.lightness), temperature: UInt16(data.cct))
            }
        })
        
    }
    
    /// 创建场景
    private func createScene() {
        
        let selectGroups = groups.filter({ $0.isSelected })
        // 组里是否存在设备
        if selectGroups.contains(where: { $0.nodes.count > 0 }) { // 同步数据
            if MeshLibManager.manager.isMeshNetworkConnected { // 去同步
                addSceneHandle()
            }else { // 未连接网络
                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            }
        }else { // 组内无设备
            addSceneHandle()
        }
        
    }
    
    private func addSceneHandle() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        MeshAPI.addOrEditScene(name: name) {[weak self] scene in
            XWHUDManager.hide()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            let selectGroups = groups.filter({ $0.isSelected })
            scene.info = .init(sceneId: scene.number, name: self.name, imageId: self.imageId, groups: selectGroups)
            scene.info.save(meshUUID: self.space.meshUUID)
            selectGroups.forEach({
                if let data = $0.executeSceneData {
                    SceneExecuteData.save(meshUUID: self.space.meshUUID, address: $0.address.address, sceneId: Int(scene.number), sceneData: data)
                }
            })
            self.createSceneCallback?(scene)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                guard let self = self else { return }
                if self.createMode == .custom {
                    let vc = SceneSettingsViewController(space: self.space, scene: scene, mode: .members)
                    self.navigationController?.pushViewController(vc, animated: true)
                }else {
                    self.close()
                }
            }
        
        } addFail: { _, _ in
            XWHUDManager.hide()
            XWHUDManager.showErrorTipHUD("failed".localizedString)
        }
        
    }
    
    // 保存
    @objc private func saveBtnAction() {
        createMode = .template
        createScene()
    }

    @objc private func hideKeyboard() {
        view.endEditing(true)
    }
    
    /// 更新预览按钮状态
    private func updatePreviewBtnState() {
        
        self.previewBtn.isEnabled = MeshLibManager.manager.isMeshNetworkConnected && groups.contains(where: { $0.isSelected && $0.executeSceneData != nil && $0.nodes.count > 0 })
        
    }
    
    private func showSceneDataUI() {
        
        menuView.isHidden = true
        scrollView.isHidden = true
        
        setupTemplateDataUI()
    }
    
    private func setupUI() {
        
        menuView = WMMenuView(frame: CGRectMake(0, navigationController?.navigationBar.height ?? 0, view.width, SCRYFrom(38)))
        menuView.style = .line
        menuView.layoutMode = .center
        menuView.lineColor = Bar_Color
        menuView.progressHeight = 2
        menuView.itemBackgroundColor = .clear
        menuView.dataSource = self
        menuView.delegate = self
        view.addSubview(menuView)
//        menuView.snp.makeConstraints { make in
//            make.left.right.equalToSuperview()
//            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
//            make.height.equalTo(SCRYFrom(38))
//        }
        
        scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(menuView.frame.maxY + SCRYFrom(17))
        }
        
        customView = SceneAddCustomView(frame: .zero, name: name, imageNames: iconImageNames)
//        customView.createBtn.addTarget(self, action: #selector(createAction), for: .touchUpInside)
        customView.delegate = self
        scrollView.addSubview(customView)
        customView.snp.makeConstraints { make in
            make.left.top.bottom.width.height.equalToSuperview()
        }
        
        templatesTableView = UITableView(frame: .zero, style: .grouped)
        templatesTableView.backgroundColor = .white
        templatesTableView.separatorStyle = .none
        templatesTableView.register(SceneAddTemplateTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        templatesTableView.register(SceneAddTemplateTitleCell.classForCoder(), forCellReuseIdentifier: "cell")
        templatesTableView.dataSource = self
        templatesTableView.delegate = self
        scrollView.addSubview(templatesTableView)
        templatesTableView.snp.makeConstraints { make in
            make.left.equalTo(customView.snp.right)
            make.right.bottom.width.height.equalToSuperview()
        }
        
        
    }
    
    private func setupTemplateDataUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        let lineView = UIView()
        lineView.backgroundColor = RGB(243, 243, 243)
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
            make.width.equalTo(1)
        }
        
        previewBtn = UIButton(title: "PREVIEW".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(previewBtnAction))
        previewBtn.setTitleColor(RGB(156, 163, 175), for: .disabled)
        previewBtn.isEnabled = false
        bottomView.addSubview(previewBtn)
        previewBtn.snp.makeConstraints { make in
            make.right.equalTo(lineView.snp.left).offset(SCRXFrom(-33))
            make.width.equalTo(SCRXFrom(120))
            make.centerY.height.equalTo(lineView)
        }
        
        saveBtn = UIButton(title: "save".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(saveBtnAction))
        saveBtn.setTitleColor(RGB(156, 163, 175), for: .disabled)
        bottomView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.left.equalTo(lineView.snp.right).offset(SCRXFrom(33))
            make.width.height.centerY.equalTo(previewBtn)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(SceneAddTemplateInfoSectionView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "infoSection")
        collectionView.register(SceneAddGroupTitleSectionView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "titleSection")
        collectionView.register(SceneAddDataListViewCell.classForCoder(), forCellWithReuseIdentifier: "dataCell")
        collectionView.register(SceneAddGroupViewCell.classForCoder(), forCellWithReuseIdentifier: "groupCell")
        collectionView.register(SceneAddGroupEmptyCell.classForCoder(), forCellWithReuseIdentifier: "groupEmptyCell")
//        collectionView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
//        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        
    }
    
}

extension SceneAddViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return templates.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (templateShowMap[section] ?? false) ? subTemplates.count : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SceneAddTemplateTitleCell
        cell.titleLabel.text = subTemplates[indexPath.row]
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! SceneAddTemplateTitleHeaderView
        headerView.nameLabel.text = templates[section]
        headerView.isShow = templateShowMap[section] ?? false
        headerView.showHideCallback = {[weak self] isShow in
            self?.templateShowMap.updateValue(isShow, forKey: section)
            tableView.reloadSections(IndexSet(integer: section), with: .automatic)
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        showSceneDataUI()
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == self.scrollView else {
            return
        }
        let progress = scrollView.contentOffset.x / scrollView.width
        menuView.slideMenu(atProgress: progress)
    }
    
}

extension SceneAddViewController: WMMenuViewDataSource, WMMenuViewDelegate {
    
    func numbersOfTitles(in menu: WMMenuView!) -> Int {
        return titles.count
    }
    
    func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return titles[index]
    }
    
    func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
        return 15
    }
    
    func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
        return state == .selected ? Bar_Color : Title_Color
    }
    
    func menuView(_ menu: WMMenuView!, widthForItemAt index: Int) -> CGFloat {
        
        let title = menuView(menu, titleAt: index) ?? ""
        return (title as NSString).size(withAttributes: [.font: FONTS(15)]).width
    }
    
    func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
        return SCRXFrom(54)
    }
    
    func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        scrollView.setContentOffset(CGPoint(x: CGFloat(index) * scrollView.width, y: 0), animated: true)
    }
}

extension SceneAddViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        case 1:
            return groups.isEmpty ? 1 : groups.count
        default:
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if indexPath.section == 0 {
            let dataCell = collectionView.dequeueReusableCell(withReuseIdentifier: "dataCell", for: indexPath) as! SceneAddDataListViewCell
            dataCell.sceneDatas = sceneDatas
            dataCell.selectIndex = sceneDataSelectIndex
            dataCell.delegate = self
            return dataCell
        }else if groups.isEmpty {
            
            let groupEmptyCell = collectionView.dequeueReusableCell(withReuseIdentifier: "groupEmptyCell", for: indexPath) as! SceneAddGroupEmptyCell
            groupEmptyCell.delegate = self
            return groupEmptyCell
            
        }else {
            let group = groups[indexPath.item]
            let groupCell = collectionView.dequeueReusableCell(withReuseIdentifier: "groupCell", for: indexPath) as! SceneAddGroupViewCell
            groupCell.nameLabel.text = group.info.name
            groupCell.selectBtn.isSelected = group.isSelected
            // 是否选中参数
            if sceneDataSelectIndex != nil, MeshLibManager.manager.isMeshNetworkConnected, group.nodes.count > 0 {
                groupCell.onoffBtn.isHidden = false
            }else {
                groupCell.onoffBtn.isHidden = true
            }
            groupCell.onoffBtn.isSelected = group.isOn
            // 赋值的参数
            if let data = group.executeSceneData, group.isSelected {
                if data.lightness > 0 {
                    groupCell.dataLabel.text = "\(data.lightness)% | \(data.cct)K"
                }else {
                    groupCell.dataLabel.text = "off".localizedString
                }
            }else {
                groupCell.dataLabel.text = nil
            }
            groupCell.delegate = self
            return groupCell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let itemW = collectionView.width
        if indexPath.section == 0 {
            let count = min(sceneDatas.count + 1, 8)
            let row = ceil(Float(count) / 4.0)
            return CGSize(width: itemW, height: CGFloat(max(row, 1)) * SCRYFrom(96))
        }else if indexPath.section == 1 && groups.isEmpty {
            return CGSize(width: collectionView.width, height: SCRYFrom(170))
        }else {
            return CGSize(width: itemW, height: SCRYFrom(44))
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if indexPath.section == 0 {
            let infoView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "infoSection", for: indexPath) as! SceneAddTemplateInfoSectionView
            infoView.delegate = self
            infoView.iconImageBtn.setImage(UIImage(named: iconImageNames[imageId - 1]), for: .normal)
            infoView.name = name
            return infoView
        }else {
            let titleView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "titleSection", for: indexPath) as! SceneAddGroupTitleSectionView
            return titleView
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        if section == 0 {
            return CGSize(width: collectionView.width, height: SCRYFrom(162))
        }else {
            return CGSize(width: collectionView.width, height: SCRYFrom(40))
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        
        if indexPath.section == 1 {
            let itemCount = collectionView.numberOfItems(inSection: indexPath.section)
            let cornerSize = CGSize(width: SCRYFrom(10), height: SCRYFrom(10))
            if itemCount == 1 {
                cell.addRoundedCorners(corners: .allCorners, cornerRadii: cornerSize)
            }else if indexPath.row == 0 {
                cell.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: cornerSize)
            }else if indexPath.row == itemCount - 1 {
                cell.addRoundedCorners(corners: [.bottomLeft, .bottomRight], cornerRadii: cornerSize)
            }else {
                cell.layer.mask = nil
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        hideKeyboard()
        
        if groups.isEmpty {
            return
        }
        
        guard let index = self.sceneDataSelectIndex, index >= 0, index < sceneDatas.count else {
            XWHUDManager.showTipHUD("scene_select_parameter_message".localizedString, isLineFeed: true)
            return
        }
        let group = groups[indexPath.item]
        if group.sceneDataIndex == index { // 同一个参数，反选
            group.executeSceneData = nil
            group.sceneDataIndex = nil
            group.isSelected = false
        }else {
            let data = sceneDatas[index]
            group.executeSceneData = .init(lightness: data.lightness, cct: data.cct)
            group.sceneDataIndex = index
            group.isSelected = true
            if group.nodes.count > 0 {
                if MeshLibManager.manager.isMeshNetworkConnected {
                    MeshAPI.setGroupCTLState(address: group.address.address, lightness: Node.getLightness(lightness100: data.lightness), temperature: UInt16(data.cct))
                }else {
                    XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                }
            }
        }
        collectionView.reloadItems(at: [indexPath])
        
        updatePreviewBtnState()
    }
    
}

extension SceneAddViewController: SceneAddCustomViewDelegate {
    
    /// 编辑名称回调
    /// - Parameters:
    ///   - name: 名称
    func view(_ view: SceneAddCustomView, didNameEditChanged name: String) -> String? {
        
        self.name = name
        if name.count > 32 {
            view.createBtn.isEnabled = false
            return "text_length_exceeded".localizedString
        } else if space.isSceneTautonym(name: name) { // 重名
            view.createBtn.isEnabled = false
            return "name_already_exists".localizedString
        }
        if name.count > 0 && !name.isAllInputTextEmpty() {
            view.createBtn.isEnabled = true
        }else {
            view.createBtn.isEnabled = false
        }
        return nil
        
    }

    /// 点击创建回调
    func customViewDidCreateAction(_ view: SceneAddCustomView) {
        self.imageId = view.selectImageIndex + 1
        createMode = .custom
        createScene()
    }
    
}

extension SceneAddViewController: SceneAddTemplateInfoSectionViewDelegate {
    /// 图标点击回调
    func sectionViewDidImageAction(_ sectionView: SceneAddTemplateInfoSectionView) {
        let vc = ImagesPickerViewController(imageNames: iconImageNames) {[weak self] imageId in
            guard let self = self else { return }
            self.imageId = imageId + 1
            self.collectionView.reloadSections(IndexSet(integer: 0))
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 重置点击回调
    func sectionViewDidResetAction(_ sectionView: SceneAddTemplateInfoSectionView) {
        hideKeyboard()
        // 场景数据是否修改
        var valueEdit = false
        if sceneDatas.count == defalutSceneDatas.count {
            for (index, data) in sceneDatas.enumerated() {
                if defalutSceneDatas[index].lightness != data.lightness || defalutSceneDatas[index].cct != data.cct {
                    valueEdit = true
                    break
                }
            }
        }else {
            valueEdit = true
        }
        
        guard self.name != self.space.getNextSceneName() || self.imageId != 1 || valueEdit else {
            return
        }
        
        SRAlertView(title: "notification".localizedString, message: "scene_parameter_reset_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            self.name = self.space.getNextSceneName()
            self.imageId = 1
            self.sceneDatas = self.defalutSceneDatas
            self.sceneDataSelectIndex = nil
            self.groups.forEach({
                $0.isSelected = false
                $0.executeSceneData = nil
            })
            self.collectionView.reloadData()
        })]).show()
        
    }
    
    /// 名称修改回调
    /// - Parameters:
    ///   - name: 输入文本
    /// - Returns: 提示内容（不合法）
    func sectionView(_ sectionView: SceneAddTemplateInfoSectionView, didNameChanged name: String) -> String? {
        self.name = name
        if name.count > 32 {
            saveBtn.isEnabled = false
            return "text_length_exceeded".localizedString
        } else if space.isSceneTautonym(name: name) { // 重名
            saveBtn.isEnabled = false
            return "name_already_exists".localizedString
        }
        if name.count > 0 && !name.isAllInputTextEmpty() {
            saveBtn.isEnabled = true
        }else {
            saveBtn.isEnabled = false
        }
        return nil
    }
    
    
}

extension SceneAddViewController: SceneAddDataListViewCellDelegate {
    
    /// 选择数据回调
    func cell(_ cell: SceneAddDataListViewCell, didSelectData index: Int) {
        hideKeyboard()
        sceneDataSelectIndex = index
        collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
    }
    
    /// 长按编辑数据回调
    func cell(_ cell: SceneAddDataListViewCell, didLongPressData index: Int) {
        hideKeyboard()
        let data = sceneDatas[index]
        SceneExecuteDataPickerView.show(lightness: data.lightness, cct: data.cct) {[weak self] lightness, cct in
            guard let self = self else { return }
            data.lightness = lightness
            data.cct = cct
//            let data = SceneExecuteData(lightness: lightness, cct: cct)
//            self.sceneDatas.replaceSubrange(index...index, with: [data])
            self.collectionView.reloadData()
//            self.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
        } delete: {[weak self] in
            guard let self = self else { return }
            self.sceneDatas.remove(at: index)
            if index == self.sceneDataSelectIndex {
                self.sceneDataSelectIndex = nil
            }
            self.collectionView.reloadData()
        }
    }
    
    /// 新增数据回调
    func cellDidAddAction(_ cell: SceneAddDataListViewCell) {
        hideKeyboard()
        SceneExecuteDataPickerView.show(showDelete: false) {[weak self] lightness, cct in
            let data = SceneExecuteData(lightness: lightness, cct: cct)
            self?.sceneDatas.append(data)
            self?.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
        }
    }
    
}

extension SceneAddViewController: SceneAddGroupViewCellDelegate {
    
    /// group选中事件回调
    /// - Parameters:
    ///   - isSelected: 是否选中
//    func cell(_ cell: SceneAddGroupViewCell, didSelectAction isSelected: Bool) {
//        
//        guard let indexPath = collectionView.indexPath(for: cell) else { return }
//        let group = groups[indexPath.item]
//        if isSelected {
//            guard let index = self.sceneDataSelectIndex, index >= 0, index < sceneDatas.count else {
//                XWHUDManager.showTipHUD("scene_select_parameter_message".localizedString, isLineFeed: true)
//                return
//            }
//            let data = sceneDatas[index]
//            group.executeSceneData = .init(lightness: data.lightness, cct: data.cct)
//            
//            if group.nodes.count > 0 {
//                MeshAPI.setGroupCTLState(address: group.address.address, lightness: Node.getLightness(lightness100: data.lightness), temperature: UInt16(data.cct))
//            }
//            
//        }else {
//            group.executeSceneData = nil
//        }
//        group.isSelected = isSelected
//        collectionView.reloadItems(at: [indexPath])
//        
//        updatePreviewBtnState()
//    }
    
    /// group开关事件回调
    /// - Parameters:
    ///   - isOn: 是否开启
    func cell(_ cell: SceneAddGroupViewCell, didOnOffAction isOn: Bool) {
        
        guard MeshLibManager.manager.isMeshNetworkConnected, let indexPath = collectionView.indexPath(for: cell) else { return }
        let group = groups[indexPath.item]
        guard group.nodes.count > 0 else {
            return
        }
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: isOn)
        cell.onoffBtn.isSelected = isOn
    }
    
    /// group长按事件回调
//    func cellDidLongPressAction(_ cell: SceneAddGroupViewCell) {
        
        
        
//        SceneExecuteDataPickerView.show(lightness: <#T##Int#>, cct: <#T##Int#>, showDelete: <#T##Bool#>, picker: <#T##SceneExecuteDataPickerView.DataPickerCallback?##SceneExecuteDataPickerView.DataPickerCallback?##(Int, Int) -> Void#>)
//        
//        SceneExecuteDataPickerView.show(lightness: data.lightness, cct: data.cct) {[weak self] lightness, cct in
//            
//        },
        
//    }
    
}

extension SceneAddViewController: SceneAddGroupEmptyCellDelegate {
    
    /// 创建组回调
    func cellDidCreateGroupAction(_ cell: SceneAddGroupEmptyCell) {
        hideKeyboard()
        let groupAddVc = GroupAddViewController(space: space)
        groupAddVc.doneCallback = {[weak self] group in
            self?.groups = [group]
            self?.collectionView.reloadSections(IndexSet(integer: 1))
        }
        present(NavigationViewController(rootViewController: groupAddVc), animated: true)
        
    }
    
}

  
private extension Group {
    
    static var executeSceneDataKey = 1
    
    static var isSelectedKey = 2
    
    static var sceneDataIndexKey = 3
    
    /// 赋值的场景数据
    var executeSceneData: SceneExecuteData? {
        get {
            objc_getAssociatedObject(self, &Group.executeSceneDataKey) as? SceneExecuteData
        }set {
            objc_setAssociatedObject(self, &Group.executeSceneDataKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 场景数据对应索引
    var sceneDataIndex: Int? {
        get {
            objc_getAssociatedObject(self, &Group.sceneDataIndexKey) as? Int
        }set {
            objc_setAssociatedObject(self, &Group.sceneDataIndexKey, newValue, .OBJC_ASSOCIATION_RETAIN)
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
