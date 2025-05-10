//
//  DeviceParameterRetedPowerViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/8.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceParameterRetedPowerViewCellDelegate: AnyObject {
    
    /// 添加阶段
    func ratedPowerCellAddPhase(_ cell: DeviceParameterRetedPowerViewCell)
    
    /// 删除阶段
    func cell(_ cell: DeviceParameterRetedPowerViewCell, deletePhase phase: DeviceParameterRatedPowerPhaseData)
    
    
    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterRetedPowerViewCell, parameterEnableStateChanged enable: Bool)
    
}

class DeviceParameterRetedPowerViewCell: UITableViewCell {

    private var ratedPowerLabel: UILabel!
    private var enableSwitch: UISwitch!
    private var countLabel: UILabel!
    private var addBtn: UIButton!
    private var headerView: UIView!
    private var lightLevelLabel: UILabel!
    private var wattageLabel: UILabel!
    private var tableView: UITableView!
    private var noteLabel: UILabel!
    
    weak var delegate: DeviceParameterRetedPowerViewCellDelegate?
    
    var phases: [DeviceParameterRatedPowerPhaseData] = [] {
        didSet {
            
            countLabel.text = "\(phases.count)/10"
            addBtn.isHidden = phases.count >= 10
            
            tableView.isScrollEnabled = phases.count > 5
            tableView.snp.updateConstraints { make in
                make.height.equalTo(headerView.height + SCRYFrom(12) + tableView.rowHeight * CGFloat(min(phases.count, 5)))
            }
            tableView.reloadData()
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateParameterEnable(enable: Bool) {
        
        enableSwitch.isOn = enable
        if enable {
            countLabel.isHidden = false
            addBtn.isHidden = false
            tableView.isHidden = false
            noteLabel.isHidden = false
            
            
            ratedPowerLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(16))
            }
            noteLabel.snp.makeConstraints { make in
                make.left.right.equalTo(tableView)
                make.top.equalTo(tableView.snp.bottom).offset(SCRYFrom(16))
                make.bottom.equalTo(SCRYFit(-26))
            }
            
        }else {
            
            countLabel.isHidden = true
            addBtn.isHidden = true
            tableView.isHidden = true
            noteLabel.isHidden = true
            
            ratedPowerLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(16))
                make.bottom.equalTo(SCRYFrom(-16))
            }
            noteLabel.snp.remakeConstraints { make in
                make.left.right.equalTo(tableView)
                make.top.equalTo(tableView.snp.bottom).offset(SCRYFrom(16))
            }
        }
        
    }
    
    @objc private func addBtnAction() {
        delegate?.ratedPowerCellAddPhase(self)
    }
    
    @objc private func enableSwitchValueChanged(sender: UISwitch) {
        
        updateParameterEnable(enable: sender.isOn)
        
        delegate?.cell(self, parameterEnableStateChanged: sender.isOn)
    }
    
    private func setupUI() {
        
        ratedPowerLabel = UILabel(text: "rated_power".localizedString + ":", textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(ratedPowerLabel)
        ratedPowerLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        contentView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(ratedPowerLabel)
        }
        
        addBtn = UIButton(title: "＋", titleSize: 14, titleColor: Bar_Color, target: self, action: #selector(addBtnAction))
        contentView.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(enableSwitch.snp.bottom).offset(SCRYFrom(12))
            make.width.equalTo(SCRXFrom(38))
            make.height.equalTo(SCRYFrom(17))
        }
        
        countLabel = UILabel(text: "3/10", textColor: Message_Color, fontSize: 14)
        contentView.addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(addBtn)
        }
        
        headerView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: SCRYFrom(36)))
        
        lightLevelLabel = UILabel(text: "light_level".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        headerView.addSubview(lightLevelLabel)
        lightLevelLabel.snp.makeConstraints { make in
            make.centerX.equalTo(headerView).offset(SCRXFrom(-65))
            make.bottom.equalTo(SCRYFrom(-3))
        }
        
        wattageLabel = UILabel(text: "wattage".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        headerView.addSubview(wattageLabel)
        wattageLabel.snp.makeConstraints { make in
            make.centerX.equalTo(headerView).offset(SCRXFrom(45))
            make.bottom.equalTo(SCRYFrom(-3))
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.backgroundColor = Background_Color
        tableView.rowHeight = SCRYFrom(40)
        tableView.layer.cornerRadius = SCRYFrom(10)
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(12), right: 0)
        tableView.showsVerticalScrollIndicator = false
        tableView.register(DeviceRetedPowerPhaseViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableHeaderView = headerView
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(addBtn.snp.bottom).offset(SCRYFrom(10))
            make.height.equalTo(headerView.height + SCRYFrom(12))
        }
        
        noteLabel = UILabel(text: "device_rated_power_note".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 0
        noteLabel.textAlignment = .center
        contentView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(tableView)
            make.top.equalTo(tableView.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFit(-26))
        }
        
    }
    
}

