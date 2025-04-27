//
//  SRAlertView.swift
//  BLE-OTA
//
//  Created by 袁科鸿 on 2022/12/9.
//

import UIKit

class SRAlertView: UIView {

    /// 按钮排列方向
    enum ActionDirection {
    case horizontal // 水平
    case vertical // 垂直
    }
    
    /// 输入框文本输入完成回调
    typealias InputTextDoneBack = ((String)->())
    /// 输入框文本输入回调  输入文本,是否有效长度->提示文本（重名/超范围）
    typealias InputTextChangedBack = ((String, Bool)->(String?))
    
    /// 底部按钮点击回调
    typealias BottomBtnClickBack = (()->())
    
    var shadeView: UIView!
    /// 内容view
    var contentView: UIView!
    /// 标题
    var titleLabel: UILabel!
    /// 文本
    var messageLabel: UILabel!
    /// 富文本按钮
    var messageAttStrBtn: UIButton!
    /// 富文本按钮配置
    private var messageAttBtnStyle: SRAlertMessageAttBtnStyle?
    
    /// 输入框
    private var textField: UITextField!
    
    /// 第一个按钮
    var firstBtn: UIButton!
    /// 第二个按钮
    var secondBtn: UIButton!
    /// 内容分割线
    var hLineView: UIView!
    /// 按钮分割线
    private var vLineView: UIView!
    
    /// 状态图标
    var stateImageView: UIImageView!
    
    /// 进度
    var progressView: SRProgressView!
    var progressLabel: UILabel!
    
    // 底部设置按钮（打开权限弹窗）
    var bottomBtn: UIButton!
    
    /// 右上角关闭按钮
    private var closeBtn: UIButton!
    
    /// 底部按钮配置（最多设置两个）
    private var actions: [SRAlertAction] = []
    
    /// 输入框最小输入内容长度
    private var minInputLength: Int = 1
    /// 输入框最大输入内容长度
    private var maxInputLength: Int = 32
    /// 输入框输入完成回调
    private var inputDoneBack: InputTextDoneBack?
    private var textValueChangedBack: InputTextChangedBack?
    
    /// 底部按钮点击回调（一般开启权限提示等需要）
    private var bottomBtnClickBack: BottomBtnClickBack?
    /// 是否关闭弹窗（关闭动画过程防止触发事件）
    private var isDismiss: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    /// 初始化弹窗view
    /// - Parameters:
    ///   - title: 标题
    ///   - titleColor: 标题颜色
    ///   - titleFont: 标题字体
    ///   - message: 消息
    ///   - messageColor: 消息颜色
    ///   - messageFont: 消息字体
    ///   - stateImage: 状态图片
    ///   - loadingState: 是否loading状态（旋转动画）
    ///   - showProgress： 是否展示进度条
    ///   - progress： 进度 0~100
    ///   - tapBackgroundHide: 点击背景是否关闭弹窗
    ///   - contentMinHeight: 内容最小高度默认140
    ///   - margin: 弹窗左右边距
    ///   - actionDirection: 底部按钮排列方向
    ///   - showClose: 是否显示关闭按钮
    ///   - actionHeight: 底部按钮高度
    ///   - actions: 底部按钮配置
    convenience init(title: String? = nil,
                     titleColor: UIColor = Title_Color,
                     titleFont: UIFont = FONTS(SCRYFrom(15)),
                     message: String? = nil,
                     messageAttStr: NSAttributedString? = nil,
                     messageColor: UIColor = Title_Color,
                     messageFont: UIFont = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light),
                     messageAttBtnStyle: SRAlertMessageAttBtnStyle? = nil,
                     stateImage: UIImage? = nil,
                     loadingState: Bool = false,
                     showProgress: Bool = false,
                     progress: Int = 0,
                     tapBackgroundHide: Bool = true,
                     margin: CGFloat = isIPad ? SCRXFrom(150) : SCRXFrom(36),
                     contentPadding: CGFloat = SCRXFrom(27),
                     contentMinHeight: CGFloat = SCRYFrom(130),
                     actionDirection: ActionDirection = .horizontal,
                     showClose: Bool = false,
                     actionHeight: CGFloat = 60,
                     actions: [SRAlertAction] = []) {
        self.init(frame: UIScreen.main.bounds)
        
        var minHeight = contentMinHeight
        if title?.isEmpty ?? true || message?.isEmpty ?? true {
            minHeight = SCRYFrom(74)
        }
        
        contentView.snp.remakeConstraints { make in
            make.left.equalTo(margin)
            make.right.equalTo(-margin)
            make.centerY.equalToSuperview()
            if actions.count > 0 {
                make.height.greaterThanOrEqualTo(minHeight + actionHeight)
            }else {
                make.height.greaterThanOrEqualTo(minHeight)
            }
        }
        
        if message?.isEmpty ?? true && messageAttStr?.length == 0 {
            self.titleLabel.snp.remakeConstraints { make in
                make.top.equalTo(SCRYFrom(24))
                //                    make.height.greaterThanOrEqualTo(SCRYFrom(50))
                make.left.equalTo(contentPadding)
                make.right.equalTo(-contentPadding)
            }
        }else {
            if title?.isEmpty ?? true {
                messageLabel.snp.remakeConstraints { make in
                    make.top.equalTo(SCRYFrom(32))
                    make.left.equalTo(contentPadding)
                    make.right.equalTo(-contentPadding)
                }
            }else {
                self.titleLabel.snp.updateConstraints { make in
                    //                    make.height.greaterThanOrEqualTo(SCRYFrom(50))
                    make.left.equalTo(contentPadding)
                    make.right.equalTo(-contentPadding)
                }
                
                messageLabel.snp.remakeConstraints { make in
                    make.left.right.equalTo(titleLabel)
                    make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(26))
                    //                    make.height.greaterThanOrEqualTo(SCRYFrom(50))
                }
            }
        }
        
        
        
        if title != nil {
            self.titleLabel.text = title
            self.titleLabel.textColor = titleColor
            self.titleLabel.font = titleFont
        }
        
        if message != nil || messageAttStr != nil {
            self.messageLabel.textColor = messageColor
            self.messageLabel.font = messageFont
            if messageAttStr != nil {
                self.messageLabel.attributedText = messageAttStr
            }else {
                self.messageLabel.text = message
            }
        }
        
        if let style = messageAttBtnStyle {
            self.messageAttBtnStyle = style
            self.messageAttStrBtn.isHidden = false
            self.messageAttStrBtn.titleLabel?.font = style.textFont
            if style.underline {
                
                let attStr = NSMutableAttributedString(string: style.text, attributes: [.foregroundColor: style.textColor])
                attStr.addAttributes([.underlineStyle: 1, .underlineColor: style.textColor], range: NSMakeRange(0, style.text.count))
                self.messageAttStrBtn.setAttributedTitle(attStr, for: .normal)
            }else {
                self.messageAttStrBtn.setTitle(style.text, for: .normal)
                self.messageAttStrBtn.setTitleColor(style.textColor, for: .normal)
            }
            if let imageName = style.imageName {
                self.messageAttStrBtn.setImage(UIImage(named: imageName), for: .normal)
                self.messageAttStrBtn.setImagePosition(position: .right, spacing: 2)
            }
            if let selectImageName = style.selectImageName {
                self.messageAttStrBtn.setImage(UIImage(named: selectImageName), for: .selected)
            }
            self.messageAttStrBtn.snp.updateConstraints { make in
                make.centerX.equalTo(messageLabel).offset(style.offset.x)
                make.centerY.equalTo(messageLabel).offset(style.offset.y)
            }
        }
        
