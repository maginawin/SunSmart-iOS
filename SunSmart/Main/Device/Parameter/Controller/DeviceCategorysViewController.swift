//
//  DeviceCategorysViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/11.
//

import UIKit
import NordicSigMeshSDK

class DeviceCategorysViewController: UIViewController {

    private var tableView: UITableView!
    private var allDevices: [Node] = []
    private var categorys: [[DeviceCategoryData]] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "device_parameter_settings".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
        setupData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if categorys.flatMap({ $0 }).isEmpty && allDevices.isEmpty {
            tableView.showEmptyDataView(title: "no_devices".localizedString)
        }
    }
    
    @objc private func back() {
        dismiss(animated: true)
    }
    
    private func setupData() {
        var typeCategorys: [DeviceCategoryData] = []
        
        MeshNetworkManager.instance.realNodes.forEach { node in
            if let pid = node.productIdentifier, node.isKeybindComplete, node.supportSetParameter {
                allDevices.append(node)
                if let categoryData = typeCategorys.first(where: { $0.pid == pid }) {
                    categoryData.devices.append(node)
                }else {
                    let data = DeviceCategoryData(name: node.categoryName ?? "Lighting", iconName: node.iconName, pid: pid, devices: [node])
                    typeCategorys.append(data)
                }
            }
        }
        
        categorys.removeAll()
        if !allDevices.isEmpty {
            let allData = DeviceCategoryData(name: "all_devices".localizedString, iconName: "device_Lighting", pid: nil, devices: allDevices)
            categorys.append([allData])
        }
        if !typeCategorys.isEmpty {
            categorys.append(typeCategorys)
        }
    }

    private func setupUI() {
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = SCRYFrom(44)
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: 0, bottom: 0, right: 0)
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(7))
            make.left.right.bottom.equalToSuperview()
        }
    }

}
 
extension DeviceCategorysViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return categorys.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return categorys[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        let data = categorys[indexPath.section][indexPath.row]
        cell.cellStyle = .icon
        cell.iconImageView.image = UIImage(named: data.iconName)
        cell.titleLabel.text = data.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        if data.pid == nil {
            cell.contentLabel.text = nil
        } else {
            cell.contentLabel.text = String(format: "0x%4X", data.pid ?? 0)
        }
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = categorys[indexPath.section][indexPath.row]
        
        if category.pid == nil {
            let vc = DeviceParameterSettingsController(devices: category.devices, displayMode: .behaviorOnly)
            navigationController?.pushViewController(vc, animated: true)
            return
        }
        
        let vc = DeviceParameterDevicesViewController(devices: category.devices)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return SCRYFrom(16)
    }
    
}

extension DeviceCategorysViewController {
    
    class DeviceCategoryData {
        /// 类型名称
        let name: String
        /// 图标
        let iconName: String
        /// pid类型
        let pid: UInt16?
        /// 对应类型设备list
        var devices: [Node]
        
        init(name: String, iconName: String, pid: UInt16?, devices: [Node]) {
            self.name = name
            self.iconName = iconName
            self.pid = pid
            self.devices = devices
        }
    }
    
}
