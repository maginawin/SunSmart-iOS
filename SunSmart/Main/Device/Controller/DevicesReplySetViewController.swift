//
//  DevicesReplySetViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/3/3.
//

import UIKit
import NordicSigMeshSDK

class `DevicesReplySetViewController`: UIViewController {

    private lazy var tableView: UITableView = {
        let tableV = UITableView(frame: CGRectMake(0, view.safeAreaInsets.top, self.view.width, self.view.height - view.safeAreaInsets.top))
        tableV.backgroundColor = Background_Color
        tableV.separatorStyle = .none
        tableV.rowHeight = SCRYFrom(44)
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "emptyCell")
        tableV.register(GroupSwitchEnOceanProxyHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableV.dataSource = self
        tableV.delegate = self
        return tableV
    }()
    
    private var groups: [Group] = []
    private var devices: [Node] = []
    /// 展开的组
    private var showSections: [Int] = []
    
    private var replyEnableDatas: [Address: Bool] = [:]
    private var initReplyEnableDatas: [Address: Bool] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Devices Reply"
        
        view.addSubview(tableView)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "save".localizedString, color: Bar_Color, target: self, sel: #selector(saveAction))
        
        tableView.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        groups = MeshNetworkManager.instance.groups
//        devices = MeshNetworkManager.instance.realNodes
        groups.forEach { group  in
            group.nodes.forEach { node in
                replyEnableDatas.updateValue(true, forKey: node.primaryUnicastAddress)
            }
        }
        // node.features == nil || node.features?.relay == .enabled
        initReplyEnableDatas = replyEnableDatas
        
    }
    
    @objc private func saveAction() {
        
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            return
        }
        
        groups.forEach { group  in
            group.nodes.forEach { node in
                replyEnableDatas.updateValue(node.features == nil || node.features?.relay == nil || node.features?.relay == .enabled, forKey: node.primaryUnicastAddress)
            }
        }
        
        let setReplyDatas = replyEnableDatas.filter({ data in initReplyEnableDatas[data.key] != data.value })
        let messageHandles = setReplyDatas.map({ MeshMessageHandle(message: ConfigRelaySet(count: 0, steps: 1), address: $0.key) })

        guard messageHandles.count > 0 else {
            return
        }
        
        let alertView =  SRAlertView(title: "reply set".localizedString, titleFont: FONTS(SCRYFrom(15)), message: "0/\(messageHandles.count)", messageColor: TextBlack_Color, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "loading_big"), loadingState: true, btnText: "STOP".localizedString, btnTextColor: .white, btnTextFont: Font_Medium_Size(SCRYFrom(15))) {[weak self] in
            SRAlertView.hide()
            MeshProxyMessageCommand.shared.stopSendMessage(finishedBack: nil)
        }
        alertView.show()
        
        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles) { current, total in
            alertView.messageLabel.text = "\(current)/\(total)"
        } finishedBack: {[weak self] messageHandles in
            alertView.dismiss()
            guard let self = self else { return  }
            let failedHandles = messageHandles.filter({ !$0.isSuccessful })
            if failedHandles.count > 0 {
                XWHUDManager.showErrorTipHUD("failed".localizedString + ":\(failedHandles.count)")
                failedHandles.forEach { handle in
                    let failedDatas = self.replyEnableDatas.filter({ data in failedHandles.contains(where: { $0.address == data.key }) })
                    failedDatas.forEach { data in
                        self.replyEnableDatas.updateValue(self.initReplyEnableDatas[data.key] ?? false, forKey: data.key)
                    }
                    self.tableView.reloadData()
                }
            }else {
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
            }
        }
    }
    
}

extension DevicesReplySetViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return groups.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let group = groups[section]
        if showSections.contains(section) {
            return max(group.nodes.count, 1) // 无数据时显示空数据cell
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let isLast = indexPath.section == tableView.numberOfSections - 1 && indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1
        
        let group = groups[indexPath.section]
        if indexPath.row == 0 && group.nodes.isEmpty { // 没有设备
            let emptyCell = tableView.dequeueReusableCell(withIdentifier: "emptyCell", for: indexPath) as! CustomTableViewCell
            emptyCell.cellStyle = .none
            emptyCell.titleLabel.text = "no_devices".localizedString
            emptyCell.titleLabel.textColor = SubText_Color
            emptyCell.titleLabel.font = FONTS(SCRYFrom(14))
            emptyCell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
            emptyCell.configureCell(isFirst: false, isLast: isLast)
            return emptyCell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        
        let node = group.nodes[indexPath.row]
        cell.cellStyle = .switch
        cell.iconImageView.isHidden = false
        cell.iconImageView.image = UIImage(named: node.iconName)
        cell.titleX = SCRXFrom(54)
        cell.titleLabel.text = node.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        
//        cell.configureCell(isFirst: false, isLast: isLast)
        cell.enabledSwitch.isEnabled = replyEnableDatas[node.primaryUnicastAddress] ?? true
//        node.features == nil || node.features!.relay == NodeFeatureState.enabled
//       && node.supportEnOceanProxy  && !MeshNetworkManager.instance.switchs.contains(where: { $0.id != switchData.id && $0.deleteProxyNodeAddress == node.primaryUnicastAddress })
        
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(13), weight: .light)
        cell.contentLabel.isHidden = false
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.contentHorizontalPriority = .required
        cell.selectionStyle = .none
        cell.iconImageClickCallback = {
            MeshAPI.identify(address: node.primaryUnicastAddress)
        }
        cell.switchActionCallback = {[weak self] isOn in
            guard let self = self else { // , node.enOceanMacAddress == nil || macAddress == self.switchData.enOceanMacAddress
                return
            }
            guard node.isKeybindComplete else {
                XWHUDManager.showTipHUD("switch_proxy_repair_message".localizedString, isLineFeed: true, afterDelay: 2)
                return
            }
            
            self.replyEnableDatas.updateValue(isOn, forKey: node.primaryUnicastAddress)
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {

        
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupSwitchEnOceanProxyHeaderView
//        headerView.backgroundColor = .white
//        headerView.contentView.backgroundColor = .clear // 清除默认背景颜色
//        // 创建自定义背景视图
//        if headerView.backgroundView == nil {
//            let backgroundView = UIView()
//            backgroundView.backgroundColor = .systemBlue // 设置背景颜色
//            headerView.backgroundView = backgroundView
//        }
        
        let group = groups[section]
        headerView.titleLabel.text = group.name
        headerView.contentLabel.text = nil
        headerView.isShow = showSections.contains(section)
//        headerView.enableSwitch.isHidden = false
//        headerView.enableSwitch.isEnabled = !replyEnableDatas.filter({ data in group.nodes.contains(where: { $0.primaryUnicastAddress == data.key }) }).values.contains(false)
//        let isLast = section == tableView.numberOfSections - 1 && !showSections.contains(section)
//        headerView.configureCell(isFirst: section == 0, isLast: isLast)
//        headerView.lineView.isHidden = isLast
        headerView.viewActionCallback = {[weak self] isShow in
            if isShow {
                self?.showSections.append(section)
            }else {
                self?.showSections.removeAll(where: { section == $0 })
            }
            tableView.reloadSections(IndexSet(integer: section), with: .automatic)
        }
//        headerView.switchEnableCallback = {[weak self] isOn in
//            guard let self else { return }
//            group.nodes.forEach({
//                self.replyEnableDatas.updateValue(isOn, forKey: $0.primaryUnicastAddress)
//            })
//        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(44)
    }
    
}
