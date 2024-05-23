//
//  ManualOverrideTimeoutInstructionController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

class ManualOverrideTimeoutInstructionController: UIViewController {

    private var imageView: UIImageView!
    private var personImageView: UIImageView!
    private var contentLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        title = "manual_override_timeout_instruction_title".localizedString
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        imageView = UIImageView(image: UIImage(named: "sensor_manul_override_timeout"))
        view.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(19))
            make.right.equalTo(SCRXFrom(-28))
            make.top.equalTo((navigationController?.navigationBar.height ?? kNavigationHeight) + SCRYFrom(11))
            make.height.equalTo(imageView.snp.width).multipliedBy(141.0 / 328.0)
        }
        
        personImageView = UIImageView(image: UIImage(named: "person_movement"))
        imageView.addSubview(personImageView)
        personImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(130))
            make.bottom.equalTo(-21)
        }
        
        
        contentLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        contentLabel.numberOfLines = 0
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        let textAttStr = NSAttributedString(string: "manual_override_timeout_instruction_desc".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        contentLabel.attributedText = textAttStr
        view.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-32))
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(26))
        }
        
    }
  
    @objc private func back() {
        navigationController?.popViewController(animated: true)
    }
    
}
