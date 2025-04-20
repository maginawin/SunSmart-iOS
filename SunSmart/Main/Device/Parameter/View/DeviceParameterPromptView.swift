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
    
}

class DeviceParameterPromptView: UIView {

    var titleLabel: UILabel!
    var filterBtn: UIButton!
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

    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.bottom.equalTo(SCRYFrom(-8))
        }
        
        filterBtn = UIButton(normalImageName: "filter", selectedImageName: "filter_selected", target: self, action: #selector(filterBtnAction))
        addSubview(filterBtn)
        filterBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
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
