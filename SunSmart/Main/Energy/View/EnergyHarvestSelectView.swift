//
//  EnergyHarvestSelectView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/30.
//

import UIKit
import NordicSigMeshSDK

protocol EnergyHarvestSelectViewDelegate: AnyObject {
    
    /// 选择能耗采集设备获取能耗
    func view(_ view: EnergyHarvestSelectView, energyStorageDeviceHarvest device: Node)
    
    /// 能耗采集设备识别
    func view(_ view: EnergyHarvestSelectView, energyStorageDeviceIdentify device: Node)
    
    /// 刷新能耗采集设备
    func view(_ view: EnergyHarvestSelectView, energyStorageDevicesRefresh devices: [Node])
    
    /// 选择mesh设备获取能耗
    func meshDevicesEnergyHarvest(_ view: EnergyHarvestSelectView)
}

class EnergyHarvestSelectView: UIView {

    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var tipsALabel: UILabel!
    /// Storage Devices(Dongle/ Gateway)
    private var storageDevicesView: UIView!
    private var storageDeviceImageView: UIImageView!
    private var storageDeviceLineImageView: UIImageView!
    private var storageDevicePhoneImageView: UIImageView!
    private var storageDeviceStartBtn: UIButton!
    private var storageDeviceMessageLabel: UILabel!
    private var storageDevicesLabel: UILabel!
    private var storageDevicesRefreshBtn: UIButton!
    private var storageDevicesTableView: UITableView!
    /// Mesh
    private var tipsBLabel: UILabel!
    private var meshDeviceView: UIView!
    private var meshDeviceImageView: UIImageView!
    private var meshDeviceLineImageView: UIImageView!
    private var meshPhoneImageView: UIImageView!
    private var meshStartBtn: UIButton!
    
    private var lineView: UIView!
    private var cancelBtn: UIButton!
    /// 选中的能耗设备
    private var selectStorageDevice: Node?
    
    weak var delegate: EnergyHarvestSelectViewDelegate?
    
