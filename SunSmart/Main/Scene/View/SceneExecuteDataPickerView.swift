//
//  SceneExecuteDataPickerView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/21.
//

import UIKit

class SceneExecuteDataPickerView: UIView {
    
    typealias DataPickerCallback = ((Int, Int)->Void)
    typealias DeleteCallback = (()->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var lightnessLabel: UILabel!
    private var lightnessSliderView: DeviceSliderFunctionView!
    private var cctLabel: UILabel!
    private var cctSliderView: DeviceSliderFunctionView!
    
    private var functionView: UIView!
    private var lineView: UIView!
    private var confirmBtn: UIButton!
    private var deleteBtn: UIButton!
    
    private var showDelete: Bool = true
    private var lightness: Int = 30
    private var cct: Int = 5500
    private var lightnessLimitRange: ClosedRange<Int>?
    private var pickerCallback: DataPickerCallback?
    private var deleteCallback: DeleteCallback?
    
    static func show(lightness: Int = 100, cct: Int = 4500, lightnessLimitRange: ClosedRange<Int>? = nil, showDelete: Bool = true, picker: DataPickerCallback?, delete: DeleteCallback? = nil) {
        
        let pickerView = SceneExecuteDataPickerView(frame: UIScreen.main.bounds)
        pickerView.showDelete = showDelete
        pickerView.lightness = lightness
        pickerView.lightnessLimitRange = lightnessLimitRange
        pickerView.pickerCallback = picker
        pickerView.deleteCallback = delete
        pickerView.cct = cct
        pickerView.setupUI()
        pickerView.tag = 100
        UIApplication.shared.keyWindow().addSubview(pickerView)
        pickerView.showAnimation()
    }
    
    private func showAnimation() {
        
        shadeView.alpha = 0
        contentView.alpha = 0
//        if functionView != nil {
//            
//        }
        functionView?.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.alpha = 1
            self.functionView?.alpha = 1
        }

    }
    
    private func dismiss() {
        
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.alpha = 0
            self.functionView?.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }

    }
    
    @objc private func deleteBtnAction() {
        deleteCallback?()
        dismiss()
    }
    
    @objc private func confirmBtnAction() {
        
        let lightness = lightnessSliderView.value
        let cct = cctSliderView.value
        pickerCallback?(lightness, cct)
        
        dismiss()
    }
    
    @objc private func shadeViewAction() {
        
//        if !showConfirm { // 没有确认按键，关闭则确认修改
            let lightness = lightnessSliderView.value
            let cct = cctSliderView.value
            pickerCallback?(lightness, cct)
//        }
        dismiss()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        if showDelete {
            
            functionView = UIView()
            functionView.backgroundColor = .white
            functionView.layer.cornerRadius = SCRYFrom(15)
            addSubview(functionView)
            functionView.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(8))
                make.right.equalTo(SCRXFrom(-8))
                make.bottom.equalTo(SCRYFrom(-34))
                make.height.equalTo(SCRYFrom(60))
            }
            
//            lineView = UIView()
//            lineView.backgroundColor = RGB(216, 216, 216)
//            functionView.addSubview(lineView)
//            lineView.snp.makeConstraints { make in
//                make.center.equalToSuperview()
//                make.width.equalTo(1)
//                make.height.equalTo(SCRYFrom(24))
//            }
            
            deleteBtn = UIButton(title: "DELETE".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(deleteBtnAction))
            functionView.addSubview(deleteBtn)
            deleteBtn.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(20))
                make.right.equalTo(SCRXFrom(-20))
                make.centerY.equalToSuperview()
                make.height.equalTo(SCRYFrom(40))
            }
            
//            confirmBtn = UIButton(title: "confirm".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(confirmBtnAction))
//            functionView.addSubview(confirmBtn)
//            confirmBtn.snp.makeConstraints { make in
//                make.left.equalTo(lineView.snp.right).offset(SCRXFrom(20))
//                make.right.equalTo(SCRXFrom(-20))
//                make.height.centerY.equalTo(deleteBtn)
//            }
            
//            if !showDelete {
//                deleteBtn.isHidden = true
//                lineView.isHidden = true
//                confirmBtn.snp.remakeConstraints { make in
//                    make.left.equalTo(SCRXFrom(20))
//                    make.right.equalTo(SCRXFrom(-20))
//                    make.centerY.equalToSuperview()
//                    make.height.equalTo(SCRYFrom(40))
//                }
//            }
        }
            
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(15)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            if showDelete {
                make.bottom.equalTo(functionView.snp.top).offset(SCRYFrom(-8))
            }else {
                make.bottom.equalTo(-34)
            }
            make.height.equalTo(SCRYFrom(220))
        }
        
        var lightnessValue = lightness
        if let range = lightnessLimitRange {
            lightnessValue = max(range.lowerBound, min(range.upperBound, lightnessValue))
        }
        
        lightnessLabel = UILabel(text: "\(lightnessValue)%", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(lightnessLabel)
        lightnessLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-67))
            make.top.equalTo(SCRYFrom(24))
        }
        
     
        lightnessSliderView = DeviceSliderFunctionView(frame: .zero, title: "", value: lightnessValue, functionType: .level(limitRange: lightnessLimitRange))
        lightnessSliderView.minLabel.isHidden = true
        lightnessSliderView.maxLabel.isHidden = true
        lightnessSliderView.minusBtn.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        lightnessSliderView.addBtn.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        lightnessSliderView.lineView.isHidden = true
        lightnessSliderView.titleLabel.isHidden = true
        lightnessSliderView.valueChangedCallback = {[weak self] value in
            self?.lightnessLabel.text = "\(value)%"
        }
        contentView.addSubview(lightnessSliderView)
        lightnessSliderView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-29))
            make.top.equalTo(lightnessLabel.snp.bottom).offset(SCRYFrom(14))
            make.height.equalTo(SCRYFrom(40))
        }
        lightnessSliderView.minusBtn.snp.remakeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        lightnessSliderView.addBtn.snp.remakeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        lightnessSliderView.slider.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-47))
            make.top.bottom.equalToSuperview()
        }
        
        
        cctLabel = UILabel(text: "\(cct)K", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(cctLabel)
        cctLabel.snp.makeConstraints { make in
            make.right.equalTo(lightnessLabel)
            make.top.equalTo(lightnessSliderView.snp.bottom).offset(SCRYFrom(28))
        }
        
        cctSliderView = DeviceSliderFunctionView(frame: .zero, title: "", value: cct, functionType: .cct())
        cctSliderView.minLabel.isHidden = true
        cctSliderView.maxLabel.isHidden = true
        cctSliderView.lineView.isHidden = true
        cctSliderView.titleLabel.isHidden = true
        cctSliderView.minusBtn.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        cctSliderView.addBtn.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        cctSliderView.valueChangedCallback = {[weak self] value in
            self?.cctLabel.text = "\(value)K"
        }
        contentView.addSubview(cctSliderView)
        cctSliderView.snp.makeConstraints { make in
            make.left.right.height.equalTo(lightnessSliderView)
            make.top.equalTo(cctLabel.snp.bottom).offset(SCRYFrom(14))
        }
        cctSliderView.minusBtn.snp.remakeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        cctSliderView.addBtn.snp.remakeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        cctSliderView.slider.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-47))
            make.top.bottom.equalToSuperview()
        }
        
    }


    
}
