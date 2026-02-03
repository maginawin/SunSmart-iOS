//
//  DeviceParameterEnergyReportViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/5.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceParameterEnergyReportViewCellDelegate: AnyObject {
    
    /// 校准点击事件
    func energyReportViewCellCalibrateAction(_ cell: DeviceParameterEnergyReportViewCell)
    
    /// 禁用所有自动功耗设置
    func energyReportViewCellInhibitAllAction(_ cell: DeviceParameterEnergyReportViewCell)
    
    /// 启用所有自动功耗设置
    func energyReportViewCellActivateAllAction(_ cell: DeviceParameterEnergyReportViewCell)
    
    /// 启用/禁用自动功耗设置
    func cell(_ cell: DeviceParameterEnergyReportViewCell, deviceActivateAction device: Node, activate: Bool)
    
    /// 设备识别
    func cell(_ cell: DeviceParameterEnergyReportViewCell, deviceIdentify device: Node)
}

class DeviceParameterEnergyReportViewCell: UITableViewCell {
    
    private var containerView: UIView!
    private var functionView: UIView!
    private var stackView: UIStackView!
    private var calibrateBtn: UIButton!
    private var inhibitAllBtn: UIButton!
    private var activateAllBtn: UIButton!
    private var lineView: UIView!
    private var tableView: UITableView!
    private var noteLabel: UILabel!
    
    weak var delegate: DeviceParameterEnergyReportViewCellDelegate?
    
