//
//  DeviceLightControlView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/27.
//

import UIKit

protocol DeviceLightControlViewDelegate: AnyObject {
    
    /// 灯控制level回调
    /// - Parameters:
    ///   - view: self
    ///   - level: 亮度
    ///   - ended: 是否最后修改
    func lightControl(_ view: DeviceLightControlView, levelValueChanged level: Int, ended: Bool)
    
    /// 灯控制cct回调
    /// - Parameters:
    ///   - view: self
    ///   - cct: 色温
    ///   - ended: 是否最后修改
    func lightControl(_ view: DeviceLightControlView, cctValueChanged cct: Int, ended: Bool)
    
    /// 灯控制消失回调
    func lightControlDidHide(_ view: DeviceLightControlView)
    
}

class DeviceLightControlView: UIView {

    private var shadeView: UIView!
    private var contentView: UIView!
    private var levelSliderView: BuoySliderView!
    private var cctSliderView: BuoySliderView!
    
    
    weak var delegate: DeviceLightControlViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show() {
        self.isHidden = false
        contentView.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
        }
    }
    
    public func hide() {
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.isHidden = true
        } completion: { _ in
            self.isHidden = true
            self.delegate?.lightControlDidHide(self)
        }
    }
    
    @objc private func shadeViewClick() {
        hide()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.alpha = 0
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewClick)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.layer.cornerRadius = SCRYFrom(15)
        contentView.backgroundColor = .white
        contentView.clipsToBounds = true
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(kSafeAreaBottomHeight != 0 ? -kSafeAreaBottomHeight : SCRXFrom(-8))
        }
        
        levelSliderView = BuoySliderView(frame: .zero, functionType: .level())
        levelSliderView.slider.throttle = true
        levelSliderView.slider.interval = 0.5
        levelSliderView.value = 100
        levelSliderView.valueThrottleChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
            self.delegate?.lightControl(self, levelValueChanged: value, ended: ended)
        }
        contentView.addSubview(levelSliderView)
        levelSliderView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(22))
            make.right.equalTo(SCRXFrom(-21))
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(83))
        }
        
        cctSliderView = BuoySliderView(frame: .zero, functionType: .cct())
        cctSliderView.value = 4600
        cctSliderView.slider.throttle = true
        cctSliderView.slider.interval = 0.5
        cctSliderView.valueThrottleChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
            self.delegate?.lightControl(self, cctValueChanged: value, ended: ended)
        }
        contentView.addSubview(cctSliderView)
        cctSliderView.snp.makeConstraints { make in
            make.bottom.equalTo(SCRYFrom(-40))
            make.left.right.height.equalTo(levelSliderView)
            make.top.equalTo(levelSliderView.snp.bottom)
        }
        
    }
    
}
