//
//  RelativeSensitivityInstructionsController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/18.
//

import UIKit

class RelativeSensitivityInstructionsController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var imageView: UIView!
    private var messageLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "relative_sensitivity".localizedString
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        view.backgroundColor = Background_Color
        
        setupUI()
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
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        imageView = UIImageView(image: UIImage(named: "profile_absolute_sensitivity"))
        imageView.sizeToFit()
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(7))
            if isIPad {
//                make.centerX.equalToSuperview()
//                make.width.equalTo(imageView.width)
//                make.height.equalTo(imageView.height)
                make.left.equalTo(SCRXFrom(100))
                make.right.equalTo(SCRXFrom(-100))
            }else {
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
            }
            make.height.equalTo(imageView.snp.width).multipliedBy(256 / 343.0)
        }
        
        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        
        let contentStyle = NSMutableParagraphStyle()
        contentStyle.lineSpacing = 4
        contentStyle.paragraphSpacing = 7
        
        let attStr = NSMutableAttributedString()
        attStr.append(NSAttributedString(string: "absolute_sensitivity_instructions_1".localizedString))
        attStr.append(NSAttributedString(string: "\n" + "absolute_sensitivity_instructions_2".localizedString))
        attStr.append(NSAttributedString(string: "\n" + "absolute_sensitivity_instructions_3".localizedString))
        attStr.addAttributes([.paragraphStyle: contentStyle], range: NSRange(location: 0, length: attStr.length))
        
        let noteStyle = NSMutableParagraphStyle()
        noteStyle.lineSpacing = 4
        attStr.append(NSAttributedString(string: "\n" + "absolute_sensitivity_instructions_4".localizedString, attributes: [.paragraphStyle: noteStyle]))
        
        messageLabel.attributedText = attStr
        messageLabel.numberOfLines = 0
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(imageView).offset(SCRXFrom(16))
            make.right.equalTo(imageView).offset(SCRXFrom(-16))
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(18))
            make.bottom.equalToSuperview()
        }
        
    }

}
