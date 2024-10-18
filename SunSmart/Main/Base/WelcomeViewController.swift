//
//  WelcomeViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/2.
//

import UIKit

class WelcomeViewController: UIViewController {

    private var iconImageView: UIImageView!
    private var welcomeLabel: UILabel!
    private var policyView: UIView!
    private var checkBoxBtn: UIButton!
    private var policyTipText: UITextView!
    private var startedBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarBackgroundColor(color: .white)
        view.backgroundColor = .white
        setupUI()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }
    
    // MARK: - Action
    
    @objc private func checkBox(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
        if sender.isSelected {
            self.startedBtn.isUserInteractionEnabled = true
            self.startedBtn.backgroundColor = Bar_Color
        }else {
            self.startedBtn.isUserInteractionEnabled = false
            self.startedBtn.backgroundColor = RGB(147, 148, 196)
        }
    }
    
    @objc private func startedBtnAction() {
        
        UserData.isTermsOfService = true
        
        let window = UIApplication.shared.keyWindow()
        let rootVc = NavigationViewController(rootViewController: SitesViewController())
        
        window.layer.addMoveInAnimation(duration: 0.3, type: .push, animationOrientation: .fromRight)
        window.rootViewController = rootVc
        window.makeKeyAndVisible()
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView(image: UIImage(named: "launch_logo_120"))
        view.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(kNavigationHeight + SCRYFrom(64))
        }
        
        welcomeLabel = UILabel(text: "welcome_title".localizedString, textColor: TextBlack_Color, fontSize: 20, fit: false)
        welcomeLabel.numberOfLines = 0
        let welcomeAttStr = NSMutableAttributedString(string: "welcome_title".localizedString)
        welcomeAttStr.addAttribute(.foregroundColor, value: Bar_Color, range: (welcomeAttStr.string as NSString).range(of: "Sunsmart"))
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        welcomeAttStr.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: welcomeAttStr.string.count))
        welcomeLabel.attributedText = welcomeAttStr
        welcomeLabel.textAlignment = .center
        view.addSubview(welcomeLabel)
        welcomeLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(iconImageView.snp.bottom).offset(SCRYFit(50))
        }
        
        startedBtn = UIButton(title: "get_started".localizedString, titleSize: 16, titleWeight: .medium, titleColor: .white, target: self, action: #selector(startedBtnAction))
        startedBtn.backgroundColor = RGB(147, 148, 196)
        startedBtn.isUserInteractionEnabled = false
        startedBtn.layer.cornerRadius = SCRYFrom(8)
        view.addSubview(startedBtn)
        startedBtn.snp.makeConstraints { make in
            make.bottom.equalTo(-kSafeAreaBottomHeight - SCRYFit(130))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(208))
            make.height.equalTo(SCRYFrom(44))
        }
        
        policyView = UIView()
        view.addSubview(policyView)
        policyView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(57)).priority(.low)
            make.right.equalTo(SCRXFrom(-58)).priority(.low)
//            make.centerX.equalToSuperview()
            make.bottom.equalTo(startedBtn.snp.top).offset(SCRYFit(-60))
        }
        
        checkBoxBtn = UIButton(normalImageName: "select_un", selectedImageName: "select", target: self, action: #selector(checkBox))
        policyView.addSubview(checkBoxBtn)
        checkBoxBtn.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.width.equalTo(30)
        }
        
        policyTipText = UITextView()
        policyTipText.textColor = TextBlack_Color
        policyTipText.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        policyTipText.isScrollEnabled = false
        policyTipText.isEditable = false
        policyTipText.backgroundColor = .clear
        policyTipText.textContainerInset = .zero
        policyTipText.textContainer.lineFragmentPadding = 0
        policyTipText.tintColor = Bar_Color
        let policyText = "welcome_policy_message".localizedString
        let policyAttStr = NSMutableAttributedString(string: policyText, attributes: [.font: UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)])
        let termsRange = (policyText as NSString).range(of: "welcome_policy_use".localizedString)
        policyAttStr.addAttribute(.link, value: "Agreement://use", range: termsRange)
//        policyAttStr.addAttribute(.foregroundColor, value: Bar_Color, range: termsRange)
        
        let privacyPolicyRange = (policyText as NSString).range(of: "welcome_privacy_policy".localizedString)
//        policyAttStr.addAttribute(.foregroundColor, value: Bar_Color, range: privacyPolicyRange)
        policyAttStr.addAttribute(.link, value: "Agreement://privacy".localizedString, range: privacyPolicyRange)
        policyTipText.attributedText = policyAttStr
        policyTipText.delegate = self
        policyView.addSubview(policyTipText)
        policyTipText.snp.makeConstraints { make in
            make.left.equalTo(checkBoxBtn.snp.right).offset(SCRXFrom(8))
            make.right.equalToSuperview()
            make.top.bottom.equalToSuperview()
        }
        
    }

}


extension WelcomeViewController: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
  
        var title = ""
        var filePath: String?
        if url.absoluteString == "Agreement://use" {
            title = "welcome_policy_use".localizedString
            filePath = Bundle.main.path(forResource: "User Agreement", ofType: "html")

        }else {
            title = "welcome_privacy_policy".localizedString
            filePath = Bundle.main.path(forResource: "Privacy Policy", ofType: "html")
        }
        if filePath != nil {
            let vc = WebViewController(loadUrl: URL(fileURLWithPath: filePath!), vcTitle: title)
            navigationController?.pushViewController(vc, animated: true)
        }
        
//        var title = ""
//        var attStr: NSMutableAttributedString = .init()
//
//        if URL.absoluteString == "Agreement://use" {
//            title = "welcome_policy_use".localizedString
//            let termsOfUse = NSMutableAttributedString(string: "protocol_terms_of_use_message".localizedString, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .light)])
//            termsOfUse.addAttributes([.font: FONTS(15)], range: NSRange(location: 0, length: title.count))
//            
//            attStr = termsOfUse
//        }else {
//            title = "welcome_privacy_policy".localizedString
//            let privacyPolicy = NSMutableAttributedString(string: "protocol_privacy_policy_message".localizedString, attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .light)])
//            privacyPolicy.addAttributes([.font: FONTS(15)], range: NSRange(location: 0, length: title.count))
//            privacyPolicy.addAttributes([.font: UIFont.systemFont(ofSize: 15, weight: .light)], range: (privacyPolicy.string as NSString).range(of: "sunsmart_application".localizedString))
//            attStr = privacyPolicy
//        }
//        let paragraphStyle = NSMutableParagraphStyle()
//        paragraphStyle.lineSpacing = 6
//        attStr.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attStr.string.count))
//        
//        let vc = AttributedTextViewController(vcTitle: title, attributedStr: attStr)
//        navigationController?.pushViewController(vc, animated: true)
        
        return false
    }
    
}