//        self.layoutIfNeeded()
//        hLineView.snp.makeConstraints { make in
//            self.titleLabel.sizeToFit()
////            self.titleLabel.frame.maxY + self.messageLabel.y
//            let topMargin = contentMinHeight - self.messageLabel.frame.maxY - actionHeight
//
//            make.top.equalTo(messageLabel.snp.bottom).offset(max(topMargin, SCRYFrom(18)))
//        }
        
        if stateImage != nil {
            self.stateImageView.isHidden = false
            self.stateImageView.image = stateImage!
            // 细微调整UI布局尺寸
            if actions.count == 0 {
                stateImageView.snp.updateConstraints { make in
                    make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(25))
                }
            }
            
            hLineView.snp.remakeConstraints { make in
                make.left.right.equalTo(0)
                make.height.equalTo(0.5)
                if actions.count > 0 {
                    make.top.equalTo(stateImageView.snp.bottom).offset(SCRYFrom(18))
                }else {
                    make.top.equalTo(stateImageView.snp.bottom).offset(SCRYFrom(31))
                }
            }
            // 如果是加载状态
            if loadingState {
                stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: 999)
            }
        }
        
        // 关闭按钮
        if showClose {
            self.closeBtn.isHidden = false
        }
        
        /// 进度条
        if showProgress {
            setProgress(progress)
            
            hLineView.snp.remakeConstraints { make in
                make.left.right.equalTo(0)
                make.height.equalTo(0)
                make.top.equalTo(progressLabel.snp.bottom).offset(SCRYFrom(14))
            }
        }
        
        if actions.count > 0 {
            self.actions = actions
            // 最多只支持两个按键
            while self.actions.count > 2 {
                self.actions.removeFirst()
            }
            updateBottomActionBtn()
            // 垂直方向
            if actionDirection == .vertical {
                if !firstBtn.isHidden {
                    firstBtn.snp.remakeConstraints { make in
                        make.left.right.bottom.equalTo(0)
                        make.height.equalTo(actionHeight)
                        make.top.equalTo(hLineView.snp.bottom)
                    }
                }
                if !secondBtn.isHidden {
                    
                    if !firstBtn.isHidden {
                        firstBtn.snp.remakeConstraints { make in
                            make.left.right.equalTo(0)
                            make.height.equalTo(actionHeight)
                            make.top.equalTo(hLineView.snp.bottom)
                        }
                    }
                    
                    vLineView.snp.remakeConstraints { make in
                        make.top.equalTo(firstBtn.snp.bottom)
                        make.left.right.equalToSuperview()
                        make.height.equalTo(1)
                    }
                    
                    secondBtn.snp.remakeConstraints { make in
                        make.left.right.height.equalTo(firstBtn)
                        make.top.equalTo(firstBtn.snp.bottom)
                        make.bottom.equalToSuperview()
                    }
                    
                }
                
            }
            
            
        }else { // 没有设置按钮时
            self.firstBtn.snp.updateConstraints { make in
                make.height.equalTo(0)
            }
            if tapBackgroundHide {
                self.shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewClick)))
            }
        }
        
    }
    
    
    /// 初始化输入框弹窗
    /// - Parameters:
    ///   - title: 标题
    ///   - titleColor: 标题颜色
    ///   - titleFont: 标题字体
    ///   - inputText: 输入内容
    ///   - inputTextColor: 输入内容颜色
    ///   - inputTextFont: 输入文本字体
    ///   - placeholder: 提示输入内容
    ///   - keyboardType: 键盘类型
    ///   - minInputLength: 最小输入长度
    ///   - maxInputLength: 最大输入长度
    convenience init(title: String? = nil,
                     titleColor: UIColor = TextBlack_Color,
                     titleFont: UIFont = FONTS(SCRYFrom(15)),
                     message: String? = nil,
                     messageColor: UIColor = Title_Color,
                     messageFont: UIFont = UIFont.systemFont(ofSize: 15, weight: .light),
                     inputText: String? = nil,
                     inputFieldStyle: TextFieldStyle,
                     margin: CGFloat = isIPad ? SCRXFrom(150) : SCRXFrom(35),
                     actions: [SRAlertAction] = [],
                     textValueChangedBack: InputTextChangedBack?,
                     inputDoneBack: InputTextDoneBack?) {
        
        self.init(frame: UIScreen.main.bounds)
        
        contentView.backgroundColor = RGB(245, 245, 245)
        
        contentView.snp.updateConstraints { make in
            make.left.equalTo(margin)
            make.right.equalTo(-margin)
        }
        
        if title != nil {
            self.titleLabel.text = title
            self.titleLabel.textColor = titleColor
            self.titleLabel.font = titleFont
        }
        
        self.textField.isHidden = false
        self.textField.text = inputText
        self.textField.textColor = inputFieldStyle.textColor
        self.textField.font = inputFieldStyle.textFont
        self.textField.keyboardType = inputFieldStyle.keyboardType
        self.textField.textAlignment = inputFieldStyle.textAlignment
        self.textField.layer.borderColor = inputFieldStyle.borderColor.cgColor
        self.textField.layer.borderWidth = inputFieldStyle.borderWidth
        self.textField.isSecureTextEntry = inputFieldStyle.secret
        self.textField.tintColor = inputFieldStyle.borderColor
        if let placeholder = inputFieldStyle.placeholder {
            self.textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.font: inputFieldStyle.textFont, .foregroundColor: RGB(134, 138, 160)])
        }
        if inputFieldStyle.showClear {
            textField.clearButtonMode = .whileEditing
        }else {
            textField.clearButtonMode = .never
            textField.rightViewMode = .never
        }
        self.minInputLength = inputFieldStyle.minInputLength
        self.maxInputLength = inputFieldStyle.maxInputLength
        self.textValueChangedBack = textValueChangedBack

        
        messageLabel.textColor = messageColor
        messageLabel.font = messageFont
        messageLabel.textAlignment = .left
        messageLabel.text = message
        if message == nil || message?.isEmpty ?? true {
            messageLabel.snp.remakeConstraints { make in
                make.left.equalTo(textField).offset(SCRXFrom(8))
                make.right.equalTo(textField)
                make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(7))
            }
            
            self.textField.snp.updateConstraints { make in
                make.left.equalTo(inputFieldStyle.margin)
                make.right.equalTo(-inputFieldStyle.margin)
                make.height.equalTo(inputFieldStyle.height)
            }
        }else {
            
            messageLabel.snp.remakeConstraints { make in
                make.left.right.equalTo(titleLabel)
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            }
            
            self.textField.snp.remakeConstraints { make in
                make.left.equalTo(inputFieldStyle.margin)
                make.right.equalTo(-inputFieldStyle.margin)
                make.height.equalTo(inputFieldStyle.height)
                make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(12))
            }
        }
        
        hLineView.snp.remakeConstraints { make in
            make.left.right.equalTo(0)
            make.height.equalTo(0.5)
            make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(32))
        }
        
        if actions.count > 0 {
            self.actions = actions
            // 最多只支持两个按键
            while self.actions.count > 2 {
                self.actions.removeFirst()
            }
            updateBottomActionBtn()
            
        }else { // 没有设置按钮时
            self.firstBtn.snp.updateConstraints { make in
                make.height.equalTo(0)
            }
        }
        
        self.shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewClick)))
        
        self.inputDoneBack = inputDoneBack
        
        
        textFieldEditChanged(sender: self.textField)
        
    }
    
    convenience init(title: String? = nil,
                     titleColor: UIColor = RGB(16, 26, 67),
                     titleFont: UIFont = Font_Bold_Size(SCRYFrom(15)),
                     message: String? = nil,
                     messageColor: UIColor = RGB(91, 91, 91),
                     messageFont: UIFont = FONTS(SCRYFrom(15)),
                     stateImage: UIImage? = nil,
                     loadingState: Bool = false,
                     backgroundColor: UIColor = .white,
                     margin: CGFloat = isIPad ? SCRXFrom(150) : SCRXFrom(38),
                     contentMinHeight: CGFloat = SCRYFrom(130),
                     btnText: String,
                     btnTextColor: UIColor = .white,
                     btnTextFont: UIFont = Font_Bold_Size(SCRYFrom(15)),
                     btnBackgroundColor: UIColor = Bar_Color,
                     btnBorderWidth: CGFloat = 0,
                     btnClickBack: BottomBtnClickBack?) {
        
        self.init(frame: UIScreen.main.bounds)
        
        self.contentView.backgroundColor = backgroundColor
        self.contentView.snp.remakeConstraints { make in
            make.left.equalTo(margin)
            make.right.equalTo(-margin)
            make.centerY.equalToSuperview()
            make.height.greaterThanOrEqualTo(contentMinHeight)
        }
        
        if title != nil {
            self.titleLabel.text = title
            self.titleLabel.textColor = titleColor
            self.titleLabel.font = titleFont
            self.titleLabel.snp.updateConstraints { make in
                make.top.equalTo(SCRYFrom(28)).priority(.high)
                make.left.equalTo(SCRXFrom(27))
                make.right.equalTo(SCRXFrom(-27))
            }
        }
        
        if message != nil {
            self.messageLabel.text = message
            self.messageLabel.textColor = messageColor
            self.messageLabel.font = messageFont
            
            messageLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            }
        }
        
        if stateImage != nil {
            self.stateImageView.isHidden = false
            self.stateImageView.image = stateImage
            self.stateImageView.snp.remakeConstraints { make in
                make.top.equalTo(SCRYFrom(24))
                make.centerX.equalToSuperview()
            }
            if title != nil {
                self.titleLabel.snp.remakeConstraints { make in
                    make.top.equalTo(stateImageView.snp.bottom).offset(SCRYFrom(8))
                    make.left.equalTo(SCRXFrom(27))
                    make.right.equalTo(SCRXFrom(-27))
                }
            }
            // 如果是加载状态
            if loadingState {
                stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max)
            }
        }
        
        
        self.bottomBtn.isHidden = false
        self.bottomBtn.setTitle(btnText, for: .normal)
        self.bottomBtn.setTitleColor(btnTextColor, for: .normal)
        self.bottomBtn.titleLabel?.font = btnTextFont
        self.bottomBtnClickBack = btnClickBack
        self.bottomBtn.backgroundColor = btnBackgroundColor
        self.bottomBtn.layer.borderColor = btnTextColor.cgColor
        self.bottomBtn.layer.borderWidth = btnBorderWidth
