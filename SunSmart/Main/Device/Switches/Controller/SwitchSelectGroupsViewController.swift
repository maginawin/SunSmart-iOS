//
//  SwitchSelectGroupsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/6.
//

import UIKit
import NordicSigMeshSDK

class SwitchSelectGroupsViewController: UIViewController {

    private lazy var tableView: UITableView = {
        let y = view.safeAreaLayoutGuide
        let tableV = UITableView()
        tableV.separatorStyle = .none
        tableV.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: 0, bottom: SCRYFrom(16), right: 0)
        tableV.backgroundColor = Background_Color
        tableV.register(SwitchSelectGroupsViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.rowHeight = SCRYFrom(44)
        tableV.dataSource = self
        tableV.delegate = self
        return tableV
    }()
    
    private lazy var selectAllBtn: UIButton = {
        let btn = UIButton(title: "select_all".localizedString, titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllAction))
        btn.setImagePosition(position: .left, spacing: SCRXFrom(8))
        return btn
    }()
    
    var groups: [Group]
    var selectGroups: [Group]
    /// 代理所在组
    var proxyGroup: Group?
    /// 当前自身所在组（组内操作）
    var currentGroup: Group?
    
    /// 选择groups回调
    var selectGroupsCallback: (([Group])->Void)?
    
    /// 是否可以编辑
    var editable: Bool = true
    
    init(groups: [Group], selectGroups: [Group]) {
        self.groups = groups
        self.selectGroups = selectGroups
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "select_group(s)".localizedString
        view.backgroundColor = Background_Color
        
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalToSuperview()
        }
        
        if groups.isEmpty {
            view.showEmptyDataView(title: "no_groups".localizedString, tipText: "scene_not_groups_message".localizedString)
        }else {
            if editable {
                selectAllBtn.isSelected = selectGroups.count == groups.count
                navigationItem.rightBarButtonItem = UIBarButtonItem(customView: selectAllBtn)
            }
        }
    }
    
    @objc private func selectAllAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
            selectGroups = groups
        }else {
            selectGroups.removeAll(where: { !(proxyGroup?.address == $0.address || currentGroup?.address == $0.address) })
        }
        tableView.reloadData()
        selectGroups.sort(by: { $0.address.address < $1.address.address })
        selectGroupsCallback?(selectGroups)
    }

}

extension SwitchSelectGroupsViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return groups.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SwitchSelectGroupsViewCell
        let group = groups[indexPath.row]
        cell.nameLabel.text = group.name
        let isSelected = selectGroups.contains(where: { $0.address.address == group.address.address })
        let isEnabled = !(isSelected && (proxyGroup?.address == group.address || currentGroup?.address == group.address))
        if editable && isEnabled {
            cell.selectImageView.image = UIImage(named: isSelected ? "device_select" : "device_select_un")
        }else {
            cell.selectImageView.image = isSelected ? UIImage(named: "device_select_disable") : UIImage(named: "device_select_un")?.withTintColor(RGB(216, 216, 216))
        }
        if group.nodes.isEmpty || !group.nodes.contains(where: { $0.state }) {
            cell.onoffBtn.setImage(UIImage(named: "scene_group_disable"), for: .normal)
        }else {
            cell.onoffBtn.setImage(UIImage(named: "scene_group_off"), for: .normal)
            cell.onoffBtn.isSelected = group.isOn
        }
        let isLast = indexPath.row == groups.count - 1
        cell.lineView.isHidden = isLast
        cell.configureCell(isFirst: indexPath.row == 0, isLast: isLast)
        cell.selectionStyle = .none
        cell.onOffCallback = { isOn in
            if group.nodes.count > 0 && group.nodes.contains(where: { $0.state }) {
                cell.onoffBtn.isSelected = isOn
                group.isOn = isOn
                MeshAPI.setGroupOnOffState(address: group.address.address, isOn: isOn)
            }
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard editable else {
            return
        }
        let group = groups[indexPath.item]
        if currentGroup?.address == group.address {
            XWHUDManager.showTipHUD("switch_group_deselected_message".localizedString, isLineFeed: true)
            return
        }
        if proxyGroup?.address == group.address {
            XWHUDManager.showTipHUD("switch_proxy_in_group_message".localizedString, isLineFeed: true)
            return
        }
        
        if selectGroups.contains(group) {
            selectGroups.removeAll(where: { $0.address.address == group.address.address })
        }else {
            selectGroups.append(group)
        }
        selectAllBtn.isSelected = selectGroups.count == groups.count
        if let cell = tableView.cellForRow(at: indexPath) as? SwitchSelectGroupsViewCell {
            cell.selectImageView.image = UIImage(named: selectGroups.contains(group) ? "device_select" : "device_select_un")
        }
        selectGroups.sort(by: { $0.address.address < $1.address.address })
        selectGroupsCallback?(selectGroups)
    }
    
}
