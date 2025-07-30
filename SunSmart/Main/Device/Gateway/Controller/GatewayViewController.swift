//
//  GatewayViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/17.
//

import UIKit
import NordicSigMeshSDK

class GatewayViewController: UIViewController {

    private var tableView: UITableView!
    private var bottomView: DeviceBottomBtnView!
    
    let node: Node
    
    private var sections: [SectionType] = [.name, .info, .associatedSpaces, .apn, .serverInformation]
    
    init(node: Node) {
        self.node = node
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
    }

    @objc private func close() {
        dismiss(animated: true)
    }
    
    private func setupUI() {
        
        bottomView = DeviceBottomBtnView()
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(GatewayNameViewCell.classForCoder(), forCellReuseIdentifier: "name")
        tableView.register(GatewayServerInformationViewCell.classForCoder(), forCellReuseIdentifier: "serverInformation")
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }

}

extension GatewayViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionType = sections[section]
        switch sectionType {
        case .associatedSpaces:
            return 1
        case .info:
            return 2
        default:
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionType = sections[indexPath.section]
        var tableviewCell: UITableViewCell!
        
        switch sectionType {
        case .name:
            let nameCell = tableView.dequeueReusableCell(withIdentifier: "name", for: indexPath) as! GatewayNameViewCell
            nameCell.nameField.text = node.name
            nameCell.nameEditChangedCallback = { name in

                return nil
            }
            tableviewCell = nameCell
        case .info:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            cell.contentLabel.text = nil
            if indexPath.row == 0 {
                cell.titleLabel.text = "mac".localizedString
                cell.cellStyle = .none
            }else if indexPath.row == 1 {
                cell.titleLabel.text = "activate".localizedString
                cell.cellStyle = .switch
            }
            tableviewCell = cell
        case .associatedSpaces:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            cell.contentLabel.text = "Nodes: 70"
            cell.cellStyle = .icon
            cell.iconX = tableView.width - SCRXFrom(8) - 30
            cell.iconImageView.image = UIImage(named: "share_delete")
            cell.iconImageClickCallback = {
                
            }
            tableviewCell = cell
        case .apn:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
            cell.cellStyle = .arrow
            cell.titleLabel.text = nil
            cell.arrowImageView.image = UIImage(named: "arrow_down_black")
            cell.contentLabel.text = ""
            tableviewCell = cell
        case .serverInformation:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! GatewayServerInformationViewCell
            cell.serverAddressField.text = "192.168.8.35"
            cell.portField.text = "9884"
            cell.clientIdField.text = "92955d46d23643e1896150c53c6c6192"
            tableviewCell = cell
        }
        tableviewCell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
        return tableviewCell
    }
}

extension GatewayViewController {
 
    /// seciton 组类型
    enum SectionType {
        /// 名称
        case name
        /// 基本信息
        case info
        /// 关联spaces
        case associatedSpaces
        /// APN
        case apn
        /// MQTT服务器信息
        case serverInformation
    }
    
    enum CellType {
        
        var title: String {
            switch self {
            case .name:
                return "name".localizedString
            case .mac:
                return "mac".localizedString
            case .activate:
                return "activate".localizedString
            case .apn:
                return "apn".localizedString
            case .serverInformation:
                return "server_information".localizedString
            }
        }
        
        case name
        case mac
        case activate
//        case space
        case apn
        case serverInformation
    }
}