//        self.bottomBtn.sizeToFit()
        
//        self.bottomBtn.snp.updateConstraints { make in
//            make.width.equalTo(self.bottomBtn.width + SCRXFrom(58))
//        }
        
//        self.bottomBtn.snp.remakeConstraints { make in
//            make.centerX.equalToSuperview()
//            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(87))
//            make.height.equalTo(SCRYFrom(44))
//        }
        
        hLineView.snp.remakeConstraints { make in
            make.left.right.equalTo(0)
            make.height.equalTo(0)
            make.top.equalTo(bottomBtn.snp.bottom).offset(SCRYFrom(20))
        }
        
        updateBottomActionBtn()
        self.firstBtn.snp.updateConstraints { make in
            make.height.equalTo(0)
        }
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
            if !self.textField.isHidden {
                self.textField.becomeFirstResponder()
            }
        }
    }
    
    
    public func dismiss(animation: Bool = true) {
        self.isDismiss = true
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
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textExceededHide), object: nil)
    }
    
    /// 更新进度条进度
    /// - Parameter progress: 进度比  0~100
    func setProgress(_ progress: Int) {
        self.progressView.isHidden = false
        self.progressLabel.isHidden = false
        self.progressView.progress = CGFloat(progress) / 100.0
        self.progressLabel.text = "\(progress)%"
        
//        self.bottomBtn.snp.updateConstraints { make in
//            make.top.equalTo(progressLabel.snp.bottom).offset(SCRYFrom(12))
//        }
        
    }
    
    // MARK: - Action
  
    /// 左侧按钮点击
    @objc private func firstBtnClick() {
        if isDismiss {
            return
        }
        if let action = actions.first {
            if action.actionHandler != nil {
                action.actionHandler!(action)
            }
            if action.closeAlert {
                dismiss(animation: action.hideAnimation)
            }
        }
//        dismiss()
    }
    
    /// 右侧按钮点击
    @objc private func secondBtnClick() {
        if isDismiss {
            return
        }
        if let action = actions.last {
            if action.actionHandler != nil {
                action.actionHandler!(action)
            }
            if action.closeAlert {
                dismiss(animation: action.hideAnimation)
            }
        }
        if self.inputDoneBack != nil {
            self.textField.resignFirstResponder()
            self.inputDoneBack!(self.textField.text ?? "")
        }
        
    }
    /// 点击背景遮罩
    @objc private func shadeViewClick() {
        // 弹出输入框时点击背景隐藏键盘
        if !self.textField.isHidden {
            self.endEditing(true)
        }else {
            dismiss()
        }
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
    /// 文本超限隐藏
    @objc private func textExceededHide() {
        textFieldEditChanged(sender: textField)
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
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textExceededHide), object: nil)
        if realText.count > maxInputLength { // 长度超限
            
            sender.text = realText.subString(rang: NSMakeRange(0, maxInputLength))
            
            if textValueChangedBack != nil {
                let message = textValueChangedBack?(realText, false)
                    messageLabel.text = message
            }
            self.perform(#selector(textExceededHide), with: nil, afterDelay: 2)
            
        }else {
            if textValueChangedBack != nil {
                let message = textValueChangedBack?(realText, realText.count >= minInputLength)
                if message?.isEmpty ?? true {
                    let enabled = realText.count >= self.minInputLength && (self.minInputLength > 0 && !realText.isAllInputTextEmpty())
                    self.secondBtn.isUserInteractionEnabled = enabled
                    self.secondBtn.setTitleColor(enabled ? Bar_Color : Bar_Color.withAlphaComponent(0.5), for: .normal)
                    messageLabel.textColor = Title_Color
                }else {
                    secondBtn.isUserInteractionEnabled = false
                    self.secondBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .normal)
                    messageLabel.textColor = Red_Color
                }
                messageLabel.text = message
            }else {
                let enabled = realText.count >= self.minInputLength && (self.minInputLength > 0 && !realText.isAllInputTextEmpty())
                self.secondBtn.isUserInteractionEnabled = enabled
                self.secondBtn.setTitleColor(enabled ? Bar_Color : Bar_Color.withAlphaComponent(0.5), for: .normal)
            }
        }
    }
    
    @objc private func clearText() {
        textField.text = nil
        textFieldEditChanged(sender: textField)
    }
    
    /// 底部按钮点击
    @objc private func bottomBtnClick() {
        if isDismiss {
            return
        }
        if self.bottomBtnClickBack != nil {
            self.bottomBtnClickBack!()
        }
        
    }
    
    ///文本点击按钮
    @objc private func messageAttStrBtnClick(sender: UIButton) {
        if messageAttBtnStyle?.selectImageName != nil {
            sender.isSelected = !sender.isSelected
        }
        messageAttBtnStyle?.actionHandler?()
    }
    
    
    // MARK: - UI
    /// 更新底部按钮
    private func updateBottomActionBtn() {
        
        if actions.count < 2 {
            secondBtn.isHidden = true
            vLineView.isHidden = true
            firstBtn.snp.remakeConstraints { make in
                make.left.right.bottom.equalTo(0)
                make.height.equalTo(60)
                make.top.equalTo(hLineView.snp.bottom)
            }
        }else {
            secondBtn.isHidden = false
            vLineView.isHidden = false
            firstBtn.snp.remakeConstraints { make in
                make.left.bottom.equalToSuperview()
                make.top.equalTo(hLineView.snp.bottom)
                make.height.equalTo(60)
                make.right.equalTo(contentView.snp.centerX)
            }
        }
        
        if let action = actions.first {
            firstBtn.setTitle(action.title, for: .normal)
            firstBtn.setTitleColor(action.titleColor, for: .normal)
            firstBtn.titleLabel?.font = action.titleFont
        }
        
        if let action = actions.last {
            secondBtn.setTitle(action.title, for: .normal)
            secondBtn.setTitleColor(action.titleColor, for: .normal)
            secondBtn.titleLabel?.font = action.titleFont
        }
    }
    
    /// 初始化UI
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.25)
        self.addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 20
        contentView.layer.masksToBounds = true
        self.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(35))
            make.right.equalTo(SCRXFrom(-35))
            make.centerY.equalToSuperview()
