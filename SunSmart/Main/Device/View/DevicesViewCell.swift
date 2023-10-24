//
//  DevicesViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/27.
//

import UIKit
import NordicSigMeshSDK

class DevicesViewCell: UICollectionViewCell {
    
    /// 图标
    var iconImageView: UIImageView!
    /// 亮度
    var brightnessLabel: UILabel!
    /// 色温
    var cctLabel: UILabel!
    /// 进度条
    var progressView: UIProgressView!
    
    var progressBgView: UIView!
    var progressValueView: UIView!
    
    /// 名称
    var nameLabel: UILabel!
    /// 离线/off
    var stateLabel: UILabel!
    /// 代理节点标识
    var proxyFlagView: UIImageView!
    /// 编辑选中
    var selectImageView: UIImageView!
    /// 修复
    var repairLabel: UILabel!
    /// 编辑点击回调
    var editClickCallback: ((Node)->Void)?
    /// 最后更新的亮度进度
    private var progress: Int = 0
    
    private var lineView: UIView!
    
    var device: Node! {
        didSet {

            lineView.isHidden = true
            var progressAnimation = true
            var progress = Float(self.device.lightness100) / 100.0
            nameLabel.text = device.name
            if device.isKeybindComplete {
                repairLabel.isHidden = true
                if device.state {
                    iconImageView.image = UIImage(named: device.isOn ? "space_light_on" : "space_light_off")
                    if device.isOn {
                        stateLabel.isHidden = true
                        
                        brightnessLabel.isHidden = false
                        brightnessLabel.text = "\(device.lightness100)%"
                        if device.temperatureModel != nil {
                            progressValueView.backgroundColor = device.getCctMixColor()
                            cctLabel.text = "\(device.temperature)K"
                            if device.temperature100 >= 48 && device.temperature100 <= 52 { // 色温为白色设置分界线标识
                                lineView.isHidden = false
                            }
                            cctLabel.isHidden = false
                            brightnessLabel.snp.updateConstraints { make in
                                make.bottom.equalTo(iconImageView.snp.centerY)
                            }
                        }else { // 不支持色温
                            progressValueView.backgroundColor = RGB(156, 163, 175)
                            cctLabel.isHidden = true
                            brightnessLabel.snp.updateConstraints { make in
                                make.bottom.equalTo(iconImageView.snp.centerY).offset(SCRYFrom(7.5))
                            }
                        }
                    }else {
                        stateLabel.isHidden = false
                        stateLabel.text = "off_state".localizedString
                        stateLabel.textColor = RGB(143, 143, 143)
                        brightnessLabel.isHidden = true
                        cctLabel.isHidden = true
                        progress = 0
                        progressAnimation = false
                    }

                }else {
                    iconImageView.image = UIImage(named: "device_light_offline")
                    stateLabel.isHidden = false
                    stateLabel.text = "offline".localizedString
                    stateLabel.textColor = Red_Color
                    brightnessLabel.isHidden = true
                    cctLabel.isHidden = true
                    progress = 0
                    progressAnimation = false
                }
                proxyFlagView.isHidden = !(device.state && device.isProxy)
                
            }else {
                iconImageView.image = UIImage(named: "space_light_off")
                progress = 0
                progressAnimation = false
                brightnessLabel.isHidden = true
                cctLabel.isHidden = true
                repairLabel.isHidden = false
            }
            
            if progressBgView.frame.isEmpty {
                self.layoutIfNeeded()
            }
            
            if Int(progress * 100) != self.progress {
                self.progress = Int(progress * 100)
                if progressAnimation {
                    UIView.animate(withDuration: 0.25) {
                        self.progressValueView.width = self.progressBgView.width * CGFloat(progress)
                    }
                }else {
                    progressValueView.width = progressBgView.width * CGFloat(progress)
                }
            }
            
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        layer.shadowOffset = CGSize(width: 0,height: 2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 4
//        clipsToBounds = true
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
//        if progressView.layer.mask == nil {
//            progressView.addRoundedCorners(corners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: SCRYFrom(10), height: SCRYFrom(10)), rect: CGRect(x: 0, y: 0, width: self.width, height: SCRYFrom(32)))
//        }
      
        if progressBgView.layer.mask == nil {
            progressBgView.addRoundedCorners(corners: [.bottomLeft, .bottomRight], cornerRadii: CGSize(width: SCRYFrom(10), height: SCRYFrom(10)), rect: CGRect(x: 0, y: 0, width: self.width, height: SCRYFrom(32)))
        }
    }
    
    @objc private func selectImageViewClick() {
        editClickCallback?(device)
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView()
        iconImageView.image = UIImage(named: "space_light_off")
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(11))
            make.top.equalTo(SCRYFrom(15))
        }
        
        brightnessLabel = UILabel(text: "60%", textColor: RGB(0, 0, 0, 0.5), fontSize: 12, fontName: FontName_Medium)
        contentView.addSubview(brightnessLabel)
        brightnessLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(iconImageView.snp.centerY)
        }
        
