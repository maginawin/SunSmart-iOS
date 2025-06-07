//
//  ScheduleDevicesView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/15.
//

import UIKit
import NordicSigMeshSDK

class ScheduleDevicesView: UIView {
    
    /// 设备选择完成回调
    typealias DevicesSelectFinishedCallback = (([Node])->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var topBarView: UIView!
    private var titleLabel: UILabel!
    private var selectAllBtn: UIButton!
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var bottomView: UIView!
    private var cancelBtn: UIButton!
    private var lineView: UIView!
    private var confirmBtn: UIButton!
    
    /// 设备list
    private let nodes: [Node]
    /// 选中的设备list
    private var selectNodes: [Node]
    /// 禁止取消选择的设备list（编辑日程-已存在离线设备）
    private var disableUnselectNodes: [Node] = []
    /// 日程（编辑时传入）
    private let schedule: Schedule?
    /// 需要同步的设备list（编辑）
    private var needSyncNodes: [Node] = []
    /// 选择设备完成回调
    private var selectCallback: DevicesSelectFinishedCallback?
    
    /// 每行个数
    private var rowNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: SCRYFrom(60), left: SCRXFrom(24), bottom: SCRXFrom(24), right: SCRXFrom(24)) : UIEdgeInsets(top: SCRYFrom(60), left: SCRXFrom(12), bottom: SCRXFrom(12), right: SCRXFrom(12))
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    
    init(nodes: [Node], selectNodes: [Node], schedule: Schedule? = nil, selectBack: DevicesSelectFinishedCallback?) {
        self.nodes = nodes
        self.selectNodes = selectNodes
        self.schedule = schedule
        super.init(frame: UIScreen.main.bounds)
        self.selectCallback = selectBack
        
        setupUI()
        
        // 获取是否有设备需要同步
        if let schedule = self.schedule {
            let data = schedule.getNeedSyncDatas()
            needSyncNodes.append(contentsOf: data.syncNodes)
            needSyncNodes.append(contentsOf: data.deleteNodes)
        }
        updateSelectAllState()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
            layoutIfNeeded()
            if nodes.isEmpty {
                showEmptyUI()
            }
            checkOffline()
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
    
    /// 检查离线设备
    private func checkOffline() {
        
        let offlineNodes = selectNodes.filter({ !$0.state })
        if self.schedule != nil { // 编辑日程-获取已保存离线并离线的设备
            disableUnselectNodes = offlineNodes
        }else {
            // 添加日程-设备选择后再次编辑
            if offlineNodes.count > 0 { // 选择设备后未保存日程，再次进入选择时发现设备离线
                XWHUDManager.showTipHUD("schedule_device_offline_tip".localizedString, isLineFeed: true)
                selectNodes.removeAll(where: { offlineNodes.contains($0) })
            }
        }
        
      
    }
    
    private func showEmptyUI() {
        
        collectionView.showEmptyDataView(title: "no_devices".localizedString, tipText: "no_devices_message".localizedString, position: .center, bottomMargin: SCRYFit(45))
    }
    
    /// 全选
    @objc private func selectAllBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            self.selectNodes = self.nodes.filter({ ($0.state && $0.isKeybindComplete) || disableUnselectNodes.contains($0) })
        }else {
            self.selectNodes.removeAll(where: { !disableUnselectNodes.contains($0) })
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
        selectNodes.sort(by: { $0.primaryUnicastAddress < $1.primaryUnicastAddress })
        selectCallback?(selectNodes)
    }
    
