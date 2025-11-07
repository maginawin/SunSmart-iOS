//
//  DeviceMeshNetworkResetSecitonHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/21.
//

import UIKit

protocol DeviceMeshNetworkResetSecitonHeaderViewDelegate: AnyObject {
    
    /// 点击section事件
    func sectionHeaderDidClick(_ headerView: DeviceMeshNetworkResetSecitonHeaderView)
    
    /// identity事件
    func sectionHeaderIdentifyAction(_ headerView: DeviceMeshNetworkResetSecitonHeaderView)
    
    /// 重置事件
    func sectionHeaderResetAction(_ headerView: DeviceMeshNetworkResetSecitonHeaderView)
    
    /// 重置状态图标点击
    func sectionHeaderResetStateImageAction(_ headerView: DeviceMeshNetworkResetSecitonHeaderView)
    
}

class DeviceMeshNetworkResetSecitonHeaderView: UITableViewHeaderFooterView {

    var arrowImageView: UIImageView!
    var networkNameLabel: UILabel!
    var networkIdLabel: UILabel!
    var numbersLabel: UILabel!
    var identifyBtn: UIButton!
    var identifyLoadingView: UIImageView!
    var identifyStateLabel: UILabel!
    var stateImageView: UIImageView!
    var resetBtn: UIButton!
    var lineView: UIView!
    