//            make.height.greaterThanOrEqualTo(140)
        }
        
        closeBtn = UIButton(normalImageName: "close", target: self, action: #selector(shadeViewClick))
        closeBtn.isHidden = true
        contentView.addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(8))
        }
        
        titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(24)).priority(.high)
            make.left.equalTo(SCRXFrom(27))
            make.right.equalTo(SCRXFrom(-27))
        }
        
        messageLabel = UILabel()
        messageLabel.numberOfLines = 0
//        messageLabel.lineBreakMode = .byCharWrapping
        messageLabel.textAlignment = .center
        messageLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
        }
        
        messageAttStrBtn = UIButton(target: self, action: #selector(messageAttStrBtnClick))
        messageAttStrBtn.isHidden = true
        contentView.addSubview(messageAttStrBtn)
        messageAttStrBtn.snp.makeConstraints { make in
            make.centerX.equalTo(messageLabel)
            make.centerY.equalTo(messageLabel)
        }
        
        textField = UITextField()
        textField.leftViewMode = .always
        textField.leftView = UIView(frame: CGRectMake(0, 0, 10, 0))
        textField.rightViewMode = .always
        let clearView = UIView(frame: CGRect(x: 0, y: 0, width: 38, height: 30))
        let clearBtn = UIButton(normalImageName: "nameField_clear", target: self, action: #selector(clearText))
        clearBtn.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        clearView.addSubview(clearBtn)
        textField.rightView = clearView
        textField.clearButtonMode = .whileEditing
        textField.backgroundColor = .white
        textField.returnKeyType = .done
        textField.layer.cornerRadius = SCRYFrom(5)
        textField.layer.borderWidth = 1
        textField.layer.borderColor = Bar_Color.cgColor
        textField.tintColor = Bar_Color
        
        textField.addTarget(self, action: #selector(textFieldEditDidBegin), for: .editingDidBegin)
        textField.addTarget(self, action: #selector(textFieldEditDidEnd), for: .editingDidEnd)
        textField.addTarget(self, action: #selector(textFieldEditChanged), for: .editingChanged)
        textField.isHidden = true
        textField.delegate = self
        contentView.addSubview(textField)
        textField.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(SCRXFrom(31))
            make.right.equalTo(SCRXFrom(-31))
            make.height.equalTo(SCRYFrom(40))
        }
        
        progressView = SRProgressView()
        progressView.startColor = Bar_Color
        progressView.endColor = Bar_Color
        progressView.cornerRadius = 1
        progressView.backgroundColor = RGB(216, 216, 216)
        progressView.isHidden = true
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(37))
            make.right.equalTo(SCRXFrom(-37))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(2)
        }
        
        progressLabel = UILabel(text: "0%", textColor: .black, fontSize: 13)
        progressLabel.isHidden = true
        contentView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(progressView.snp.bottom).offset(SCRYFrom(8))
        }
        
        stateImageView = UIImageView()
        stateImageView.isHidden = true
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(21))
            make.centerX.equalToSuperview()
        }
        
        
        bottomBtn = UIButton()
        bottomBtn.backgroundColor = Bar_Color
        bottomBtn.layer.cornerRadius = SCRYFrom(5)
        bottomBtn.addTarget(self, action: #selector(bottomBtnClick), for: .touchUpInside)
        bottomBtn.isHidden = true
        contentView.addSubview(bottomBtn)
        bottomBtn.snp.makeConstraints { make in
//            make.centerX.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(20))
//            make.width.equalTo(0)
            make.left.equalTo(SCRXFrom(67))
            make.right.equalTo(SCRXFrom(-67))
            make.height.equalTo(SCRYFrom(40))
        }
        
        hLineView = UIView()
        hLineView.backgroundColor = RGB(0, 0, 0, 0.1)
        contentView.addSubview(hLineView)
        hLineView.snp.makeConstraints { make in
            make.left.right.equalTo(0)
            make.height.equalTo(1)
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(22)).priority(.low)
        }
        
        vLineView = UIView()
        vLineView.backgroundColor = RGB(0, 0, 0, 0.1)
        contentView.addSubview(vLineView)
        vLineView.snp.makeConstraints { make in
            make.centerX.bottom.equalToSuperview()
            make.width.equalTo(1)
            make.top.equalTo(hLineView.snp.bottom)
        }
        
        firstBtn = UIButton()
        firstBtn.addTarget(self, action: #selector(firstBtnClick), for: .touchUpInside)
        contentView.addSubview(firstBtn)
        firstBtn.snp.makeConstraints { make in
            make.left.bottom.equalToSuperview()
            make.top.equalTo(hLineView.snp.bottom)
            make.height.equalTo(SCRYFrom(43))
            make.right.equalTo(contentView.snp.centerX)
        }
        
        secondBtn = UIButton()
        secondBtn.addTarget(self, action: #selector(secondBtnClick), for: .touchUpInside)
        contentView.addSubview(secondBtn)
        secondBtn.snp.makeConstraints { make in
            make.right.bottom.equalToSuperview()
            make.left.equalTo(firstBtn.snp.right)
            make.height.equalTo(firstBtn)
        }
        
    }
    
}