        cctLabel = UILabel(text: "6000K", textColor: RGB(0, 0, 0, 0.5), fontSize: 12, fontName: FontName_Medium)
        contentView.addSubview(cctLabel)
        cctLabel.snp.makeConstraints { make in
            make.right.equalTo(brightnessLabel)
            make.top.equalTo(brightnessLabel.snp.bottom)
        }

        stateLabel = UILabel(text: "offline".localizedString, textColor: Red_Color, fontSize: 12, fontName: FontName_Medium)
        stateLabel.isHidden = true
        contentView.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(iconImageView)
        }
        
        proxyFlagView = UIImageView(image: UIImage(named: "device_proxy"))
        proxyFlagView.isHidden = true
        contentView.addSubview(proxyFlagView)
        proxyFlagView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
        }
        
//        progressView = UIProgressView(progressViewStyle: .bar)
//        progressView.trackTintColor = RGB(239, 240, 241)
//        progressView.progressTintColor = RGB(244, 206, 152)
//        progressView.progress = 0
////        progressView.layer.cornerRadius = SCRYFrom(10)
//        contentView.addSubview(progressView)
//        progressView.snp.makeConstraints { make in
//            make.left.right.bottom.equalToSuperview()
//            make.height.equalTo(SCRYFrom(32))
//        }
        
        progressBgView = UIView()
        progressBgView.backgroundColor = RGB(239, 240, 241)
        progressBgView.clipsToBounds = true
        contentView.addSubview(progressBgView)
        progressBgView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(32))
        }
        
        progressValueView = UIView()
        progressValueView.frame = CGRect(x: 0, y: 0, width: 0, height: SCRYFrom(32))
        progressValueView.backgroundColor = RGB(244, 206, 152)
        progressBgView.addSubview(progressValueView)
//        progressValueView.snp.makeConstraints { make in
//            make.left.top.bottom.equalTo(progressBgView)
//        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        lineView.isHidden = true
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(1)
            make.centerY.equalTo(progressBgView.snp.top)
        }
        
        nameLabel = UILabel(text: "ID001", textColor: .black, fontSize: 14)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.centerY.equalTo(progressBgView)
        }
        
        repairLabel = UILabel(text: "repair".localizedString, textColor: .white, fontSize: 16, fontName: FontName_Medium)
        repairLabel.backgroundColor = Red_Color.withAlphaComponent(0.7)
        repairLabel.textAlignment = .center
        contentView.addSubview(repairLabel)
        repairLabel.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(progressBgView.snp.top)
        }
        repairLabel.layoutIfNeeded()
        repairLabel.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: SCRYFrom(10), height: SCRYFrom(10)), rect: CGRect(x: 0, y: 0, width: repairLabel.width, height: repairLabel.height))
        
        selectImageView = UIImageView(image: UIImage(named: "select_un"))
        selectImageView.isHidden = true
        selectImageView.isUserInteractionEnabled = true
        selectImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectImageViewClick)))
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
        }
        
        
    }
    
    
}
