//
//  SceneAddViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/20.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

private final class SceneAddPagingScrollView: UIScrollView, UIGestureRecognizerDelegate {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isDirectionalLockEnabled = true
        panGestureRecognizer.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGestureRecognizer,
              let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        let velocity = panGestureRecognizer.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }
}

class SceneAddViewController: UIViewController {
    private var templatePicker: SceneExecuteDataPickerView?
    private var backgroundObserver: NSObjectProtocol?

    /// 创建方式
    enum CreateMode {
        /// 自定义
        case custom
        /// 模板
        case template
    }
    
    private var menuView: WMMenuView!
    private var menuLayoutSize: CGSize = .zero
    private var scrollView: UIScrollView!
    private var customView: SceneAddCustomView!
    // 模板选择列表
    private var templatesTableView: UITableView!
    
    //***** 数据设置UI *****/
    private var templateCreateView: UIView!
    private var backBtn: UIButton!
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
    
    private var templates: [SceneMainTemplate] = [
        SceneMainTemplate(mainType: .frequentlyUsed),
        SceneMainTemplate(mainType: .office),
        SceneMainTemplate(mainType: .school),
        SceneMainTemplate(mainType: .medicalTreatment),
        SceneMainTemplate(mainType: .industry),
        SceneMainTemplate(mainType: .supermarket)
    ]

    private var selectTemplate: SceneMainTemplate?
    private var selectSubTemplate: SceneMainTemplate.SceneTemplate?
    
    private var templateShowMap: [TemplateMainType: Bool] = [:]
    /// 是否展示模板创建
    private var showTemplateCreate: Bool = false
    
    let space: SpaceData
    
    /// 场景执行数据list
    private var sceneDatas: [ExecuteSceneData] = []
    private var sceneDataSelectIndex: Int?
    
    private var imageId: Int = 1
    private var name: String?
    
    private var groups: [Group] = []
    /// 创建成功的场景
    private var scene: Scene?
    private var creationDraft: SceneDraft?
    private var creationRequest: UUID?
    private var creationProjectionPending = false
    
    private var meshNetworkConnectedObservation: NSKeyValueObservation?

    private var sceneDataCctRange: ClosedRange<UInt16> {
        let ranges = groups.filter({ $0.effectiveSupportCct }).map({ $0.effectiveCctRange })
        guard let first = ranges.first else {
            return NodeAbsoluteCctRange.defaultRange
        }
        return ranges.reduce(first) { result, range in
            min(result.lowerBound, range.lowerBound)...max(result.upperBound, range.upperBound)
        }
    }
    
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close)).withoutSharedBackground()
        
        groups = MeshNetworkManager.instance.groups
        
        groups.forEach({
            $0.executeSceneData = nil
            $0.isSelected = false
            $0.sceneDataIndex = nil
        })
        
        self.name = MeshNetworkManager.instance.getNextSceneName()
        
        backBtn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backAction))
        backBtn.isHidden = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backBtn).withoutSharedBackground()
        
        setupUI()
//        setupTemplateDataUI()

        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
