//
//  SitesTransferredView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/5.
//

import UIKit

class SitesTransferredView: UIView {

    typealias DoneCallback = ((TransferredData)->Void)
    
    /// 转让成功信息
    struct TransferredData {
        /// site id
        let siteId: String
        /// site名称
        let siteName: String
        /// 接收者名称
        let receiveName: String
    }
    
    private let datas: [TransferredData]
    private var doneBack: DoneCallback?
    
    private var shadeView: UIView!
    private var alertViews: [SRAlertView] = []
    
    init(datas: [TransferredData], doneBack: DoneCallback? = nil) {
        self.datas = datas
        super.init(frame: UIScreen.main.bounds)
        
        self.doneBack = doneBack
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        self.tag = 100
        UIApplication.shared.keyWindow().addSubview(self)
        
    }
    
    private func setupUI() {
        
        shadeView = UIView()
//        shadeView.frame = self.bounds
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        self.alertViews = datas.reversed().map({ data in
            
            let messagrAttStr = NSMutableAttributedString(string: String(format: "site_transferred_message".localizedString, data.siteName) + "\n\n", attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .light), .foregroundColor: Title_Color])
            messagrAttStr.append(NSAttributedString(string: "receiver:".localizedString, attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .light), .foregroundColor: Message_Color]))
            messagrAttStr.append(NSAttributedString(string: data.receiveName, attributes: [.font: FONTS(15), .foregroundColor: Bar_Color]))
            let alertView = SRAlertView(title: "notification".localizedString, messageAttStr: messagrAttStr, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                self.alertViews.removeLast()
                if self.alertViews.isEmpty {
                    self.removeFromSuperview()
                }else {
                    self.updateFrames()
                }
            })])
            alertView.messageLabel.textAlignment = .left
            
            alertView.shadeView.alpha = 0
            self.addSubview(alertView)
            return alertView
        })
        updateFrames(false)
    }
    
    private func updateFrames(_ animation: Bool = true) {
        
        for index in 0..<self.alertViews.count {
            let alertView = self.alertViews[index].contentView!
            if self.alertViews.count > 1 {
                if index == self.alertViews.count - 1 {
                    alertView.snp.updateConstraints { make in
                        make.left.equalTo(SCRXFrom(45))
                        make.right.equalTo(SCRXFrom(-28))
                        make.centerY.equalToSuperview().offset(8)
                    }
                    alertView.backgroundColor = .white
                }else {
                    alertView.snp.updateConstraints { make in
                        make.left.equalTo(SCRXFrom(29))
                        make.right.equalTo(SCRXFrom(-44))
                        make.centerY.equalToSuperview().offset(-8)
                    }
                    alertView.backgroundColor = Background_Color
                }
            }else {
                alertView.snp.updateConstraints { make in
                    make.left.equalTo(SCRXFrom(36))
                    make.right.equalTo(SCRXFrom(-37))
                    make.centerY.equalToSuperview()
                }
                alertView.backgroundColor = .white
            }
        }
        if animation {
            UIView.animate(withDuration: 0.25) {
                self.layoutIfNeeded()
            }
        }
        
    }
    
}
