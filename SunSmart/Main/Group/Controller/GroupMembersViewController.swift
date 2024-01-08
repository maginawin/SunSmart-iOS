//
//  GroupMembersViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/15.
//

import UIKit
import NordicSigMeshSDK

class GroupMembersViewController: UIViewController {

    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var functionView: GroupDevicesFunctionView!
    private var selectNodes: [Node] = []
    
    let space: SpaceData
    let group: Group

    init(space: SpaceData, group: Group) {
        self.space = space
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "members".localizedString
        view.backgroundColor = Background_Color
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "save".localizedString, color: RGB(0, 0, 0, 0.85), font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(saveAction))
        
        setupUI()
        
        if navigationController?.viewControllers.count ?? 0 == 1 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
            functionView.syncBtn.isHidden = true
            navigationItem.rightBarButtonItem?.title = "done".localizedString
        }
        
        updateEmptyUI()
        
        selectNodes = space.nodes.filter({ $0.group?.address.address == group.address.address })
        
    }
    
    @objc private func backAction() {
        if parent != nil && navigationController?.viewControllers.count ?? 0 == 1 {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func saveAction() {
        
        if selectNodes.isEmpty && group.nodes.isEmpty {
            backAction()
            return
        }
        
        let exitNodes = group.nodes.filter({ !selectNodes.contains($0) })
        let addNodes = selectNodes.filter({ !group.nodes.contains($0) })
        guard exitNodes.count > 0 || addNodes.count > 0 else {
            backAction()
            return
        }
        let vc = SyncDevicesViewController(type: .group(group, inNodes: addNodes, outNodes: exitNodes))
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func updateEmptyUI() {
        
        if space.nodes.isEmpty {
            
            view.showEmptyDataView(title: "no_devices".localizedString, tipText: "group_not_devices_message".localizedString, buttonText: "group_add_device".localizedString, buttomWidth: SCRXFrom(216), position: .center, bottomMargin: SCRYFit(50)) {[weak self] in
                guard let self = self else { return }
                let addVc = DeviceAddViewController(space: space)
                addVc.appointGroup = self.group
                addVc.deviceAddCallback = {[weak self] _ in
                    self?.updateEmptyUI()
                    self?.collectionView.reloadData()
                }
                self.navigationController?.pushViewController(addVc, animated: true)
            }
            if let emptyView = view.emptyView {
                emptyView.button.snp.updateConstraints({ make in
                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
//                    make.width.equalTo(SCRXFrom(216))
                })
            }
            
            
            functionView.isHidden = true
        }else {
            view.hideEmptyDataView()
            functionView.isHidden = false
        }
    }

    private func setupUI() {
        
        functionView = GroupDevicesFunctionView()
        functionView.delegate = self
        view.addSubview(functionView)
        functionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(14)
        flowLayout.minimumInteritemSpacing = SCRXFrom(14)
        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(12), left: SCRXFrom(12), bottom: SCRYFrom(12), right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        //        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFit(36), right: SCRXFrom(24))
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(DevicesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(functionView.snp.top)
            make.top.equalTo((navigationController?.navigationBar.frame.maxY ?? 0))
        }
    }
    
    private func showFailedAlert() {
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        
        let messageAttStr = NSMutableAttributedString(string: "device_configured_failed_title".localizedString + "\n", attributes: [.paragraphStyle: style, .foregroundColor: Title_Color])
        let noteAttStr = NSAttributedString(string: "device_configured_failed_note".localizedString, attributes: [.foregroundColor: RGB(100, 136, 139), .paragraphStyle: style])
        messageAttStr.append(noteAttStr)
        
        let messageAttBtnStyle = SRAlertMessageAttBtnStyle(offset: CGPoint(x: 0, y: -6), text: "check".localizedString) {[weak self] in
            print("Check")
            SRAlertView.hide()
            self?.checkDevices()
        }
        
        SRAlertView(title: "notification".localizedString, messageAttStr: messageAttStr, messageAttBtnStyle: messageAttBtnStyle, margin: SCRXFrom(27), actions: [SRAlertAction(title: "finish".localizedString, style: .cancel, actionHandler: nil), SRAlertAction(title: "reconfigure".localizedString, actionHandler: { _ in
            print("reconfigure")
        })]).show()
    }
    
    /// 检查设备
    private func checkDevices() {
        
        let vc = GroupCheckViewController(group: self.group, nodes: [])
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func updateFunctionView() {
        
        let canEditDevices = space.nodes.filter({ $0.state })
        
        functionView.selectAllBtn.isSelected = selectNodes.count >= canEditDevices.count
    }
}

extension GroupMembersViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return space.nodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DevicesViewCell
        let node = space.nodes[indexPath.item]
        cell.device = node
        if node.state {
            cell.selectImageView.isHidden = false
        }else {
            cell.selectImageView.isHidden = true
        }
        cell.selectImageView.image = selectNodes.contains(node) ? UIImage(named: "device_select") : UIImage(named: "device_select_un")
        cell.editClickCallback = {[weak self] node in
            guard let self = self else { return }
            if self.selectNodes.contains(node) {
                self.selectNodes.removeAll(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress })
                cell.selectImageView.image = UIImage(named: "device_select_un")
            }else {
                self.selectNodes.append(node)
                cell.selectImageView.image = UIImage(named: "device_select")
            }
            self.updateFunctionView()
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * 2.0 - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / 3.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW)
    }
    
}

extension GroupMembersViewController: GroupDevicesFunctionViewDelegate {
    
    /// 点击同步数据回调
    func functionDidSyncDataAction(view: GroupDevicesFunctionView) {
//        showFailedAlert()
        
        let vc = SyncDevicesViewController(type: .group(group))
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    /// 点击检查回调
//    func functionDidCheckAction(view: GroupDevicesFunctionView) {
//        checkDevices()
//    }
    
    /// 点击排序回调
    func functionDidSortAction(view: GroupDevicesFunctionView) {
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 3) { nodes in
            
        }
    }
    
    /// 全选点击回调  selectAll：是否全选
    func function(view: GroupDevicesFunctionView, selectAllStateChanged selectAll: Bool) {
        let canEditDevices = space.nodes.filter({ $0.state })
        selectNodes = canEditDevices
    }

    
}
