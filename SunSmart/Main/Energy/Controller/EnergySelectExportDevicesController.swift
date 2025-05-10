//
//  EnergySelectExportDevicesController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/29.
//

import UIKit
import NordicSigMeshSDK

class EnergySelectExportDevicesController: UIViewController {

    private var tableView: UITableView!
    private var groupsView: DeviceGroupsView!
    private var bottomView: DeviceParameterBottomView!
    
    private var selectDevices: [Node] = []
    private var groupDatas: [DeviceGroupsSelectData] = []
    /// 设备选择完成回调
    var devicesSelectDoneCallback: (([Node])->Void)?
    
    let devices: [Node]
    
    init(devices: [Node], selectDevices: [Node] = []) {
        self.devices = devices
        self.selectDevices = selectDevices
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "select_device(s)".localizedString
        view.backgroundColor = Background_Color
        
        devices.forEach { node in
            node.selectOn = false
            node.selectOff = false
            if let group = node.group {
                if let data = groupDatas.first(where: { $0.groupAddress == group.address.address }) {
                    data.addresss.append(node.primaryUnicastAddress)
                }else {
                    let data = DeviceGroupsSelectData(name: group.name, groupAddress: group.address.address, addresss: [node.primaryUnicastAddress], isSelected: false)
                    groupDatas.append(data)
                }
            }else { // 不在组内
                if let data = groupDatas.first(where: { $0.groupAddress == 0 }) {
                    data.addresss.append(node.primaryUnicastAddress)
                }else {
                    let data = DeviceGroupsSelectData(name: "not_in_group".localizedString, groupAddress: 0, addresss: [node.primaryUnicastAddress], isSelected: false)
                    groupDatas.insert(data, at: 0)
                }
            }
        }
        
        groupDatas.sort(by: { $0.groupAddress < $1.groupAddress })
        
        setupUI()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if devices.isEmpty {
            tableView.showEmptyDataView(title: "no_devices".localizedString)
            bottomView.isHidden = true
            groupsView.isHidden = true
        }
    }
    
    @objc private func cancelAction() {
        
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func doneAction() {
        devicesSelectDoneCallback?(selectDevices)
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {
        
        
        bottomView = DeviceParameterBottomView()
        bottomView.leftBtn.setTitle("alert_item_cancel".localizedString, for: .normal)
        bottomView.rightBtn.setTitle("done".localizedString, for: .normal)
        bottomView.leftBtn.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        bottomView.rightBtn.addTarget(self, action: #selector(doneAction), for: .touchUpInside)
        bottomView.rightBtn.isEnabled = false
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(DeviceParameterDeviceCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.rowHeight = SCRYFrom(60)
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(8), left: 0, bottom: 0, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Background_Color
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        groupsView = DeviceGroupsView()
        groupsView.sortBtn.isHidden = true
        groupsView.selectCountLabel.isHidden = false
        groupsView.lineView.isHidden = true
        groupsView.datas = groupDatas
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        groupsView.delegate = self
        view.addSubview(groupsView)
        groupsView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(tableView)
//            make.bottom.equalToSuperview()
//            make.height.greaterThanOrEqualTo(SCRYFrom(64))
        }
        
    }
    
 



}

extension DeviceParameterDeviceCell {
    
    /// 更新设备cell布局
    fileprivate func updateDeviceCellLayout() {
        
        selectImageView.snp.remakeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(8))
        }
        nameLabel.snp.remakeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.right.equalTo(identifyBtn.snp.left).offset(SCRXFrom(-30)).priority(.low)
        }
        groupNameLabel.snp.remakeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(3))
        }
        
    }
}

extension EnergySelectExportDevicesController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return devices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceParameterDeviceCell
        let device = devices[indexPath.row]
        cell.device = device
        cell.selectState = selectDevices.contains(device) ? .selected : .none
        cell.updateDeviceCellLayout()
        cell.ratedPowerLabel.isHidden = true
        cell.pwmLabel.isHidden = true
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let device = devices[indexPath.row]
        if let index = selectDevices.firstIndex(of: device) {
            selectDevices.remove(at: index)
        }else {
            selectDevices.append(device)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        
        if let group = device.group, let data = groupDatas.first(where: { $0.groupAddress == group.address.address }) {
            let groupSelectDevices = selectDevices.filter({ device in data.addresss.contains(device.primaryUnicastAddress) })
            data.isSelected = groupSelectDevices.count == data.addresss.count
//            !selectDevices.contains(where: { device in !data.addresss.contains(device.primaryUnicastAddress) })
            groupsView.datas = groupDatas
        }
        groupsView.selectAllBtn.isSelected = selectDevices.count == devices.count
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        bottomView.rightBtn.isEnabled = selectDevices.count > 0
    }
    
}

extension EnergySelectExportDevicesController: DeviceParameterDeviceCellDelegate {
    
    /// 设备identity事件
    func cell(_ cell: DeviceParameterDeviceCell, deviceIdentifyAction device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 设备onoff事件
    func cell(_ cell: DeviceParameterDeviceCell, deviceOnOffAction device: Node, isOn: Bool) {
        device.isOn = isOn
        device.selectOn = isOn
        device.selectOff = !isOn
        cell.device = device
        MeshAPI.setNodeOnOffState(address: device.primaryUnicastAddress, isOn: isOn)
    }
}

extension EnergySelectExportDevicesController: DeviceGroupsViewDelegate {
    func view(_ view: DeviceGroupsView, didSelectAllAction selectAll: Bool) {
        if selectAll {
            selectDevices = devices
        }else {
            selectDevices.removeAll()
        }
        tableView.reloadData()
        groupDatas.forEach({
            $0.isSelected = selectAll
        })
        groupsView.datas = groupDatas
        groupsView.selectAllBtn.isSelected = selectDevices.count == devices.count
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        bottomView.rightBtn.isEnabled = selectDevices.count > 0
    }
    
    func view(_ view: DeviceGroupsView, didSelectData data: DeviceGroupsSelectData) {
        let groupDevices = data.addresss.compactMap({ address in devices.first(where: { $0.primaryUnicastAddress == address }) })
        if data.isSelected {
            selectDevices.append(contentsOf: groupDevices)
        }else {
            selectDevices.removeAll(where: { device in groupDevices.contains(device) })
        }
        groupsView.selectAllBtn.isSelected = selectDevices.count == devices.count
        groupsView.selectCountLabel.text = "\(selectDevices.count)/\(devices.count)"
        tableView.reloadData()
        bottomView.rightBtn.isEnabled = selectDevices.count > 0
    }
    
    func viewDidSortAction(_ view: DeviceGroupsView) {
        
    }
}
