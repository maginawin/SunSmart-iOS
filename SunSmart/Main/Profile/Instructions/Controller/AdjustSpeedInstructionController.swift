//
//  AdjustSpeedInstructionController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

class AdjustSpeedInstructionController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        title = "adjust_speed_instruction".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
    }
    
    @objc private func back() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
//            make.top.equalTo((navigationController?.navigationBar.height ?? kNavigationHeight))
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 10
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        let slowLabel = UILabel(text: "adjust_speed_slow".localizedString, textColor: TextBlack_Color, fontSize: 14, fit: false)
        contentView.addSubview(slowLabel)
        slowLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(24))
        }
        
        let slowImageView = UIImageView(image: UIImage(named: "adjust_speed_slow"))
        contentView.addSubview(slowImageView)
        slowImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-38))
            make.top.equalTo(slowLabel.snp.bottom).offset(SCRYFrom(24))
            make.height.equalTo(slowImageView.snp.width).multipliedBy(163.0 / 289.0)
        }
        
        let fastLabel = UILabel(text: "adjust_speed_fast".localizedString, textColor: TextBlack_Color, fontSize: 14, fit: false)
        contentView.addSubview(fastLabel)
        fastLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(slowImageView.snp.bottom).offset(SCRYFrom(24))
        }
        
        let fastImageView = UIImageView(image: UIImage(named: "adjust_speed_fast"))
        contentView.addSubview(fastImageView)
        fastImageView.snp.makeConstraints { make in
            make.left.right.height.equalTo(slowImageView)
            make.top.equalTo(fastLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        let contentLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        contentLabel.numberOfLines = 0
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(fastImageView.snp.bottom).offset(SCRYFrom(20))
            make.bottom.equalToSuperview().offset(SCRYFrom(-20))
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacingBefore = 5
        
        let text = "adjust_speed_instruction_desc".localizedString
        let attStr = NSMutableAttributedString(string: text, attributes: [.paragraphStyle: paragraphStyle])
        attStr.addAttributes([.font: FONTS(14), .foregroundColor: TextBlack_Color], range: (text as NSString).range(of: "adjust_speed".localizedString))
        
        contentLabel.attributedText = attStr
        
    }
    

 

}
