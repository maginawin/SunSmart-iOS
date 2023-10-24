//
//  EmptyDataView.swift
//  HomeeMesh
//
//  Created by 袁科鸿 on 2023/1/4.
//

import UIKit

class EmptyDataView: UIView {

    var contentView: UIView!
    var imageView: UIImageView!
    var titleLabel: UILabel!
    var tipLabel: UILabel!
    var button: UIButton!
    
    private var btnClickBack: (()->())?
    
    
    convenience init(frame: CGRect, imageName: String = "empty", title: String?, tipText: String?, buttomWidth: CGFloat = SCRXFrom(180), bottomMargin: CGFloat = 0, buttonText: String? = nil, btnClickBack: (()->())? = nil) {
        self.init(frame: frame)
        
        imageView.image = UIImage(named: imageName)
        titleLabel.text = title
        tipLabel.text = tipText
        if buttonText != nil {
            button.isHidden = false
            button.setTitle(buttonText, for: .normal)
            
            tipLabel.snp.remakeConstraints { make in
                make.left.right.equalToSuperview()
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            }
            
            button.snp.remakeConstraints { make in
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(56))
                make.centerX.equalToSuperview()
                make.width.equalTo(buttomWidth)
                make.height.equalTo(SCRYFrom(44))
                make.bottom.equalToSuperview()
            }
            self.btnClickBack = btnClickBack
        }
        if bottomMargin > 0 {
            contentView.snp.updateConstraints { make in
                if UIDevice.current.model == "iPad" {
                    make.centerY.equalToSuperview().offset(-bottomMargin - SCRYFit(100))
                }else {
                    make.bottom.equalTo(self.snp.centerY).offset(-bottomMargin)
                }
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func buttonClick() {
        
        if btnClickBack != nil {
            btnClickBack!()
        }
    }
    
    private func setupUI() {
        
        contentView = UIView()
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            
            if UIDevice.current.model == "iPad" {
                make.centerY.equalToSuperview().offset(-SCRYFit(100))
            }else {
                make.bottom.equalTo(self.snp.centerY)
            }
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(-SCRXFrom(20))
        }
        
        imageView = UIImageView()
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "", textColor: RGB(100, 116, 139), fontSize: 14)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(2))
        }
        
        tipLabel = UILabel(text: "", textColor: RGB(100, 136, 139), fontSize: 14)
        tipLabel.textAlignment = .center
        tipLabel.numberOfLines = 0
        contentView.addSubview(tipLabel)
        tipLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview()
        }
        
        button = UIButton(title: "", titleSize: 16, titleColor: .white, target: self, action: #selector(buttonClick))
        button.titleLabel?.font = Font_Medium_Size(16)
        button.backgroundColor = Bar_Color
        button.layer.cornerRadius = SCRYFrom(10)
        button.isHidden = true
        contentView.addSubview(button)
        button.snp.makeConstraints { make in
            make.top.equalTo(tipLabel.snp.bottom).offset(SCRYFrom(56))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(128))
            make.height.equalTo(SCRYFrom(44))
        }
    }
    
}


extension UIView {
    
    private static var emptyViewKey = "emptyView"
    
    var emptyView: EmptyDataView? {
        get {
            return objc_getAssociatedObject(self, &UIView.emptyViewKey) as? EmptyDataView
        }
        set {
            objc_setAssociatedObject(self, &UIView.emptyViewKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    func showEmptyDataView(frame: CGRect? = nil, imageName: String? = nil, title: String? = nil, tipText: String? = nil, buttonText: String? = nil, buttomWidth: CGFloat = SCRXFrom(180), bottomMargin: CGFloat = 0, btnClickBack: (()->())? = nil) {
        
        hideEmptyDataView()
        
        let emptyView = EmptyDataView(frame: frame ?? self.bounds, imageName: imageName ?? "data_empty", title: title, tipText: tipText, buttomWidth: buttomWidth, bottomMargin: bottomMargin, buttonText: buttonText, btnClickBack: btnClickBack)
        addSubview(emptyView)
        self.emptyView = emptyView
    }
    
    func hideEmptyDataView() {
        if self.emptyView != nil {
            self.emptyView?.removeFromSuperview()
        }
    }
    
    func showStatusView(frame: CGRect? = nil, imageName: String? = nil, title: String? = nil, tipText: String? = nil, buttonText: String? = nil, btnClickBack: (()->())? = nil) {
        hideStatusView()
        
        let emptyView = EmptyDataView(frame: frame ?? self.bounds, imageName: imageName ?? "data_empty", title: title, tipText: tipText, buttonText: buttonText, btnClickBack: btnClickBack)
        emptyView.backgroundColor = .black
        addSubview(emptyView)
        emptyView.contentView.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        emptyView.imageView.snp.remakeConstraints { make in
            make.top.equalTo(SCRYFit(80))
            make.centerX.equalToSuperview()
        }
        emptyView.tipLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(28))
            make.right.equalTo(SCRXFrom(-28))
            make.top.equalTo(emptyView.imageView.snp.bottom).offset(SCRYFit(64))
        }
        emptyView.button.snp.remakeConstraints { make in
            make.top.equalTo(emptyView.tipLabel.snp.bottom).offset(SCRYFit(135))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(128))
            make.height.equalTo(SCRYFrom(44))
        }
        
        self.emptyView = emptyView
    }
    
    func hideStatusView() {
        if self.emptyView != nil {
            self.emptyView?.removeFromSuperview()
        }
    }
    
    
}
