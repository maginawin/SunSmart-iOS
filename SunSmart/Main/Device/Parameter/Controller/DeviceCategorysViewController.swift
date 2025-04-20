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
    private var categorys: [DeviceCategoryData] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "device_parameter_settings".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
        setupData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if categorys.isEmpty {
            tableView.showEmptyDataView(title: "no_devices".localizedString)
        }
    }
    
    @objc private func back() {
        dismiss(animated: true)
    }
    
    private func setupData() {
        
        MeshNetworkManager.instance.realNodes.forEach { node in
            if let pid = node.productIdentifier, node.isKeybindComplete {
                if let categoryData = categorys.first(where: { $0.pid == pid }) {
                    categoryData.devices.append(node)
                }else {
                    let data = DeviceCategoryData(name: node.categoryName ?? "Lighting", iconName: node.iconName, pid: pid, devices: [node])
                    categorys.append(data)
                }
            }
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
            make.top.equalTo((navigationController?.navigationBar.height ?? 0) + SCRYFrom(7))
            make.left.right.bottom.equalToSuperview()
        }
    }

}
 
extension DeviceCategorysViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return categorys.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .icon
        let data = categorys[indexPath.row]
        cell.iconImageView.image = UIImage(named: data.iconName)
        cell.titleLabel.text = data.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.contentLabel.text = String(format: "0x%4X", data.pid)
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let category = categorys[indexPath.row]
        
        let vc = DeviceParameterDevicesViewController(devices: category.devices)
        navigationController?.pushViewController(vc, animated: true)
    }
    
}

extension DeviceCategorysViewController {
    
    class DeviceCategoryData {
        /// 类型名称
        let name: String
        /// 图标
        let iconName: String
        /// pid类型
        let pid: UInt16
        /// 对应类型设备list
        var devices: [Node]
        
        init(name: String, iconName: String, pid: UInt16, devices: [Node]) {
            self.name = name
            self.iconName = iconName
            self.pid = pid
            self.devices = devices
        }
    }
    
}