//        sceneDatas = defalutSceneDatas
     
        addNotificationObserver()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if createMode == .custom, let scene { openCreatedScene(scene) }
        
        if collectionView?.firstShowFlashScrollIndicators ?? false {
            collectionView?.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if menuView.bounds.size != menuLayoutSize {
            menuLayoutSize = menuView.bounds.size
            menuView.resetFrames()
        }
    }
    
    deinit {
        if self.scene == nil && self.space.isConfiguring { // 未创建场景退出页面，停止引导配置流程
            self.space.isConfiguring = false
        }
        meshNetworkConnectedObservation = nil
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    private func makeDraft() throws -> SceneDraft? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 32,
              !MeshNetworkManager.instance.isSceneTautonym(name: name) else { return nil }
        let scope = SceneScope(meshUUID: space.meshUUID, networkID: space.meshNetworkId)
        try SceneConfigurationStore.validateAccess(scope)
        var parameters: [UInt16: SceneParameters] = [:]
        if createMode == .template {
            for group in groups where group.isSelected {
                if let value = group.executeSceneData {
                    parameters[group.address.address] = .init(isOn: value.isOn,
                        lightness: value.isOn ? Node.getLightness(lightness100: value.lightness) : 0,
                        cct: group.clampEffectiveCct(UInt16(value.cct)))
                }
            }
        }
        return try SceneDraft(scope: scope, name: name, imageId: imageId, kind: .groups, groupParameters: parameters)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelCreationRequest()
        stopTemplatePreview()
    }
    private func stopTemplatePreview() {
        templatePicker?.cancel(); templatePicker = nil
        templateCreateView?.isUserInteractionEnabled = true
    }

    private func addNotificationObserver() {
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelCreationRequest()
            self?.stopTemplatePreview()
        }
        
        // mesh网络连接观察者
        meshNetworkConnectedObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            guard self.showTemplateCreate else {
                return
            }
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                self?.collectionView?.reloadSections(IndexSet(integer: 1))
            }
        })
        
        NotificationCenter.default.addObserver(forName: .init(groupsRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            //            self?.refreshData = true
            guard let self = self else { return }
//            self.collectionView.reloadData()
            self.groups = MeshNetworkManager.instance.groups
            if self.showTemplateCreate {
                self.collectionView?.reloadSections(IndexSet(integer: 1))
            }
        }
        
    }
    
    
    @objc private func backAction() {
//        backHandle(close: false)
        sceneEditTemplateCheack(close: false)
    }
    
    
    @objc private func close() {
        sceneEditTemplateCheack(close: true)
    }
    
    
    /// 模板编辑检查
    private func sceneEditTemplateCheack(close: Bool) {
        if showTemplateCreate, let selectSubTemplate = self.selectSubTemplate {
            if selectSubTemplate.title != name || selectSubTemplate.imageId != imageId || selectSubTemplate.parameters.count != sceneDatas.count || !selectSubTemplate.parameters.elementsEqual(sceneDatas, by: { $0.lightness == $1.lightness && $0.cct == $1.cct }) || groups.contains(where: { $0.isSelected }) { // 提示是否放弃修改
                
                SRAlertView(title: "notification".localizedString, message: "templates_exit_message".localizedString, actions: [.cancelAction, .init(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    
                    self?.backHandle(close: close)
                })]).show()
                return
            }
        }
        
        backHandle(close: close)
    }
  
    /// 返回/退出处理
    private func backHandle(close: Bool) {
        
        view.endEditing(true)
        if close {
            cancelCreationRequest()
//            let spaceVc = UIViewController.getVisibleVc()?.presentingViewController
            if self.scene != nil && self.space.isConfiguring { // 创建成功并在引导配置流程中
//                self.backHandle(close: true)
                dismiss(animated: false)
                // 跳转到连续创建页面
                let vc = SpaceNewCreationProcessController(space: space, options: .scene)
//                spaceVc?.present(NavigationViewController(rootViewController: vc), animated: true)
                NotificationCenter.default.post(name: .init(spaceModalViewControllerNotificaitonName), object: NavigationViewController(rootViewController: vc))
            }else {
                dismiss(animated: true)
            }
        }else {
            groups.forEach({
                $0.executeSceneData = nil
                $0.sceneDataIndex = nil
                $0.isSelected = false
            })
            self.name = MeshNetworkManager.instance.getNextSceneName()
            self.imageId = 1
            showTemplateCreate = false
            updateUI()
        }
        
    }
    
    
    /// 预览
    @objc private func previewBtnAction() {
        createMode = .template
        openDraftEditor(preview: true)
    }
    

    
    /// 创建场景
    private func createScene() {
        
//        let selectGroups = groups.filter({ $0.isSelected })
        
        addSceneHandle()
        
        // 组里是否存在设备
//        if selectGroups.contains(where: { $0.nodes.count > 0 }) { // 同步数据
//            if MeshLibManager.manager.isMeshNetworkConnected { // 去同步
//                addSceneHandle()
//            }else { // 未连接网络
//                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
//            }
//        }else { // 组内无设备
//            addSceneHandle()
//        }
        
    }
    
    private func addSceneHandle() {
        guard createMode == .custom else { openDraftEditor(preview: false); return }
        guard creationRequest == nil else { return }
        if let scene { openCreatedScene(scene); return }
        do {
            guard let draft = try creationDraft ?? makeDraft() else { return }
            creationDraft = draft
            let request = UUID(); creationRequest = request
            view.endEditing(true); updateCreationInteraction()
            saveCreatedScene(draft, request: request)
        } catch { TimedSchedulerBindings.showFailure(error) }
    }

    private func acceptsCreation(_ request: UUID) -> Bool {
        creationRequest == request && viewIfLoaded?.window != nil
            && navigationController?.topViewController === self
    }

    private func cancelCreationRequest() {
        guard creationRequest != nil else { return }
        creationRequest = nil
        if !creationProjectionPending { creationDraft = nil }
        updateCreationInteraction()
        XWHUDManager.hide()
    }

    private func updateCreationInteraction() {
        let editable = creationRequest == nil && !creationProjectionPending && scene == nil
        customView?.isUserInteractionEnabled = creationRequest == nil
        customView?.nameField.isEnabled = editable
        customView?.collectionView.isUserInteractionEnabled = editable
        menuView?.isUserInteractionEnabled = editable
        scrollView?.isScrollEnabled = editable
    }

    private func saveCreatedScene(_ draft: SceneDraft, request: UUID, requestAddressIfNeeded: Bool = true) {
        guard acceptsCreation(request) else { return }
        do {
            switch try SceneConfigurationStore().createEmpty(draft: draft) {
            case .ready(let saved):
                scene = saved; creationProjectionPending = false
                createSceneCallback?(saved)
                publishCreatedSceneChange()
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString, timer: 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.acceptsCreation(request) else { return }
                    self.creationRequest = nil
                    self.openCreatedScene(saved)
                }
            case .projectionPending:
                creationProjectionPending = true
                publishCreatedSceneChange()
                failCreation(SceneConfigurationStore.Failure.persistence)
            }
        } catch SceneConfigurationStore.Failure.noNumber {
            guard requestAddressIfNeeded else { failCreation(SceneConfigurationStore.Failure.noNumber); return }
            XWHUDManager.showCustomHUD(withMessage: "syncing_data".localizedString, isWindow: false)
            NetworkRequest.shared.request(.applyAddress(siteId: space.siteId, type: .scene, number: 16)) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.acceptsCreation(request) else { return }
                    do {
                        try SceneConfigurationStore.validateAccess(draft.scope)
                        switch result {
                        case .success(let response):
                            guard let site = SiteData.load(siteId: self.space.siteId),
                                  let data = JSON(response)["data"]["provisioner"].dictionaryObject,
                                  SceneCapacity.validSceneAllocation(data) else { throw SceneConfigurationStore.Failure.noNumber }
                            site.setProvisioner(provisionerData: data)
                            guard MeshNetworkManager.instance.meshNetwork?.save() == true else { throw SceneConfigurationStore.Failure.persistence }
                            self.saveCreatedScene(draft, request: request, requestAddressIfNeeded: false)
                        case .failure(let error): throw error
                        }
                    } catch { self.failCreation(error) }
                }
            }
        } catch { failCreation(error) }
    }

    private func failCreation(_ error: Error) {
        cancelCreationRequest()
        // Retain the same revision after a durable write so retry repairs its projection.
        if creationProjectionPending {
            XWHUDManager.showTipHUD("scene_projection_pending".localizedString, isLineFeed: true)
        } else if let failure = error as? SceneConfigurationStore.Failure, failure == .noNumber {
            XWHUDManager.showTipHUD("scene_address_unavailable".localizedString, isLineFeed: true)
        } else { TimedSchedulerBindings.showFailure(error) }
    }

    private func publishCreatedSceneChange() {
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: scene)
        NotificationCenter.default.post(name: .init(scenesRefreshNotificationName), object: nil)
    }

    private func openCreatedScene(_ scene: Scene) {
        let vc = SceneSettingsViewController(space: space, scene: scene, mode: .members)
        vc.finishesCreation = true
        vc.enablesGroupLiveControl = true
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openDraftEditor(preview: Bool) {
        do {
            guard let draft = try makeDraft() else { return }
            let vc = SceneSettingsViewController(space: space, draft: draft)
            vc.enablesGroupLiveControl = true
            vc.beginSaveOnAppearance = createMode == .template && !preview
            vc.beginPreviewOnAppearance = preview
            vc.sceneUpdateCallback = { [weak self] scene in
                self?.scene = scene; self?.createSceneCallback?(scene)
            }
            navigationController?.pushViewController(vc, animated: true)
        } catch { TimedSchedulerBindings.showFailure(error) }
    }




    
    // 保存
    @objc private func saveBtnAction() {
        createMode = .template
        createScene()
    }
    
    /// 更新预览按钮状态
    private func updatePreviewBtnState() {
        
        self.previewBtn.isEnabled = groups.contains(where: { $0.isSelected && $0.executeSceneData != nil && $0.nodes.count > 0 })
        
    }
    
//    private func showSceneDataUI() {
//        
//        if let subTemplate = selectSubTemplate {
//            
//            sceneDatas = subTemplate.parameters.map({
//                SceneExecuteData(lightness: $0.lightness, cct: $0.cct)
//            })
//            imageId = subTemplate.imageId
//            name = subTemplate.title
////            infoView.templateLabel.text = "\(mainTemplate.title)->\(subTemplate.title)"
//        }
//        setupTemplateDataUI()
//    }
    
    private func updateUI() {
        
        if showTemplateCreate {
            backBtn.isHidden = false
            
            if let subTemplate = selectSubTemplate {
                sceneDatas = subTemplate.parameters.map({
                    ExecuteSceneData(lightness: $0.lightness, cct: $0.cct)
                })
                imageId = subTemplate.imageId
                name = subTemplate.title
            }
            
            if templateCreateView == nil {
                setupTemplateDataUI()
            }else {
                templateCreateView.isHidden = false
                collectionView.reloadData()
            }
            
         
            templateCreateView.layer.addMoveInAnimation(duration: 0.25, animationOrientation: .fromRight)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.menuView.isHidden = true
                self.scrollView.isHidden = true
            }
            
        }else {
            backBtn.isHidden = true
            menuView.isHidden = false
            scrollView.isHidden = false
            
            templateCreateView.layer.addMoveInAnimation(type: .reveal, animationOrientation: .fromLeft)
            self.templateCreateView.isHidden = true

        }
    }
    
    private func setupUI() {
        
        menuView = WMMenuView(frame: .zero)
        menuView.style = .line
        menuView.layoutMode = .center
        menuView.lineColor = Bar_Color
        menuView.progressHeight = 2
        menuView.progressViewBottomSpace = 4
        menuView.itemBackgroundColor = .clear
        menuView.dataSource = self
        menuView.delegate = self
        view.addSubview(menuView)
        menuView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(SCRYFrom(38))
        }
        
        scrollView = SceneAddPagingScrollView()
        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(menuView.snp.bottom).offset(SCRYFrom(17))
        }
        
        customView = SceneAddCustomView(frame: .zero, name: name, imageNames: sceneImageNames)
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
        templatesTableView.enableKeyboardDismissal()
        scrollView.addSubview(templatesTableView)
        templatesTableView.snp.makeConstraints { make in
            make.left.equalTo(customView.snp.right)
            make.right.bottom.width.height.equalToSuperview()
        }
        
    }
    
    private func setupTemplateDataUI() {
        
        templateCreateView = UIView()
        view.addSubview(templateCreateView)
        templateCreateView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        templateCreateView.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        let bottomLineView = UIView()
        bottomLineView.backgroundColor = Line_Color
        bottomView.addSubview(bottomLineView)
        bottomLineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
        let lineView = UIView()
        lineView.backgroundColor = Line_Color
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
//            make.right.equalTo(lineView.snp.left).offset(SCRXFrom(-33))
            make.centerX.equalToSuperview().multipliedBy(0.5)
            make.width.equalTo(SCRXFrom(120))
            make.centerY.height.equalTo(lineView)
        }
        
        saveBtn = UIButton(title: "save".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(saveBtnAction))
        saveBtn.setTitleColor(RGB(156, 163, 175), for: .disabled)
        bottomView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