extension DeviceParameterRetedPowerViewCell: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return phases.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceRetedPowerPhaseViewCell
        let phase = phases[indexPath.row]
        if phase.necessary {
            cell.levelField.backgroundColor = RGB(220, 220, 220)
            cell.levelField.textColor = SubText_Color
            cell.levelField.isEnabled = false
            cell.deleteBtn.isHidden = true
        }else {
            cell.levelField.backgroundColor = .white
            cell.levelField.textColor = TextBlack_Color
            cell.levelField.isEnabled = true
            cell.deleteBtn.isHidden = false
        }
        if let level = phase.lightLevel {
            cell.levelField.text = "\(level)%"
        }else {
            cell.levelField.text = nil
        }
        if let power = phase.power {
            cell.powerField.text = (Float(power) * 0.1).toSimplifyStr(maxDigits: 1)
        }else {
            cell.powerField.text = nil
        }
        cell.delegate = self
        return cell
    }
    
}

extension DeviceParameterRetedPowerViewCell: DeviceRetedPowerPhaseViewCellDelegate {
    
    /// 阶段cell输入light level
    func phaseCellInputLightLevel(_ cell: DeviceRetedPowerPhaseViewCell) {
        
        var phase: DeviceParameterRatedPowerPhaseData?
        if let index = tableView.indexPath(for: cell)?.row {
            phase = phases[index]
        }

        SRAlertView(title: "\("light_level".localizedString) \("input".localizedString)", inputText: cell.levelField.text, inputFieldStyle: .init(placeholder: "1~99", keyboardType: .numberPad), actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString)]) {[weak self] text, _ in
            guard let self = self, let value = Int(text) else {
                return nil
            }
            if value < 0 || value > 100 {
                return "illegal_input".localizedString
            }
            // 已存在
            if phases.contains(where: { $0.lightLevel ?? 0 == value }) {
                return "value_already_exists".localizedString
            }
            return nil
        } inputDoneBack: {[weak self] text in
            guard let self = self, let value = UInt8(text) else {
                return
            }
            phase?.lightLevel = value
            cell.levelField.text = "\(value)"
            self.phases = self.phases.sorted(by: { $0.lightLevel ?? 100 < $1.lightLevel ?? 100 })
        }.show()

        
    }
    
    /// 阶段cell输入瓦数
    func phaseCellInputWattage(_ cell: DeviceRetedPowerPhaseViewCell) {
        
        var phase: DeviceParameterRatedPowerPhaseData?
        if let index = tableView.indexPath(for: cell)?.row {
            phase = phases[index]
        }

        SRAlertView(title: "\("rated_power".localizedString) \("input".localizedString)", inputText: cell.powerField.text, inputFieldStyle: .init(placeholder: "0~6553.5", keyboardType: .decimalPad), actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString)]) { text, _ in
            guard let value = Float(text) else {
                return nil
            }
            let power = Int(value * 10)
            if power < 0 || power > 65535 {
                return "\("limit_range".localizedString) 0~6553.5"
            }
            return nil
        } inputDoneBack: { text in
            guard let value = Float(text), Int(value * 10) <= 65535 else {
                return
            }
            let power = UInt16(value * 10)
            phase?.power = power
            cell.powerField.text = value.toSimplifyStr(maxDigits: 1)
        }.show()

        
    }
    
    /// 删除阶段
    func phaseCellDeleteAction(_ cell: DeviceRetedPowerPhaseViewCell) {
        if let index = tableView.indexPath(for: cell)?.row {
            delegate?.cell(self, deletePhase: phases[index])
        }
        
    }
    
}

