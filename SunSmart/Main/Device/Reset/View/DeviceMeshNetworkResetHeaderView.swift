//
//  DeviceMeshNetworkResetHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/21.
//

import UIKit

class DeviceMeshNetworkResetHeaderView: UIView {

    /// 信号滑条
    var rssiView: UIView!
    var nearLabel: UILabel!
    var rssiSlider: RangeSlider!
    var farLabel: UILabel!
    /// 注意事项
    var noteView: UIView!
    var noteImageView: UIImageView!
    var noteLabel: UILabel!
    /// 设备信息
    var devicesInfoView: UIView!
    var totalNumbersLabel: UILabel!
    var sortBtn: UIButton!
    var stretchBtn: UIButton!
    
    /// 选择rssi范围回调
    var selectRSSIRangeCallback: ((ClosedRange<Int>)->Void)?
    
    /// 滑条信号范围
    var filterRSSIRange: ClosedRange<Int> = -100 ... -25 {
        didSet {
            rssiSlider.minimumValue = Double(abs(filterRSSIRange.upperBound))
            rssiSlider.maximumValue = Double(abs(filterRSSIRange.lowerBound))
        }
    }
    /// 选择的信号范围
    var selectRSSIRange: ClosedRange<Int> = -100 ... -25 {
        didSet {
            farLabel.text = "\(selectRSSIRange.lowerBound) dBm"
            nearLabel.text = "\(selectRSSIRange.upperBound) dBm"
            rssiSlider.minimumValue = Double(abs(filterRSSIRange.upperBound))
            rssiSlider.maximumValue = Double(abs(filterRSSIRange.lowerBound))
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func rssiSliderValueChanged(sender: RangeSlider) {
        let changeRSSIRange = Int(-sender.upperValue)...Int(-sender.lowerValue)
        guard selectRSSIRange != changeRSSIRange else {
            return
        }
        selectRSSIRange = changeRSSIRange
        selectRSSIRangeCallback?(selectRSSIRange)
    }
    

    private func setupUI() {
        
        rssiView = UIView()
        addSubview(rssiView)
        rssiView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }
        
        nearLabel = UILabel(text: "\(selectRSSIRange.upperBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        nearLabel.sizeToFit()
        rssiView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
//            make.width.equalTo(nearLabel.width)
        }
        
        farLabel = UILabel(text: "\(selectRSSIRange.lowerBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        farLabel.sizeToFit()
        rssiView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(nearLabel)
//            make.width.equalTo(farLabel.width)
        }
        
        rssiSlider = RangeSlider()
        rssiSlider.trackHighlightTintColor = Slider_Color
        rssiSlider.trackHighlightDisableTintColor = Slider_Color.withAlphaComponent(0.5)
        rssiSlider.trackTintColor = RGB(229, 229, 229)
        rssiSlider.thumbDisableTintColor = Background_Color
        rssiSlider.minimumValue = Double(abs(filterRSSIRange.upperBound))
        rssiSlider.maximumValue = Double(abs(filterRSSIRange.lowerBound))
        rssiSlider.lowerValue = Double(abs(selectRSSIRange.upperBound))
        rssiSlider.upperValue = Double(abs(selectRSSIRange.lowerBound))
        rssiSlider.minimumRange = 10
        rssiSlider.addTarget(self, action: #selector(rssiSliderValueChanged), for: .valueChanged)
        rssiView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(64))
            make.right.equalTo(SCRXFrom(-65))
            make.centerY.equalTo(nearLabel)
            make.height.equalTo(SCRYFrom(40))
        }
        
        noteView = UIView()
        noteView.layer.cornerRadius = SCRYFrom(7)
        noteView.backgroundColor = RGB(239, 239, 239)
        addSubview(noteView)
        noteView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(rssiView.snp.bottom).offset(SCRYFrom(2))
            make.height.equalTo(SCRYFrom(27))
        }
        
        noteImageView = UIImageView(image: UIImage(named: "tips"))
        noteView.addSubview(noteImageView)
        noteImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }
        
        noteLabel = UILabel(text: "devoce_motion_reset_note".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(noteImageView.snp.right).offset(SCRXFrom(4))
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-16))
        }
        
        devicesInfoView = UIView()
        addSubview(devicesInfoView)
        devicesInfoView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(noteView.snp.bottom)
            make.height.equalTo(SCRYFrom(40))
        }
        
        totalNumbersLabel = UILabel(text: "Total numbers：205", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        devicesInfoView.addSubview(totalNumbersLabel)
        totalNumbersLabel.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-8))
        }
        
        stretchBtn = UIButton(normalImageName: "device_reset_expand", selectedImageName: "device_reset_fold")
        devicesInfoView.addSubview(stretchBtn)
        stretchBtn.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(totalNumbersLabel)
        }
        
        sortBtn = UIButton(title: "static_sorting".localizedString, titleSize: 14, titleColor: Bar_Color)
        sortBtn.setTitle("dynamic_sorting".localizedString, for: .selected)
        devicesInfoView.addSubview(sortBtn)
        sortBtn.snp.makeConstraints { make in
            make.right.equalTo(stretchBtn.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalTo(stretchBtn)
        }
            
    }
    
}
