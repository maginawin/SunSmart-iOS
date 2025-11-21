//
//  ImportProjectView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/28.
//

import UIKit

class ImportProjectView: UIView {
    
    /// 导入方式
    enum ImportMode {
        /// 扫码
        case scanQRCode
        /// uuid输入
        case uuid
    }
    
    typealias SelectCallback = ((ImportMode)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    
    private var scanQRCodeView: UIView!
    private var scanImageView: UIImageView!
    private var scanTitleLabel: UILabel!
    private var scanMessageLabel: UILabel!
    
    private var uuidView: UIView!
    private var uuidImageView: UIImageView!
    private var uuidTitleLabel: UILabel!
    private var uuidMessageLabel: UILabel!
    
    private var selectCallback: SelectCallback?
    
    init(select: SelectCallback?) {
        super.init(frame: UIScreen.main.bounds)
        self.selectCallback = select
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        
        if superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        
        shadeView.alpha = 0
        contentView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.alpha = 1
        }
    }
    
    @objc func hide() {
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    static func dismiss() {
        if let importView = UIApplication.shared.keyWindow().subviews.first(where: { $0.isKind(of: ImportProjectView.classForCoder()) }) as? ImportProjectView {
            importView.hide()
        }
    }
    
    @objc private func scanQRCodeAction() {
        hide()
        selectCallback?(.scanQRCode)
    }
    
    @objc private func uuidAction() {
        hide()
        selectCallback?(.uuid)
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hide)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 20
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            if isIphoneX {
                make.bottom.equalTo(-kSafeAreaBottomHeight)
            }else {
                make.bottom.equalTo(SCRYFrom(-8))
            }
            make.height.equalTo(SCRYFrom(203))
        }
        
        titleLabel = UILabel(text: "import_project".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        scanQRCodeView = UIView()
        scanQRCodeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(scanQRCodeAction)))
        contentView.addSubview(scanQRCodeView)
        scanQRCodeView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        scanImageView = UIImageView(image: UIImage(named: "import_qr_code"))
        scanQRCodeView.addSubview(scanImageView)
        scanImageView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
//            make.width.height.equalTo(30)
        }
        
        scanTitleLabel = UILabel(text: "scan_qrcode_import_title".localizedString, textColor: TextBlack_Color, fontSize: 14)
        scanQRCodeView.addSubview(scanTitleLabel)
        scanTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(scanImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(scanImageView)
        }
        
        scanMessageLabel = UILabel(text: "scan_qrcode_import_message".localizedString, textColor: Message_Color, fontSize: 14, fontWeight: .light)
        scanQRCodeView.addSubview(scanMessageLabel)
        scanMessageLabel.snp.makeConstraints { make in
            make.left.equalTo(scanTitleLabel)
            make.top.equalTo(scanTitleLabel.snp.bottom).offset(SCRYFrom(4))
            make.bottom.equalToSuperview()
        }
        
        uuidView = UIView()
        uuidView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(uuidAction)))
        contentView.addSubview(uuidView)
        uuidView.snp.makeConstraints { make in
            make.left.right.equalTo(scanQRCodeView)
            make.top.equalTo(scanQRCodeView.snp.bottom).offset(SCRYFrom(16))
        }
        
        uuidImageView = UIImageView(image: UIImage(named: "import_uuid"))
        uuidView.addSubview(uuidImageView)
        uuidImageView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
//            make.width.height.equalTo(30)
        }
        
        uuidTitleLabel = UILabel(text: "uuid_import_title".localizedString, textColor: TextBlack_Color, fontSize: 14)
        uuidView.addSubview(uuidTitleLabel)
        uuidTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(uuidImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(uuidImageView)
        }
        
        uuidMessageLabel = UILabel(text: "uuid_import_message".localizedString, textColor: Message_Color, fontSize: 14, fontWeight: .light)
        uuidView.addSubview(uuidMessageLabel)
        uuidMessageLabel.snp.makeConstraints { make in
            make.left.equalTo(uuidTitleLabel)
            make.top.equalTo(uuidTitleLabel.snp.bottom).offset(SCRYFrom(4))
            make.bottom.equalToSuperview()
        }
        
    }
    
}