//            make.left.equalTo(lineView.snp.right).offset(SCRXFrom(33))
            make.centerX.equalToSuperview().multipliedBy(1.5)
            make.width.height.centerY.equalTo(previewBtn)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        collectionView.dataSource = self
        collectionView.delegate = self
//        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(SceneAddTemplateInfoSectionView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "infoSection")
        collectionView.register(SceneAddGroupTitleSectionView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "titleSection")
        collectionView.register(SceneAddDataListViewCell.classForCoder(), forCellWithReuseIdentifier: "dataCell")
        collectionView.register(SceneAddGroupViewCell.classForCoder(), forCellWithReuseIdentifier: "groupCell")
        collectionView.register(SceneAddGroupEmptyCell.classForCoder(), forCellWithReuseIdentifier: "groupEmptyCell")
        collectionView.enableKeyboardDismissal()
//        collectionView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
        templateCreateView.addSubview(collectionView)
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
        let template = templates[section]
        return (templateShowMap[template.mainType] ?? false) ? template.sceneTemplates.count : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SceneAddTemplateTitleCell
        let template = templates[indexPath.section]
        cell.titleLabel.text = template.sceneTemplates[indexPath.row].title
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! SceneAddTemplateTitleHeaderView
        let template = templates[section]
        headerView.nameLabel.text = template.title
        headerView.isShow = templateShowMap[template.mainType] ?? false
        headerView.showHideCallback = {[weak self] isShow in
            self?.templateShowMap.updateValue(isShow, forKey: template.mainType)
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
        
        tableView.deselectRow(at: indexPath, animated: true)
        let template = templates[indexPath.section]
        selectTemplate = template
        selectSubTemplate = template.sceneTemplates[indexPath.row]
//        showSceneDataUI()
        self.showTemplateCreate = true
        sceneDataSelectIndex = nil
        groups.forEach({ $0.isSelected = false })
        updateUI()
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
//        if index > 0 {
            return SCRXFrom(54)
//        }
//        return 0
    }
    
    func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        
        view.endEditing(true)
        
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
            dataCell.cctRange = sceneDataCctRange
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
            groupCell.nameLabel.text = group.name
            groupCell.selectBtn.isSelected = group.isSelected
            // 是否选中参数
