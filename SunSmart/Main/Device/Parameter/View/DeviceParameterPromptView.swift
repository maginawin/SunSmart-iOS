//
//  DeviceParameterPromptView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/11.
//

import UIKit

protocol DeviceParameterPromptViewDelegate: AnyObject {
    
    /// 筛选
    func promptViewFilterAction(_ view: DeviceParameterPromptView)
    
    /// 重新同步
    func promptViewReSyncAction(_ view: DeviceParameterPromptView)
    
}

class DeviceParameterPromptView: UIView {

    var titleLabel: UILabel!
    var filterBtn: UIButton!
    var settingFailedBtn: UIButton!
    weak var delegate: DeviceParameterPromptViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    func showLoading() {
//        loadingImageView.isHidden = false
//        loadingImageView.layer.addRotationAnimation(duration: 1.2, repeatCount: 9999, animationKey: "loading")
//    }
//    
//    func stopLoading() {
//        loadingImageView.layer.removeAnimation(forKey: "loading")
//        loadingImageView.isHidden = true
//    }
    
    @objc private func filterBtnAction() {
        delegate?.promptViewFilterAction(self)
    }
    
    @objc private func settingFailedBtnAction() {
        delegate?.promptViewReSyncAction(self)
    }

    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(8))
            make.right.equalTo(SCRXFrom(-62))
        }
        
        filterBtn = UIButton(normalImageName: "filter", selectedImageName: "filter_selected", target: self, action: #selector(filterBtnAction))
        addSubview(filterBtn)
        filterBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }
        
        settingFailedBtn = UIButton(title: "device_parameter_setting_failed".localizedString, titleSize: 14, titleWeight: .light, titleColor: Red_Color, normalImageName: "setting_failed", target: self, action: #selector(settingFailedBtnAction))
        let attStr = NSAttributedString(string: "device_parameter_setting_failed".localizedString, attributes: [.underlineStyle: 1])
        settingFailedBtn.setAttributedTitle(attStr, for: .normal)
        settingFailedBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        settingFailedBtn.isHidden = true
        addSubview(settingFailedBtn)
        settingFailedBtn.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(4))
            make.left.equalTo(titleLabel)
        }
//        loadingImageView = UIImageView(image: UIImage(named: "loading"))
//        loadingImageView.isHidden = true
//        addSubview(loadingImageView)
//        loadingImageView.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-20))
//            make.centerY.equalTo(titleLabel)
//        }
        
    }
    
}