    var devices: [Node] = [] {
        didSet {
            
            inhibitAllBtn.isEnabled = devices.contains(where: { $0.phaseEnergyConsumptions.count > 0 })
            
            if let device = devices.first {
                if device.supportRealPowerCalibration {
                    stackView.addArrangedSubview(calibrateBtn)
                }
            }
            stackView.addArrangedSubview(inhibitAllBtn)
            stackView.addArrangedSubview(activateAllBtn)
            
            let maxShowDevicesCount = min(devices.count, 5)
            tableView.isScrollEnabled = devices.count > 5
            tableView.snp.updateConstraints { make in
                make.height.equalTo(CGFloat(maxShowDevicesCount) * tableView.rowHeight)
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
    
    @objc private func calibrateBtnAction() {
        
        delegate?.energyReportViewCellCalibrateAction(self)
    }
    
    @objc private func inhibitAllBtnAction() {
        
        delegate?.energyReportViewCellInhibitAllAction(self)
    }
    
    @objc private func activateAllBtnAction() {
        delegate?.energyReportViewCellActivateAllAction(self)
    }
    
    func reloadDevice(device: Node) {
        inhibitAllBtn.isEnabled = devices.contains(where: { $0.phaseEnergyConsumptions.count > 0 })
        if let index = devices.firstIndex(of: device) {
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        }
    }
    
    private func setupUI() {
        
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        containerView.layer.masksToBounds = true
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview().priority(.high)
//            make.bottom.equalToSuperview().priority(.high)
        }
        
        functionView = UIView()
        containerView.addSubview(functionView)
        functionView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(64))
        }
        
        stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = SCRXFrom(12)
        stackView.distribution = .fillEqually
//        functionView.alignment = .leading
        functionView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(32))
            make.left.right.equalToSuperview()
        }
        
        calibrateBtn = UIButton(title: "calibrate".localizedString, titleSize: 13, titleColor: Title_Color, target: self, action: #selector(calibrateBtnAction))
        calibrateBtn.layer.cornerRadius = SCRYFrom(10)
        calibrateBtn.backgroundColor = Background_Color
//        functionView.addSubview(calibrateBtn)
//        calibrateBtn.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(16))
//            make.centerY.equalToSuperview()
//            make.height.equalTo(SCRYFrom(32))
//        }
        
        inhibitAllBtn = UIButton(title: "inhibit_all".localizedString, titleSize: 13, titleColor: Title_Color, target: self, action: #selector(inhibitAllBtnAction))
        inhibitAllBtn.layer.cornerRadius = SCRYFrom(10)
        inhibitAllBtn.backgroundColor = Background_Color
//        functionView.addSubview(inhibitAllBtn)
//        inhibitAllBtn.snp.makeConstraints { make in
//            make.left.equalTo(calibrateBtn.snp.right).offset(SCRXFrom(12))
//            make.centerY.width.height.equalTo(calibrateBtn)
//        }
        
        activateAllBtn = UIButton(title: "activate_all".localizedString, titleSize: 13, titleColor: Title_Color, target: self, action: #selector(activateAllBtnAction))
        activateAllBtn.layer.cornerRadius = SCRYFrom(10)
        activateAllBtn.backgroundColor = Background_Color
//        functionView.addSubview(activateAllBtn)
//        activateAllBtn.snp.makeConstraints { make in
//            make.left.equalTo(inhibitAllBtn.snp.right).offset(SCRXFrom(12))
//            make.centerY.width.height.equalTo(inhibitAllBtn)
//            make.right.equalTo(SCRXFrom(-15))
//        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        functionView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(60)
        tableView.register(EnergyReportDeviceViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        containerView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(functionView.snp.bottom).priority(.high)
            make.height.equalTo(0)
            make.bottom.equalToSuperview().priority(.high)
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        noteLabel = UILabel(text: nil, textColor: Message_Color, fontSize: 12, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 0
        noteLabel.attributedText = NSAttributedString(string:  "energy_reporting_note".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        noteLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        noteLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        contentView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(containerView)
            make.top.equalTo(containerView.snp.bottom).offset(SCRYFrom(8)).priority(.high)
            make.bottom.equalTo(SCRYFrom(-8)).priority(.high)
        }
        
    }
}

extension DeviceParameterEnergyReportViewCell: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return devices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! EnergyReportDeviceViewCell
        let device = devices[indexPath.row]
        cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
        cell.device = device
        cell.activateStateCallback = {[weak self] activate in
            guard let self = self else { return }
            self.delegate?.cell(self, deviceActivateAction: device, activate: activate)
        }
        cell.identifyCallback = {
            MeshAPI.identify(address: device.primaryUnicastAddress)
        }
        return cell
    }
    
}
 
class EnergyReportDeviceViewCell: UITableViewCell {
    
    private var deviceImageView: UIImageView!
    private var nameLabel: UILabel!
    private var powerLabel: UILabel!
    private var inhibitBtn: UIButton!
    private var activateBtn: UIButton!
    var lineView: UIView!
    /// 自动能耗功率是否激活
    var activateStateCallback: ((Bool)->Void)?
    /// 识别设备
    var identifyCallback: (()->Void)?
    
    var device: Node! {
        didSet {
            deviceImageView.image = UIImage(named: device.iconName)
            nameLabel.text = device.name
            if let ratedPower = device.phaseEnergyConsumptions.last?.power {
                powerLabel.text = "\((CGFloat(ratedPower) * 0.1).toSimplifyStr(maxDigits: 1)) W"
                inhibitBtn.isEnabled = true
            }else {
                powerLabel.text = "--"
                inhibitBtn.isEnabled = false
            }
            
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func activateBtnAction() {
        activateStateCallback?(true)
    }
    
    @objc private func inhibitBtnAction() {
        activateStateCallback?(false)
    }
    
    @objc private func deviceImageViewTapAction() {
        identifyCallback?()
    }
    
    private func setupUI() {
        deviceImageView = UIImageView()
        deviceImageView.isUserInteractionEnabled = true
        deviceImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(deviceImageViewTapAction)))
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(30)
        }
        
        nameLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
            if isIPad {
                make.width.lessThanOrEqualTo(SCRXFrom(200))
            }else {
                make.width.lessThanOrEqualTo(SCRXFrom(80))
            }
        }
        
        activateBtn = UIButton(title: "activate".localizedString, titleSize: 13, titleWeight: .light, titleColor: ImportantText_Color, target: self, action: #selector(activateBtnAction))
        activateBtn.layer.cornerRadius = SCRYFrom(14)
        activateBtn.backgroundColor = Background_Color
        contentView.addSubview(activateBtn)
        activateBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(56))
            make.height.equalTo(SCRYFrom(28))
        }
        
        inhibitBtn = UIButton(title: "inhibit".localizedString, titleSize: 13, titleWeight: .light, titleColor: ImportantText_Color, target: self, action: #selector(inhibitBtnAction))
        inhibitBtn.setTitleColor(Message_Color, for: .disabled)
        inhibitBtn.layer.cornerRadius = SCRYFrom(14)
        inhibitBtn.backgroundColor = Background_Color
        contentView.addSubview(inhibitBtn)
        inhibitBtn.snp.makeConstraints { make in
            make.right.equalTo(activateBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.height.equalTo(activateBtn)
            make.width.equalTo(SCRXFrom(48))
        }
        
        powerLabel = UILabel(text: nil, textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(powerLabel)
        powerLabel.snp.makeConstraints { make in
            make.right.equalTo(inhibitBtn.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalTo(inhibitBtn)
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(15))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
    }
    
    
}
    