    /// 存储能耗的设备list
    var storageDevices: [Node] = [] {
        didSet {
            storageDevicesTableView.isScrollEnabled = storageDevices.count > 3
            storageDevicesTableView.snp.updateConstraints { make in
                let height = CGFloat(min(storageDevices.count, 3)) * storageDevicesTableView.rowHeight
                make.height.equalTo(height)
            }
            storageDevicesTableView.reloadData()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
        }
        contentView.layoutIfNeeded()
        contentView.transform = CGAffineTransformMakeScale(0.1, 0.1)
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 1, options: .curveEaseInOut) {
            self.contentView.transform = .identity
            self.shadeView.alpha = 1
        } completion: { _ in
            
        }
    }
    
    func hide() {
        
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.layer.addScaleAnimation(fromScale: 1, toScale: 0.7, duration: 0.2)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    /// 能耗设备开始获取
    @objc private func storageDeviceStartBtnAction() {
        guard let device = selectStorageDevice else {
            return
        }
        delegate?.view(self, energyStorageDeviceHarvest: device)
        hide()
    }
    
    /// 刷新采集能耗设备信号
    @objc private func storageDevicesRefreshBtnAction(sender: UIButton) {
        
        sender.imageView?.layer.addRotationAnimation(duration: 1.2, repeatCount: 8)
        
        delegate?.view(self, energyStorageDevicesRefresh: storageDevices)
    }
    
    /// mesh设备开始获取能耗
    @objc private func meshStartBtnAction() {
        delegate?.meshDevicesEnergyHarvest(self)
        hide()
    }
    
    /// 取消
    @objc private func cancelBtnAction() {
        
        hide()
    }
    
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.layer.cornerRadius = SCRYFrom(20)
        contentView.backgroundColor = Background_Color
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "harvest".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(24))
        }
        
        tipsALabel = UILabel(text: "harvest_storage_mode_prompt".localizedString, textColor: Title_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentView.addSubview(tipsALabel)
        tipsALabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        storageDevicesView = UIView()
        storageDevicesView.backgroundColor = .white
        storageDevicesView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(storageDevicesView)
        storageDevicesView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(tipsALabel.snp.bottom).offset(SCRYFrom(6))
        }
        
        storageDeviceImageView = UIImageView(image: UIImage(named: "harvest_dongle"))
        storageDevicesView.addSubview(storageDeviceImageView)
        storageDeviceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(17))
            make.top.equalTo(SCRYFrom(12))
        }
        
        storageDeviceLineImageView = UIImageView(image: UIImage(named: "harvest_process_line"))
        storageDevicesView.addSubview(storageDeviceLineImageView)
        storageDeviceLineImageView.snp.makeConstraints { make in
            make.left.equalTo(storageDeviceImageView.snp.right).offset(SCRXFrom(3))
            make.centerY.equalTo(storageDeviceImageView)
        }
        
        storageDevicePhoneImageView = UIImageView(image: UIImage(named: "harvest_phone"))
        storageDevicesView.addSubview(storageDevicePhoneImageView)
        storageDevicePhoneImageView.snp.makeConstraints { make in
            make.left.equalTo(storageDeviceLineImageView.snp.right).offset(SCRXFrom(5))
            make.centerY.equalTo(storageDeviceLineImageView)
        }
        
        storageDeviceStartBtn = UIButton(title: "Start".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(storageDeviceStartBtnAction))
        storageDeviceStartBtn.layer.cornerRadius = SCRYFrom(5)
        storageDeviceStartBtn.backgroundColor = Bar_Color.withAlphaComponent(0.5)
        storageDeviceStartBtn.isUserInteractionEnabled = false
        storageDevicesView.addSubview(storageDeviceStartBtn)
        storageDeviceStartBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-17))
            make.top.equalTo(SCRYFrom(8))
            make.width.equalTo(SCRXFrom(68))
            make.height.equalTo(SCRYFrom(28))
        }
        
        storageDeviceMessageLabel = UILabel(text: "harvest_storage_mode_message".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        storageDeviceMessageLabel.textAlignment = .center
        storageDeviceMessageLabel.numberOfLines = 0
        storageDevicesView.addSubview(storageDeviceMessageLabel)
        storageDeviceMessageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-6))
            make.top.equalTo(storageDeviceStartBtn.snp.bottom).offset(SCRYFrom(12))
        }
        
        storageDevicesLabel = UILabel(text: "harvest_storage_devices_select".localizedString, textColor: Title_Color, fontSize: 12, fit: false)
        storageDevicesView.addSubview(storageDevicesLabel)
        storageDevicesLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(storageDeviceMessageLabel.snp.bottom).offset(SCRYFrom(14))
            make.right.equalTo(SCRXFrom(-54))
        }
        
        storageDevicesRefreshBtn = UIButton(normalImageName: "refresh", target: self, action: #selector(storageDevicesRefreshBtnAction))
        storageDevicesView.addSubview(storageDevicesRefreshBtn)
        storageDevicesRefreshBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalTo(storageDevicesLabel)
        }
        
        storageDevicesTableView = UITableView()
        storageDevicesTableView.backgroundColor = .clear
        storageDevicesTableView.separatorStyle = .none
        storageDevicesTableView.rowHeight = SCRYFrom(40)
        storageDevicesTableView.register(EnergyHarvestStorageDevicesView.classForCoder(), forCellReuseIdentifier: "cell")
        storageDevicesTableView.dataSource = self
        storageDevicesTableView.delegate = self
        storageDevicesView.addSubview(storageDevicesTableView)
        storageDevicesTableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(storageDevicesLabel.snp.bottom).offset(SCRYFrom(8))
            
            make.height.equalTo(CGFloat(3) * storageDevicesTableView.rowHeight)
            make.bottom.equalTo(SCRYFrom(-16))
        }
        
        tipsBLabel = UILabel(text: "harvest_mesh_mode_prompt".localizedString, textColor: Title_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentView.addSubview(tipsBLabel)
        tipsBLabel.snp.makeConstraints { make in
            make.left.equalTo(tipsALabel)
            make.top.equalTo(storageDevicesView.snp.bottom).offset(SCRYFrom(16))
        }
        
        meshDeviceView = UIView()
        meshDeviceView.backgroundColor = .white
        meshDeviceView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(meshDeviceView)
        meshDeviceView.snp.makeConstraints { make in
            make.left.right.equalTo(storageDevicesView)
            make.top.equalTo(tipsBLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(48))
        }
        
        meshDeviceImageView = UIImageView(image: UIImage(named: "energy_harvest_devices"))
        meshDeviceView.addSubview(meshDeviceImageView)
        meshDeviceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(13))
            make.centerY.equalToSuperview()
        }
        
        meshDeviceLineImageView = UIImageView(image: UIImage(named: "harvest_process_line"))
        meshDeviceView.addSubview(meshDeviceLineImageView)
        meshDeviceLineImageView.snp.makeConstraints { make in
            make.left.equalTo(meshDeviceImageView.snp.right).offset(SCRXFrom(1))
            make.centerY.equalTo(meshDeviceImageView)
        }
        
        meshPhoneImageView = UIImageView(image: UIImage(named: "harvest_phone"))
        meshDeviceView.addSubview(meshPhoneImageView)
        meshPhoneImageView.snp.makeConstraints { make in
            make.left.equalTo(meshDeviceLineImageView.snp.right).offset(SCRXFrom(5))
            make.centerY.equalTo(meshDeviceLineImageView)
        }
        
        meshStartBtn = UIButton(title: "Start".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(meshStartBtnAction))
        meshStartBtn.layer.cornerRadius = SCRYFrom(5)
        meshStartBtn.backgroundColor = Bar_Color
        meshDeviceView.addSubview(meshStartBtn)
        meshStartBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-17))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(storageDeviceStartBtn)
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(meshDeviceView.snp.bottom).offset(SCRYFrom(28))
            make.height.equalTo(1)
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 15, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(cancelBtnAction))
        contentView.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(lineView.snp.bottom)
            make.height.equalTo(SCRYFrom(60))
        }
        
    }
}

