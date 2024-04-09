//
//  LightSensorCalibrationSelectView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/29.
//

import UIKit
import NordicSigMeshSDK

protocol LightSensorCalibrationSelectViewDelegate: AnyObject {
    
    
    /// identify回调
    /// - Parameters:
    ///   - view: self
    ///   - sensor: 传感器
    func view(_ view: LightSensorCalibrationSelectView, identify sensor: Node)
    
    /// 选择传感器回调
    /// - Parameters:
    ///   - view: self
    ///   - selectSensor: 选中的传感器
    ///   - lastSelectSensor: 上一个选中的传感器
    func view(_ view: LightSensorCalibrationSelectView, didSelectDaylightSensor selectSensor: Node, lastSelectSensor: Node?)
    
    /// 取消选择传感器回调
    /// - Parameters:
    ///   - view: self
    ///   - selectSensor: 取消选中的传感器
    func view(_ view: LightSensorCalibrationSelectView, didDeselectDaylightSensor sensor: Node)
    
    /// 点击帮助回调
    func sensorViewClickHelpAction(_ view: LightSensorCalibrationSelectView)
    
}

class LightSensorCalibrationSelectView: UIView {

    private var titleLabel: UILabel!
    private var helpBtn: UIButton!
    private var tableView: UITableView!
    
    weak var delegate: LightSensorCalibrationSelectViewDelegate?
    
    /// 所有传感器
    var daylightSensors: [Node] = [] {
        didSet {
            tableView.snp.updateConstraints { make in
                make.height.equalTo(tableView.rowHeight * CGFloat(min(daylightSensors.count, 5)))
            }
            tableView.isScrollEnabled = daylightSensors.count > 5
            tableView.reloadData()
        }
    }
    
    /// 选中的传感器
    var selectDaylightSensor: Node? {
        didSet {
            
            var reloadIndexPaths: [IndexPath] = []
            if let lastSelectSensor = self.lastSelectSensor, let index = daylightSensors.firstIndex(of: lastSelectSensor) {
                reloadIndexPaths.append(IndexPath(row: index, section: 0))
            }
            
            if let sensor = selectDaylightSensor {
                if let index = daylightSensors.firstIndex(of: sensor) {
                    reloadIndexPaths.append(IndexPath(row: index, section: 0))
                }
            }
            if reloadIndexPaths.count > 0 {
                tableView.reloadRows(at: reloadIndexPaths, with: .automatic)
            }
            
            lastSelectSensor = selectDaylightSensor
        }
    }
    
    private var lastSelectSensor: Node?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func helpBtnAction() {
        
        delegate?.sensorViewClickHelpAction(self)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "select_daylight_sensor".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.left.equalTo(titleLabel.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(titleLabel)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = SCRYFrom(40)
        tableView.showsVerticalScrollIndicator = false
        tableView.register(LightSensorCalibrationSelectViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(13))
            make.bottom.equalTo(SCRYFrom(-8))
            make.height.equalTo(tableView.rowHeight)
        }
        
        
    }
    
    /// 刷新cell
    func reloadSensorCell(sensor: Node) {
        
        if let index = daylightSensors.firstIndex(of: sensor), let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? LightSensorCalibrationSelectViewCell {
            
            cell.calibratedSignView.isHidden = !sensor.sensorCalibrated
            if sensor.selectState == .loading {
                cell.enableSwitch.isHidden = true
                cell.loadingImageView.isHidden = false
                cell.loadingImageView.layer.addRotationAnimation(duration: 1.2, repeatCount: 999, animationKey: "loading")
            }else {
                cell.enableSwitch.setOn(sensor.selectState == .switchOn, animated: true)
                cell.enableSwitch.isHidden = false
                cell.loadingImageView.isHidden = true
                cell.loadingImageView.layer.removeAnimation(forKey: "loading")
            }
        }
        
    }
}

extension LightSensorCalibrationSelectView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return daylightSensors.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! LightSensorCalibrationSelectViewCell
        let sensor = daylightSensors[indexPath.row]
        cell.nameLabel.text = sensor.name
        if sensor.selectState == .loading {
            cell.enableSwitch.isHidden = true
            cell.loadingImageView.isHidden = false
            cell.loadingImageView.layer.addRotationAnimation(duration: 1.2, repeatCount: 999, animationKey: "loading")
        }else {
            cell.enableSwitch.isOn = sensor.selectState == .switchOn
            cell.enableSwitch.isHidden = false
            cell.loadingImageView.isHidden = true
            cell.loadingImageView.layer.removeAnimation(forKey: "loading")
        }
        cell.calibratedSignView.isHidden = !sensor.sensorCalibrated
        
        cell.identifyCallback = {[weak self] in
            guard let self = self else { return }
            self.delegate?.view(self, identify: sensor)
        }
        cell.enabledCallback = {[weak self] enabled in
            guard let self = self else { return }
            
            if enabled {
                self.delegate?.view(self, didSelectDaylightSensor: sensor, lastSelectSensor: self.daylightSensors.first(where: { $0.selectState == .switchOn }))
//                self.selectDaylightSensor = sensor
            }else {
//                self.selectDaylightSensor = nil
                self.delegate?.view(self, didDeselectDaylightSensor: sensor)
            }
//            self.delegate?.view(self, didSelectDaylightSensor: sensor, enabled: enabled)
        }
        return cell
    }
    
}


class LightSensorCalibrationSelectViewCell: UITableViewCell {
    
    private var infoView: UIView!
    var iconImageView: UIImageView!
    var nameLabel: UILabel!
    var enableSwitch: UISwitch!
    private var enableSwitchBtn: UIButton!
    var calibratedSignView: UIView!
    var loadingImageView: UIImageView!
    
    var enabledCallback: ((Bool)->Void)?
    var identifyCallback: (()->Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        backgroundColor = .clear
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    @objc private func enableSwitchValueChanged(sender: UISwitch) {
//        enabledCallback?(sender.isOn)
//    }
    
    @objc private func enableSwitchBtnAction() {
        enabledCallback?(!enableSwitch.isOn)
    }
    
    @objc private func identifying() {
        identifyCallback?()
    }
    
    private func setupUI() {
        
        infoView = UIView()
        contentView.addSubview(infoView)
        infoView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(32))
        }
        
        calibratedSignView = UIView()
        calibratedSignView.backgroundColor = RGB(0, 209, 124)
        calibratedSignView.layer.cornerRadius = 3
        calibratedSignView.isHidden = true
        contentView.addSubview(calibratedSignView)
        calibratedSignView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalTo(infoView)
            make.width.height.equalTo(6)
        }
        
        iconImageView = UIImageView(image: UIImage(named: "profile_device_lightsensor"))
        iconImageView.isUserInteractionEnabled = true
        iconImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(identifying)))
        infoView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "ID001", textColor: TextBlack_Color, fontSize: 14)
        infoView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(iconImageView)
            make.width.lessThanOrEqualTo(SCRXFrom(160))
        }
        
        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.tintColor = RGB(207, 207, 207)
//        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        infoView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-3))
        }
        
        enableSwitchBtn = UIButton(target: self, action: #selector(enableSwitchBtnAction))
        enableSwitch.addSubview(enableSwitchBtn)
        enableSwitchBtn.snp.makeConstraints { make in
            make.edges.equalTo(enableSwitch)
        }
        
        loadingImageView = UIImageView(image: UIImage(named: "loading"))
        loadingImageView.isHidden = true
        infoView.addSubview(loadingImageView)
        loadingImageView.snp.makeConstraints { make in
            make.center.equalTo(enableSwitch)
        }
        
    }
    
}