    var networkData: DeviceMeshNetworkResetSectionData! {
        didSet {
            if networkData.unfold {
                arrowImageView.image = UIImage(named: "arrow_up_black")
                lineView.isHidden = false
                configureCorners(isFirst: true, isLast: false)
            }else {
                arrowImageView.image = UIImage(named: "arrow_down_black")
                lineView.isHidden = true
                configureCorners(isFirst: true, isLast: true)
            }

            networkNameLabel.text = networkData.name ?? "unknown_mesh_network".localizedString
            
            let networkIdAttStr = NSMutableAttributedString(string: "ID:\(networkData.networkId)")
            networkIdAttStr.addAttribute(.foregroundColor, value: Message_Color, range: (networkIdAttStr.string as NSString).range(of: "ID:"))
            networkIdLabel.attributedText = networkIdAttStr
            
            let numbersAttStr = NSMutableAttributedString(string: "\("numbers".localizedString):\(networkData.devices.count)")
            numbersAttStr.addAttribute(.foregroundColor, value: Message_Color, range: (numbersAttStr.string as NSString).range(of: "\("numbers".localizedString):"))
            numbersLabel.attributedText = numbersAttStr
            
            
            identifyBtn.isHidden = true
            resetBtn.isHidden = true
            stateImageView.isHidden = true
            stateImageView.snp.updateConstraints { make in
                make.width.height.equalTo(30)
            }
            identifyLoadingView.isHidden = true
            identifyStateLabel.isHidden = true
            
            let resetState = networkData.resetState
            
            if !(resetState == .identifying || resetState == .identifyWait) {
                identifyLoadingView.layer.removeAnimation(forKey: "loading")
            }
         
            if resetState != .reseting {
                stateImageView.layer.removeAnimation(forKey: "loading")
            }
         
            switch resetState {
            case .none, .scanning, .disable:
                identifyBtn.isHidden = false
                resetBtn.isHidden = false
                if resetState == .scanning || resetState == .disable {
                    identifyBtn.isEnabled = false
                    resetBtn.isEnabled = false
                    identifyBtn.layer.borderColor = RGB(156, 163, 175, 0.5).cgColor
                }else {
                    identifyBtn.isEnabled = true
                    resetBtn.isEnabled = true
                    identifyBtn.layer.borderColor = Bar_Color.cgColor
                }
                
            case .identifyWait, .identifying, .identifyFail:
                resetBtn.isHidden = false
                identifyLoadingView.isHidden = false
                identifyStateLabel.isHidden = false
                identifyStateLabel.textColor = TextBlack_Color
                if resetState == .identifyWait {
                    identifyStateLabel.text = "device_add_waiting".localizedString
                }else if resetState == .identifying {
                    identifyStateLabel.text = "identifying".localizedString
//                    deviceImageView.layer.addOpacityAnimation(fromOpacity: 1, toOpacity: 0, duration: 0.5, repeatCount: 10, animationKey: "identify")
                }else if resetState == .identifyFail {
                    identifyStateLabel.text = "device_identify_failed".localizedString
                    identifyStateLabel.textColor = Red_Color
                }
                let textSize = identifyStateLabel.sizeThatFits(CGSize(width: 120, height: 30))
                identifyStateLabel.snp.updateConstraints { make in
                    make.width.equalTo(textSize.width + SCRXFrom(12))
                }
                if identifyLoadingView.layer.animation(forKey: "loading") == nil {
                    identifyLoadingView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "loading")
                }
            case .wait:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_add_waiting")
            case .reseting:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "loading")
                if stateImageView.layer.animation(forKey: "loading") == nil {
                    stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "loading")
                }
            case .success:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_add_success")
            case .failed:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_fault")
                identifyBtn.isHidden = false
            }
            
        }
    }
    
    weak var delegate: DeviceMeshNetworkResetSecitonHeaderViewDelegate?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        contentView.backgroundColor = .white
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewDidClick)))
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func viewDidClick() {
        
        delegate?.sectionHeaderDidClick(self)
    }
    
    @objc private func resetBtnAction() {
        delegate?.sectionHeaderResetAction(self)
    }
    
    @objc private func identifyBtnClick() {
        delegate?.sectionHeaderIdentifyAction(self)
    }
    
    @objc private func stateImageViewClick() {
        delegate?.sectionHeaderResetStateImageAction(self)
    }
    
    private func setupUI() {
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down_black"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(10))
            make.width.height.equalTo(30)
        }
        
        resetBtn = UIButton(normalImageName: "reset", target: self, action: #selector(resetBtnAction))
        contentView.addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(arrowImageView)
        }
        
        stateImageView = UIImageView()
        stateImageView.isUserInteractionEnabled = true
        stateImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stateImageViewClick)))
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(resetBtn)
            make.width.height.equalTo(30)
        }
        
        identifyBtn = UIButton(title: "identify".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(identifyBtnClick))
        identifyBtn.setTitleColor(RGB(39, 37, 54, 0.5), for: .disabled)
        identifyBtn.layer.cornerRadius = 15
        identifyBtn.layer.borderColor = Bar_Color.cgColor
        identifyBtn.layer.borderWidth = 0.6
        identifyBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(14), bottom: 0, right: SCRXFrom(14))
        contentView.addSubview(identifyBtn)
        identifyBtn.snp.makeConstraints { make in
            make.right.equalTo(resetBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(resetBtn)
            make.height.equalTo(resetBtn)
        }
        
        identifyLoadingView = UIImageView(image: UIImage(named: "loading"))
        identifyLoadingView.isHidden = true
        contentView.addSubview(identifyLoadingView)
        identifyLoadingView.snp.makeConstraints { make in
            make.center.equalTo(identifyBtn)
            make.width.height.equalTo(SCRYFrom(40))
        }
        
        identifyStateLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        identifyStateLabel.layer.cornerRadius = 3
        identifyStateLabel.layer.borderWidth = 0.6
        identifyStateLabel.layer.borderColor = Message_Color.cgColor
        identifyStateLabel.textAlignment = .center
        identifyStateLabel.backgroundColor = .white
        identifyStateLabel.isHidden = true
        contentView.addSubview(identifyStateLabel)
        identifyStateLabel.snp.makeConstraints { make in
            make.center.equalTo(identifyLoadingView)
            make.height.equalTo(16)
            make.width.equalTo(50)
        }
        
        
        networkNameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light, fit: false)
        networkNameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        networkNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentView.addSubview(networkNameLabel)
        networkNameLabel.snp.makeConstraints { make in
            make.left.equalTo(arrowImageView.snp.right).offset(SCRXFrom(10))
            make.right.equalTo(identifyBtn.snp.left).offset(SCRXFrom(-9)).priority(.low)
            make.centerY.equalTo(arrowImageView)
        }
        
        networkIdLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(networkIdLabel)
        networkIdLabel.snp.makeConstraints { make in
            make.left.equalTo(networkNameLabel)
            make.top.equalTo(networkNameLabel.snp.bottom).offset(SCRYFrom(10))
        }
        
        numbersLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(numbersLabel)
        numbersLabel.snp.makeConstraints { make in
            make.left.equalTo(networkIdLabel.snp.right).offset(SCRXFrom(16))
            make.centerY.equalTo(networkIdLabel)
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(15))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
        
    }
    
}

extension UITableViewHeaderFooterView {
    
    func configureCorners(isFirst: Bool, isLast: Bool) {
        let cornerRadius: CGFloat = SCRYFrom(10)
        var corners: CACornerMask = []
        
        // 设置顶部圆角
        if isFirst {
            corners.insert(.layerMinXMinYCorner)
            corners.insert(.layerMaxXMinYCorner)
        }
        
        // 设置底部圆角
        if isLast {
            corners.insert(.layerMinXMaxYCorner)
            corners.insert(.layerMaxXMaxYCorner)
        }
        
        // 设置圆角
        self.backgroundColor = .clear
        self.contentView.backgroundColor = .white
        if isFirst || isLast {
            self.contentView.layer.cornerRadius = cornerRadius
            self.contentView.layer.maskedCorners = corners
            self.contentView.layer.masksToBounds = true
        }
    }
    
}