extension SRAlertView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        return true
    }
    
    

//    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//
//        // 计算的实际文本
//        let realText = (textField.text ?? "") + string
//        //获取输入文本的字节数
//        //获取高亮部分，如拼音
//
////        if let markedTextRange = textField.markedTextRange, textField.offset(from: markedTextRange.start, to: markedTextRange.end) == 0 {
////            if realText?.byteLength() ?? 0 > maxInputLength && !string.isEmpty {
////                return false
////            }
////        }
//        
//        if realText.count > maxInputLength && !string.isEmpty {
//            let message = textValueChangedBack?(realText, false)
//            messageLabel.text = message
//            secondBtn.isUserInteractionEnabled = false
//            secondBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .normal)
//            return false
//        }
//        
//        return true
//    }
    
}

class SRProgressView: UIView {
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(progressLayer)
        layer.masksToBounds = true
        progressLayer.masksToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: 2.private methods
    override public func draw(_ rect: CGRect) {
        var frameprogress = rect
        frameprogress.size.width = progress * rect.width
        progressLayer.frame = frameprogress
        progressLayer.colors = [startColor.cgColor, endColor.cgColor]
        progressLayer.cornerRadius = cornerRadius
        layer.cornerRadius = cornerRadius
    }
    
    // MARK: 3.event response
    