    /// 更新全选状态
    private func updateSelectAllState() {
        
        // 编辑日程-选中的设备未
        let canSelectNodes = nodes.filter({ $0.isKeybindComplete && $0.state })
        if canSelectNodes.isEmpty {
            selectAllBtn.isHidden = true
        }else {
            selectAllBtn.isHidden = false
            selectAllBtn.isSelected = selectNodes.count == canSelectNodes.count
        }
        
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
        confirmBtn.setTitleColor(RGB(180, 190, 209), for: .disabled)
        bottomView.addSubview(confirmBtn)
        confirmBtn.snp.makeConstraints { make in
            make.left.equalTo(lineView.snp.right)
            make.top.bottom.right.equalToSuperview()
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.itemRowCount = rowNum
        flowLayout.offsetY = SCRYFrom(-53)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset = collectionViewInsets
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = Background_Color
        collectionView.layer.cornerRadius = SCRYFrom(15)
        collectionView.register(DevicesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
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
        
        titleLabel = UILabel(text: "devices".localizedString, textColor: RGB(72, 72, 74), fontSize: 18)
        topBarView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        selectAllBtn = UIButton(title: "select_all".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(39, 37, 54), normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        selectAllBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
//        selectAllBtn.isHidden = nodes.isEmpty
        topBarView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-23))
            make.centerY.equalTo(titleLabel)
        }
        
    }
    
    /// 开始修复节点
    private func repair(node: Node) {
        
        XWHUDManager.showCustomHUD(withMessage: "repairing".localizedString, isWindow: true)
        MeshAPI.startKeyBind(node: node, startKeyBind: nil) {[weak self] node in
            XWHUDManager.hide()
            if MeshLibManager.manager.bluetoothState == .poweredOn {
                XWHUDManager.showSuccessTipHUD("complete!".localizedString)
            }
            guard let self = self else { return }
//            if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
//                node.saveNodeInfo(meshUUID: uuid, networkKey: MeshNetworkManager.instance.currentNetworkKey)
//            }
            
            if let index = self.nodes.firstIndex(of: node), let cell = collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? DevicesViewCell {
                cell.device = node
                cell.selectImageView.isHidden = false
            }
//                MeshAPI.getNodeCTLState(address: node.primaryUnicastAddress)
        } keyBindFail: {[weak self] _ in
            XWHUDManager.hide()
            self?.repairFailed(node: node)
        }
        
    }
    
    /// 修复失败
    private func repairFailed(node: Node) {
        
        let alertView = SRAlertView(message: "repair_failed_message".localizedString, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "alert_failed"), actions: [.cancelAction, SRAlertAction(title: "repair".localizedString, style: .default, actionHandler: {[weak self] _ in
            self?.repair(node: node)
        })])
        alertView.stateImageView.snp.remakeConstraints { make in
            make.top.equalTo(SCRYFrom(24))
            make.centerX.equalToSuperview()
        }
        alertView.messageLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(27))
            make.right.equalTo(SCRXFrom(-27))
            make.top.equalTo(alertView.stateImageView.snp.bottom).offset(SCRYFrom(16))
        }
        alertView.hLineView.snp.remakeConstraints { make in
            make.left.right.equalTo(0)
            make.height.equalTo(0.5)
            make.top.equalTo(alertView.messageLabel.snp.bottom).offset(SCRYFrom(16))
        }
        alertView.show()
    }
    
}

extension ScheduleDevicesView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return nodes.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DevicesViewCell
        let node = nodes[indexPath.item]
        cell.device = node
        if needSyncNodes.contains(node) {
            cell.iconImageView.image = UIImage(named: node.unsyncIconName)
        }
        if node.isKeybindComplete && node.state {
            cell.selectImageView.isHidden = false
        }else {
            cell.selectImageView.isHidden = true
        }
        cell.selectImageView.image = UIImage(named: selectNodes.contains(node) ? "device_select" : "device_select_un")
        cell.editClickCallback = {[weak self] node in
            guard let self = self, !self.disableUnselectNodes.contains(node) else { return }
            if self.selectNodes.contains(node) {
                self.selectNodes.removeAll(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress })
            }else {
                self.selectNodes.append(node)
            }
            cell.selectImageView.image = UIImage(named: selectNodes.contains(node) ? "device_select" : "device_select_un")
            self.updateSelectAllState()
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(rowNum - 1)) / CGFloat(rowNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let node = nodes[indexPath.item]
        guard node.isKeybindComplete else {
            repair(node: node)
            return
        }
        
        guard node.state else {
            return
        }
        node.isOn = !node.isOn
        MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn)
        if let cell = collectionView.cellForItem(at: indexPath) as? DevicesViewCell {
            cell.device = node
        }
        
    }
    
}
