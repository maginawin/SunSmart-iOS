//
//  DeviceInformationViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/29.
//

import UIKit
import NordicSigMeshSDK

class DeviceInformationViewController: UIViewController {

    private var tableView: UITableView!
    
    private var sections: [SectionType] = [.deviceInfo, .group, .scene]
    private var sectionShowMap: [SectionType: Bool] = [:]
    private var deviceInfoModels: [CustomCellModel] = []
    
    let node: Node
    
    init(node: Node) {
        self.node = node
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "information".localizedString
        view.backgroundColor = Background_Color
        
        setupDeviceInfoDataSource()
        
        sectionShowMap = [.deviceInfo: true, .group: true, .scene: true]
        
        setupTableView()
        getData()
    }
    
    private func getData() {
        
        if let model = node.firmwareUpdateServerModel {
            MeshAPI.sendMessage(message: FirmwareUpdateInformationGet(firstIndex: 0, entriesLimit: 1), model: model) {[weak self] response in
//                guard let self = self else { return }
                self?.setupDeviceInfoDataSource()
                self?.tableView.reloadSections(IndexSet(integer: 0), with: .none)
            }
        }
    }
    
    /// 设备数据
    private func setupDeviceInfoDataSource() {
        
//        let messageColor = RGB(13, 14, 28, 0.5)
        
        let nameModel = CustomCellModel(title: "name".localizedString, content: node.name, style: .none)
        
        let macModel = CustomCellModel(icon: UIImage(named: "copy"), title: "MAC", content: node.macAddressResult, style: .icon)
        
        let devModel = CustomCellModel(title: "model".localizedString, content: "--", style: .none)
        let typeName = node.categoryName
        let deviceTypeModel = CustomCellModel(title: "device_type".localizedString, content: typeName ?? "--", style: .none)
        
        let firmwareModel = CustomCellModel(title: "firmware".localizedString, content: node.firmwareVersion ?? "--", style: .none)
        
        let singleStrengthModel = CustomCellModel(title: "signal_strength".localizedString, content: node.rssi != nil ? "\(node.rssi!)dB" : "--", style: .none)
        
        deviceInfoModels = [nameModel, macModel, devModel, deviceTypeModel, firmwareModel, singleStrengthModel]
    }
    
    private func setupTableView() {
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = Background_Color
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DeviceLightInfoSectionView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    


}

extension DeviceInformationViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionType = sections[section]
        switch sectionType {
        case .deviceInfo:
            let isShow = sectionShowMap[sectionType] ?? false
            return isShow ? deviceInfoModels.count : 0
        case .scene:
            let sceneCount = node.scenes.count
            let isShow = sectionShowMap[sectionType] ?? false
            return (isShow && sceneCount > 0) ? sceneCount : 0
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionType = sections[section]
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceLightInfoSectionView
        headerView.contentLabel.isHidden = true
        headerView.showImageView.isHidden = true
        switch sectionType {
        case .deviceInfo:
            headerView.titleLabel.text = "device".localizedString
            headerView.showImageView.isHidden = false
            let isShow = sectionShowMap[sectionType] ?? false
            headerView.showImageView.image = UIImage(named: isShow ? "arrow_up": "arrow_down")
        case .group:
            headerView.titleLabel.text = "group".localizedString
            headerView.contentLabel.isHidden = false
            headerView.contentLabel.text = node.group?.name ?? "device_not_added_group".localizedString
        case .scene:
            headerView.titleLabel.text = "scene".localizedString
            if node.scenes.count > 0 {
                headerView.showImageView.isHidden = false
                let isShow = sectionShowMap[sectionType] ?? false
                headerView.showImageView.image = UIImage(named: isShow ? "arrow_up": "arrow_down")
            }else {
                headerView.contentLabel.isHidden = false
                headerView.contentLabel.text = "device_not_added_scene".localizedString
            }
        }
        headerView.sectionViewClickCallback = {[weak self] in
            if sectionType == .deviceInfo || sectionType == .scene {
                let isShow = self?.sectionShowMap[sectionType] ?? false
                self?.sectionShowMap[sectionType] = !isShow
                self?.tableView.reloadSections(IndexSet(integer: section), with: .automatic)
            }
        }
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        let sectionType = sections[indexPath.section]
//        if sectionType == .deviceInfo && indexPath.row == 3 {
//            return SCRYFrom(60)
//        }
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let sectionType = sections[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.selectionStyle = .none
        if sectionType == .deviceInfo {
            let model = deviceInfoModels[indexPath.row]
            cell.cellStyle = model.style
            cell.titleLabel.text = model.title
            cell.titleLabel.textColor = model.titleColor
            cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
            cell.contentLabel.text = model.content
            cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            cell.contentLabel.textColor = model.contentColor
            cell.contentLabel.numberOfLines = 2
            cell.titleX = SCRXFrom(32)
            if model.style == .icon {
                cell.iconImageView.image = model.icon
                cell.iconX = tableView.width - 30 - SCRXFrom(8)
                cell.arrowImageView.isHidden = true
            }
//            cell.lineView.isHidden = indexPath.row != deviceInfoModels.count - 1
            //                tableView.numberOfRows(inSection: indexPath.section) - 1 != indexPath.row
        }else {
            let scene = node.scenes[indexPath.row]
            cell.cellStyle = .none
            cell.titleLabel.text = scene.name
            cell.titleLabel.textColor = TextBlack_Color.withAlphaComponent(0.5)
            cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            //                Font_Medium_Size(SCRYFrom(14))
            if let sceneData = node.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                if sceneData.lightness == 0 {
                    cell.contentLabel.text = "off".localizedString
                }else {
                    if node.temperatureModel != nil {
                        let cct100 = Node.getTemperature100(temperature: UInt16(sceneData.cct), range: node.lightCTLTemperatureRange ?? node.defalutLightCTLTemperatureRange)
                        cell.contentLabel.text = "\("brightness".localizedString)-\(Node.getLightness100(lightness: sceneData.lightness))%.\("cct".localizedString)-\(cct100)%"
                    }else {
                        cell.contentLabel.text = "\("brightness".localizedString)-\(Node.getLightness100(lightness: sceneData.lightness))%."
                    }
                }
            }
            //                "Brightness-20%."
            cell.contentLabel.textColor = RGB(13, 14, 28, 0.5)
            cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
//            cell.lineView.isHidden = false
        }
        cell.lineView.backgroundColor = Line_Color
        //            cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let sectionType = sections[indexPath.section]
        if sectionType == .deviceInfo && indexPath.row == 1 { // 复制
            let model = deviceInfoModels[indexPath.row]
            if let content = model.content {
                let pasteboard = UIPasteboard.general
                pasteboard.string = content
                XWHUDManager.showTipHUD(inView: "copy_success".localizedString, isLineFeed: false)
            }
        }
    }
    
}

extension DeviceInformationViewController {
    
    /// 组类型
    enum SectionType {
        /// 设备信息
        case deviceInfo
        /// 组
        case group
        /// 场景
        case scene
    }
    
}
