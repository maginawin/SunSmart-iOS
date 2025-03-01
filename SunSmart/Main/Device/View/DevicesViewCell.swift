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
    
    var progressView: CustomProgressView!
    /// 名称
    var nameLabel: UILabel!
    /// 离线/off
//    var stateLabel: UILabel!
    /// 代理节点标识
    var proxyFlagView: UIView!
    /// 编辑选中
    var selectImageView: UIImageView!
    /// 修复
//    var repairLabel: UILabel!
    /// 编辑点击回调
    var editClickCallback: ((Node)->Void)?
    
    var device: Node! {
        didSet {

            backgroundColor = .white
            nameLabel.text = device.name
//            if device.isKeybindComplete {
            if device.isKeybindComplete {
                progressView.isHidden = false
//                lightnessProgressView.isHidden = false
                iconImageView.image = UIImage(named: device.iconName)
                
                if device.state {
                    
                    var progressAnimation = false
                    var progress: Int = 0
                    
//                    progressView.isHidden = false
                    iconImageView.snp.updateConstraints { make in
                        make.top.equalTo(SCRYFrom(12))
                    }
                    
                    if device.isOn {
                        nameLabel.textColor = Title_Color
                        var lightness100 = Node.getLightness100(lightness: device.lightness)
                        if device.isOn, device.lightness == 0, let trunOffLightness = device.trunOffLightness { // 开灯并且亮度0，设备亮度未上报；先显示设备关灯前的亮度值
                            lightness100 = Node.getLightness100(lightness: trunOffLightness) // , range: device.lightnessRange
                        }
                        
                        progress = lightness100
                        
                        if device.lastLightness != device.lightness {
                            device.lastLightness = device.lightness
                            progressAnimation = true
                        }
                        
                    }else {
                        nameLabel.textColor = RGB(148, 163, 184)
                        backgroundColor = RGB(226, 226, 226)
                        progress = 0
                    }
                   
                    progressView.setProgress(Int(progress), animated: progressAnimation)

                    if device.temperatureModel != nil {
                        progressView.progressColor = Node.getCctMixColor(temperature100: device.temperature100)
                    }else {
                        progressView.progressColor = RGB(156, 163, 175)
                    }
                    
                }else {
                    
                    iconImageView.snp.updateConstraints { make in
                        make.top.equalTo(SCRYFrom(24))
                    }
                    
                    iconImageView.image = UIImage(named: device.offlineIconName)
                    
                    device.lastLightness = 0
                    nameLabel.textColor = RGB(148, 163, 184)
                    progressView.isHidden = true
                }
                proxyFlagView.isHidden = !(device.state && device.isProxy)
            }else {
            
                progressView.isHidden = true
                iconImageView.image = UIImage(named: "device_repair")
                iconImageView.snp.updateConstraints { make in
                    make.top.equalTo(SCRYFrom(24))
                }
                nameLabel.textColor = RGB(148, 163, 184)
                proxyFlagView.isHidden = true
            }
            
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
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
        
        layer.cornerRadius = height * 0.5
    }
    
    @objc private func selectImageViewClick() {
        editClickCallback?(device)
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView()
        iconImageView.image = UIImage(named: "device_light")
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(11))
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(12))
            make.width.height.equalTo(SCRXFrom(40))
        }
        
        proxyFlagView = UIView()
        proxyFlagView.layer.cornerRadius = 3
        proxyFlagView.backgroundColor = Bar_Color
        proxyFlagView.isHidden = true
        contentView.addSubview(proxyFlagView)
        proxyFlagView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRXFrom(20))
            make.width.height.equalTo(6)
        }

        progressView = CustomProgressView()
        progressView.cornerRadius = 2
        progressView.progressPadding = 0.5
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(25))
            make.right.equalTo(SCRXFrom(-25))
            make.top.equalTo(self.snp.centerY).offset(SCRYFrom(12))
            //            make.bottom.equalTo(SCRYFrom(-40))
            make.height.equalTo(4)
        }
        
        nameLabel = UILabel(text: "ID001", textColor: Title_Color, fontSize: 14, fontWeight: .light)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.bottom.equalTo(SCRYFit(-14))
        }

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
 
private extension Node {
    
    static var lastLightnessKey = 100
    /// 最后保存的亮度值
    var lastLightness: UInt16 {
        get {
            objc_getAssociatedObject(self, &Node.lastLightnessKey) as? UInt16 ?? 0
        }set {
            objc_setAssociatedObject(self, &Node.lastLightnessKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    
}
