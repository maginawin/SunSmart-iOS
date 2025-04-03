//
//  BetaTestingAlertView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/3/31.
//

import UIKit

class BetaTestingAlertView: UIView {

    /// 输入框文本输入回调  输入文本->提示文本
    typealias InputTextChangedBack = ((String)->(String?))
    /// 导入事件回调
    typealias ImportActionCallBack = (()->Void)
    
    var shadeView: UIView!
    /// 内容view
    var contentView: UIView!
    /// 标题
    var titleLabel: UILabel!
    /// 文本
    var messageLabel: UILabel!
    /// 输入框
    private var textField: UITextField!
    /// 提示
    var promptLabel: UILabel!
    
    private let maxInputLength = 4
    /// 导入按钮
    var importBtn: UIButton!

    /// 右上角关闭按钮
    private var closeBtn: UIButton!
    private var textValueChangedBack: InputTextChangedBack?
    private var importCallback: ImportActionCallBack?
    
    init(inputTextCallback: InputTextChangedBack?, importCallback: ImportActionCallBack?) {
        super.init(frame: UIScreen.main.bounds)
        self.textValueChangedBack = inputTextCallback
        self.importCallback = importCallback
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Publish Methods
    
    public func show() {
        // 如果已有弹窗则先关闭之前的弹窗
        if let alartView = SRAlertView.getCurrentAlertView(){
            alartView.dismiss(animation: false)
        }
        
        UIApplication.shared.keyWindow().addSubview(self)
        contentView.layoutIfNeeded()
        contentView.transform = CGAffineTransformMakeScale(0.1, 0.1)
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 1, options: .curveEaseInOut) {
            self.contentView.transform = .identity
            self.shadeView.alpha = 1
        } completion: { _ in
            self.textField.becomeFirstResponder() 
        }
    }
    
    
    public func dismiss(animation: Bool = true) {
        
        if animation {
            UIView.animate(withDuration: 0.15) {
                self.shadeView.alpha = 0
                self.contentView.layer.addScaleAnimation(fromScale: 1, toScale: 0.7, duration: 0.2)
            } completion: { _ in
                self.removeFromSuperview()
            }
        }else {
            self.removeFromSuperview()
        }
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textPromptHide), object: nil)
    }
    
    // 获取当前展示弹窗
    static func getCurrentAlertView() -> BetaTestingAlertView? {
        
        let alertView = UIApplication.shared.keyWindow().subviews.first(where: {$0.isKind(of: self.classForCoder())})
        return alertView as? BetaTestingAlertView
    }
    
    // 关闭弹窗
    static func hide() {
        self.getCurrentAlertView()?.dismiss()
    }
    
    /// 输入框开始输入事件
    @objc private func textFieldEditDidBegin(sender: UITextField) {
        UIView.animate(withDuration: 0.25) {
            self.contentView.y = (self.height - self.contentView.height) * 0.5 - SCRYFrom(80)
        }
    }
    
    /// 输入框停止输入事件
    @objc private func textFieldEditDidEnd(sender: UITextField) {
        UIView.animate(withDuration: 0.25) {
            self.contentView.center = self.center
        }
    }
    
    /// 输入框输入内容事件
    @objc private func textFieldEditChanged(sender: UITextField) {
        
        let realText = sender.text ?? ""
//        let markedTextRange = textField.markedTextRange
//        if markedTextRange == nil || textField.offset(from: markedTextRange!.start, to: markedTextRange!.end) == 0 {
//            if realText?.byteLength() ?? 0 > maxInputLength {
//                textField.text = realText?.subString(rang: NSRange(location: 0, length: maxInputLength))
//            }
//        }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textPromptHide), object: nil)
        if realText.count > maxInputLength { // 长度超限
            sender.text = realText.subString(rang: NSMakeRange(0, maxInputLength))
        }
        if textValueChangedBack != nil {
            let message = textValueChangedBack?(realText)
            if message != nil && !message!.isEmpty {
                textField.layer.borderColor = Red_Color.cgColor
                self.perform(#selector(textPromptHide), with: nil, afterDelay: 2)
            }else {
                textField.layer.borderColor = Bar_Color.cgColor
            }
            promptLabel.text = message
            
        }
        
    }
    
    /// 提示文本隐藏
    @objc private func textPromptHide() {
        promptLabel.text = nil
        textField.layer.borderColor = Bar_Color.cgColor
    }
    
    @objc private func clearText() {
        textField.text = nil
        textFieldEditChanged(sender: textField)
    }
    
    @objc private func closeBtnAction() {
        dismiss()
    }
    
    @objc private func hideKeyboard() {
        self.endEditing(true)
    }
    
    /// 导入
    @objc private func importBtnClick() {
        dismiss()
        importCallback?()
    }
    
    /// 初始化UI
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.25)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        self.addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 20
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        contentView.layer.masksToBounds = true
        self.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(isIPad ? SCRXFrom(150) : SCRXFrom(35))
            make.right.equalTo(isIPad ? SCRXFrom(-150) : SCRXFrom(-35))
            make.centerY.equalToSuperview()
            make.height.height.equalTo(SCRYFrom(280))
        }
        
        closeBtn = UIButton(normalImageName: "close", target: self, action: #selector(closeBtnAction))
        contentView.addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-10))
            make.top.equalTo(SCRYFrom(10))
        }
        
        titleLabel = UILabel(text: "beta_testing_environment".localizedString, textColor: TextBlack_Color, fontSize: 15)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(24))
            make.left.equalTo(SCRXFrom(27))
            make.right.equalTo(SCRXFrom(-27))
        }
        
        messageLabel = UILabel(text: "download_from_server".localizedString, textColor: SubText_Color, fontSize: 14)
        messageLabel.numberOfLines = 0
        //        messageLabel.lineBreakMode = .byCharWrapping
        messageLabel.textAlignment = .center
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(28))
        }
        
        textField = UITextField()