extension EnergyHarvestSelectView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! EnergyHarvestStorageDevicesView
//        let device =
        cell.iconImageView.image = UIImage(named: "energy_storage_dongle")
        cell.selectImageView.image = UIImage(named: "device_select_un")
        cell.identifyCallback = {[weak self] in
            guard let self = self else { return }
//            self.delegate?.view(self, energyStorageDeviceIdentify: <#T##Node#>)
        }
        cell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1, backgroundColor: Background_Color)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        storageDeviceStartBtn.backgroundColor = Bar_Color
        storageDeviceStartBtn.isUserInteractionEnabled = true
        
        selectStorageDevice = storageDevices[indexPath.row]
        tableView.reloadData()
    }
    
}


class EnergyHarvestStorageDevicesView: UITableViewCell {
    
    var selectImageView: UIImageView!
    var iconImageView: UIImageView!
    var nameLabel: UILabel!
    var rssiLabel: UILabel!
    var identifyBtn: UIButton!
    var lineView: UIView!
    var identifyCallback: (()->Void)?
    
    var node: Node! {
        didSet {
            
            nameLabel.text = node.name
            
            if let rssi = node.rssi {
                rssiLabel.text = "\(rssi)dB"
                nameLabel.textColor = TextBlack_Color
                identifyBtn.setImage(UIImage(named: "device_identify"), for: .normal)
                identifyBtn.isEnabled = true
                selectImageView.isHidden = true
                
            }else {
                rssiLabel.text = "--"
                nameLabel.textColor = Message_Color
                identifyBtn.setImage(UIImage(named: "device_identify_disable"), for: .normal)
                identifyBtn.isEnabled = false
                selectImageView.isHidden = true
            }
            
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        contentView.backgroundColor = Background_Color
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    @objc private func identifyBtnAction() {
        
        identifyCallback?()
    }
    
    private func setupUI() {
        
        selectImageView = UIImageView(image: UIImage(named: "device_select_un"))
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.centerY.equalToSuperview()
        }
        
        iconImageView = UIImageView()
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(6))
            make.centerY.equalTo(selectImageView)
        }
        
        nameLabel = UILabel(text: "ETC1", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(6))
            make.centerY.equalTo(iconImageView)
            make.width.lessThanOrEqualTo(SCRXFrom(100))
        }

        identifyBtn = UIButton(normalImageName: "device_identify", target: self, action: #selector(identifyBtnAction))
        contentView.addSubview(identifyBtn)
        identifyBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalToSuperview()
        }
        
        rssiLabel = UILabel(text: "--", textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(rssiLabel)
        rssiLabel.snp.makeConstraints { make in
            make.right.equalTo(identifyBtn.snp.left).offset(SCRXFrom(-10))
            make.centerY.equalToSuperview()
            make.width.greaterThanOrEqualTo(SCRXFrom(33))
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
    }
    
}
