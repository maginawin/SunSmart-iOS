//
//  EnergyConsumptionInstructionView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/7.
//

import UIKit

class EnergyConsumptionInstructionView: UIView {

    enum DataType {
        case staticData
        case timeSeriesData
    }
    
    var titleLabel: UILabel!
    var messageLabel: UILabel!
    private var contentView: UIView!
    private var energyDeviceProcessView: EnergyConsumptionInstructionProcessView!
    private var orLabel: UILabel?
    private var meshDeviceProcessView: EnergyConsumptionInstructionProcessView?
    
    let type: DataType
    
    init(type: DataType) {
        self.type = type
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(32))
            make.top.equalToSuperview()
        }
        
        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.right.equalTo(SCRXFrom(-32))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
        }
        
        contentView = UIView()
        contentView.layer.cornerRadius = SCRYFrom(10)
        contentView.backgroundColor = .white
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(64))
        }
        
        energyDeviceProcessView = EnergyConsumptionInstructionProcessView(type: .energyDevice)
        contentView.addSubview(energyDeviceProcessView)
        switch type {
        case .staticData:
            
            orLabel = UILabel(text: "or".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light)
            contentView.addSubview(orLabel!)
            orLabel!.snp.makeConstraints { make in
                make.centerX.equalToSuperview().offset(SCRXFrom(21.5))
                make.centerY.equalToSuperview()
            }
            
            energyDeviceProcessView.snp.makeConstraints { make in
                make.right.equalTo(orLabel!.snp.left).offset(SCRXFrom(-20))
                make.centerY.equalTo(orLabel!)
                make.width.equalTo(SCRXFrom(140))
                make.height.equalTo(SCRYFrom(28))
            }
            
            meshDeviceProcessView = EnergyConsumptionInstructionProcessView(type: .meshDevice)
            contentView.addSubview(meshDeviceProcessView!)
            meshDeviceProcessView!.snp.makeConstraints { make in
                make.left.equalTo(orLabel!.snp.right).offset(SCRXFrom(20))
                make.centerY.height.equalTo(energyDeviceProcessView)
                make.width.equalTo(SCRXFrom(96))
            }
            
        case .timeSeriesData:
            energyDeviceProcessView.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.width.equalTo(SCRXFrom(140))
                make.height.equalTo(SCRYFrom(28))
            }
        }
     
        
    }
}

class EnergyConsumptionInstructionProcessView: UIView {
    
    /// 流程类型
    enum ProcessType {
        /// 能耗设备
        case energyDevice
        /// mesh设备
        case meshDevice
    }
    
    private let type: ProcessType
    
    var phoneImageView: UIImageView!
    var phoneArrowImageView: UIImageView!
    
    var energyDeviceImageView: UIImageView?
    var energyDeviceArrowImageView: UIImageView?
    
    var deviceImageView: UIImageView!
    
    init(type: ProcessType) {
        self.type = type
        super.init(frame: .zero)
        
        layer.borderWidth = 0.5
        layer.borderColor = RGB(220, 220, 220).cgColor
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.cornerRadius = self.height * 0.5
    }
    
    private func setupUI() {
        
        phoneImageView = UIImageView(image: UIImage(named: "harvest_phone")?.withTintColor(Bar_Color))
        addSubview(phoneImageView)
        phoneImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(20))
        }
        
        phoneArrowImageView = UIImageView(image: UIImage(named: "energy_arrow_left"))
        addSubview(phoneArrowImageView)
        phoneArrowImageView.snp.makeConstraints { make in
            make.left.equalTo(phoneImageView.snp.right).offset(SCRXFrom(6))
            make.centerY.equalTo(phoneImageView)
        }
        
        if type == .energyDevice {
            energyDeviceImageView = UIImageView(image: UIImage(named: "harvest_dongle")?.withTintColor(Bar_Color))
            addSubview(energyDeviceImageView!)
            energyDeviceImageView!.snp.makeConstraints { make in
                make.left.equalTo(phoneArrowImageView.snp.right).offset(SCRXFrom(6))
                make.centerY.equalTo(phoneArrowImageView)
                make.width.height.equalTo(phoneImageView)
            }
            
            energyDeviceArrowImageView = UIImageView(image: UIImage(named: "energy_arrow_left"))
            addSubview(energyDeviceArrowImageView!)
            energyDeviceArrowImageView!.snp.makeConstraints { make in
                make.left.equalTo(energyDeviceImageView!.snp.right).offset(SCRXFrom(6))
                make.centerY.equalTo(energyDeviceImageView!)
            }
        }
        
        deviceImageView = UIImageView(image: UIImage(named: "energy_light"))
        addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo((energyDeviceArrowImageView ?? phoneArrowImageView).snp.right).offset(SCRXFrom(6))
            make.centerY.equalTo(phoneArrowImageView)
            make.width.height.equalTo(phoneImageView)
        }
    }
}
