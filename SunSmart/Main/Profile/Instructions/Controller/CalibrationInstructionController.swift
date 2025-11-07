//
//  CalibrationInstructionController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

class CalibrationInstructionController: UIViewController {
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var contentLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        title = "calibration_instruction_title".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
//        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
        
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        
        let contentAttStr = NSMutableAttributedString()
        
        let text = "calibration_instruction_desc".localizedString
        let textAttStr = NSMutableAttributedString(string: text, attributes: [.paragraphStyle: paragraphStyle, .foregroundColor: SubText_Color])
        
        textAttStr.addAttributes([.foregroundColor: TextBlack_Color, .font: FONTS(14)], range: (text as NSString).range(of: "calibration_instruction_desc_1".localizedString))
        textAttStr.addAttributes([.foregroundColor: TextBlack_Color, .font: FONTS(14)], range: (text as NSString).range(of: "calibration_instruction_desc_2".localizedString))
        textAttStr.addAttributes([.foregroundColor: TextBlack_Color, .font: FONTS(14)], range: (text as NSString).range(of: "calibration_instruction_desc_3".localizedString))
        
        
        let image = UIImage(named: "calibration_formula")!
        let attch = NSTextAttachment()
        attch.bounds = CGRect(x: 0, y: -50, width: SCRXFrom(image.size.width), height: image.size.height)
        attch.image = image
        let iconAttStr = NSAttributedString(attachment: attch)
        contentAttStr.append(textAttStr)
        contentAttStr.append(iconAttStr)
        
        contentAttStr.append(NSAttributedString(string: "calibration_instruction_desc_end".localizedString, attributes: [.paragraphStyle: paragraphStyle, .foregroundColor: SubText_Color]))
        
        contentLabel.attributedText = contentAttStr
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.scrollView.firstShowFlashScrollIndicators {
            self.scrollView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    @objc private func back() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
//        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(-kSafeAreaBottomHeight)
//            make.top.equalTo((navigationController?.navigationBar.height ?? kNavigationHeight))
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 10
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
            make.height.greaterThanOrEqualToSuperview()
        }
        
        contentLabel = UILabel(text: nil, textColor: .black, fontSize: 14, fontWeight: .light, fit: false)
        contentLabel.numberOfLines = 0
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(22))
            make.bottom.equalTo(SCRYFrom(-89)).priority(.low)
//            make.height.greaterThanOrEqualTo(500)
        }
        
    }
        
}
