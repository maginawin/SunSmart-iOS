//
//  BleFirmwareTypeUpdateViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/8/22.
//

import UIKit
import NordicSigMeshSDK

protocol BleFirmwareTypeUpdateViewCellDelegate: AnyObject {
    
    /// 展开/收起设备列表
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, didShowDevices show: Bool)
    
    /// 选择设备list更新回调
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, selectDevicesDidChange selectDevices: [Node])
    
    /// 设备开始升级
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, startUpgraded device: Node)
    
    /// 设备升级失败原因
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, failureReasonAction device: Node)
    
    /// 设备识别
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, identifying device: Node)
    
    /// 查看当前版本
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, viewCurrentTargetVersion firmwareTypeData: FirmwareUpdateTypeData)
}

class BleFirmwareTypeUpdateViewCell: UICollectionViewCell {
    
    /// 设备类型
    private var deviceTypeView: UIView!
    private var deviceTypeLabel: UILabel!
    private var productIdLabel: UILabel!
    private var deviceTypeLineView: UIView!
    
    /// 本地版本
    private var targetVersionView: UIView!
    private var targetVersionTitleLabel: UILabel!
    private var targetVersionLabel: UILabel!
    private var newVersionView: UIView!
    private var versionInfoImageView: UIImageView!
    private var targetVersionLineView: UIView!
    
    /// 设备数量
    private var deviceNumberView: UIView!
    private var totalLabel: UILabel!
    private var totalNumberLabel: UILabel!
    private var upgradedLabel: UILabel!
    private var upgradedNumberLabel: UILabel!
    
    /// 设备列表
    private var deviceTableView: UITableView!
    
    private weak var headerView: BleFirmwareTypeUpdateHeaderView?
    
    /// 展开/收起
    private var pinchView: UIView!
    private var arrowImageView: UIImageView!
    
    var firmwareTypeData: FirmwareUpdateTypeData! {
        didSet {
            deviceTypeLabel.text = firmwareTypeData.categoryName
            productIdLabel.text = String(format: "0x%04X", firmwareTypeData.productId)
            if let targetVersion = firmwareTypeData.targetVersion, let serverVersion = firmwareTypeData.serverData?.version {
                newVersionView.isHidden = !(serverVersion.compare(targetVersion) == .orderedDescending)
            }else {
                newVersionView.isHidden = true
            }
            targetVersionLabel.text = firmwareTypeData.targetVersion ?? "None"
            
            totalNumberLabel.text = "\(firmwareTypeData.nodes.count)"
            if let targetVersion = firmwareTypeData.targetVersion{
                
                // 已升级的设备
                let upgradedCount = firmwareTypeData.nodes.filter({ $0.firmwareVersion != nil && targetVersion.compare($0.firmwareVersion!) == .orderedSame }).count
                
//                let  firmwareTypeData.nodes.count - firmwareTypeData.upgradedNodes.count
                upgradedNumberLabel.text = "\(upgradedCount)"
//                "\(firmwareTypeData.upgradedNodes.count)"
            }else {
                upgradedNumberLabel.text = "--"
            }
            reload()
        }
    }
    
    weak var delegate: BleFirmwareTypeUpdateViewCellDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowOpacity = 1
        layer.shadowRadius = SCRYFrom(10)
        layer.shadowColor = RGB(0, 0, 0, 0.05).cgColor
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Action
    /// 当前版本
    @objc private func targetVersionAction() {
        delegate?.cell(self, viewCurrentTargetVersion: firmwareTypeData)
    }
    
    func reload() {
        if firmwareTypeData.isShow {
            
            if firmwareTypeData.nodes.count > 4 {
                deviceTableView.isScrollEnabled = true
            }else {
                deviceTableView.isScrollEnabled = false
            }
            
            arrowImageView.transform = .init(rotationAngle: .pi)
            deviceNumberView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(52))
            }
            deviceTableView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(44) + CGFloat(min(firmwareTypeData.nodes.count, 4)) * deviceTableView.rowHeight).priority(.low)
            }
            pinchView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(38))
            }
            arrowImageView.snp.updateConstraints { make in
                make.top.equalTo(SCRYFrom(4))
            }
        }else {
            arrowImageView.transform = .identity
            deviceNumberView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(40))
            }
            deviceTableView.snp.updateConstraints { make in
                make.height.equalTo(0).priority(.low)
            }
            pinchView.snp.updateConstraints { make in
                make.height.equalTo(SCRYFrom(32))
            }
            arrowImageView.snp.updateConstraints { make in
                make.top.equalTo(0)
            }
            
        }
        deviceTableView.reloadData()
//        CATransaction.setDisableActions(true)
        
