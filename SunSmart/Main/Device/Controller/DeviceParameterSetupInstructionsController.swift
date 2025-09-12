//
//  DeviceParameterSetupInstructionsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/29.
//

import UIKit

class DeviceParameterSetupInstructionsController: UIViewController {

    /// 模式
    enum Mode {
        /// 添加
        case add
        /// 重置
        case reset
    }
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!

    let mode: Mode
    
    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "setup_instructions".localizedString
        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(closeAction))
        
        setupUI()
    }
    
    @objc private func closeAction() {
        if navigationController?.viewControllers.count ?? 0 == 1 {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.bottom.equalToSuperview()
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        let attStrStyle = NSMutableParagraphStyle()
        attStrStyle.lineSpacing = 4
        
        let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: attStrStyle, .font: UIFont.systemFont(ofSize: 14, weight: .light)]
        
        
        let brightnessTitle = UILabel(text: "brightness_of_the_device_in_mode".localizedString, textColor: ImportantText_Color, fontSize: 15, fit: false)
        contentView.addSubview(brightnessTitle)
        brightnessTitle.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(SCRYFrom(7))
        }
        
        let brightnessNote = UILabel(text: nil, textColor: ImportantText_Color)
        brightnessNote.numberOfLines = 0
        let brightnessString = mode == .add ? "brightness_instructions".localizedString : "brightness_reset_instructions".localizedString
        brightnessNote.attributedText = NSAttributedString(string: brightnessString, attributes: attributes)
        contentView.addSubview(brightnessNote)
        brightnessNote.snp.makeConstraints { make in
            make.left.right.equalTo(brightnessTitle)
            make.top.equalTo(brightnessTitle.snp.bottom).offset(SCRYFrom(8))
        }
        
        let brightnessImage = UIImageView(image: UIImage(named: "device_parameters_brigness"))
        contentView.addSubview(brightnessImage)
        brightnessImage.snp.makeConstraints { make in
            make.left.right.equalTo(brightnessNote)
            make.top.equalTo(brightnessNote.snp.bottom).offset(SCRYFrom(26))
            make.height.equalTo(brightnessImage.snp.width).multipliedBy(154 / 335.0)
        }
        
        let illuminationTitle = UILabel(text: "illumination_fluctuation_range".localizedString, textColor: ImportantText_Color, fontSize: 15, fit: false)
        contentView.addSubview(illuminationTitle)
        illuminationTitle.snp.makeConstraints { make in
            make.left.right.equalTo(brightnessNote)
            make.top.equalTo(brightnessImage.snp.bottom).offset(SCRYFrom(16))
        }
        
        let illuminationMessage = UILabel(text: nil, textColor: ImportantText_Color)
        illuminationMessage.numberOfLines = 0
        illuminationMessage.attributedText = NSAttributedString(string: "illuminance_instructions".localizedString, attributes: attributes)
        contentView.addSubview(illuminationMessage)
        illuminationMessage.snp.makeConstraints { make in
            make.left.right.equalTo(illuminationTitle)
            make.top.equalTo(illuminationTitle.snp.bottom).offset(SCRYFrom(8))
        }
        
        let illuminationCase1 = UILabel(text: nil, textColor: SubText_Color)
        illuminationCase1.numberOfLines = 0
        illuminationCase1.attributedText = NSAttributedString(string: "illuminance_instructions_case1".localizedString, attributes: attributes)
        contentView.addSubview(illuminationCase1)
        illuminationCase1.snp.makeConstraints { make in
            make.left.right.equalTo(illuminationMessage)
            make.top.equalTo(illuminationMessage.snp.bottom).offset(SCRYFrom(8))
        }
        
        let illuminationCase1Image = UIImageView(image: UIImage(named: "device_illumination_case1"))
        contentView.addSubview(illuminationCase1Image)
        illuminationCase1Image.snp.makeConstraints { make in
            make.left.right.equalTo(illuminationCase1)
            make.top.equalTo(illuminationCase1.snp.bottom).offset(SCRYFrom(26))
            make.height.equalTo(illuminationCase1Image.snp.width).multipliedBy(58 / 335.0)
        }
        
        let illuminationCase2 = UILabel(text: nil, textColor: SubText_Color)
        illuminationCase2.numberOfLines = 0
        illuminationCase2.attributedText = NSAttributedString(string: "illuminance_instructions_case2".localizedString, attributes: attributes)
        contentView.addSubview(illuminationCase2)
        illuminationCase2.snp.makeConstraints { make in
            make.left.right.equalTo(illuminationCase1)
            make.top.equalTo(illuminationCase1Image.snp.bottom).offset(SCRYFrom(44))
        }
        
        let illuminationCase2Image = UIImageView(image: UIImage(named: "device_illumination_case2"))
        contentView.addSubview(illuminationCase2Image)
        illuminationCase2Image.snp.makeConstraints { make in
            make.left.right.equalTo(illuminationCase2)
            make.top.equalTo(illuminationCase2.snp.bottom).offset(SCRYFrom(26))
            make.height.equalTo(illuminationCase2Image.snp.width).multipliedBy(120 / 335.0)
        }
        
        let illuminationNote = UILabel(text: nil, textColor: ImportantText_Color)
        illuminationNote.numberOfLines = 0
        let illuminationNoteAttStr = NSMutableAttributedString(string: "illuminance_instructions_note".localizedString, attributes: attributes)
        illuminationNoteAttStr.addAttributes([.font: UIFont.systemFont(ofSize: 14)], range: (illuminationNoteAttStr.string as NSString).range(of: "note:".localizedString))
        illuminationNote.attributedText = illuminationNoteAttStr
        contentView.addSubview(illuminationNote)
        illuminationNote.snp.makeConstraints { make in
            make.left.right.equalTo(illuminationCase2)
            make.top.equalTo(illuminationCase2Image.snp.bottom).offset(SCRYFrom(8))
        }
        
        let notificationVolumeTitle = UILabel(text: "notification_volume".localizedString, textColor: ImportantText_Color, fontSize: 15, fit: false)
        contentView.addSubview(notificationVolumeTitle)
        notificationVolumeTitle.snp.makeConstraints { make in
            make.left.right.equalTo(illuminationTitle)
            make.top.equalTo(illuminationNote.snp.bottom).offset(SCRYFrom(16))
        }
        
        let notificationVolumeNote = UILabel(text: nil, textColor: ImportantText_Color)
        notificationVolumeNote.numberOfLines = 0
        notificationVolumeNote.attributedText = NSAttributedString(string: "notification_volume_instructions".localizedString, attributes: attributes)
        contentView.addSubview(notificationVolumeNote)
        notificationVolumeNote.snp.makeConstraints { make in
            make.left.right.equalTo(notificationVolumeTitle)
            make.top.equalTo(notificationVolumeTitle.snp.bottom).offset(SCRYFrom(8))
        }
        
        let vibrationTitle = UILabel(text: "vibration".localizedString, textColor: ImportantText_Color, fontSize: 15, fit: false)
        contentView.addSubview(vibrationTitle)
        vibrationTitle.snp.makeConstraints { make in
            make.left.right.equalTo(notificationVolumeNote)
            make.top.equalTo(notificationVolumeNote.snp.bottom).offset(SCRYFrom(16))
        }
        
        let vibrationNote = UILabel(text: nil, textColor: ImportantText_Color)
        vibrationNote.numberOfLines = 0
        vibrationNote.attributedText = NSAttributedString(string: "vibration_instructions".localizedString, attributes: attributes)
        contentView.addSubview(vibrationNote)
        vibrationNote.snp.makeConstraints { make in
            make.left.right.equalTo(vibrationTitle)
            make.top.equalTo(vibrationTitle.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalTo(-SCRYFrom(16))
        }
        
        if mode == .reset {
            brightnessImage.isHidden = true
            illuminationTitle.snp.remakeConstraints { make in
                make.left.right.equalTo(brightnessNote)
                make.top.equalTo(brightnessNote.snp.bottom).offset(SCRYFrom(16))
            }
            
        }
        
    }

}
