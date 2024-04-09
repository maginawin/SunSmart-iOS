//
//  ProfileDaylightSensorControlView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

protocol ProfileDaylightSensorControlViewDelegate: AnyObject {
    
    /// 帮助
    func daylightSensorViewHelpAction(view: ProfileDaylightSensorControlView)
    
    /// 选择传感器
    func daylightSensorViewSelectAction(view: ProfileDaylightSensorControlView)
    
}

class ProfileDaylightSensorControlView: UIView {

    private var titleLabel: UILabel!
    private var helpBtn: UIButton!
    private var sensorView: UIView!
    private var selectLabel: UILabel!
    private var arrowImageView: UIImageView!
    private var sensorImageView: UIImageView!
    var sensorNameLabel: UILabel!
    var emptyLabel: UILabel!
    
    weak var delegate: ProfileDaylightSensorControlViewDelegate?
    
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
        delegate?.daylightSensorViewHelpAction(view: self)
    }
    
    @objc private func sensorViewAction() {
        delegate?.daylightSensorViewSelectAction(view: self)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "daylight_sensor_control".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
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
        
        sensorView = UIView()
        sensorView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(sensorViewAction)))
        addSubview(sensorView)
        sensorView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(SCRYFrom(-21))
            make.top.equalTo(SCRYFrom(55))
        }
        
        selectLabel = UILabel(text: "daylight_sensor_select".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        sensorView.addSubview(selectLabel)
        selectLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_light_right"))
        sensorView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalTo(selectLabel)
        }
        
        emptyLabel = UILabel(text: "daylight_sensor_empty".localizedString, textColor: Red_Color, fontSize: 14, fontWeight: .light)
        sensorView.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.left.equalTo(selectLabel)
            make.top.equalTo(selectLabel.snp.bottom).offset(SCRYFrom(16))
            make.right.equalTo(SCRXFrom(-20))
        }
        
        sensorImageView = UIImageView(image: UIImage(named: "profile_device_lightsensor"))
        sensorImageView.isHidden = true
        sensorView.addSubview(sensorImageView)
        sensorImageView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.bottom.equalToSuperview()
        }
        
        sensorNameLabel = UILabel(text: "ID001", textColor: TextBlack_Color, fontSize: 14)
        sensorNameLabel.isHidden = true
        sensorView.addSubview(sensorNameLabel)
        sensorNameLabel.snp.makeConstraints { make in
            make.left.equalTo(sensorImageView.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(sensorImageView)
        }
        
    }
    
}