//        CATransaction.commit()
//        self.layoutIfNeeded()
    }
    
    /// 展开/收起
    @objc private func pinchAction() {
        firmwareTypeData.isShow = !firmwareTypeData.isShow
        
        reload()
//        if isShow {
//            deviceNumberView.snp.updateConstraints { make in
//                make.height.equalTo(SCRYFrom(52))
//            }
//            deviceTableView.snp.updateConstraints { make in
//                make.height.equalTo(SCRYFrom(44) + SCRYFrom(60))
//            }
//            pinchView.snp.updateConstraints { make in
//                make.height.equalTo(SCRYFrom(38))
//            }
//        }else {
//            deviceNumberView.snp.updateConstraints { make in
//                make.height.equalTo(SCRYFrom(40))
//            }
//            deviceTableView.snp.updateConstraints { make in
//                make.height.equalTo(0)
//            }
//            pinchView.snp.updateConstraints { make in
//                make.height.equalTo(SCRYFrom(32))
//            }
//        }
        
        self.delegate?.cell(self, didShowDevices: firmwareTypeData.isShow)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        deviceTypeView = UIView()
        contentView.addSubview(deviceTypeView)
        deviceTypeView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        deviceTypeLabel = UILabel(text: "BLE to 0-10V converter ", textColor: TextBlack_Color, fontSize: 14)
        deviceTypeView.addSubview(deviceTypeLabel)
        deviceTypeLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(22))
        }
        
        productIdLabel = UILabel(text: "0xBD01", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        deviceTypeView.addSubview(productIdLabel)
        productIdLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(deviceTypeLabel)
        }
        
        deviceTypeLineView = UIView()
        deviceTypeLineView.backgroundColor = RGB(236, 236, 236)
        deviceTypeView.addSubview(deviceTypeLineView)
        deviceTypeLineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
        targetVersionView = UIView()
        targetVersionView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(targetVersionAction)))
        contentView.addSubview(targetVersionView)
        targetVersionView.snp.makeConstraints { make in
            make.left.right.equalTo(deviceTypeView)
            make.top.equalTo(deviceTypeView.snp.bottom)
            make.height.equalTo(SCRYFrom(49))
        }
        
        targetVersionTitleLabel = UILabel(text: "current_target_version".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        targetVersionView.addSubview(targetVersionTitleLabel)
        targetVersionTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.centerY.equalToSuperview()
        }
        
        versionInfoImageView = UIImageView(image: UIImage(named: "firmware_version_more"))
        targetVersionView.addSubview(versionInfoImageView)
        versionInfoImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalToSuperview()
        }
        
        targetVersionLabel = UILabel(text: "1.2.0", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        targetVersionView.addSubview(targetVersionLabel)
        targetVersionLabel.snp.makeConstraints { make in
            make.right.equalTo(versionInfoImageView.snp.left).offset(SCRXFrom(-9))
            make.centerY.equalTo(versionInfoImageView)
        }
        
        newVersionView = UIView()
        newVersionView.backgroundColor = RGB(255, 72, 49)
        newVersionView.layer.cornerRadius = 2
        targetVersionView.addSubview(newVersionView)
        newVersionView.snp.makeConstraints { make in
            make.right.equalTo(targetVersionLabel.snp.left).offset(SCRXFrom(-6))
            make.centerY.equalTo(targetVersionLabel)
            make.width.height.equalTo(4)
        }
        
        targetVersionLineView = UIView()
        targetVersionLineView.backgroundColor = deviceTypeLineView.backgroundColor
        targetVersionView.addSubview(targetVersionLineView)
        targetVersionLineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
        deviceNumberView = UIView()
        contentView.addSubview(deviceNumberView)
        deviceNumberView.snp.makeConstraints { make in
            make.left.right.equalTo(targetVersionView)
            make.top.equalTo(targetVersionView.snp.bottom)
            make.height.equalTo(SCRYFrom(40))
        }
        
        totalLabel = UILabel(text: "total".localizedString + ":", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        deviceNumberView.addSubview(totalLabel)
        totalLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(17))
        }
        
        totalNumberLabel = UILabel(text: "10", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        totalNumberLabel.textAlignment = .right
        deviceNumberView.addSubview(totalNumberLabel)
        totalNumberLabel.snp.makeConstraints { make in
            make.left.equalTo(totalLabel.snp.right)
            make.centerY.equalTo(totalLabel)
            make.width.equalTo(SCRXFrom(34))
        }
        
        upgradedNumberLabel = UILabel(text: "10", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        upgradedNumberLabel.textAlignment = .right
        deviceNumberView.addSubview(upgradedNumberLabel)
        upgradedNumberLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-26))
            make.centerY.equalTo(totalLabel)
            make.width.equalTo(SCRXFrom(34))
        }
        
        upgradedLabel = UILabel(text: "upgraded".localizedString + ":", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        deviceNumberView.addSubview(upgradedLabel)
        upgradedLabel.snp.makeConstraints { make in
            make.right.equalTo(upgradedNumberLabel.snp.left)
            make.centerY.equalTo(upgradedNumberLabel)
        }
        
        deviceTableView = UITableView(frame: .zero, style: .grouped)
        deviceTableView.backgroundColor = Background_Color
        deviceTableView.layer.cornerRadius = SCRYFrom(8)
        deviceTableView.separatorStyle = .none
        deviceTableView.rowHeight = SCRYFrom(60)
        deviceTableView.register(BleFirmwareTypeUpdateHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        deviceTableView.register(BleFirmwareUpdateDeviceCell.classForCoder(), forCellReuseIdentifier: "cell")
        deviceTableView.dataSource = self
        deviceTableView.delegate = self
        contentView.addSubview(deviceTableView)
        deviceTableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(deviceNumberView.snp.bottom)
            make.height.equalTo(0).priority(.low)
        }
        
        pinchView = UIView()
        pinchView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pinchAction)))
        contentView.addSubview(pinchView)
        pinchView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(deviceTableView.snp.bottom)
            make.height.equalTo(SCRYFrom(34))
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down_black"))
        pinchView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(4))
            make.centerX.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
    }
    
}