//            if sceneDataSelectIndex != nil {
//                groupCell.onoffBtn.isHidden = false
                
                groupCell.onoffBtn.setImage(UIImage(named: "scene_group_off"), for: .normal)
                groupCell.onoffBtn.isSelected = group.executeSceneData?.isOn ?? true
                groupCell.onoffBtn.isEnabled = group.executeSceneData != nil
                
//            }else {
//                groupCell.onoffBtn.isHidden = true
//            }
          

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
            let count = min(sceneDatas.count + 1, 16)
            let rowCount = isIPad ? 7 : 4
            let row = max(ceil(Float(count) / Float(rowCount)), 1)
            let itemHeight = isIPad ? SCRYFrom(80) : SCRYFrom(68)
            return CGSize(width: itemW, height: CGFloat(row) * itemHeight + CGFloat(row - 1) * SCRXFrom(16) + SCRYFrom(28))
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
            if let mainTemplate = selectTemplate, let subTemplate = selectSubTemplate {
                infoView.templateLabel.text = "\(mainTemplate.title)->\(subTemplate.title)"
            }
            infoView.iconImageView.image = UIImage(named: sceneImageNames[imageId - 1])
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
        
        guard indexPath.section == 1 else { return }
        
        if groups.isEmpty {
            return
        }
        
        let group = groups[indexPath.item]
        if group.isSelected {
            group.executeSceneData = nil
            group.sceneDataIndex = nil
            group.isSelected = false
        }else {
            guard let index = self.sceneDataSelectIndex, index >= 0, index < sceneDatas.count else {
                XWHUDManager.showTipHUD("scene_select_parameter_message".localizedString, isLineFeed: true)
                return
            }
            let data = sceneDatas[index]
            group.executeSceneData = .init(isOn: data.isOn, lightness: data.lightness, cct: Int(group.clampEffectiveCct(UInt16(data.cct))))
            group.sceneDataIndex = index
            group.isSelected = true
        }
        
