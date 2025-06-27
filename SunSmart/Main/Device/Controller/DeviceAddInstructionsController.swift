//
//  DeviceAddInstructionsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/27.
//

import UIKit

class DeviceAddInstructionsController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    private var classModeLabel: UILabel!
    private var classModeMessageLabel: UILabel!
    
//    private let margin = isIPad ? SCRXFrom(24) : SCRXFrom(20)
    private let contentMargin = isIPad ? SCRXFrom(100) : SCRXFrom(20)
    
    private var professionmlModeLabel: UILabel!
    private var professionmlModeImageView: UIImageView!
    
    private var stepView: GroupPathSequenceDeviceAddStepView!
    private var noteLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "add_device_instructions".localizedString
        
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
    }
    
    @objc private func back() {
        dismiss(animated: true)
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
        contentView.backgroundColor = Background_Color
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        classModeLabel = UILabel(text: "classic_mode".localizedString, textColor: ImportantText_Color, fontSize: 15, fit: false)
        contentView.addSubview(classModeLabel)
        classModeLabel.snp.makeConstraints { make in
            
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(6))
        }
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.alignment = .center
        
        classModeMessageLabel = UILabel(text: nil, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        classModeMessageLabel.textAlignment = .center
        classModeMessageLabel.numberOfLines = 0
        classModeMessageLabel.attributedText = NSMutableAttributedString(string: "classic_mode_instructions".localizedString, attributes: [.paragraphStyle: style])
        contentView.addSubview(classModeMessageLabel)
        classModeMessageLabel.snp.makeConstraints { make in
            make.left.equalTo(contentMargin)
            make.right.equalTo(-contentMargin)
            make.top.equalTo(classModeLabel.snp.bottom).offset(SCRYFrom(8))
        }
        
        professionmlModeLabel = UILabel(text: "professional_mode".localizedString, textColor: ImportantText_Color, fontSize: 15, fit: false)
        contentView.addSubview(professionmlModeLabel)
        professionmlModeLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(classModeMessageLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        professionmlModeImageView = UIImageView(image: UIImage(named: "device_add_professionmal_mode"))
        professionmlModeImageView.sizeToFit()
        contentView.addSubview(professionmlModeImageView)
        professionmlModeImageView.snp.makeConstraints { make in
            make.top.equalTo(professionmlModeLabel.snp.bottom).offset(SCRYFrom(20))
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualToSuperview()
            make.height.equalTo(professionmlModeImageView.snp.width).multipliedBy(226 / 351.0)
        }
        
        stepView = GroupPathSequenceDeviceAddStepView()
        stepView.step1View.titleLabel.text = "professional_mode_step_1".localizedString
        stepView.step2View.titleLabel.text = "professional_mode_step_2".localizedString
        stepView.step3View.titleLabel.text = "professional_mode_step_3".localizedString
        contentView.addSubview(stepView)
        stepView.snp.makeConstraints { make in
            make.left.equalTo(contentMargin)
            make.right.equalTo(-contentMargin)
            make.top.equalTo(professionmlModeImageView.snp.bottom).offset(SCRYFrom(30))
            make.height.equalTo(SCRYFrom(110))
        }
        
        noteLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 0
        noteLabel.attributedText = NSMutableAttributedString(string: "professional_mode_instructions".localizedString, attributes: [.paragraphStyle: style])
        noteLabel.textAlignment = .center
        contentView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(classModeMessageLabel)
            make.top.equalTo(stepView.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-28))
        }
        
    }


}
