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
    
    let group: Group
    
    init(group: Group) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
        
        templates = group.info.profile.lightSensorTemplates
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
    
    @objc private func createTemplateAction() {
        
        let canAddDevices = group.nodes.filter({ node in !templates.contains(where: { $0.devices.contains(node) }) })
        let vc = ProfileLightSensorTemplateController(canAppliedDevices: canAddDevices)
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
        collectionView.register(ProfileLightSensorTemplateViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
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
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right, height: SCRYFrom(80))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }
}
