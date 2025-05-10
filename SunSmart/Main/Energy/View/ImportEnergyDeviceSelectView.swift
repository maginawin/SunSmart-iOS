//
//  ImportEnergyDeviceSelectView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/7.
//

import UIKit
import NordicSigMeshSDK

protocol ImportEnergyDeviceSelectViewDelegate: AnyObject {
    
    /// 选择能耗采集设备获取能耗
    func view(_ view: ImportEnergyDeviceSelectView, energyStorageDeviceHarvest device: Node)
    
    /// 能耗采集设备识别
    func view(_ view: ImportEnergyDeviceSelectView, energyStorageDeviceIdentify device: Node)
    
    /// 刷新能耗采集设备
    func view(_ view: ImportEnergyDeviceSelectView, energyStorageDevicesRefresh devices: [Node])
}

class ImportEnergyDeviceSelectView: UIView {

    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var messageLabel: UILabel!
    private var storageDevicesLabel: UILabel!
    private var storageDevicesRefreshBtn: UIButton!
    private var storageDevicesTableView: UITableView!
    
    private var bottomView: UIView!
    private var lineView: UIView!
    private var hLineView: UIView!
    private var cancelBtn: UIButton!
    private var importBtn: UIButton!

    /// 选中的能耗设备
    private var selectStorageDevice: Node?
    
    weak var delegate: ImportEnergyDeviceSelectViewDelegate?
    
    /// 存储能耗的设备list
    var storageDevices: [Node] = [] {
        didSet {
            storageDevicesTableView.isScrollEnabled = storageDevices.count > 4
            storageDevicesTableView.snp.updateConstraints { make in
                let height = CGFloat(min(storageDevices.count, 4)) * storageDevicesTableView.rowHeight
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
    
    @objc private func storageDevicesRefreshBtnAction() {
        delegate?.view(self, energyStorageDevicesRefresh: storageDevices)
    }
    
    @objc private func cancelBtnAction() {
        hide()
    }
    
    @objc private func importBtnAction() {
        hide()
        guard let storageDevice = self.selectStorageDevice else { return }
        delegate?.view(self, energyStorageDeviceHarvest: storageDevice)
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
        
        messageLabel = UILabel(text: "harvest_storage_mode_prompt".localizedString, textColor: Title_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
        }

        storageDevicesLabel = UILabel(text: "harvest_storage_devices_select".localizedString, textColor: Title_Color, fontSize: 12, fit: false)
        contentView.addSubview(storageDevicesLabel)
        storageDevicesLabel.snp.makeConstraints { make in
            make.left.equalTo(messageLabel).offset(SCRXFrom(2))
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(15))
            make.right.equalTo(SCRXFrom(-54))
        }
        
        storageDevicesRefreshBtn = UIButton(normalImageName: "refresh", target: self, action: #selector(storageDevicesRefreshBtnAction))
        contentView.addSubview(storageDevicesRefreshBtn)
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
        contentView.addSubview(storageDevicesTableView)
        storageDevicesTableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(storageDevicesLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(CGFloat(3) * storageDevicesTableView.rowHeight)
        }
        
        bottomView = UIView()
        contentView.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
            make.top.equalTo(storageDevicesTableView.snp.bottom).offset(SCRYFrom(51))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(0, 0, 0, 0.03)
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
        }
        
        hLineView = UIView()
        hLineView.backgroundColor = RGB(0, 0, 0, 0.03)
        bottomView.addSubview(hLineView)
        hLineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.width.equalTo(1)
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 15, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(cancelBtnAction))
        bottomView.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.right.equalTo(hLineView.snp.left)
        }
        
        importBtn = UIButton(title: "IMPORT".localizedString, titleSize: 15, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(importBtnAction))
        importBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        importBtn.isEnabled = false
        bottomView.addSubview(importBtn)
        importBtn.snp.makeConstraints { make in
            make.right.top.bottom.equalToSuperview()
            make.left.equalTo(hLineView.snp.right)
        }
        
    }
    
}

extension ImportEnergyDeviceSelectView: UITableViewDataSource, UITableViewDelegate {
    
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
        
        importBtn.isEnabled = true
        
        selectStorageDevice = storageDevices[indexPath.row]
        tableView.reloadData()
    }
    
}