//        textField.leftViewMode = .always
//        textField.leftView = UIView(frame: CGRectMake(0, 0, 10, 0))
//        textField.rightViewMode = .always
//        let clearView = UIView(frame: CGRect(x: 0, y: 0, width: 38, height: 30))
//        let clearBtn = UIButton(normalImageName: "nameField_clear", target: self, action: #selector(clearText))
//        clearBtn.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
//        clearView.addSubview(clearBtn)
//        textField.rightView = clearView
//        textField.clearButtonMode = .whileEditing
        textField.backgroundColor = .white
        textField.returnKeyType = .done
        textField.layer.cornerRadius = SCRYFrom(5)
        textField.layer.borderWidth = 1
        textField.layer.borderColor = Bar_Color.cgColor
        textField.tintColor = Bar_Color
        textField.textAlignment = .center
        textField.keyboardType = .numberPad
        textField.addTarget(self, action: #selector(textFieldEditDidBegin), for: .editingDidBegin)
        textField.addTarget(self, action: #selector(textFieldEditDidEnd), for: .editingDidEnd)
        textField.addTarget(self, action: #selector(textFieldEditChanged), for: .editingChanged)
        textField.delegate = self
        contentView.addSubview(textField)
        textField.snp.makeConstraints { make in
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(10))
            make.left.equalTo(SCRXFrom(55))
            make.right.equalTo(SCRXFrom(-56))
            make.height.equalTo(SCRYFrom(32))
        }
        
        promptLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 14, fontWeight: .light)
        promptLabel.textAlignment = .center
        contentView.addSubview(promptLabel)
        promptLabel.snp.makeConstraints { make in
            make.left.right.equalTo(messageLabel)
            make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(4))
        }
        
        importBtn = UIButton(title: nil, titleSize: 14, titleColor: Bar_Color, normalImageName: "import", target: self, action: #selector(importBtnClick))
        let attStr = NSAttributedString(string: "Import from local", attributes: [.underlineStyle: 1, .underlineColor: Bar_Color])
        importBtn.setAttributedTitle(attStr, for: .normal)
        importBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        contentView.addSubview(importBtn)
        importBtn.snp.makeConstraints { make in
            make.centerX.equalTo(messageLabel)
            make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(50))
        }
        
        
    }
}

extension BetaTestingAlertView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        return true
    }
    
    
}
