//
//  EmptyDataView.swift
//  HomeeMesh
//
//  Created by 袁科鸿 on 2023/1/4.
//

import UIKit

class EmptyDataView: UIView {

    enum ContentPosition {
    case center
    case bottomCenter
    }
    
    var contentView: UIView!
    var imageView: UIImageView!
    var titleLabel: UILabel!
    var tipLabel: UILabel!
    var button: UIButton!
    
    private var position: ContentPosition = .bottomCenter
    private var bottomMargin: CGFloat = 0
    private var margin: CGFloat = SCRXFrom(20)
    
    private var btnClickBack: (()->())?
    
    
    init(frame: CGRect, imageName: String = "empty", title: String?, tipText: String?, margin: CGFloat = SCRXFrom(20), buttomWidth: CGFloat = SCRXFrom(180), bottomMargin: CGFloat = 0, position: ContentPosition = .bottomCenter, buttonText: String? = nil, btnClickBack: (()->())? = nil) {
        
        super.init(frame: frame)
        self.position = position
        self.bottomMargin = bottomMargin
        self.margin = margin
        setupUI()
        
        imageView.image = UIImage(named: imageName)
        titleLabel.text = title
        tipLabel.text = tipText
//        contentView.snp.remakeConstraints { make in
//            make.left.equalTo(margin)
//            make.right.equalTo(-margin)
//            if position == .bottomCenter {
//                make.bottom.equalTo(self.snp.centerY).offset(-bottomMargin)
//            }else {
//                make.centerY.equalTo(self).offset(-bottomMargin)
//            }
//        }
        
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
//        if bottomMargin > 0 {
//            contentView.snp.updateConstraints { make in
//                if UIDevice.current.model == "iPad" {
//                    make.centerY.equalToSuperview().offset(-bottomMargin - SCRYFit(100))
//                }else {
//                    if position == .bottomCenter {
//                        make.bottom.equalTo(self.snp.centerY).offset(-bottomMargin)
//                    }else {
//                        make.centerY.equalTo(self).offset(-bottomMargin)
//                    }
//                }
//            }
//        }
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
//        contentView.snp.makeConstraints { make in
//            
//            if UIDevice.current.model == "iPad" {
//                make.centerY.equalToSuperview().offset(-SCRYFit(100))
//            }else {
//                make.bottom.equalTo(self.snp.centerY)
//            }
//            make.left.equalTo(SCRXFrom(20))
//            make.right.equalTo(-SCRXFrom(20))
//        }
        contentView.snp.makeConstraints { make in
//            if UIDevice.current.model == "iPad" {
//                make.centerY.equalToSuperview().offset(-bottomMargin - SCRYFit(50))
//            }else {
                if position == .bottomCenter {
                    make.bottom.equalTo(self.snp.centerY).offset(-bottomMargin)
                }else {
                    make.centerY.equalTo(self).offset(-bottomMargin)
                }
//            }
            make.left.equalTo(margin)
            make.right.equalTo(-margin)
        }
        
        
        
        imageView = UIImageView()
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "", textColor: RGB(100, 116, 139), fontSize: 15, fontWeight: .light)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(2))
        }
        
        tipLabel = UILabel(text: "", textColor: RGB(100, 136, 139), fontSize: 15, fontWeight: .light)
        tipLabel.textAlignment = .center
        tipLabel.numberOfLines = 0
        contentView.addSubview(tipLabel)
        tipLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalToSuperview()
        }
        
        button = UIButton(title: "", titleSize: 16, titleWeight: .light, titleColor: .white, target: self, action: #selector(buttonClick))
        button.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
        button.backgroundColor = Bar_Color
        button.layer.cornerRadius = SCRYFrom(10)
        button.isHidden = true
        contentView.addSubview(button)
        button.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(56))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(128))
            make.height.equalTo(SCRYFrom(44))
        }
        
        
    }
    
}


extension UIView {
    
    private static var emptyViewKey: UInt8 = 0
    
    var emptyView: EmptyDataView? {
        get {
            return objc_getAssociatedObject(self, &UIView.emptyViewKey) as? EmptyDataView
        }
        set {
            objc_setAssociatedObject(self, &UIView.emptyViewKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    func showEmptyDataView(frame: CGRect? = nil, imageName: String? = nil, title: String? = nil, tipText: String? = nil, backgroundColor: UIColor = .clear, buttonText: String? = nil, buttomWidth: CGFloat = SCRXFrom(180), position: EmptyDataView.ContentPosition = .bottomCenter, margin: CGFloat = SCRXFrom(20), bottomMargin: CGFloat = 0, btnClickBack: (()->())? = nil) {
        
        hideEmptyDataView()
//        CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height)
        let emptyView = EmptyDataView(frame: frame ?? self.bounds, imageName: imageName ?? "data_empty", title: title, tipText: tipText, margin: margin, buttomWidth: buttomWidth, bottomMargin: bottomMargin, position: position, buttonText: buttonText, btnClickBack: btnClickBack)
        emptyView.backgroundColor = backgroundColor
        addSubview(emptyView)
        self.emptyView = emptyView
    }
    
    func hideEmptyDataView() {
        if self.emptyView != nil {
            self.emptyView?.removeFromSuperview()
            self.emptyView = nil
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
