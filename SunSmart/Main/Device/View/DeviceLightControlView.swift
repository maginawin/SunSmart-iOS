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
    
    /// 点击Auto回调
    func lightControlAutoAction(_ view: DeviceLightControlView)
    
}

class DeviceLightControlView: UIView {

    /// 支持功能项
    enum SupportOptions {
        /// 亮度
        case level
        /// 色温
        case cct
    }
    /// Auto状态
    enum AutoButtonState {
        case normal
        case progress
    }
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var autoBtn: UIButton!
    private var levelSliderView: BuoySliderView!
    private var cctSliderView: BuoySliderView!
    
    var autoState: AutoButtonState = .normal
    
    private var lastSupportOptions: [SupportOptions] = [.level, .cct]
    
    /// 支持的功能项
    var supportOptions: [SupportOptions] = [.level, .cct] {
        didSet {
            guard supportOptions != lastSupportOptions else {
                return
            }
            lastSupportOptions = supportOptions
            
            if supportOptions.contains(.level) {
                levelSliderView.isHidden = false
            }else {
                levelSliderView.isHidden = true
            }
            if supportOptions.contains(.cct) {
                cctSliderView.isHidden = false
            }else {
                cctSliderView.isHidden = true
            }
            
            if supportOptions.count == 1 {
                var slider: BuoySliderView!
                if supportOptions.contains(.level) {
                    slider = levelSliderView
                }else {
                    slider = cctSliderView
                }
                slider.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(22))
                    make.right.equalTo(SCRXFrom(-21))
                    make.top.equalTo(SCRYFrom(8))
                    make.height.equalTo(SCRYFrom(83))
                    make.bottom.equalTo(SCRYFrom(-58))
                }
            }else {
                levelSliderView.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(22))
                    make.right.equalTo(SCRXFrom(-21))
                    make.top.equalTo(SCRYFrom(8))
                    make.height.equalTo(SCRYFrom(83))
                }
                
                cctSliderView.snp.remakeConstraints { make in
                    make.bottom.equalTo(SCRYFrom(-40))
                    make.left.right.height.equalTo(levelSliderView)
                    make.top.equalTo(levelSliderView.snp.bottom)
                }
            }
            
        }
    }
    
    var level: Int {
        return levelSliderView.value
    }
    
    var cct: Int {
        return cctSliderView.value
    }
    
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
    
    /// 更新Auto状态
    func updateAutoStateUI(autoState: AutoButtonState) {
        self.autoState = autoState
        if autoState == .normal {
            autoBtn.backgroundColor = Bar_Color
            autoBtn.setImage(nil, for: .normal)
            autoBtn.setTitle("AUTO", for: .normal)
            autoBtn.imageView?.layer.removeAnimation(forKey: "loading")
            autoBtn.isUserInteractionEnabled = true
        }else {
            autoBtn.backgroundColor = Bar_Color.withAlphaComponent(0.5)
            autoBtn.setTitle(nil, for: .normal)
            autoBtn.setImage(UIImage(named: "loading_small_white"), for: .normal)
            autoBtn.imageView?.layer.addRotationAnimation(duration: 1, repeatCount: 100, animationKey: "loading")
            autoBtn.isUserInteractionEnabled = false
        }
    }
    
    @objc private func shadeViewClick() {
        hide()
    }
    
    @objc private func autoBtnAction() {
        delegate?.lightControlAutoAction(self)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        
        if !autoBtn.isHidden, autoBtn.isUserInteractionEnabled, autoBtn.isEnabled {
            let pointInAutoBtn = autoBtn.convert(point, from: self)
            if autoBtn.point(inside: pointInAutoBtn, with: event) {
                return autoBtn
            }
        }
        return super.hitTest(point, with: event)
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
            make.height.greaterThanOrEqualTo(SCRYFrom(156))
        }
        
        autoBtn = UIButton(title: "AUTO", titleSize: 12, titleWeight: .light, titleColor: .white, target: self, action: #selector(autoBtnAction))
        autoBtn.layer.cornerRadius = SCRYFrom(10)
        autoBtn.backgroundColor = Bar_Color
        contentView.addSubview(autoBtn)
        autoBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(SCRYFrom(16))
            make.width.equalTo(SCRXFrom(52))
            make.height.equalTo(SCRYFrom(32))
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
            make.top.equalTo(SCRYFrom(20))
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