    // MARK: 4.interface
    @IBInspectable public var startColor: UIColor = .red {
        didSet {
            setNeedsDisplay()
        }
    }
    
    @IBInspectable public var endColor: UIColor = .yellow {
        didSet {
            setNeedsDisplay()
        }
    }
    
    @IBInspectable public var progress: CGFloat = 0.0 {
        didSet {
            setNeedsDisplay()
        }
    }
    
    @IBInspectable public var cornerRadius: CGFloat = 0 {
        didSet {
            setNeedsLayout()
        }
    }
    
    
    // MARK: 5.getter
    private lazy var progressLayer: CAGradientLayer = {
        let progressLayer = CAGradientLayer()
        progressLayer.frame = CGRect.zero
        progressLayer.locations = [0, 1]
        progressLayer.startPoint = CGPoint(x: 0, y: 1)
        progressLayer.endPoint = CGPoint(x: 1, y: 1)
        return progressLayer
    }()
}

extension SRAlertView {
    
    // 是否显示
    static func isVisible() -> Bool {
        return UIApplication.shared.keyWindow().subviews.contains(where: {$0.isKind(of: self.classForCoder())}) 
    }
    
    // 获取当前展示弹窗
    static func getCurrentAlertView() -> SRAlertView? {
        
        let alertView = UIApplication.shared.keyWindow().subviews.first(where: {$0.isKind(of: self.classForCoder())})
        return alertView as? SRAlertView
    }
    
