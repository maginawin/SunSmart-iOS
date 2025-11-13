//
//  LightSensorCalibrationAdjustSpeedView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/12.
//

import UIKit

protocol LightSensorCalibrationAdjustSpeedViewDelegate: AnyObject {
    
    /// 调节速率修改回调
    /// - Parameters:
    ///   - view: view
    ///   - speed: 0~100
    func view(_ view: LightSensorCalibrationAdjustSpeedView, adjustSpeedChanged speed: Int)
    
    /// 点击调整速率帮助
    func calibrationAdjustSpeedHelpAction(_ view: LightSensorCalibrationAdjustSpeedView)
}

class LightSensorCalibrationAdjustSpeedView: UIView {
    
    private var speedLabel: UILabel!
    private var speedHelpBtn: UIButton!
    private var speedSlowLabel: UILabel!
    private var speedFastLabel: UILabel!
    var speedSlider: CustomDeviceSlider!

    weak var delegate: LightSensorCalibrationAdjustSpeedViewDelegate?
    
    /// 调节速率 0~100
    var adjustSpeed: Int {
        return Int(speedSlider.value)
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func speedHelpBtnAction() {
        delegate?.calibrationAdjustSpeedHelpAction(self)
    }
    
    private func setupUI() {
        
        speedLabel = UILabel(text: "adjust_speed".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        addSubview(speedLabel)
        speedLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(10.5))
        }

        speedHelpBtn = UIButton(normalImageName: "help", target: self, action: #selector(speedHelpBtnAction))
        addSubview(speedHelpBtn)
        speedHelpBtn.snp.makeConstraints { make in
            make.left.equalTo(speedLabel.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(speedLabel)
        }
        
        speedSlider = CustomDeviceSlider()
        speedSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        speedSlider.minimumTrackTintColor = Slider_Color
        speedSlider.maximumTrackTintColor = RGB(229, 229, 229)
        speedSlider.layer.cornerRadius = 2
        speedSlider.minimumValue = 0
        speedSlider.maximumValue = 100
        speedSlider.value = 50
        speedSlider.delegate = self
        addSubview(speedSlider)
        speedSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(61))
            make.right.equalTo(SCRXFrom(-62))
            make.top.equalTo(speedHelpBtn.snp.bottom).offset(SCRYFrom(5))
            make.height.equalTo(SCRYFrom(40))
        }
        
        speedSlowLabel = UILabel(text: "slow".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(speedSlowLabel)
        speedSlowLabel.snp.makeConstraints { make in
            make.left.equalTo(speedLabel)
            make.centerY.equalTo(speedSlider)
        }
        
        speedFastLabel = UILabel(text: "fast".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(speedFastLabel)
        speedFastLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(speedSlowLabel)
        }
        
    }
    
}

extension LightSensorCalibrationAdjustSpeedView: CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        
        delegate?.view(self, adjustSpeedChanged: Int(value))
    }
    
}