extension BleFirmwareTypeUpdateViewCell: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return firmwareTypeData.isShow ? 1 : 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return firmwareTypeData.nodes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! BleFirmwareUpdateDeviceCell
        cell.device = firmwareTypeData.nodes[indexPath.item]
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! BleFirmwareTypeUpdateHeaderView
        let canSelectNodes = self.firmwareTypeData.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade })
        headerView.selectAllBtn.isSelected = canSelectNodes.count == canSelectNodes.filter({ $0.selectedState == .selected }).count && canSelectNodes.count > 0
        headerView.selectAllBtn.isEnabled = canSelectNodes.count > 0
        headerView.selectAllCallback = {[weak self] allSelect in
            guard let self = self else { return }
            let canSelectNodes = self.firmwareTypeData.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade })
            
            if allSelect {
                canSelectNodes.forEach({ $0.selectedState = .selected })
            }else {
                canSelectNodes.forEach({ $0.selectedState = .unselected })
            }
            
            // 未选中全部设备
            if canSelectNodes.contains(where: { $0.selectedState == .unselected }) || canSelectNodes.isEmpty {
                headerView.selectAllBtn.isSelected = false
            }else { // 已选择全部设备
                headerView.selectAllBtn.isSelected = true
            }
            
            tableView.reloadData()
            self.delegate?.cell(self, selectDevicesDidChange: canSelectNodes.filter({ $0.selectedState == .selected }))
        }
        self.headerView = headerView
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
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let node = firmwareTypeData.nodes[indexPath.row]
        if node.updateState.rawValue == Node.UpdateState.none.rawValue && node.enableUpgrade {
            if node.selectedState == .selected {
                node.selectedState = .unselected
            }else {
                node.selectedState = .selected
            }
            let canSelectNodes = firmwareTypeData.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade })
            // 未选中全部设备
            if canSelectNodes.contains(where: { $0.selectedState == .unselected }) {
                headerView?.selectAllBtn.isSelected = false
            }else { // 已选择全部设备
                headerView?.selectAllBtn.isSelected = true
            }
            tableView.reloadRows(at: [indexPath], with: .none)
            delegate?.cell(self, selectDevicesDidChange: canSelectNodes.filter({ $0.selectedState == .selected }))
        }else if !node.enableUpgrade, let rssi = node.rssi, rssi < -80 { // 信号太差不能选择
            XWHUDManager.showTipHUD("signal_below_message".localizedString, isLineFeed: true)
        }
    }
    
}

extension BleFirmwareTypeUpdateViewCell: BleFirmwareUpdateDeviceCellDelegate {
    
    /// identify点击回调
    func cell(cell: BleFirmwareUpdateDeviceCell, identifyingAction device: Node) {
        delegate?.cell(self, identifying: device)
    }
    
    /// 开始升级点击回调
    func cell(cell: BleFirmwareUpdateDeviceCell, startUpgradeAction device: Node) {
        delegate?.cell(self, startUpgraded: device)
    }
    
    /// 失败原因点击回调
    func cell(cell: BleFirmwareUpdateDeviceCell, failureReasonAction device: Node) {
        delegate?.cell(self, failureReasonAction: device)
    }
    
}