    // 关闭弹窗
    static func hide() {
        self.getCurrentAlertView()?.dismiss()
    }
}

class SRSheetView: UIView {
    
    private var shadeView: UIView!
    /// 内容view
    private var contentView: UIView!
    /// 列表
    private var tableView: UITableView!
    /// 添加的选择项
    private var actions: [SRAlertAction] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(actions: [SRAlertAction]) {

        self.init(frame: UIScreen.main.bounds)
        if actions.isEmpty {
            return
        }
        
        self.actions = actions
        self.tableView.reloadData()
        self.tableView.snp.updateConstraints { make in
//            let showCancel = actions.contains(where: {$0.style == .cancel })
            make.height.equalTo(CGFloat(actions.count) * self.tableView.rowHeight)
        }
    }
    
    public func show() {
        // 如果已有弹窗则先关闭之前的弹窗
        UIApplication.shared.keyWindow().addSubview(self)
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
        }
        // 显示tabbar时背景需要覆盖住底部tabbar
        if !(UIViewController.getVisibleVc()?.hidesBottomBarWhenPushed ?? true) {
            self.contentView.backgroundColor = .black
        }
    }
    
    @objc private func dismiss() {
        self.removeFromSuperview()
    }
    
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.5)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))
        self.addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        self.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }

        tableView = UITableView()
        tableView.backgroundColor = RGB(19, 19, 23)
        tableView.layer.cornerRadius = 20
        tableView.layer.masksToBounds = true
        tableView.rowHeight = SCRYFrom(60)
        tableView.showsVerticalScrollIndicator = false
        tableView.separatorStyle = .none
        tableView.isScrollEnabled = false
        tableView.register(SRSheetActionViewCell.self, forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        self.contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.right.equalTo(SCRXFrom(-10))
            make.bottom.equalTo(isIphoneX ? SCRYFrom(-40) : SCRYFrom(-10))
            make.top.equalToSuperview()
            make.height.equalTo(0)
        }
    }

//    override func layoutSubviews() {
//        super.layoutSubviews()
//
//        self.contentView.addRoundedCorners(corners: [.topLeft,.topRight], cornerRadii: CGSize(width: 20, height: 20))
//    }
    
}

extension SRSheetView {
    // 获取当前展示弹窗
    static func getCurrentSheetView() -> SRSheetView? {
        
        let alertView = UIApplication.shared.keyWindow().subviews.first(where: {$0.isKind(of: self.classForCoder())})
        return alertView as? SRSheetView
    }
    
    // 关闭弹窗
    static func hide() {
        self.getCurrentSheetView()?.dismiss()
    }
}

extension SRSheetView: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return actions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SRSheetActionViewCell
        let action = actions[indexPath.row]
        cell.titleLabel.text = action.title
        cell.titleLabel.font = action.titleFont
        cell.titleLabel.textColor = action.titleColor
        cell.lineView.isHidden = indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1
        return cell
    }
    