//        if group.sceneDataIndex == index { // 同一个参数，反选
//            group.executeSceneData = nil
//            group.sceneDataIndex = nil
//            group.isSelected = false
//        }else {
//            let data = sceneDatas[index]
//            group.executeSceneData = .init(lightness: data.lightness, cct: data.cct)
//            group.sceneDataIndex = index
//            group.isSelected = true
////            if group.nodes.count > 0 {
////                if MeshLibManager.manager.isMeshNetworkConnected {
////                }else {
////                    XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
////                }
////            }
//        }
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
        } else if MeshNetworkManager.instance.isSceneTautonym(name: name) { // 重名
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
        let vc = ImagesPickerViewController(imageNames: sceneImageNames, selectIndex: imageId - 1) {[weak self] imageId in
            guard let self = self else { return }
            self.imageId = imageId + 1
            self.collectionView.reloadSections(IndexSet(integer: 0))
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 重置点击回调
    func sectionViewDidResetAction(_ sectionView: SceneAddTemplateInfoSectionView) {
        
        guard let subTemplate = self.selectSubTemplate else { return }
        // 场景数据是否修改
        let defalutSceneDatas = subTemplate.parameters.map({
            ExecuteSceneData(lightness: $0.lightness, cct: $0.cct)
        })
        
        var valueEdit = false
        if sceneDatas.count == defalutSceneDatas.count {
            for (index, data) in sceneDatas.enumerated() {
                if defalutSceneDatas[index].isOn != data.isOn || defalutSceneDatas[index].lightness != data.lightness || defalutSceneDatas[index].cct != data.cct {
                    valueEdit = true
                    break
                }
            }
        }else {
            valueEdit = true
        }
        
        guard self.name != subTemplate.title || self.imageId != subTemplate.imageId || valueEdit else {
            return
        }
        
        SRAlertView(title: "notification".localizedString, message: "scene_parameter_reset_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            self.name = subTemplate.title
            self.imageId = subTemplate.imageId
            self.sceneDatas = defalutSceneDatas
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
        } else if MeshNetworkManager.instance.isSceneTautonym(name: name) { // 重名
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
        if sceneDataSelectIndex == index {
            sceneDataSelectIndex = nil
        }else {
            sceneDataSelectIndex = index
        }
        collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
    }
    
    /// 长按编辑数据回调
    func cell(_ cell: SceneAddDataListViewCell, didLongPressData index: Int) {
        guard index < sceneDatas.count else {
            return
        }
        let data = sceneDatas[index]
        templatePicker = SceneExecuteDataPickerView.show(lightness: data.lightness, isOn: data.isOn, cct: data.cct, cctRange: sceneDataCctRange) {[weak self] isOn, lightness, cct in
            guard let self = self else { return }
            data.isOn = isOn
            data.lightness = isOn ? lightness : 0
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
        
        templatePicker = SceneExecuteDataPickerView.show(cctRange: sceneDataCctRange, showDelete: false) {[weak self] isOn, lightness, cct in
            let data = ExecuteSceneData(isOn: isOn, lightness: lightness, cct: cct)
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
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let group = groups[indexPath.item]
        guard let current = group.executeSceneData else { return }
        // Template rows edit their own parameter copy, never the current lamp state.
        group.executeSceneData = ExecuteSceneData(isOn: isOn, lightness: isOn ? group.info.profile.lightControlData.highEndTrim : 0, cct: current.cct)
        group.isSelected = true
        collectionView.reloadItems(at: [indexPath])
    }
    
}

extension SceneAddViewController: SceneAddGroupEmptyCellDelegate {
    
    /// 创建组回调
    func cellDidCreateGroupAction(_ cell: SceneAddGroupEmptyCell) {
        
        let groupAddVc = GroupAddViewController(space: space)
//        groupAddVc.doneCallback = {[weak self] group in
//            self?.groups = [group]
//            self?.collectionView.reloadSections(IndexSet(integer: 1))
//        }
        if isIPad {
            groupAddVc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: groupAddVc), animated: true)
        
    }
    
}

class ExecuteSceneData {
    /// 是否开启
    var isOn: Bool
    /// 亮度 0~100
    var lightness: Int
    /// 色温
    var cct: Int
    
    init(isOn: Bool = true, lightness: Int, cct: Int) {
        self.isOn = isOn
        self.lightness = isOn ? lightness : 0
        self.cct = cct
    }
    
    init(data: SceneExecuteData) {
        self.isOn = data.isOn
        self.lightness = data.isOn ? Node.getLightness100(lightness: data.lightness) : 0
        self.cct = Int(data.cct)
    }
}
  
private extension Group {
    
    static var executeSceneDataKey: UInt8 = 0
    
    static var isSelectedKey: UInt8 = 0
    
    static var sceneDataIndexKey: UInt8 = 0
    
    /// 赋值的场景数据
    var executeSceneData: ExecuteSceneData? {
        get {
            objc_getAssociatedObject(self, &Group.executeSceneDataKey) as? ExecuteSceneData
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
