//
//  DeviceDongleDeleteAlertView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/24.
//

import UIKit

class DeviceDongleDeleteAlertView: UIView {

    typealias DeleteActionCallback = ((DeleteMode)->Void)
    
    /// 删除方式
    enum DeleteMode {
        /// 保留数据
    case retainStoredData
        /// 清除数据
    case clearAllStoredData
    }
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var messageLabel: UILabel!
    private var deleteRetainStoredView: DeviceDongleDeleteOptionsView!
    private var deleteClearAllStoredView: DeviceDongleDeleteOptionsView!
    private var lineView: UIView!
    private var cancelBtn: UIButton!
    private var deleteCallback: DeleteActionCallback?
    
    init(deleteCallback: DeleteActionCallback?) {
        self.deleteCallback = deleteCallback
        super.init(frame: UIScreen.main.bounds)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
        }
        contentView.layoutIfNeeded()
        contentView.transform = CGAffineTransformMakeScale(0.1, 0.1)
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 1, options: .curveEaseInOut) {
            self.contentView.transform = .identity
            self.shadeView.alpha = 1
        }
    }
    
    private func hide() {
        
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.layer.addScaleAnimation(fromScale: 1, toScale: 0.7, duration: 0.2)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func cancelBtnAction() {
        hide()
    }
    
    @objc private func deleteRetainStoredAction() {
        deleteCallback?(.retainStoredData)
        hide()
    }
    
    @objc private func deleteClearAllStoredAction() {
        deleteCallback?(.clearAllStoredData)
        hide()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = RGB(247, 247, 247)
        contentView.layer.cornerRadius = SCRYFrom(20)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(37))
            make.right.equalTo(SCRXFrom(-36))
            make.centerY.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "notification".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(24))
        }
        
        messageLabel = UILabel(text: "dongle_reset_message".localizedString, textColor: Title_Color, fontSize: 12, fontWeight: .light, fit: false)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
        }
        
        deleteRetainStoredView = DeviceDongleDeleteOptionsView()
        deleteRetainStoredView.messageLabel.text = "dongle_reset_retain_stored_message".localizedString
        deleteRetainStoredView.deleteBtn.setTitle("dongle_reset_retain_stored".localizedString, for: .normal)
        deleteRetainStoredView.deleteBtn.addTarget(self, action: #selector(deleteRetainStoredAction), for: .touchUpInside)
        contentView.addSubview(deleteRetainStoredView)
        deleteRetainStoredView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(17))
            make.right.equalTo(SCRXFrom(-17))
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        deleteClearAllStoredView = DeviceDongleDeleteOptionsView()
        deleteClearAllStoredView.messageLabel.text = "dongle_reset_clear_stored_message".localizedString
        deleteClearAllStoredView.deleteBtn.setTitle("dongle_reset_clear_stored".localizedString, for: .normal)
        deleteClearAllStoredView.deleteBtn.addTarget(self, action: #selector(deleteClearAllStoredAction), for: .touchUpInside)
        contentView.addSubview(deleteClearAllStoredView)
        deleteClearAllStoredView.snp.makeConstraints { make in
            make.left.right.equalTo(deleteRetainStoredView)
            make.top.equalTo(deleteRetainStoredView.snp.bottom).offset(SCRYFrom(16))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(0, 0, 0, 0.03)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(deleteClearAllStoredView.snp.bottom).offset(SCRYFrom(18))
            make.height.equalTo(1)
        }
        
        cancelBtn = UIButton(title: "alert_item_cancel".localizedString, titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(cancelBtnAction))
        contentView.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(lineView.snp.bottom)
            make.height.equalTo(SCRYFrom(60))
        }
        
    }
    
    
    class DeviceDongleDeleteOptionsView: UIView {
        var messageLabel: UILabel!
        var deleteBtn: UIButton!
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            layer.cornerRadius = SCRYFrom(10)
            backgroundColor = .white
            
            messageLabel = UILabel(text: "", textColor: Title_Color, fontSize: 12, fontWeight: .light, fit: false)
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            addSubview(messageLabel)
            messageLabel.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(SCRYFrom(8))
            }
            
            deleteBtn = UIButton(title: nil, titleSize: 14, titleWeight: .light, titleColor: Bar_Color)
            deleteBtn.layer.cornerRadius = SCRYFrom(10)
            deleteBtn.layer.borderColor = RGB(220, 220, 220).cgColor
            deleteBtn.layer.borderWidth = 0.5
            deleteBtn.backgroundColor = Background_Color
            addSubview(deleteBtn)
            deleteBtn.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(20))
                make.right.equalTo(SCRXFrom(-20))
                make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(14))
                make.bottom.equalTo(SCRYFrom(-14))
                make.height.equalTo(SCRYFrom(32))
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
}