//    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
//        return SCRYFrom(60)
//    }
  
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let action =  actions[indexPath.row]
        action.actionHandler?(action)
        
        dismiss()
    }
    
}

class SRSheetActionViewCell: UITableViewCell {
    
    var titleLabel: UILabel!
    var lineView: UIView!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        titleLabel = UILabel(text: "", textColor: .white, fontSize: 17, fontName: FontName_Bold)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-30))
            make.centerY.equalToSuperview()
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        
        lineView.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.left.right.equalTo(titleLabel)
            make.height.equalTo(1)
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


struct SRAlertAction {
    /// 文本
    let title: String
    /// 文本颜色 默认蓝牙
    var titleColor: UIColor!
    /// 文本字体
    var titleFont: UIFont!// FONTS(17)
    /// 风格
    let style: SRAlertActionStyle
    /// 点击是否关闭弹窗
    var closeAlert: Bool = true
    /// 点击后关闭弹窗是否展示动画
    var hideAnimation: Bool = true
    /// 点击事件
    var actionHandler: ((SRAlertAction)->())? = nil
    
    init(title: String, titleColor: UIColor? = nil, titleFont: UIFont? = nil, style: SRAlertActionStyle = .default, closeAlert: Bool = true, hideAnimation: Bool = true, actionHandler: ((SRAlertAction) -> Void)? = nil) {
        self.title = title
        
        switch style {
        case .default:
            self.titleColor = Bar_Color
            self.titleFont = FONTS(15)
        case .cancel:
            self.titleColor = Title_Color
            self.titleFont = FONTS(15)
        case .destructive:
            self.titleColor = Red_Color
            self.titleFont = FONTS(15)
        }
        
        if titleColor != nil {
            self.titleColor = titleColor!
        }
        if titleFont != nil {
            self.titleFont = titleFont!
        }
        self.style = style
        self.closeAlert = closeAlert
        self.hideAnimation = hideAnimation
        self.actionHandler = actionHandler
    }
}

extension SRAlertView {
    
    struct SRAlertMessageAttBtnStyle {
        
        /// 是否偏移（与message居中）
        let offset: CGPoint
        /// 文本
        let text: String
        /// 文本颜色
        let textColor: UIColor
        /// 文本字体
        let textFont: UIFont
        /// 是否显示下划线
        let underline: Bool
        /// 图标
        let imageName: String?
        /// 点击后图标
        let selectImageName: String?
        /// 事件回调
        var actionHandler: (()->())? = nil
        
        init(offset: CGPoint = .zero, text: String, textColor: UIColor = Bar_Color, textFont: UIFont = FONTS(SCRYFrom(15)), imageName: String? = nil, selectImageName: String? = nil, underline: Bool = true, actionHandler: (()->Void)? = nil) {
            self.offset = offset
            self.text = text
            self.textColor = textColor
            self.textFont = textFont
            self.underline = underline
            self.imageName = imageName
            self.selectImageName = selectImageName
            self.actionHandler = actionHandler
        }
    }
    
    /// 输入框样式
    struct TextFieldStyle {
        /// 输入文本颜色
        let textColor: UIColor
        /// 文本字体
        let textFont: UIFont
        /// 提示语
        let placeholder: String?
        /// 键盘类型
        let keyboardType: UIKeyboardType
        /// 输入框边距
        let margin: CGFloat
        /// 输入框高度
        let height: CGFloat
        /// 最小输入文本限制
        let minInputLength: Int
        /// 最大输入文本限制
        let maxInputLength: Int
        /// 边框颜色
        let borderColor: UIColor
        /// 边框宽度
        let borderWidth: CGFloat
        /// 文本排列
        let textAlignment: NSTextAlignment
        /// 是否密文
        let secret: Bool
        /// 是否展示清空
        let showClear: Bool
        
        init(textColor: UIColor = TextBlack_Color, textFont: UIFont = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light), placeholder: String? = nil, keyboardType: UIKeyboardType = .default, margin: CGFloat = SCRXFrom(31), height: CGFloat = SCRYFrom(40), minInputLength: Int = 1, maxInputLength: Int = 32, borderColor: UIColor = Bar_Color, borderWidth: CGFloat = 0.5, textAlignment: NSTextAlignment = .left, secret: Bool = false, showClear: Bool = true) {
            self.textColor = textColor
            self.textFont = textFont
            self.placeholder = placeholder
            self.keyboardType = keyboardType
            self.margin = margin
            self.height = height
            self.minInputLength = minInputLength
            self.maxInputLength = maxInputLength
            self.borderColor = borderColor
            self.borderWidth = borderWidth
            self.textAlignment = textAlignment
            self.secret = secret
            self.showClear = showClear
        }
    }
}

extension SRAlertAction {
    /// 弹窗按钮风格
    enum SRAlertActionStyle {
        /// 默认（蓝色 加粗字体）
        case `default`
        /// 取消（灰色 默认字体）
        case cancel
        /// 警示（红色  加粗字体）
        case destructive
    }
    /// 取消按键
    static let cancelAction = SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel)
    
}