class BleFirmwareTypeUpdateHeaderView: UITableViewHeaderFooterView {
    
    var selectAllBtn: UIButton!
    private var lineView: UIView!
    /// 选中所有点击事件
    var selectAllCallback: ((Bool)->Void)?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        selectAllCallback?(!sender.isSelected)
    }
    
    private func setupUI() {
        
        selectAllBtn = UIButton(title: "select_all".localizedString, titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        selectAllBtn.setImagePosition(position: .left, spacing: SCRXFrom(8))
        selectAllBtn.setImage(UIImage(named: "device_select_disable"), for: .disabled)
        addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color1
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
    }
    
}

protocol BleFirmwareUpdateDeviceCellDelegate: AnyObject {
    
    /// identify点击回调
    func cell(cell: BleFirmwareUpdateDeviceCell, identifyingAction device: Node)
    
    /// 开始升级点击回调
    func cell(cell: BleFirmwareUpdateDeviceCell, startUpgradeAction device: Node)
    
    /// 失败原因点击回调
    func cell(cell: BleFirmwareUpdateDeviceCell, failureReasonAction device: Node)
}

class BleFirmwareUpdateDeviceCell: UITableViewCell {
    
    private var selectedImageView: UIImageView!
    private var deviceImageView: UIImageView!
    private var nameLabel: UILabel!
    private var rssiLabel: UILabel!
    private var versionLabel: UILabel!
    private var updateStateBtn: UIButton!
    
    weak var delegate: BleFirmwareUpdateDeviceCellDelegate?
    
    var device: Node! {
        didSet {
            nameLabel.text = device.name
            versionLabel.text = device.firmwareVersion
            
            selectedImageView.isHidden = !device.enableUpgrade
            updateStateBtn.isHidden = !device.enableUpgrade
            
            
            switch device.updateState {
            case .none:
                if device.enableUpgrade {
                    switch device.selectedState {
                    case .selected:
                        selectedImageView.image = UIImage(named: "device_select")
                    case .unselected:
                        selectedImageView.image = UIImage(named: "device_select_un")
                    case .disabled:
                        selectedImageView.image = UIImage(named: "device_select_disable")
                    }
                    updateStateBtn.setImage(UIImage(named: "firmware_update"), for: .normal)
                }
            case .successful:
                selectedImageView.isHidden = true
                updateStateBtn.isHidden = false
                updateStateBtn.setImage(UIImage(named: "device_add_success"), for: .normal)
            case .failure:
                selectedImageView.image = UIImage(named: "device_select_disable")
                updateStateBtn.setImage(UIImage(named: "device_add_fail"), for: .normal)
            }
            
            if let rssi = device.rssi {
                nameLabel.textColor = TextBlack_Color
                rssiLabel.text = "\(rssi)dB"
                rssiLabel.textColor = rssi >= -80 ? SubText_Color : Red_Color
                deviceImageView.image = UIImage(named: device.iconName)
            }else {
                nameLabel.textColor = SubText_Color
                deviceImageView.image = UIImage(named: device.iconName)?.withTintColor(SubText_Color)
                rssiLabel.text = "--"
                rssiLabel.textColor = SubText_Color
                selectedImageView.isHidden = true
            }
            
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 识别
    @objc private func identifyingAction() {
        delegate?.cell(cell: self, identifyingAction: device)
    }
    
    /// 更新状态点击
    @objc private func updateStateBtnAction() {
        switch device.updateState {
        case .none:
            delegate?.cell(cell: self, startUpgradeAction: device)
        case .failure:
            delegate?.cell(cell: self, failureReasonAction: device)
        default:
            break
        }
    }
    
    private func setupUI() {
        
        selectedImageView = UIImageView(image: UIImage(named: "device_select_un"))
        contentView.addSubview(selectedImageView)
        selectedImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        deviceImageView = UIImageView(image: UIImage(named: "device_light"))
        deviceImageView.isUserInteractionEnabled = true
        deviceImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(identifyingAction)))
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(selectedImageView.snp.right).offset(SCRXFrom(2))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        nameLabel = UILabel(text: "ID001", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.width.lessThanOrEqualTo(SCRXFrom(150))
        }
        
        rssiLabel = UILabel(text: "-70dB", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(rssiLabel)
        rssiLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(3))
        }
        
        versionLabel = UILabel(text: "1.0.0", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(versionLabel)
        versionLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-66))
            make.centerY.equalToSuperview()
        }
        
        updateStateBtn = UIButton(normalImageName: "firmware_update", target: self, action: #selector(updateStateBtnAction))
        contentView.addSubview(updateStateBtn)
        updateStateBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalToSuperview()
        }
        
        
    }
}
