//
//  BleFirmwareUpdateRestoreView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/3/27.
//

import UIKit

protocol BleFirmwareUpdateRestoreViewDelegate: AnyObject {
    
    /// 点击恢复数据
    func firmwareUpdateDidRestoreAction(_ view: BleFirmwareUpdateRestoreView)
    
    /// 点击展开/收起
    func firmwareUpdateDidUnfoldAction(_ view: BleFirmwareUpdateRestoreView)
}

class BleFirmwareUpdateRestoreView: UICollectionReusableView {
    
    private var restoreView: UIView!
    private var arrowImageView: UIImageView!
    private var devicesNumberLabel: UILabel!
    private var restoreBtn: UIButton!
    private var messageView: UIView!
    private var iconImageView: UIImageView!
    private var messageLabel: UILabel!
    
    weak var delegate: BleFirmwareUpdateRestoreViewDelegate?
    
    /// 是否展开
    var unfold: Bool = true {
        didSet {
            if unfold {
                messageView.isHidden = false
                arrowImageView.image = UIImage(named: "arrow_unfold")
//                restoreView.snp.remakeConstraints { make in
//                    make.left.right.top.equalToSuperview()
//                    make.height.equalTo(SCRYFrom(50))
//                }
            }else {
                messageView.isHidden = true
                arrowImageView.image = UIImage(named: "arrow_fold")
//                restoreView.snp.remakeConstraints { make in
//                    make.left.right.top.equalToSuperview()
//                    make.height.equalTo(SCRYFrom(50))
//                    make.bottom.equalToSuperview()
//                }
            }
        }
    }
    
    var resetDevicesCount: Int = 0 {
        didSet {
            devicesNumberLabel.text = String(format: "ble_ota_reset_number".localizedString, self.resetDevicesCount)
        }
    }
    
    /// 获取内容高度
    static func getSectionHeight(unfold: Bool) -> CGFloat {
        
        var height = SCRYFrom(50)
        if unfold {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2
            paragraphStyle.paragraphSpacing = 4
            
            let attStr = NSAttributedString(string: "ble_ota_reset_message".localizedString, attributes: [.paragraphStyle: paragraphStyle])
            let size = attStr.boundingRect(with: CGSize(width: SCREEN_WIDTH - SCRXFrom(38 + 18), height: CGFloat(MAXFLOAT)), options: .usesLineFragmentOrigin, context: nil).size
            height += size.height + SCRYFrom(16)
        }
        return height
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RGB(236, 238, 239)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func restoreBtnAction() {
        delegate?.firmwareUpdateDidRestoreAction(self)
    }
    
    @objc private func restoreViewAction() {
        delegate?.firmwareUpdateDidUnfoldAction(self)
    }
    
    private func setupUI() {
        
        restoreView = UIView()
        restoreView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(restoreViewAction)))
        addSubview(restoreView)
        restoreView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(50))
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_unfold"))
        arrowImageView.sizeToFit()
        restoreView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.centerY.equalToSuperview()
            make.width.equalTo(arrowImageView.width)
        }
        
        restoreBtn = UIButton(title: "restore".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(restoreBtnAction))
        restoreBtn.backgroundColor = Bar_Color
        restoreBtn.layer.cornerRadius = SCRYFrom(16)
        restoreView.addSubview(restoreBtn)
        restoreBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.width.equalTo(SCRXFrom(70))
            make.height.equalTo(SCRYFrom(32))
            make.centerY.equalToSuperview()
        }
        
        devicesNumberLabel = UILabel(text: String(format: "ble_ota_reset_number".localizedString, self.resetDevicesCount), textColor: TextBlack_Color, fontSize: 13)
        restoreView.addSubview(devicesNumberLabel)
        devicesNumberLabel.snp.makeConstraints { make in
            make.left.equalTo(arrowImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.right.equalTo(restoreBtn.snp.left).offset(SCRXFrom(-17))
        }
        
        messageView = UIView()
        addSubview(messageView)
        messageView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(restoreView.snp.bottom)
//            make.bottom.equalToSuperview()
        }
        
        iconImageView = UIImageView(image: UIImage(named: "tips"))
        iconImageView.sizeToFit()
        messageView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalToSuperview()
            make.width.equalTo(iconImageView.width)
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 4
        let attStr = NSAttributedString(string: "ble_ota_reset_message".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        messageLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        messageLabel.attributedText = attStr
        messageView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-18))
            make.top.bottom.equalToSuperview()
        }
        
        
    }
    
}