protocol DeviceRetedPowerPhaseViewCellDelegate: AnyObject {
    
    /// 阶段cell输入light level
    func phaseCellInputLightLevel(_ cell: DeviceRetedPowerPhaseViewCell)
    
    /// 阶段cell输入瓦数
    func phaseCellInputWattage(_ cell: DeviceRetedPowerPhaseViewCell)
    
    /// 删除阶段
    func phaseCellDeleteAction(_ cell: DeviceRetedPowerPhaseViewCell)
    
}


class DeviceRetedPowerPhaseViewCell: UITableViewCell {
    
    var levelField: UITextField!
    var powerField: UITextField!
    private var unitLabel: UILabel!
    var deleteBtn: UIButton!
    weak var delegate: DeviceRetedPowerPhaseViewCellDelegate?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func deleteBtnAction() {
        
        delegate?.phaseCellDeleteAction(self)
    }
    
    private func setupUI() {
        
        powerField = UITextField()
        powerField.layer.cornerRadius = SCRYFrom(5)
        powerField.layer.borderColor = RGB(220, 220, 220).cgColor
        powerField.layer.borderWidth = 0.5
        powerField.backgroundColor = .white
        powerField.placeholder = "0~6553.5"
        powerField.textAlignment = .center
        powerField.textColor = TextBlack_Color
        powerField.font = UIFont.systemFont(ofSize: SCRYFrom(13))
        powerField.delegate = self
        contentView.addSubview(powerField)
        powerField.snp.makeConstraints { make in
            make.left.equalTo(self.snp.centerX).offset(SCRXFrom(-3.5))
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(96))
            make.height.equalTo(SCRYFrom(32))
        }
        
        
        levelField = UITextField()
        levelField.layer.cornerRadius = SCRYFrom(5)
        levelField.layer.borderColor = RGB(220, 220, 220).cgColor
        levelField.layer.borderWidth = 0.5
        levelField.textAlignment = .center
        levelField.backgroundColor = .white
//        levelField.isEnabled = false
        levelField.placeholder = "1%~99%"
        levelField.textColor = TextBlack_Color
        levelField.font = UIFont.systemFont(ofSize: SCRYFrom(13))
        levelField.delegate = self
        contentView.addSubview(levelField)
        levelField.snp.makeConstraints { make in
            make.right.equalTo(powerField.snp.left).offset(SCRXFrom(-22))
            make.centerY.width.height.equalTo(powerField)
        }
        
        unitLabel = UILabel(text: "W", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(unitLabel)
        unitLabel.snp.makeConstraints { make in
            make.left.equalTo(powerField.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(powerField).offset(SCRYFrom(-1))
        }
        
        deleteBtn = UIButton(normalImageName: "firmware_delete", target: self, action: #selector(deleteBtnAction))
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.left.equalTo(unitLabel.snp.right).offset(SCRXFrom(9))
            make.centerY.equalTo(powerField)
        }
        
    }
}

extension DeviceRetedPowerPhaseViewCell: UITextFieldDelegate {
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField == levelField {
            delegate?.phaseCellInputLightLevel(self)
        }else {
            delegate?.phaseCellInputWattage(self)
        }
        return false
    }
    
}
