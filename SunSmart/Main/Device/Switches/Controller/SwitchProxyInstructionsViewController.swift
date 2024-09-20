//
//  SwitchProxyInstructionsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/6.
//

import UIKit

class SwitchProxyInstructionsViewController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "kinetic_switch_proxy_instructions".localizedString
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        isModalInPresentation = true
        
        setupUI()
    }
    
    @objc private func back() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalTo(scrollView)
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = SCRXFrom(13)
        paragraphStyle.lineSpacing = SCRYFrom(4)
        paragraphStyle.paragraphSpacing = SCRYFrom(8)
        
        let titleStr = "\("kinetic_switch_proxy_instructions_title_1".localizedString)\n\("kinetic_switch_proxy_instructions_message_1".localizedString)\n\("kinetic_switch_proxy_instructions_title_2".localizedString)\n\("kinetic_switch_proxy_instructions_message_2".localizedString)"
        
        let titleAttStr = NSMutableAttributedString(string: titleStr, attributes: [.paragraphStyle: paragraphStyle])
 
        titleAttStr.addAttributes([.font: FONTS(15)], range: (titleStr as NSString).range(of: "kinetic_switch_proxy_instructions_title_1".localizedString))
        titleAttStr.addAttributes([.font: FONTS(15)], range: (titleStr as NSString).range(of: "kinetic_switch_proxy_instructions_title_2".localizedString))
        
        
        let titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        titleLabel.numberOfLines = 0
        titleLabel.attributedText = titleAttStr
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(SCRYFrom(7))
        }
        
        let messageParagraphStyle = NSMutableParagraphStyle()
        messageParagraphStyle.lineSpacing = SCRYFrom(4)
        
        let correctView = SwitchProxyInstructionsGuideView()
        correctView.imageView.image = UIImage(named: "switch_proxy_instructions_1")
        correctView.messageLabel.attributedText = NSAttributedString(string: "kinetic_switch_proxy_correct_message".localizedString, attributes: [.paragraphStyle: messageParagraphStyle])
        contentView.addSubview(correctView)
        correctView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(32))
            make.right.equalTo(SCRXFrom(-32))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.greaterThanOrEqualTo(SCRYFrom(300))
        }
//        "kinetic_switch_proxy_error_title".localizedString
        let errorStr = "kinetic_switch_proxy_error_title".localizedString
        let errorAttStr = NSAttributedString(string: errorStr, attributes: [.paragraphStyle: paragraphStyle])
        
        let errorTitleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        errorTitleLabel.numberOfLines = 0
        errorTitleLabel.attributedText = errorAttStr
        contentView.addSubview(errorTitleLabel)
        errorTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(correctView.snp.bottom).offset(SCRYFrom(20))
            make.left.right.equalTo(titleLabel)
        }
        
        let errorView = SwitchProxyInstructionsGuideView()
        errorView.imageView.image = UIImage(named: "switch_proxy_instructions_2")
        errorView.messageLabel.attributedText = NSAttributedString(string: "kinetic_switch_proxy_error_message".localizedString, attributes: [.paragraphStyle: messageParagraphStyle])
        contentView.addSubview(errorView)
        errorView.snp.makeConstraints { make in
            make.left.right.equalTo(correctView)
            make.top.equalTo(errorTitleLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.greaterThanOrEqualTo(SCRYFrom(300))
            make.bottom.equalToSuperview()
        }
        
    }

}

class SwitchProxyInstructionsGuideView: UIView {
    
    var imageView: UIImageView!
    var switchLabel: UILabel!
    var proxyLabel: UILabel!
    var messageLabel: UILabel!
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        imageView = UIImageView()
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(imageView.snp.width).multipliedBy(324 / 310.0)
        }
        
        switchLabel = UILabel(text: "kinetic_switch".localizedString, textColor: Bar_Color, fontSize: 13, fontWeight: .light, fit: false)
        addSubview(switchLabel)
        switchLabel.snp.makeConstraints { make in
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(6))
            make.centerX.equalTo(imageView.snp.left).offset(SCRXFrom(45))
        }
        
        proxyLabel = UILabel(text: "kinetic_switch".localizedString + "proxy".localizedString, textColor: Bar_Color, fontSize: 13, fontWeight: .light, fit: false)
        addSubview(proxyLabel)
        proxyLabel.snp.makeConstraints { make in
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(6))
            make.centerX.equalTo(imageView.snp.right).offset(SCRXFrom(-66))
        }
        
        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .left
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(proxyLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(SCRXFrom(7))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
