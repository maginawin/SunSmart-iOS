//
//  ProfileLightSensorTemplateListController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/22.
//

import UIKit
import NordicSigMeshSDK

class ProfileLightSensorTemplateListController: UIViewController {

    private var bottomView: DeviceBottomBtnView!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    var templates: [ProfileLightSensorTemplate] = []
    
    let profile: Profile
    let groupNodes: [Node]
    let setMode: ProfileDayNightLuxSetMode
    
    var templatesSetCallback: (([ProfileLightSensorTemplate])->Void)?
    
    init(profile: Profile, groupNodes: [Node], setMode: ProfileDayNightLuxSetMode) {
        self.profile = profile
        self.groupNodes = groupNodes
        self.setMode = setMode
        super.init(nibName: nil, bundle: nil)
        
//        templates = group.info.profile.lightSensorTemplates
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupUI()
        
        DispatchQueue.main.async {
            self.updateEmptyUI()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        wm_pageController?.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "profile_help")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(helpAction))
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        wm_pageController?.navigationItem.rightBarButtonItem = nil
    }
    
    @objc private func helpAction() {
        
        let instructions: [ProfileTextInstructionInfo] = [
            ProfileTextInstructionInfo(title: "light_sensor_template".localizedString, content: "light_sensor_template_note".localizedString),
            ProfileTextInstructionInfo(title: "design_intent".localizedString, content: "light_sensor_template_design_intent_note".localizedString),
            ProfileTextInstructionInfo(title: "typical_use_cases".localizedString, content: "light_sensor_template_typical_use_cases_note".localizedString)
        ]
        
        let vc = ProfileTextInstructionsViewController(vcTitle: "light_sensor_template".localizedString, instructions: instructions)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func resyncDevices(_ devices: [Node]) {
        
        let syncDatas: [(node: Node, profiles: [ProfileType])] = devices.compactMap { node in
            let profileTypes = node.getSyncDayNightLuxProfiles()
            if profileTypes.count > 0 {
                return (node, profileTypes)
            }
            return nil
        }
        let vc = SyncDevicesViewController(type: .profile(syncDatas))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            self?.collectionView.reloadData()
        }
        vc.backActionCallback = {[weak self] _ in
            self?.navigationController?.popViewController(animated: true)
            self?.collectionView.reloadData()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    @objc private func createTemplateAction() {
        
        let canAddDevices = groupNodes.filter({ node in !templates.contains(where: { $0.devices.contains(node) }) })
        let vc = ProfileLightSensorTemplateController(profile: profile, canAppliedDevices: canAddDevices, setMode: setMode)
        vc.createOrEditCallback = {[weak self] template in
            guard let self = self else { return }
            if template.devices.contains(where: { $0.getSyncDayNightLuxProfiles().count > 0 }) {
                self.collectionView.reloadData()
                self.updateEmptyUI()
            }else {
                if let index = self.templates.firstIndex(where: { $0.id == template.id }) {
                    self.templates.replaceSubrange(index...index, with: [template])
                    self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                }else {
                    self.templates.append(template)
                    self.collectionView.insertItems(at: [IndexPath(item: self.templates.count - 1, section: 0)])
                    self.updateEmptyUI()
                }
            }
            self.templatesSetCallback?(self.templates)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func updateEmptyUI() {
        

        if templates.isEmpty {
            view.showEmptyDataView(frame: view.bounds, title: "no_light_sensor_template".localizedString, backgroundColor: Background_Color, buttonText: "create_new_template".localizedString, buttomWidth: SCRXFrom(216), position: .center, bottomMargin: SCRYFit(50) + kSafeAreaBottomHeight) {[weak self] in
                self?.createTemplateAction()
            }
            view.emptyView?.titleLabel.font = UIFont.systemFont(ofSize: FontFit(15))
        }else {
            view.hideEmptyDataView()
        }
        
    }
    
    private func setupUI() {
        
        bottomView = DeviceBottomBtnView()
        bottomView.showCreateUI()
        bottomView.createBtn.setTitle("create_new_template".localizedString, for: .normal)
        bottomView.createBtn.setTitleColor(Title_Color, for: .normal)
        bottomView.createBtn.addTarget(self, action: #selector(createTemplateAction), for: .touchUpInside)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaTopHeight + SCRYFrom(56))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(12)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(4), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.backgroundColor = Background_Color
        collectionView.register(ProfileLightSensorTemplateViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.register(DeviceResyncHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collectionView.register(UICollectionReusableView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "emptyHeader")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(8))
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        
    }

}

extension ProfileLightSensorTemplateListController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return templates.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ProfileLightSensorTemplateViewCell
        cell.templateModel = templates[indexPath.item]
        cell.resyncActionCallback = {[weak self] in
            guard let self = self else { return }
            let template = templates[indexPath.item]
            let syncNodes = template.devices.filter({ $0.getSyncDayNightLuxProfiles().count > 0 })
            self.resyncDevices(syncNodes)
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right, height: SCRYFrom(80))
    }

    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let nodes = templates.flatMap({ $0.devices })
        let syncNodes = nodes.filter({ $0.getSyncDayNightLuxProfiles().count > 0 })
        guard syncNodes.count > 0 else {
            return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "emptyHeader", for: indexPath)
        }
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! DeviceResyncHeaderView
        headerView.retryActionCallback = {[weak self] in
            self?.resyncDevices(syncNodes)
        }
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        let nodes = templates.flatMap({ $0.devices })
        let existSyncNodes = nodes.contains(where: { $0.getSyncDayNightLuxProfiles().count > 0 })
        let width = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        if existSyncNodes {
            return CGSize(width: width, height: SCRYFrom(32))
        }
        return CGSize(width: width, height: SCRYFrom(8))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let template = templates[indexPath.item]
        
        let canAddDevices = groupNodes.filter({ node in template.devices.contains(node) || !templates.contains(where: { $0.devices.contains(node) }) })
        let vc = ProfileLightSensorTemplateController(profile: profile, canAppliedDevices: canAddDevices, setMode: setMode)
        vc.template = template
        vc.createOrEditCallback = {[weak self] template in
            guard let self = self else { return }
            if let index = self.templates.firstIndex(where: { $0.id == template.id }) {
                self.templates.replaceSubrange(index...index, with: [template])
//                self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                self.collectionView.reloadData()
            }else {
                self.templates.append(template)
//                self.collectionView.insertItems(at: [IndexPath(item: self.templates.count - 1, section: 0)])
                self.collectionView.reloadData()
                self.updateEmptyUI()
            }
            self.templatesSetCallback?(self.templates)
        }
        vc.deleteCallback = {[weak self] template in
            guard let self = self else { return }
            if let index = self.templates.firstIndex(where: { $0.id == template.id }) {
                self.templates.remove(at: index)
//                self.collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
                self.collectionView.reloadData()
                self.updateEmptyUI()
                self.templatesSetCallback?(self.templates)
            }
            
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
}
