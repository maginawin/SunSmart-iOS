//
//  SwitchSelectPanelTypeController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/3/4.
//

import UIKit

class SwitchSelectPanelTypeController: UIViewController {

    private var tableView: UITableView!
    private var switchPanelTypes: [DeviceSwitchData.PanelType] = [.default, .scenes]
    var selectPanelType: DeviceSwitchData.PanelType = .default
    
    /// 是否已选择场景
    var scenesSelected: Bool = false
    var selectPanelTypeCallback: ((DeviceSwitchData.PanelType)->Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "select_panel".localizedString
        view.backgroundColor = Background_Color
        
        setupTableView()
    }
    
    private func setupTableView() {
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Background_Color
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
        tableView.register(GroupSwitchPanelViewCell.classForCoder(), forCellReuseIdentifier: "panel")
        tableView.register(SyncDevicesTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(288 + 8)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaInsets.top)
            make.left.right.equalToSuperview()
//            make.left.equalTo(SCRXFrom(16))
//            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalToSuperview()
        }
        
    }

}

extension SwitchSelectPanelTypeController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return switchPanelTypes.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let panelCell = tableView.dequeueReusableCell(withIdentifier: "panel", for: indexPath) as! GroupSwitchPanelViewCell
        let type = switchPanelTypes[indexPath.section]
        switch type {
        case .default:
            panelCell.key1ShortPressBtn.setTitle("switch_key_on".localizedString, for: .normal)
            panelCell.key2ShortPressBtn.setTitle("switch_key_off".localizedString, for: .normal)
            panelCell.key3ShortPressBtn.setTitle("switch_key_sceneA".localizedString, for: .normal)
            panelCell.key4ShortPressBtn.setTitle("switch_key_sceneB".localizedString, for: .normal)
        case .scenes:
            panelCell.key1ShortPressBtn.setTitle("switch_key_sceneA".localizedString, for: .normal)
            panelCell.key2ShortPressBtn.setTitle("switch_key_sceneB".localizedString, for: .normal)
            panelCell.key3ShortPressBtn.setTitle("switch_key_sceneC".localizedString, for: .normal)
            panelCell.key4ShortPressBtn.setTitle("switch_key_sceneD".localizedString, for: .normal)
        }
        panelCell.saveBtn.isHidden = true
        panelCell.deleteBtn.isHidden = true
//        panelCell.margin = SCRXFrom(16)
        panelCell.switchContentView.layer.borderWidth = type == selectPanelType ? 1 : 0
        panelCell.switchContentView.layer.borderColor = Bar_Color.cgColor
        return panelCell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! SyncDevicesTitleHeaderView
        headerView.titleLabel.text = switchPanelTypes[section].describe
        headerView.titleLabel.font = FONTS(14)
        headerView.titleLabel.textColor = TextBlack_Color
        headerView.titleLeftMargin = SCRXFrom(20)
        headerView.bottomMargin = 0
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let type = switchPanelTypes[section]
        return type == .default ? SCRYFrom(25) : SCRYFrom(33)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let type = switchPanelTypes[indexPath.section]
        guard type != selectPanelType else {
            return
        }
        
        selectPanelType = type
        tableView.reloadData()
        selectPanelTypeCallback?(type)
        
        // 是否已有场景
        if scenesSelected {
            SRAlertView(title: "notification".localizedString, message: "switch_panel_scenes_changed".localizedString, actions: [SRAlertAction(title: "ok".localizedString, style: .default)]).show()
        }
    }
}
